# CI/CD

O Jenkins roda em contêiner (`api/jenkins/compose.yaml`), com Maven, Docker,
`kubectl` e AWS CLI instalados. Cada repositório tem seu `Jenkinsfile`.

## Estágios

| Estágio | O que faz |
| --- | --- |
| Dependencies | Dispara os jobs dos contratos dos quais o serviço depende |
| Build | `mvn clean package` |
| Build & Push Image | Imagem multi-arquitetura (`amd64` e `arm64`) enviada ao Docker Hub com as tags `latest` e o número do build |
| Deploy to K8s | Atualiza a imagem do Deployment no EKS e aguarda o rollout |

O estágio de deploy está implementado no `order-service`:

```groovy
stage('Deploy to K8s') {
    environment {
        CLUSTER = 'eks-store'
        REGION = 'us-east-1'
        NAMESPACE = 'store'
    }
    steps {
        withCredentials([
            usernamePassword(credentialsId: 'dockerhub-credential',
                usernameVariable: 'USERNAME', passwordVariable: 'TOKEN'),
            usernamePassword(credentialsId: 'aws-credential',
                usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
            sh '''
                export KUBECONFIG="$WORKSPACE/.kubeconfig"
                aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
                kubectl -n "$NAMESPACE" set image "deployment/$SERVICE" "$SERVICE=$USERNAME/$SERVICE:$BUILD_ID"
                kubectl -n "$NAMESPACE" rollout status "deployment/$SERVICE" --timeout=300s
            '''
        }
    }
}
```

## Pré-requisitos no Jenkins e na AWS

1. Credencial `dockerhub-credential` (usuário e token do Docker Hub), já usada
   pelo push das imagens.
2. Credencial `aws-credential` do tipo *username with password*: usuário = Access
   Key ID, senha = Secret Access Key de um usuário IAM dedicado ao Jenkins.
3. Esse usuário IAM precisa de acesso ao cluster `eks-store`, por uma *access
   entry* do EKS com permissão de editar o namespace `store`.

O deploy usa a tag do build (`$BUILD_ID`), e não `latest`, para que cada execução
force um novo rollout e o histórico de versões fique rastreável.

!!! warning "Pendente"
    Replicar o estágio `Deploy to K8s` nos `Jenkinsfile`s de account, auth,
    product, exchange e gateway, e criar um pipeline na raiz da plataforma que
    dispare todos.

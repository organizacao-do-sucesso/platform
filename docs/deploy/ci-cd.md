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

## Imagens no Docker Hub

O estágio *Build & Push Image* publica cada serviço no Docker Hub, de onde o EKS
baixa as imagens (overlay `k8s/overlays/aws`).

| Serviço | Imagem |
| --- | --- |
| account | [`rafaeldbo/account`](https://hub.docker.com/r/rafaeldbo/account){ target="_blank" } |
| auth | [`rafaeldbo/auth`](https://hub.docker.com/r/rafaeldbo/auth){ target="_blank" } |
| product | [`rafaeldbo/product`](https://hub.docker.com/r/rafaeldbo/product){ target="_blank" } |
| order | [`rafaeldbo/order`](https://hub.docker.com/r/rafaeldbo/order){ target="_blank" } |
| exchange | [`rafaeldbo/exchange`](https://hub.docker.com/r/rafaeldbo/exchange){ target="_blank" } |
| gateway | [`rafaeldbo/gateway`](https://hub.docker.com/r/rafaeldbo/gateway){ target="_blank" } |

Cada build publica duas tags: `latest` e o número do build do Jenkins. As
imagens são multi-arquitetura (`amd64` e `arm64`), então rodam tanto nos nodes
do EKS quanto em Macs com Apple Silicon.

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

Todos os serviços estão implantados e rodando no EKS: o order pelo estágio
acima, os demais pelo script `k8s/scripts/deploy-aws.ps1`.

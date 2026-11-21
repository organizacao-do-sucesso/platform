# CI/CD

O Jenkins roda em contêiner (`api/jenkins/compose.yaml`, porta `9080`), com
Maven, Docker, `kubectl` e AWS CLI instalados. Cada repositório tem seu
`Jenkinsfile`, e o estágio SCM é o próprio *Pipeline from SCM* de cada job.

## Estágios

| Estágio | O que faz |
| --- | --- |
| Dependencies | Dispara os jobs dos contratos dos quais o serviço depende |
| Build | `mvn clean package` |
| Build & Push Image | Imagem multi-arquitetura (`amd64` e `arm64`) enviada ao Docker Hub com as tags `latest` e o número do build |

| Repositório | Dependencies | Build | Push |
| --- | --- | --- | --- |
| order-service | `order`, `product`, `exchange` | ✅ | ✅ |
| account-service | `account` | ✅ | ✅ |
| auth-service | `auth` | ✅ | ✅ |
| product-service | `product` | ✅ | ✅ |
| gateway-service | `auth` | ✅ | ✅ |
| exchange-service | — (Python) | — | ✅ |
| contratos (`account`, `auth`, `product`, `order`, `exchange`) | só `auth` → `account` | ✅ `mvn install` | — |

O login no Docker Hub usa `--password-stdin`, para o token não aparecer na linha
de comando.

## Imagens no Docker Hub

O estágio *Build & Push Image* publica cada serviço no Docker Hub, de onde o EKS
baixa as imagens (overlay `k8s/overlays/aws`).
Todas ficam no perfil
[hub.docker.com/u/rafaeldbo](https://hub.docker.com/u/rafaeldbo){ target="_blank" }.

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

## Deploy no EKS

O pipeline termina no push da imagem. A implantação no cluster é feita pelo
script `k8s/scripts/deploy-aws.ps1`, que aplica o overlay AWS do Kustomize: todos
os Deployments usam a tag `latest` com `imagePullPolicy: Always`, então cada
aplicação do overlay baixa a versão mais recente publicada pelo Jenkins.

Para atualizar um serviço já implantado depois de um novo build:

```bash
kubectl rollout restart deployment/<serviço> -n store
kubectl rollout status deployment/<serviço> -n store
```

O `rollout restart` recria os pods, que baixam de novo a imagem `latest`. Os pods
antigos só saem depois que os novos passam na `readinessProbe`, então a troca
acontece sem indisponibilidade.

Separar o build (Jenkins) do deploy (script) mantém as credenciais da AWS fora
do Jenkins: só quem tem acesso ao cluster aplica mudanças nele.

# Jenkins

*Responsáveis: todos, cada um no `Jenkinsfile` do seu serviço · Jenkins em
[api/jenkins](https://github.com/organizacao-do-sucesso/platform/tree/main/api/jenkins)*

## O que o enunciado pede

Um `Jenkinsfile` em cada microsserviço, com os estágios **SCM**,
**Dependencies**, **Build**, **Push to Docker Hub** e **Deploy to K8s**, e um
pipeline na raiz do projeto cobrindo todos os serviços.

## Implementação

O Jenkins roda em contêiner (porta `9080`), com Maven, Docker, `kubectl` e AWS
CLI. O estágio SCM é o próprio *Pipeline from SCM* de cada job.

| Repositório | Dependencies | Build | Push to Docker Hub | Deploy no EKS |
| --- | --- | --- | --- | --- |
| order-service | `order`, `product`, `exchange` | ✅ | ✅ | ✅ estágio `Deploy to K8s` |
| account-service | `account` | ✅ | ✅ | ✅ `deploy-aws.ps1` |
| auth-service | `auth` | ✅ | ✅ | ✅ `deploy-aws.ps1` |
| product-service | `product` | ✅ | ✅ | ✅ `deploy-aws.ps1` |
| gateway-service | `auth` | ✅ | ✅ | ✅ `deploy-aws.ps1` |
| exchange-service | — (Python) | — | ✅ | ✅ `deploy-aws.ps1` |
| contratos (`account`, `auth`, `product`, `order`, `exchange`) | só `auth` → `account` | ✅ `mvn install` | — | — |

As imagens são multi-arquitetura (`amd64` e `arm64`), com as tags `latest` e o
número do build. O login no Docker Hub usa `--password-stdin`, para o token não
aparecer na linha de comando.

O estágio de deploy do order está detalhado em [CI/CD](../deploy/ci-cd.md).

Todos os serviços estão implantados e rodando no EKS. O order é atualizado pelo
próprio pipeline (estágio `Deploy to K8s`); os demais, pelo script
`k8s/scripts/deploy-aws.ps1`, que aplica o overlay AWS do Kustomize.

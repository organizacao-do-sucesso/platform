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

| Repositório | Dependencies | Build | Push to Docker Hub | Deploy to K8s |
| --- | --- | --- | --- | --- |
| order-service | `order`, `product`, `exchange` | ✅ | ✅ | ✅ |
| account-service | `account` | ✅ | ✅ | ❌ |
| auth-service | `auth` | ✅ | ✅ | ❌ |
| product-service | `product` | ✅ | ✅ | ❌ |
| gateway-service | `auth` | ✅ | ✅ | ❌ |
| exchange-service | — (Python) | — | ✅ | ❌ |
| contratos (`account`, `auth`, `product`, `order`, `exchange`) | só `auth` → `account` | ✅ `mvn install` | — | — |

As imagens são multi-arquitetura (`amd64` e `arm64`), com as tags `latest` e o
número do build. O login no Docker Hub usa `--password-stdin`, para o token não
aparecer na linha de comando.

O estágio de deploy do order está detalhado em [CI/CD](../deploy/ci-cd.md).

!!! warning "Pendente"
    Copiar o estágio `Deploy to K8s` para os demais serviços e criar o pipeline
    raiz do projeto.

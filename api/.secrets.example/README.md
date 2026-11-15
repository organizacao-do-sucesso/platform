# Secrets locais do Kubernetes

Esta pasta contém valores de exemplo utilizáveis somente em desenvolvimento
local. Eles servem como ponto de partida para os Secrets consumidos pelos
manifests Kubernetes da Store.

Não use estes valores em ambientes compartilhados, demonstrações públicas ou
produção. Como esta pasta pode ser versionada, considere todo o seu conteúdo
público e conhecido.

## Preparação

Na raiz do repositório, copie esta pasta para `api/.secrets`:

```powershell
New-Item -ItemType Directory -Force api/.secrets | Out-Null
Copy-Item api/.secrets.example/*.env api/.secrets/
```

O diretório `api/.secrets` é ignorado pelo Git. Troque nele todos os valores
antes de usar um cluster compartilhado ou remoto.

Os arquivos esperados são:

| Arquivo | Secret Kubernetes | Conteúdo |
| --- | --- | --- |
| `postgres.env` | `postgres-secret` | Usuário e senha usados pelo PostgreSQL |
| `auth.env` | `auth-secret` | Chave Base64 usada para assinar os JWTs |
| `account.env` | `account-secret` | Credenciais do banco e senha inicial do administrador |
| `product.env` | `product-secret` | Credenciais do banco do serviço de produtos |

## Cuidados importantes

- Mantenha a senha do PostgreSQL igual em `postgres.env`, `account.env` e
  `product.env`.
- `JWT_SECRET_KEY` deve ser uma chave aleatória codificada em Base64, com pelo
  menos 32 bytes depois da decodificação.
- `ADMIN_PASSWORD` é usado para criar o administrador quando ele ainda não
  existe. Alterar esse valor não troca automaticamente a senha de uma conta já
  criada.
- Nunca faça commit de `api/.secrets`, copie seu conteúdo para mensagens ou
  imprima Secrets do cluster em logs.

## Validação

Valide os arquivos locais sem acessar nenhum cluster:

```powershell
./k8s/scripts/apply-secrets.ps1 -ValidateOnly
```

Os scripts `deploy-minikube.ps1` e `deploy-aws.ps1` executam a aplicação dos
Secrets automaticamente antes de aplicar o overlay Kustomize.

# Account API

*Responsáveis: Luca Cazzolato Machado e Rafael Dourado Bastos de Oliveira (papéis) · código:
[account](https://github.com/organizacao-do-sucesso/account) (contrato) e
[account-service](https://github.com/organizacao-do-sucesso/account-service)
(implementação)*

Guarda as contas da plataforma e seus papéis. É usada pelo auth no cadastro e
no login; pelo gateway, só o papel `account.admin` gerencia contas.

## Rotas

| Método | Rota | Descrição |
| --- | --- | --- |
| `POST` | `/accounts` | Cria uma conta (`201`), sempre com o papel `customer` |
| `GET` | `/accounts`, `/accounts/{id}` | Lista ou busca contas (`404` se não existir) |
| `DELETE` | `/accounts/{id}` | Remove uma conta (`204`) |
| `POST` | `/accounts/login` | Confere e-mail e senha (`401` se não baterem) |
| `POST` | `/accounts/{id}/roles` | Troca o papel da conta |

## Implementação

- **Senha:** nunca é gravada em texto. O serviço guarda só o hash SHA-256
  (coluna `password_sha256`) e, no login, compara os hashes.
- **Papéis:** coluna `role`, com padrão `customer`. A troca de papel valida o
  valor (`400` para papel inexistente) e é o que o RBAC do gateway usa.
- **Administrador inicial:** ao subir, cria a conta definida por `ADMIN_EMAIL` e
  `ADMIN_PASSWORD`, para que exista alguém capaz de promover outros usuários.
- **Banco:** schema `accounts`, tabela `accounts` com e-mail único, criada pelo
  Flyway.

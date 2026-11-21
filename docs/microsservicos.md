# Microsserviços

Seis serviços, cinco em Java (Spring Boot 4, Java 25) e um em Python. Todas as
rotas abaixo são acessadas pelo gateway; as marcadas com permissão exigem login
e o papel correspondente.

## Gateway

Entrada única da plataforma, em Spring Cloud Gateway (WebFlux). Para cada
requisição protegida, lê o JWT do cookie `__store_jwt_token`, resolve-o em
`/auth/solve`, confere a permissão exigida pela rota e injeta o header
`id-account` antes de encaminhar.

| Rota | Destino | Acesso |
| --- | --- | --- |
| `/auth/**` | auth | `register`, `login` e `logout` são públicas |
| `/accounts/**` | account | login; trocar papel exige `account.admin` |
| `/products/**` | product | leitura `product.read`, escrita `product.write` |
| `/orders/**` | order | leitura `order.read`, criação `order.write` |
| `/exchanges/**` | exchange | `exchange.read` |
| `/grafana/**` | grafana | pública, protegida pelo login do Grafana |
| `/prometheus/**` | prometheus | papel `administrator` |

### Papéis

| Papel | Permissões |
| --- | --- |
| `customer` (padrão de toda conta nova) | `product.read`, `order.read`, `order.write`, `exchange.read` |
| `product-manager` | `product.read`, `product.write` |
| `account-manager` | `product.read`, `account.admin` |
| `administrator` | todas |

## Auth

Cadastro, login e resolução de tokens. Não tem banco: delega as contas ao
account e assina JWTs com uma chave HMAC.

| Método | Rota | Descrição |
| --- | --- | --- |
| `POST` | `/auth/register` | Cria a conta (papel `customer`) |
| `POST` | `/auth/login` | Valida as credenciais e devolve o JWT no cookie |
| `GET` | `/auth/logout` | Apaga o cookie |
| `GET` | `/auth/whoiam` | Dados da conta logada |
| `POST` | `/auth/solve` | Uso interno do gateway: token → conta, papel e permissões |

## Account

Contas, hash de senha e papéis, no schema `accounts`. Ao subir, cria o
administrador definido por `ADMIN_EMAIL` e `ADMIN_PASSWORD`. Detalhes em
[Account API](account.md).

| Método | Rota | Descrição |
| --- | --- | --- |
| `POST` | `/accounts` | Cria uma conta |
| `GET` | `/accounts`, `/accounts/{id}` | Lista ou busca contas |
| `DELETE` | `/accounts/{id}` | Remove uma conta |
| `POST` | `/accounts/login` | Confere e-mail e senha |
| `POST` | `/accounts/{id}/roles` | Troca o papel da conta |

## Product

Catálogo de produtos, no schema `products`, com validação de nome, preço e
unidade. Detalhes em [Product API](product.md).

| Método | Rota | Descrição |
| --- | --- | --- |
| `POST` | `/products` | Cria um produto (`201`) |
| `GET` | `/products`, `/products/{id}` | Lista ou busca produtos |
| `DELETE` | `/products/{id}` | Remove um produto (`204`) |

## Order

Pedidos do usuário logado, com total em USD e conversão de moeda na leitura.
Detalhes em [Order API](order.md).

| Método | Rota | Descrição |
| --- | --- | --- |
| `POST` | `/orders` | Cria um pedido para o usuário logado |
| `GET` | `/orders` | Lista os pedidos do usuário |
| `GET` | `/orders/{id}?currency=` | Detalha um pedido, opcionalmente em outra moeda |

## Exchange

Cotação entre moedas, em Python (FastAPI). Busca a taxa na PTAX do Banco
Central e guarda no Redis por 5 minutos. Detalhes em
[Exchange API](exchange.md).

| Método | Rota | Descrição |
| --- | --- | --- |
| `GET` | `/exchanges/{from}/{to}` | Taxas de compra e venda; `422` para moeda inválida |

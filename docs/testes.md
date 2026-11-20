# Testes

A plataforma é validada por **testes de ponta a ponta**: um script sobe todos os
serviços e faz requisições reais **pelo gateway**, como um cliente faria. Assim,
cada teste exercita ao mesmo tempo o roteamento, a autenticação, a autorização,
a comunicação entre serviços e a persistência.

O script está em [`scripts/test-e2e.sh`](https://github.com/organizacao-do-sucesso/platform/blob/main/scripts/test-e2e.sh)
e termina com código de erro se algum cenário falhar.

## Como executar

=== "Ambiente completo (Docker Compose)"

    Compila os contratos e serviços a partir dos submódulos de `api/`, sobe a
    stack com Docker Compose e roda os testes.

    ```bash
    git submodule update --init
    bash scripts/test-e2e.sh
    bash scripts/test-e2e.sh down   # ao terminar
    ```

=== "Contra um ambiente já no ar (ex.: EKS)"

    Roda só os testes contra um gateway existente.

    ```bash
    kubectl port-forward -n store service/gateway 8080:8080
    ADMIN_PASSWORD=... GRAFANA_ADMIN_PASSWORD=... bash scripts/test-e2e.sh test
    ```

Requisitos: `bash`, `curl` e `python3`; o modo completo também precisa de
Docker, Maven e Java 25.

## Cenários

O roteiro cria um produto como administrador, faz um pedido com ele e depois
cadastra um cliente comum para testar o isolamento entre usuários e as
permissões.

### Pedidos (Order API)

| # | Cenário | Esperado | O que comprova |
| --- | --- | --- | --- |
| 1 | Administrador cria um produto | `201` | Rota de produtos e permissão `product.write` |
| 2 | `POST /orders` com 2 unidades do produto | `201` | Order consulta o product pelo contrato e grava o pedido |
| 3 | Total do pedido | `20.24` (2 × 10,12) | Preço vem do product e é multiplicado pela quantidade |
| 4 | Pedido com produto inexistente | `400` | `ProductClient` traduz o `404` do product |
| 5 | Pedido com quantidade 0 | `400` | Validação de entrada do order |
| 6 | `GET /orders` | `200` | Listagem dos pedidos do usuário |
| 7 | `GET /orders/{id}` | `200` | Detalhe do pedido |
| 8 | Moeda padrão | `USD` | Valores armazenados em dólar |
| 9 | `GET /orders/{id}?currency=BRL` | `200` | Order chama o exchange pelo contrato |
| 10 | Moeda da resposta | `BRL` | Conversão aplicada aos totais |
| 11 | Moeda inexistente (`XYZ`) | `422` | `ExchangeClient` traduz o erro do exchange |

### Autenticação e autorização

| # | Cenário | Esperado | O que comprova |
| --- | --- | --- | --- |
| 12 | Cliente se cadastra e faz login | token recebido | Fluxo auth → account e emissão do JWT |
| 13 | Cliente abre o pedido do administrador | `404` | Pedidos isolados por usuário (`id-account`) |
| 14 | Cliente tenta criar produto | `403` | RBAC: `customer` não tem `product.write` |
| 15 | Requisição sem token | `401` | Gateway bloqueia rotas protegidas |
| 16 | Cliente abre o Prometheus | `403` | Prometheus restrito ao papel `administrator` |

### Observabilidade

| # | Cenário | Esperado | O que comprova |
| --- | --- | --- | --- |
| 17 | Prometheus sem login | `401` | Prometheus só é acessível pelo gateway, autenticado |
| 18 | `GET /grafana/api/health` | `200` | Grafana publicado em `/grafana/` pelo gateway |
| 19 | Saúde do datasource Prometheus no Grafana | `200` | Grafana alcança o Prometheus pela rede interna |
| 20 | Alvo `order` no Prometheus | `up` | Descoberta automática do serviço |
| 21 | `orders_placed_total` | ≥ 1 | Métrica de negócio coletada após o pedido |

Os cenários 20 e 21 esperam até 40 s, porque o Prometheus coleta a cada 15 s.

## Resultado

```text
== 21 passed, 0 failed
```

Execução de 20/11/2026, com Docker Compose.

## Problemas encontrados pelos testes

| Problema | Causa | Correção |
| --- | --- | --- |
| Métrica de pedidos não aparecia no Grafana | A biblioteca do Prometheus remove o sufixo `_created` de contadores: `orders.created` virava `orders_total` | Contador renomeado para `orders.placed` |
| `account` caía na primeira subida | Com todos os serviços iniciando juntos, o account levou mais de 60 s, o limite do script que cria o administrador | Reexecução após a subida; o limite fica como ponto de atenção |
| Testes falhavam logo após um deploy | O script começava antes de o order terminar de subir | O script espera o `/orders` responder antes de testar |

## Limitações

Nenhum serviço tem testes unitários (`src/test` vazio em todos os repositórios),
e os pipelines do Jenkins compilam com `-DskipTests`. A cobertura vem toda dos
testes de ponta a ponta acima, que dependem da plataforma completa no ar. O
próximo passo seria adicionar testes de serviço com JUnit e Mockito,
começando pelo `OrderService`, e rodá-los no estágio *Build* do Jenkins.

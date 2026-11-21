# Order API

*Responsável: Luísa Carvalho Farah · código:
[order](https://github.com/organizacao-do-sucesso/order) (contrato) e
[order-service](https://github.com/organizacao-do-sucesso/order-service)
(implementação)*

Os pedidos pertencem ao usuário autenticado, identificado pelo
header `id-account` que o gateway injeta.

## Funcionamento

1. **Criar** (`POST /orders`): para cada item, consulta o produto no
   product-service pelo contrato `product`, guarda o preço do momento e calcula
   o total do item. O total do pedido é a soma, em USD.
2. **Listar** (`GET /orders`): devolve só os pedidos do usuário, do mais recente
   para o mais antigo.
3. **Detalhar** (`GET /orders/{id}`): devolve `404` se o pedido não for do
   usuário. Com `?currency=BRL`, busca a taxa no exchange pelo contrato
   `exchange` e converte os totais.

## Implementação

- **Usa os contratos dos outros serviços**, sem reimplementar nada: o
  `ProductController` e o `ExchangeController` vêm dos repositórios `product` e
  `exchange`.
- **O preço é copiado para o item** no momento do pedido, então mudar o preço
  do produto depois não altera pedidos antigos.
- **Banco:** schema `orders`, tabelas `orders` e `items`, criadas pelo Flyway.
- **Kubernetes:** `k8s/k8s.yaml` com probes no actuator e anotações para o
  Prometheus coletar as métricas; na AWS, usa o RDS.

## Exemplos

=== "POST /orders"

    ```json
    {
      "items": [
        { "idProduct": "0195abfb-7074-73a9-9d26-b4b9fbaab0a8", "quantity": 2 }
      ]
    }
    ```

=== "Resposta 201"

    ```json
    {
      "id": "0195ac33-73e5-7cb3-90ca-7b5e7e549569",
      "date": "2026-11-11T18:31:37",
      "currency": "USD",
      "items": [
        {
          "id": "01961b9a-bca2-78c4-9be1-7092b261f217",
          "product": { "id": "0195abfb-7074-73a9-9d26-b4b9fbaab0a8" },
          "quantity": 2,
          "total": 20.24
        }
      ],
      "total": 20.24
    }
    ```

## Erros

| Situação | Status |
| --- | --- |
| Produto inexistente, id em branco ou quantidade ≤ 0 | `400` |
| Pedido de outro usuário | `404` |
| Moeda não suportada | `422` |
| Product ou exchange fora do ar | `503` |

Os erros das chamadas Feign são traduzidos por `ProductClient` e
`ExchangeClient`, que não têm lógica de negócio: apenas mapeiam o status da
resposta para o erro da Order API.

## Métricas

Além das métricas padrão do Spring Boot (latência por rota, JVM), o serviço
publica em `/order/actuator/prometheus`:

| Métrica | Tipo | Significado |
| --- | --- | --- |
| `orders_placed_total` | contador | Pedidos criados |
| `orders_amount_usd` | distribuição | Valor dos pedidos, em USD |
| `orders_items` | distribuição | Itens por pedido |

O contador se chamava `orders.created`, mas a biblioteca do Prometheus remove o
sufixo `_created` dos contadores, e o nome exportado virava `orders_total`. Por
isso ele foi renomeado para `orders.placed`.

## Testes de ponta a ponta

Antes de cada entrega, um script sobe a plataforma completa com Docker Compose e
verifica pelo gateway 21 cenários: criação e listagem de pedidos, total
calculado, erros `400`/`404`/`422`, conversão para BRL, RBAC (`401`/`403`) e a
coleta das métricas pelo Prometheus.

# Order API

*Responsável: Luísa Carvalho Farah · código:
[order](https://github.com/organizacao-do-sucesso/order) (contrato) e
[order-service](https://github.com/organizacao-do-sucesso/order-service)
(implementação)*

## O que o enunciado pede

| Requisito | Como foi atendido |
| --- | --- |
| `POST /orders` com itens (`idProduct`, `quantity`), retornando `201` com itens e total | `OrderService.create` consulta cada produto e calcula os totais |
| `400` se um produto não existir | `ProductClient` traduz o `404` do product |
| `GET /orders` com os pedidos do usuário | Filtrados pelo header `id-account` |
| `GET /orders/{id}`, `404` se não for do usuário | Busca por `id` e `idAccount` juntos |
| `currency` opcional, USD por padrão, conversão pela Exchange API | `ExchangeController` (contrato `exchange`) via OpenFeign |
| `422` para moeda não suportada | `ExchangeClient` traduz os erros do exchange |
| Usuário autenticado | Gateway: `order.read` e `order.write` |
| Extra: validação e tratamento de erros | Itens obrigatórios, quantidade > 0, `503` se product ou exchange cair |
| Nice to have: observabilidade | Métricas de negócio, logs JSON e dashboard (ver [Bottlenecks](bottlenecks.md)) |

## Implementação

A documentação completa, com exemplos de requisição e resposta, erros e
métricas, está em [Order API](../order.md). Pontos principais:

- **Usa os contratos dos outros serviços**, sem reimplementar nada: o
  `ProductController` e o `ExchangeController` vêm dos repositórios `product` e
  `exchange`. `ProductClient` e `ExchangeClient` só traduzem os erros do Feign.
- **O preço é copiado para o item** no momento do pedido, então mudar o preço
  do produto depois não altera pedidos antigos.
- **Banco:** schema `orders`, tabelas `orders` e `items`, criadas pelo Flyway.
- **Kubernetes:** `k8s/k8s.yaml` com probes no actuator e anotações para o
  Prometheus; na AWS, usa o RDS.

## Como testar

Os cenários da Order API são os de número 1 a 13 em [Testes](../testes.md).

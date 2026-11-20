# Product API

*Responsável: Rafael Dourado Bastos de Oliveira · código:
[product](https://github.com/organizacao-do-sucesso/product) (contrato) e
[product-service](https://github.com/organizacao-do-sucesso/product-service)
(implementação)*

## O que o enunciado pede

Uma API REST de produtos, acessível só a usuários autenticados, com quatro
operações.

| Requisito | Como foi atendido |
| --- | --- |
| `POST /products` com `name`, `price` e `unit`, retornando `201` e o `id` | `ProductResource.create`, com header `Location` |
| `GET /products` retornando `200` | `ProductResource.findAll` |
| `GET /products/{id}` retornando `200` | `ProductResource.findById`; `404` se não existir |
| `DELETE /products/{id}` retornando `204` | `ProductResource.delete` |
| Usuário autenticado | Gateway exige login; leitura pede `product.read`, escrita `product.write` |
| Extra: validação de entrada | Nome e unidade obrigatórios, preço ≥ 0 (`400` caso contrário) |
| Extra: papéis (admin gerencia produtos) | RBAC no gateway: só `product-manager` e `administrator` escrevem |

## Implementação

- **Contrato `product`:** `ProductController` (interface `@FeignClient`),
  `ProductIn` e `ProductOut`. O preço é `BigDecimal`, para não perder centavos.
- **Serviço:** `ProductResource` → `ProductService` → `ProductRepository`
  (Spring Data JPA), com o modelo separado do DTO (`ProductParser`).
- **Banco:** schema `products`, criado pelo Flyway, com `price NUMERIC(19, 2)`.

## Como testar

```bash
# com o cookie de um usuário administrator
curl -X POST http://localhost:8080/products -H 'Content-Type: application/json' \
  -b "__store_jwt_token=$TOKEN" -d '{"name":"Tomato","price":10.12,"unit":"kg"}'
```

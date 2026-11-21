# Product API

*Responsável: Rafael Dourado Bastos de Oliveira · código:
[product](https://github.com/organizacao-do-sucesso/product) (contrato) e
[product-service](https://github.com/organizacao-do-sucesso/product-service)
(implementação)*

Catálogo de produtos. Qualquer usuário logado consulta; só `product-manager` e
`administrator` criam e removem.

## Rotas

| Método | Rota | Descrição | Permissão |
| --- | --- | --- | --- |
| `POST` | `/products` | Cria um produto (`201`, com header `Location`) | `product.write` |
| `GET` | `/products` | Lista os produtos | `product.read` |
| `GET` | `/products/{id}` | Busca um produto (`404` se não existir) | `product.read` |
| `DELETE` | `/products/{id}` | Remove um produto (`204`) | `product.write` |

Nome e unidade são obrigatórios e o preço não pode ser negativo; caso
contrário, a resposta é `400`.

## Implementação

- **Contrato `product`:** `ProductController` (interface `@FeignClient`),
  `ProductIn` e `ProductOut`. O preço é `BigDecimal`, para não perder centavos.
  O order usa esse mesmo contrato para consultar produtos.
- **Serviço:** `ProductResource` → `ProductService` → `ProductRepository`
  (Spring Data JPA), com o modelo separado do DTO (`ProductParser`).
- **Banco:** schema `products`, criado pelo Flyway, com `price NUMERIC(19, 2)`.

## Exemplo

```bash
# com o cookie de um usuário administrator
curl -X POST http://localhost:8080/products -H 'Content-Type: application/json' \
  -b "__store_jwt_token=$TOKEN" -d '{"name":"Tomato","price":10.12,"unit":"kg"}'
```

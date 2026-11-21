# Exchange API

*Responsável: Luca Cazzolato Machado · código:
[exchange](https://github.com/organizacao-do-sucesso/exchange) (contrato Java) e
[exchange-service](https://github.com/organizacao-do-sucesso/exchange-service)
(implementação em Python)*

Cotação entre moedas, em **Python** (FastAPI, dependências gerenciadas pelo
`uv`). Exige login e a permissão `exchange.read`.

## Rota

| Método | Rota | Descrição |
| --- | --- | --- |
| `GET` | `/exchanges/{from}/{to}` | Taxas `sell` e `buy`, com a `date` da cotação e o `id-account` de quem pediu |

## Implementação

- **Fonte:** **PTAX**, API pública do Banco Central. A PTAX cota tudo em real,
  então um par como USD → EUR é calculado passando pelo BRL. O próprio BRL
  vale 1.
- **Cache no Redis:** cada cotação fica 5 minutos em cache (a PTAX publica
  poucos boletins por dia). Se o Redis cair, o serviço consulta a PTAX direto.
  Esse é o bottleneck de [caching](bottlenecks.md).
- **Erros:** `422` para código de moeda inválido, `404` para moeda que a PTAX
  não cota, `503` se a PTAX não responder (timeout de 3 s).
- **Contrato Java `exchange`:** como o serviço é em Python, o grupo publicou um
  contrato Feign (`ExchangeController` e `ExchangeOut`) para os serviços Java,
  usado pelo order.
- **Saúde:** `GET /health`, usado pelas probes do Kubernetes.

## Exemplo

```bash
curl -b "__store_jwt_token=$TOKEN" http://localhost:8080/exchanges/USD/BRL
```

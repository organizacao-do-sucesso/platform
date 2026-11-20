# Exchange API

*Responsável: Luca Cazzolato Machado · código:
[exchange](https://github.com/organizacao-do-sucesso/exchange) (contrato Java) e
[exchange-service](https://github.com/organizacao-do-sucesso/exchange-service)
(implementação em Python)*

## O que o enunciado pede

| Requisito | Como foi atendido |
| --- | --- |
| Microsserviço em **Python** | FastAPI, com dependências gerenciadas pelo `uv` |
| `GET /exchanges/{from}/{to}` com `sell`, `buy`, `date` e `id-account` | `resource.py`; `id-account` vem do header injetado pelo gateway |
| Cotação de um serviço externo | **PTAX**, API pública do Banco Central (opção BACEN do enunciado) |
| Usuário autenticado | Gateway exige login e a permissão `exchange.read` |

## Implementação

- **Câmbio cruzado:** a PTAX cota tudo em real, então um par como USD → EUR é
  calculado passando pelo BRL. O próprio BRL vale 1.
- **Cache no Redis:** cada cotação fica 5 minutos em cache (a PTAX publica
  poucos boletins por dia). Se o Redis cair, o serviço consulta a PTAX direto.
  Esse é o bottleneck de [caching](bottlenecks.md).
- **Erros:** `422` para código de moeda inválido, `404` para moeda que a PTAX
  não cota, `503` se a PTAX não responder (timeout de 3 s).
- **Contrato Java `exchange`:** como o serviço é em Python, o grupo publicou um
  contrato Feign (`ExchangeController` e `ExchangeOut`) para os serviços Java,
  usado pelo order.
- **Saúde:** `GET /health`, usado pelas probes do Kubernetes.

## Como testar

```bash
curl -b "__store_jwt_token=$TOKEN" http://localhost:8080/exchanges/USD/BRL
```

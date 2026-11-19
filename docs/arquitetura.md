# Arquitetura

Toda requisição externa entra pelo **gateway**, o único componente exposto. Ele
autentica o usuário, aplica as permissões da rota e encaminha a chamada ao
serviço de destino pela rede interna. Os serviços se falam por HTTP síncrono
(OpenFeign), usando os contratos publicados por cada um.

```mermaid
flowchart TB
    client([Cliente])
    subgraph cluster [Namespace store]
        gateway[gateway-service<br/>Spring Cloud Gateway]
        auth[auth-service]
        account[account-service]
        product[product-service]
        order[order-service]
        exchange[exchange-service<br/>Python · FastAPI]
        redis[(Redis)]
        subgraph obs [observability]
            prometheus[Prometheus]
            loki[Loki]
            alloy[Alloy]
            grafana[Grafana]
        end
    end
    db[(PostgreSQL / RDS)]
    ptax[[PTAX · Banco Central]]

    client --> gateway
    gateway -->|/auth/solve| auth
    auth --> account
    gateway --> account & product & order & exchange
    gateway -->|/grafana, /prometheus| grafana & prometheus
    order --> product
    order --> exchange
    exchange --> redis
    exchange --> ptax
    account & product & order --> db
    prometheus -.métricas.-> order
    alloy -.logs.-> loki
    grafana --> prometheus & loki
```

## Fluxo de uma requisição autenticada

```mermaid
sequenceDiagram
    participant C as Cliente
    participant G as gateway
    participant A as auth
    participant AC as account
    participant O as order
    participant P as product

    C->>G: POST /orders (cookie __store_jwt_token)
    G->>A: POST /auth/solve {token}
    A->>AC: GET /accounts/{id}
    AC-->>A: conta e papel
    A-->>G: AuthContext (idAccount, papel, permissões)
    G->>G: confere a permissão order.write
    G->>O: POST /orders + header id-account
    O->>P: GET /products/{id} (para cada item)
    P-->>O: produto e preço
    O-->>G: 201 Created
    G-->>C: 201 Created
```

## Decisões de arquitetura

| Decisão | Motivo |
| --- | --- |
| Contrato separado da implementação | Quem consome um serviço depende só da interface Feign e dos DTOs, não do código interno. |
| Gateway como porta única | Autenticação e autorização ficam em um só lugar; os serviços confiam no header `id-account`. |
| Papel resolvido a cada requisição | O JWT não carrega o papel: uma troca de papel vale na hora, ao custo de uma chamada extra ao auth. |
| Um schema por serviço (`accounts`, `products`, `orders`) | Cada serviço controla suas tabelas com Flyway, mesmo compartilhando a instância de banco. |
| Valores dos pedidos em USD | A moeda de armazenamento é fixa; a conversão acontece só na leitura, pelo exchange. |
| Observabilidade em repositório próprio | Os serviços entram na coleta com labels (Compose) ou anotações (Kubernetes), sem alterar a stack. |

# Store

Plataforma de e-commerce em microsserviços construída para a disciplina
**Plataformas, Microsserviços e APIs** (Insper, 2026.2). Usuários se cadastram,
fazem login, consultam produtos e criam pedidos, com valores convertidos entre
moedas. Tudo entra por um único gateway, roda em contêineres e é implantado no
Amazon EKS.

## Equipe

| Integrante | Microsserviços | Bottleneck |
| --- | --- | --- |
| Luca Cazzolato Machado | account, auth, gateway, exchange | Caching (Redis no exchange) |
| Luísa Carvalho Farah | order | Observabilidade (Prometheus, Loki, Grafana) |
| Rafael Dourado Bastos de Oliveira | product, gateway, account, auth | Autorização (RBAC no gateway) |

A divisão acima reflete os autores dos commits em cada repositório.

## Repositórios

Cada microsserviço tem um repositório de **contrato** (interface Feign + DTOs) e
um de **implementação**, incluídos como submódulos neste repositório principal.

| Serviço | Contrato | Implementação |
| --- | --- | --- |
| Account | [account](https://github.com/organizacao-do-sucesso/account) | [account-service](https://github.com/organizacao-do-sucesso/account-service) |
| Auth | [auth](https://github.com/organizacao-do-sucesso/auth) | [auth-service](https://github.com/organizacao-do-sucesso/auth-service) |
| Product | [product](https://github.com/organizacao-do-sucesso/product) | [product-service](https://github.com/organizacao-do-sucesso/product-service) |
| Order | [order](https://github.com/organizacao-do-sucesso/order) | [order-service](https://github.com/organizacao-do-sucesso/order-service) |
| Exchange | [exchange](https://github.com/organizacao-do-sucesso/exchange) | [exchange-service](https://github.com/organizacao-do-sucesso/exchange-service) (Python) |
| Gateway | — | [gateway-service](https://github.com/organizacao-do-sucesso/gateway-service) |
| Observabilidade | — | [observability](https://github.com/organizacao-do-sucesso/observability) |
| Plataforma | — | [platform](https://github.com/organizacao-do-sucesso/platform) (este repositório) |

## Entregas

| Entrega | Situação | Onde |
| --- | --- | --- |
| Exercícios individuais (Product, Order, Exchange, Jenkins, MiniKube, Bottlenecks) | :material-check: documentados | [Exercícios individuais](exercicios/index.md) |
| Microsserviços (account, auth, product, order, exchange, gateway) | :material-check: concluído | [Microsserviços](microsservicos.md) |
| Bottlenecks | :material-check: concluído | [Bottlenecks](bottlenecks.md) |
| Kubernetes local (MiniKube) | :material-check: manifests prontos (falta o vídeo) | [MiniKube](deploy/minikube.md) |
| AWS e EKS, com RDS | :material-check: guia e manifests prontos | [AWS e EKS](deploy/aws.md) |
| CI/CD com Jenkins | :material-progress-clock: em andamento | [CI/CD](deploy/ci-cd.md) |
| Testes de ponta a ponta (21 cenários) | :material-check: concluído | [Testes](testes.md) |
| Teste de carga com HPA | :material-progress-clock: pendente | [Teste de carga](testes-de-carga.md) |
| Custos, PaaS e SLA | :material-check: concluído | [Custos, PaaS e SLA](custos/index.md) |
| Apresentação (vídeo de 1 a 2 min) | :material-progress-clock: pendente | — |
| Uso de IA declarado | :material-check: concluído | [Uso de IA](uso-de-ia.md) |

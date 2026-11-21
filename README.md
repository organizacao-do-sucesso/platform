# Store Platform

Plataforma de e-commerce em microsserviços desenvolvida para a disciplina
**Plataformas, Microsserviços e APIs** do Insper (2026.2). Permite cadastrar
usuários, autenticar, gerenciar produtos e criar pedidos com conversão de
moedas, sempre por uma única entrada protegida por papéis e permissões.

A aplicação é conteinerizada, executa localmente ou no Amazon EKS com RDS,
possui CI/CD com Jenkins, escalonamento com HPA e observabilidade com
Prometheus, Loki e Grafana.

## Links

| Recurso | Link |
| --- | --- |
| Documentação completa | [organizacao-do-sucesso.github.io/platform](https://organizacao-do-sucesso.github.io/platform/) |
| Vídeo de apresentação e teste de carga | [YouTube](https://youtu.be/mIeXadebfQ0) |
| Imagens dos microsserviços | [Docker Hub — `rafaeldbo`](https://hub.docker.com/u/rafaeldbo) |
| Deploy na AWS | [Link](http://k8s-store-gatewayp-44069d17b3-860581f701ba188b.elb.us-east-1.amazonaws.com) |

OBS.: O link do deploy na AWS acima é o link funcional no momento da entrega do projeto (20/11/2026), podendo estar indisponível no futuro.

## Serviços e observabilidade

| Serviço | Responsabilidade | Diferencial |
| --- | --- | --- |
| [Gateway](https://github.com/organizacao-do-sucesso/gateway-service) | Entrada única e roteamento das APIs | Centraliza autenticação e RBAC, injeta a identidade do usuário e protege o acesso ao Prometheus |
| [Auth](https://github.com/organizacao-do-sucesso/auth-service) | Cadastro, login e resolução de tokens | Serviço sem banco próprio; assina JWTs e consulta papéis atualizados no Account |
| [Account](https://github.com/organizacao-do-sucesso/account-service) | Contas, senhas e papéis | Hash de senha, administrador inicial e troca de papéis com efeito imediato |
| [Product](https://github.com/organizacao-do-sucesso/product-service) | Catálogo de produtos | Validação de preço e unidade, persistência com Flyway e controle de escrita por permissão |
| [Order](https://github.com/organizacao-do-sucesso/order-service) | Pedidos e cálculo de totais | Integra Product e Exchange, preserva o preço do item e oferece conversão de moeda na leitura |
| [Exchange](https://github.com/organizacao-do-sucesso/exchange-service) | Cotação entre moedas | Implementado em Python/FastAPI, consulta a PTAX e mantém cache de cinco minutos no Redis |
| [Observability](https://github.com/organizacao-do-sucesso/observability) | Métricas, logs e dashboards da plataforma | Integra Prometheus, Loki, Alloy e Grafana, com descoberta no Kubernetes e painéis de serviços e autoscaling |

## Integrantes

| Integrante | Principais frentes |
| --- | --- |
| Luca Cazzolato Machado | Exchange, caching e custos |
| Luísa Carvalho Farah | Order, observabilidade e ducumentação |
| Rafael Dourado Bastos de Oliveira | Product, autorização (RBAC), infraestrutura Kubernetes/AWS e teste de carga |

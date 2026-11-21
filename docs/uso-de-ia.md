# Uso de IA

A disciplina permite IA para código repetitivo, sugestões de melhoria e correção
de erros, desde que o uso seja declarado e que todos entendam o resultado. Cada
integrante registra abaixo o que fez com apoio de IA.

## Luísa Carvalho Farah

Ferramenta: Claude (Anthropic).

| Parte | Com IA | Revisão feita pela integrante |
| --- | --- | --- |
| order-service: integração com os contratos `product` e `exchange`, `ProductClient` e `ExchangeClient` | Implementação sugerida a partir do feedback do grupo | Build local, testes de ponta a ponta e revisão do diff |
| Observabilidade: repositório `observability` (Compose e Kubernetes), dashboard do Grafana, métricas do order-service | Implementação | Execução da stack, validação no Grafana e no Prometheus |
| Exposição de Grafana e Prometheus pelo gateway, restrição do Prometheus ao papel `administrator` | Implementação | Testes `401`/`403` pelo gateway |
| Manifests Kubernetes do order-service e da observabilidade, integração no `platform` | Implementação | Renderização com Kustomize e validação de schema |
| Script de testes de ponta a ponta (21 cenários) | Implementação | Execução local |
| Esta documentação (MkDocs) | Redação inicial | Leitura e correção do conteúdo |

## Luca Cazzolato Machado

| Parte | Com IA | Revisão feita pelo integrante |
| --- | --- | --- |
| Custos, PaaS e SLA: consultas ao Cost Explorer, estimativas na Pricing Calculator, scripts e rascunho da página | Levantamento de dados, scripts e redação inicial | Números conferidos no Cost Explorer, SLAs nas páginas oficiais da AWS, texto revisado |

Detalhes na seção *Uso de IA* de [Custos, PaaS e SLA](custos/index.md#uso-de-ia).

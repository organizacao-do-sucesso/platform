# Uso de IA

A disciplina permite IA para código repetitivo, sugestões de melhoria e correção
de erros, desde que o uso seja declarado e que todos entendam o resultado. Cada
integrante registra abaixo o que fez com apoio de IA.

## Rafael Dourado Bastos de Oliveira

Ferramenta: Codex (OpenAI).

| Parte | Com IA | Condução e revisão pelo integrante |
| --- | --- | --- |
| Organização da configuração Kubernetes com Kustomize, bases remotas e overlays para Minikube e AWS | Análise da estrutura existente, propostas de organização, ajustes em manifests e scripts de deploy | Definição dos limites entre configuração Kubernetes e configuração dos serviços, rejeição de alternativas inadequadas e aprovação da estrutura final após renderizar os overlays |
| Gerenciamento de Secrets para execução local e Kubernetes | Proposta e implementação dos scripts de validação e aplicação, além da documentação do fluxo | Definição de que os valores permaneceriam locais e fora do Git, orientação sobre a organização dos arquivos e conferência dos Secrets aplicados ao cluster |
| Configuração do Amazon EKS, RDS PostgreSQL, HPA do gateway e Cluster Autoscaler | Apoio na preparação dos comandos, análise do estado dos recursos e diagnóstico de problemas | Escolha das soluções de infraestrutura, definição do que deveria ser independente, autorização das operações na AWS e acompanhamento dos rollouts e testes no cluster |
| Exposição do Grafana e do Prometheus pelo gateway | Diagnóstico do erro de origem, análise do encaminhamento de cabeçalhos e implementação da configuração `PreserveHostHeader` | Definição de que o acesso deveria ocorrer pelo próprio gateway e sem URL fixa da AWS, delimitação da correção a `PreserveHostHeader` e validação das rotas |
| Observabilidade com Prometheus, Grafana, Loki, Alloy e kube-state-metrics | Apoio na integração dos componentes, configuração das coletas e criação do dashboard de autoscaling do gateway | Definição do escopo de observabilidade, orientação sobre a localização das configurações, aprovação dos componentes necessários e validação das métricas, logs e dashboards |
| Dashboard de HPA e Cluster Autoscaler | Elaboração das consultas PromQL, configuração dos painéis e diagnóstico de lacunas nas séries temporais | Definição das informações que deveriam ser exibidas, escolha da estratégia para corrigir séries descontínuas e condução dos testes de carga e escalonamento |
| Collection do Postman e testes dos serviços | Reorganização das requisições, criação de testes automáticos e preparação de uma sequência simples de demonstração | Definição dos endpoints e do fluxo de apresentação, retirada do conteúdo de observabilidade da collection e execução dos testes contra o ambiente na AWS |

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

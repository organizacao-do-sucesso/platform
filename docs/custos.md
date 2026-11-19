# Custos e PaaS

!!! warning "Pendente"
    O plano de custos ainda não foi calculado. A tabela lista os recursos que a
    plataforma usa na AWS, conforme o guia [AWS e EKS](deploy/aws.md), para
    serem estimados na [AWS Pricing Calculator](https://calculator.aws/).

## Recursos cobrados

| Recurso | Configuração | Custo mensal estimado |
| --- | --- | --- |
| EKS (control plane) | 1 cluster `eks-store` | a calcular |
| EC2 (managed node group) | `t2.small`, de 1 a 10 nodes (2 iniciais) | a calcular |
| RDS for PostgreSQL | `db.t4g.micro`, Single-AZ, 20 GiB gp3 | a calcular |
| NAT Gateway | 2 (um por zona) | a calcular |
| Network Load Balancer | 1, gateway público | a calcular |
| **Total** | | a calcular |

O guia de AWS alerta que NAT Gateways, EKS, nodes, RDS e NLB são cobrados
enquanto existirem, e traz na seção 15 o procedimento para remover tudo.

## Onde usamos PaaS

| Serviço gerenciado | Uso no projeto | O que deixamos de operar |
| --- | --- | --- |
| Amazon EKS | Control plane do Kubernetes | Servidores de API, etcd e atualizações do Kubernetes |
| Amazon RDS | Banco de account, product e order | Instalação, backups e patches do PostgreSQL |
| Elastic Load Balancing (NLB) | Exposição pública do gateway | Balanceadores próprios |
| Docker Hub | Registro das imagens | Registro de imagens próprio |

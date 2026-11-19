# Kubernetes da Store

Esta pasta contém os manifestos compartilhados, scripts de implantação e guias
para executar account, auth, product, exchange, order, gateway e a stack de
observabilidade (Prometheus, Loki, Alloy e Grafana) no namespace Kubernetes `store`.
No Minikube, o PostgreSQL também executa no cluster; na AWS, os serviços usam
uma instância privada do Amazon RDS.

## Conteúdo

- [`base`](base): reúne namespace, PostgreSQL e as bases Kubernetes remotas dos
  microsserviços.
- [`overlays/minikube`](overlays/minikube): imagens locais e exposição
  `NodePort` para o Minikube.
- [`overlays/aws`](overlays/aws): imagens do Docker Hub, conexão privada com o
  RDS e manifesto opcional do gateway público.
- [`scripts/build-images.ps1`](../scripts/build-images.ps1): compila os projetos e
  constrói as imagens locais dentro do Minikube.
- [`scripts/apply-secrets.ps1`](scripts/apply-secrets.ps1): valida os arquivos
  locais ignorados pelo Git e cria ou atualiza os Secrets do namespace `store`.
- [`scripts/deploy-minikube.ps1`](scripts/deploy-minikube.ps1): aplica o overlay
  local e aguarda todos os Deployments.
- [`scripts/deploy-aws.ps1`](scripts/deploy-aws.ps1): aplica o overlay do EKS e
  acompanha todos os Deployments na AWS.
- [`minikube.md`](minikube.md): tutorial de construção, implantação, acesso,
  diagnóstico e remoção no Minikube.
- [`AWS.md`](AWS.md): tutorial completo de criação do ambiente AWS/EKS,
  configuração independente do escalonamento de nodes e do HPA opcional do
  gateway, publicação do gateway e remoção dos recursos cobrados.

Os manifestos próprios de cada microsserviço ficam no diretório `k8s` de seu
repositório. O arquivo `base/kustomization.yaml` consome essas bases diretamente
do branch `main` no GitHub e as reúne com os recursos compartilhados. Cada
overlay contém somente as diferenças do ambiente correspondente.

Por isso, o deploy exige acesso à internet, mas não exige inicializar os
submódulos. Basta clonar o repositório `platform`; o Kustomize baixa as bases
remotas durante o build. O parâmetro `submodules=false` evita baixar os
submódulos internos dos serviços, pois eles não são necessários para renderizar
os manifests. Para uma release imutável, substitua `ref=main` por uma tag nos
recursos remotos.

## Escalonamento na AWS

O [`AWS.md`](AWS.md) mantém duas configurações independentes:

### Nodes do cluster

A seção 9 configura o Cluster Autoscaler para aumentar ou reduzir os nodes do
managed node group. Essa é uma configuração do cluster, atende a todas as
cargas e não depende do HPA do gateway.

### Pods do gateway

A seção 11 configura, opcionalmente, o Metrics Server e o HPA do gateway. O HPA
altera somente a quantidade de Pods do Deployment `gateway` e pode funcionar
sem o Cluster Autoscaler, enquanto houver capacidade nos nodes existentes. O
Cluster Autoscaler também pode funcionar sem esse HPA.

O repositório `gateway-service` declara `requests.cpu: 100m` no Deployment do
gateway, usado pelo HPA para calcular a utilização percentual. O HPA não é
necessário para implantar ou executar o gateway.

O `deploy-aws.ps1` não instala o Cluster Autoscaler, o Metrics Server ou o HPA,
e nenhum deles faz parte dos manifests do Kustomize. Cada configuração deve ser
aplicada somente quando desejada, seguindo sua seção no [`AWS.md`](AWS.md).

## Banco de dados na AWS

A seção 8 de [`AWS.md`](AWS.md) cria um RDS for PostgreSQL Single-AZ
`db.t4g.micro`, privado e criptografado. O overlay AWS gera `rds-secret` a
partir do arquivo ignorado `api/.secrets/rds.env` e o injeta somente em
`account` e `product`.

O endpoint do RDS não é versionado. Depois de criar ou reconstruir a instância,
atualize `DATABASE_HOST` no arquivo local antes de executar `deploy-aws.ps1`.
O usuário e a senha mestre são gerenciados pelo AWS Secrets Manager e copiados
para esse arquivo local sem serem exibidos no terminal.
O PostgreSQL definido em `base/postgres.yaml` permanece disponível no Minikube
e, temporariamente, no overlay AWS para os serviços ainda não migrados. Por
isso, a migração de `account` e `product` não interrompe esses serviços.

Ao preparar uma release, inclua as alterações deste guia e do README no commit
da plataforma e confirme que a referência versionada do `gateway-service`
aponta para um commit que contenha o request de CPU. Alterações presentes apenas
no diretório de trabalho não acompanham um novo clone do repositório.

## Secrets locais

Os manifests versionados contêm somente referências a Secrets. Os valores ficam
em `api/.secrets`, que é ignorado pelo Git. Para preparar um clone novo:

```powershell
New-Item -ItemType Directory -Force api/.secrets | Out-Null
Copy-Item api/.secrets.example/*.env api/.secrets/
```

No overlay AWS, `rds.env` precisa conter o endpoint privado retornado pelo RDS.
O Kustomize usa esse arquivo para gerar `rds-secret`; o script de deploy rejeita
o valor de exemplo `CHANGE_ME_RDS_ENDPOINT`.

Os scripts de deploy interrompem a execução se algum arquivo, chave ou valor obrigatório estiver ausente. Antes de
aplicar o Kustomize, eles executam `scripts/apply-secrets.ps1`, que cria ou
atualiza `postgres-secret`, `auth-secret`, `account-secret` e `product-secret`
no namespace `store`.

Valide os arquivos locais sem acessar nenhum cluster:

```powershell
./k8s/scripts/apply-secrets.ps1 -ValidateOnly
```

## Observabilidade

A base também consome o repositório `observability`, cuja `kustomization.yaml`
fica na raiz para reaproveitar as mesmas configurações do Docker Compose (Loki,
datasources e dashboard do Grafana). Ela cria no namespace `store`:

- **Prometheus**, que descobre pela API do Kubernetes os pods anotados com
  `prometheus.io/scrape: "true"` (hoje, o `order`);
- **Alloy**, que envia ao Loki os logs de todos os pods do namespace;
- **Loki** e **Grafana**, com o dashboard *Store - Services* provisionado.

Nada disso é exposto diretamente: o gateway encaminha `/grafana/**` (rota
pública, protegida pelo login do Grafana) e `/prometheus/**` (exige login da
loja com o papel `administrator`). O `grafana-secret` vem de
`api/.secrets/grafana.env`; troque a senha de exemplo antes do deploy.

Na AWS, ajuste `OBSERVABILITY_PUBLIC_URL` no ConfigMap `observability-config`
para o endereço público do gateway, usado pelo Grafana e pelo Prometheus para
montar links e redirecionamentos.

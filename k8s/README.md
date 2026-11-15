# Kubernetes da Store

Esta pasta contém os manifestos compartilhados, scripts de implantação e guias
para executar PostgreSQL, account, auth, product e gateway no namespace
Kubernetes `store`.

## Conteúdo

- [`base`](base): reúne namespace, PostgreSQL e as bases Kubernetes remotas dos
  microsserviços.
- [`overlays/minikube`](overlays/minikube): imagens locais e exposição
  `NodePort` para o Minikube.
- [`overlays/aws`](overlays/aws): imagens do Docker Hub, PostgreSQL efêmero e
  manifesto opcional do gateway público.
- [`scripts/build-images.ps1`](../scripts/build-images.ps1): compila os projetos e
  constrói as imagens locais dentro do Minikube.
- [`scripts/apply-secrets.ps1`](scripts/apply-secrets.ps1): valida os arquivos
  locais ignorados pelo Git e cria ou atualiza os Secrets do namespace `store`.
- [`scripts/deploy-minikube.ps1`](scripts/deploy-minikube.ps1): aplica o overlay
  local e aguarda os cinco Deployments.
- [`scripts/deploy-aws.ps1`](scripts/deploy-aws.ps1): aplica o overlay do EKS e
  acompanha os cinco Deployments na AWS.
- [`minikube.md`](minikube.md): tutorial de construção, implantação, acesso,
  diagnóstico e remoção no Minikube.
- [`AWS.md`](AWS.md): tutorial completo de criação do ambiente AWS/EKS,
  publicação do gateway e remoção dos recursos cobrados.

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

## Secrets locais

Os manifests versionados contêm somente referências a Secrets. Os valores ficam
em `api/.secrets`, que é ignorado pelo Git. Para preparar um clone novo:

```powershell
New-Item -ItemType Directory -Force api/.secrets | Out-Null
Copy-Item api/.secrets.example/*.env api/.secrets/
```

Os scripts de deploy interrompem a execução se algum arquivo, chave ou valor obrigatório estiver ausente. Antes de
aplicar o Kustomize, eles executam `scripts/apply-secrets.ps1`, que cria ou
atualiza `postgres-secret`, `auth-secret`, `account-secret` e `product-secret`
no namespace `store`.

Valide os arquivos locais sem acessar nenhum cluster:

```powershell
./k8s/scripts/apply-secrets.ps1 -ValidateOnly
```

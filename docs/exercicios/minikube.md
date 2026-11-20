# MiniKube

*Responsáveis: Rafael Dourado Bastos de Oliveira (base, overlays e scripts);
cada integrante no `k8s/` do seu serviço · guia completo em
[MiniKube](../deploy/minikube.md)*

## O que o enunciado pede

| Requisito | Como foi atendido |
| --- | --- |
| Uma pasta `k8s` com um `k8s.yaml` por microsserviço | account, auth, product, order, exchange e gateway têm `k8s/k8s.yaml` |
| `Secret`, `ConfigMap`, `Deployment` e `Service` em cada arquivo | ConfigMap, Deployment e Service no `k8s.yaml`; os **Secrets ficam fora do git** (ver abaixo) |
| Gateway exposto, demais serviços `ClusterIP` | Só o gateway é exposto (`NodePort 30080` no Minikube, NLB na AWS) |
| Todos os serviços no mesmo cluster | Namespace `store`, montado por um único Kustomize |
| Vídeo com os serviços rodando | :material-progress-clock: a gravar |

## Implementação

- **Kustomize em camadas:** cada serviço publica seu `k8s/`; a base em
  `platform/k8s/base` junta tudo com PostgreSQL, Redis e observabilidade, e os
  overlays `minikube` e `aws` mudam só imagens, exposição e banco.
- **Secrets fora do repositório (escolha deliberada):** em vez de `Secret` com
  valores em base64 no `k8s.yaml`, que qualquer um decodifica, os valores ficam
  em `api/.secrets` (ignorado pelo git). O script `apply-secrets.ps1` valida os
  arquivos e cria os Secrets no cluster. Os manifests só referenciam os nomes.
- **Probes e recursos:** todos os Deployments têm `startupProbe`,
  `readinessProbe`, `livenessProbe` e `requests`/`limits`.
- **Imagens locais:** `build-images.ps1` constrói as imagens dentro do Minikube
  (`store/*:local`, `imagePullPolicy: Never`).

## Como executar

```powershell
./scripts/build-images.ps1
./k8s/scripts/deploy-minikube.ps1
kubectl port-forward -n store service/gateway 8080:8080
```

--8<-- "k8s/minikube.md"

## Decisões de projeto

- **Kustomize em camadas:** cada serviço publica seu `k8s/`; a base em
  `k8s/base` junta tudo com Redis e observabilidade, e os overlays `minikube` e
  `aws` mudam só imagens, exposição e banco. Só o gateway é exposto
  (`NodePort 30080` no Minikube, NLB na AWS); os demais são `ClusterIP`.
- **Secrets fora do repositório:** em vez de `Secret` com valores em base64 no
  `k8s.yaml`, que qualquer um decodifica, os valores ficam em `api/.secrets`
  (ignorado pelo git). O script `apply-secrets.ps1` valida os arquivos e cria os
  Secrets no cluster. Os manifests só referenciam os nomes.
- **Probes e recursos:** todos os Deployments têm `startupProbe`,
  `readinessProbe`, `livenessProbe` e `requests`/`limits`.

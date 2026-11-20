# Teste de carga

O teste de carga foi gravado no vídeo de apresentação do projeto:

<div style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;">
  <iframe src="https://www.youtube.com/embed/mIeXadebfQ0" title="Store: demonstração e teste de carga"
    style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
    allowfullscreen></iframe>
</div>

[Assistir no YouTube](https://youtu.be/mIeXadebfQ0){ target="_blank" }

## O que é pedido

Um vídeo mostrando um teste de carga contra o gateway no EKS e o
*Horizontal Pod Autoscaler* (HPA) aumentando o número de pods em resposta.

## Preparação

- O gateway declara `requests.cpu: 100m`, base do cálculo de utilização do HPA.
- A seção 11 de [AWS e EKS](deploy/aws.md) instala o Metrics Server e cria o HPA
  do gateway (CPU a 50%, de 1 a 10 réplicas).
- O Cluster Autoscaler (seção 9) adiciona nodes quando faltar capacidade para os
  novos pods.
- O dashboard *Store - Services* no Grafana mostra requisições por segundo,
  latência p95 e erros durante o teste.
- [Custos, PaaS e SLA](custos/index.md) estima quanto custa levar o node group ao
  máximo durante o teste.

## Roteiro

```bash
# terminal 1: acompanhar o HPA
kubectl get hpa gateway -n store --watch

# terminal 2: acompanhar os pods
kubectl get pods -n store -l app=gateway --watch

# terminal 3: gerar carga contra o gateway
kubectl run load -n store --rm -it --image=busybox:1.36 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://gateway:8080/health-check > /dev/null; done"
```


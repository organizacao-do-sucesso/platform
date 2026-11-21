# Teste de carga

O teste aplica carga ao gateway no Amazon EKS para demonstrar o escalonamento
horizontal da aplicação. O HPA aumenta a quantidade de Pods quando a utilização
média de CPU ultrapassa o alvo e a reduz novamente depois que a carga termina.

## Resultado registrado

O vídeo apresenta o gerador em execução e o HPA aumentando as réplicas do
gateway:

<div style="position:relative;padding-bottom:56.25%;height:0;overflow:hidden;">
  <iframe src="https://www.youtube.com/embed/mIeXadebfQ0" title="Store: demonstração e teste de carga"
    style="position:absolute;top:0;left:0;width:100%;height:100%;border:0;"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
    allowfullscreen></iframe>
</div>

[Assistir no YouTube](https://youtu.be/mIeXadebfQ0){ target="_blank" }

## Configuração utilizada

| Item | Configuração |
| --- | --- |
| Alvo | `deployment/gateway`, endpoint `/health-check` |
| CPU solicitada pelo gateway | `100m` por Pod |
| HPA | alvo de 50% de CPU, mínimo de 1 e máximo de 10 réplicas |
| Gerador de carga | BusyBox executado como Pod no namespace `store` |
| Monitoramento | `kubectl` e dashboard *Gateway - Autoscaling* no Grafana |

O HPA e o Cluster Autoscaler atuam em níveis diferentes. O HPA altera a
quantidade de Pods do gateway. O Cluster Autoscaler só adiciona nodes quando
novos Pods não podem ser agendados por falta de capacidade no cluster.

## Preparação

O procedimento pressupõe que o Metrics Server, o HPA e o Cluster Autoscaler já
tenham sido configurados conforme o guia de [AWS e EKS](deploy/aws.md). Antes do
teste, confirme o estado dos componentes:

```powershell
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get hpa gateway --namespace store
kubectl get deployment gateway --namespace store
kubectl get deployment cluster-autoscaler --namespace kube-system
```

O HPA deve mostrar o alvo `50%`, sem o valor `<unknown>`, e o gateway deve ter
ao menos uma réplica disponível. A CPU solicitada pelo Deployment pode ser
conferida com:

```powershell
kubectl get deployment gateway `
  --namespace store `
  --output jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'
```

## Monitoramento

Abra dois terminais antes de iniciar a carga. No primeiro, acompanhe a decisão
do HPA:

```powershell
kubectl get hpa gateway --namespace store --watch
```

No segundo, acompanhe a criação e a remoção dos Pods:

```powershell
kubectl get pods --namespace store --selector app=gateway --watch
```

Para observar também o escalonamento do cluster, use um terceiro terminal:

```powershell
kubectl get nodes --watch
```

O mesmo comportamento pode ser acompanhado no Grafana, no dashboard
*Gateway - Autoscaling*. Como o endereço do NLB muda quando o cluster é
reconstruído, obtenha a URL atual em vez de mantê-la fixa:

```powershell
$GatewayHost = kubectl get service gateway-public `
  --namespace store `
  --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'

"http://$GatewayHost/grafana/d/gateway-autoscaling/gateway-autoscaling"
```

O dashboard apresenta a utilização e o alvo de CPU do HPA, réplicas atuais e
desejadas, consumo por Pod, estado do Deployment e métricas do Cluster
Autoscaler.

## Executar a carga

Crie um Pod temporário dentro do próprio cluster para enviar uma carga 
de requisições ao gateway. O camando abaixo cria um pod que envia, aproximadamente,
1000 requisições por segundo ao health-check do gateway.

```powershell
kubectl run load-generator `
  --namespace store `
  --rm -i --tty `
  --image=busybox:1.28 `
  --restart=Never `
  -- /bin/sh -c 'while sleep 0.001; do wget -q -O /dev/null http://gateway:8080/health-check; done'
```

Durante o teste, a utilização deve ultrapassar o alvo de 50%. Em seguida, o
campo de réplicas desejadas aumenta e o Deployment cria novos Pods. A mudança
não é instantânea, pois o Metrics Server, o HPA e o scheduler trabalham em
intervalos próprios.

## Encerrar e observar a redução

Pressione `Ctrl+C` no terminal do gerador. A opção `--rm` remove o Pod ao final.
Se a sessão for interrompida antes da remoção, execute:

```powershell
kubectl delete pod load-generator `
  --namespace store `
  --ignore-not-found
```

Depois que a CPU retornar ao nível normal e passar o período de estabilização,
o HPA reduz gradualmente o gateway até o mínimo de uma réplica. O HPA e o
Cluster Autoscaler permanecem instalados; somente o gerador de carga é
descartado.


# Execução local no Minikube

Este conjunto sobe PostgreSQL, account, auth, product e gateway no namespace
`store`. As imagens são compiladas e armazenadas diretamente no Minikube, sem
necessidade de publicação no Docker Hub.

## Pré-requisitos

- Minikube iniciado;
- `kubectl` configurado para o contexto do Minikube;
- Maven e Java disponíveis no terminal.

Confira o contexto antes do deploy:

```powershell
kubectl config current-context
minikube status
```

## Construção das imagens

Na raiz de `platform`:

```powershell
./scripts/build-images.ps1
```

## Deploy

```powershell
./k8s/scripts/deploy-minikube.ps1
```

## Acesso ao gateway

Mantenha este comando em execução:

```powershell
kubectl port-forward -n store service/gateway 8080:8080
```

A API ficará disponível em `http://localhost:8080`.

## Diagnóstico

```powershell
kubectl get all -n store
kubectl get pods -n store
kubectl logs -n store deployment/account
kubectl logs -n store deployment/auth
kubectl logs -n store deployment/product
kubectl logs -n store deployment/gateway
```

Para reaplicar alterações nos manifestos:

```powershell
kubectl apply -k ./k8s/overlays/minikube
```

Para remover os recursos da aplicação, preservando o Minikube:

```powershell
kubectl delete -k ./k8s/overlays/minikube
```

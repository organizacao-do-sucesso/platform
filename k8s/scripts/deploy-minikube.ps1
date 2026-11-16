[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$overlay = Join-Path $repositoryRoot 'k8s\overlays\minikube'

$currentContext = kubectl config current-context
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível consultar o contexto atual do kubectl.'
}

if ($currentContext.Trim() -ne 'minikube') {
    throw "Contexto incorreto: $currentContext. Esperado: minikube"
}

$applySecrets = Join-Path $PSScriptRoot 'apply-secrets.ps1'
& $applySecrets

Write-Host 'Aplicando os recursos no namespace store...' -ForegroundColor Cyan
kubectl apply -k $overlay
if ($LASTEXITCODE -ne 0) {
    throw "Não foi possível aplicar os manifests."
}

foreach ($deployment in @('account', 'auth', 'product', 'exchange', 'gateway')) {
    kubectl rollout restart "deployment/$deployment" -n store
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível reiniciar deployment/$deployment."
    }
}

foreach ($deployment in @('db', 'redis', 'account', 'auth', 'product', 'exchange', 'gateway')) {
    Write-Host "Aguardando deployment/$deployment..." -ForegroundColor Cyan
    kubectl rollout status "deployment/$deployment" -n store --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        kubectl get pods -n store
        throw "O deployment/$deployment não ficou pronto."
    }
}

Write-Host "`nTodos os deployments estão prontos." -ForegroundColor Green
Write-Host 'Para acessar a API em http://localhost:8080, execute:'
Write-Host 'kubectl port-forward -n store service/gateway 8080:8080'

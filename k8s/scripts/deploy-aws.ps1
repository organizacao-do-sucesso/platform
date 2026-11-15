[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$expectedContext = 'arn:aws:eks:us-east-1:891377137095:cluster/eks-store'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$overlay = Join-Path $repositoryRoot 'k8s\overlays\aws'

$currentContext = kubectl config current-context
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível consultar o contexto atual do kubectl.'
}

if ($currentContext.Trim() -ne $expectedContext) {
    throw "Contexto incorreto: $currentContext. Esperado: $expectedContext"
}

$applySecrets = Join-Path $PSScriptRoot 'apply-secrets.ps1'
& $applySecrets

Write-Host 'Aplicando a configuração temporária no EKS...' -ForegroundColor Cyan
kubectl apply -k $overlay
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível aplicar os manifestos no EKS.'
}

foreach ($deployment in @('db', 'account', 'auth', 'product', 'gateway')) {
    Write-Host "Aguardando deployment/$deployment..." -ForegroundColor Cyan
    kubectl rollout status "deployment/$deployment" -n store --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        kubectl get pods -n store -o wide
        kubectl get events -n store --sort-by='.lastTimestamp'
        throw "O deployment/$deployment não ficou pronto."
    }
}

Write-Host "`nAplicação pronta no EKS." -ForegroundColor Green
Write-Host 'Para testar em http://localhost:8080, mantenha em execução:'
Write-Host 'kubectl port-forward -n store service/gateway 8080:8080'

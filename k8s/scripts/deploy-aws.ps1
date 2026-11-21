[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$expectedContext = 'arn:aws:eks:us-east-1:891377137095:cluster/eks-store'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$overlay = Join-Path $repositoryRoot 'k8s\overlays\aws'
$rdsEnvironmentFile = Join-Path $repositoryRoot 'api\.secrets\rds.env'

$currentContext = kubectl config current-context
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível consultar o contexto atual do kubectl.'
}

if ($currentContext.Trim() -ne $expectedContext) {
    throw "Contexto incorreto: $currentContext. Esperado: $expectedContext"
}

if (-not (Test-Path -LiteralPath $rdsEnvironmentFile -PathType Leaf)) {
    throw "Arquivo local ausente: $rdsEnvironmentFile. Copie api/.secrets.example/rds.env e preencha o endpoint do RDS."
}

$rdsValues = @{}
foreach ($line in Get-Content -LiteralPath $rdsEnvironmentFile) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) {
        continue
    }

    $separator = $trimmed.IndexOf('=')
    if ($separator -le 0) {
        throw "Linha inválida em $rdsEnvironmentFile. Use o formato CHAVE=VALOR."
    }

    $key = $trimmed.Substring(0, $separator).Trim()
    $rdsValues[$key] = $trimmed.Substring($separator + 1)
}

foreach ($requiredKey in @(
    'DATABASE_HOST',
    'DATABASE_PORT',
    'DATABASE_DB',
    'DATABASE_USERNAME',
    'DATABASE_PASSWORD'
)) {
    if (-not $rdsValues.ContainsKey($requiredKey) -or
        [string]::IsNullOrWhiteSpace($rdsValues[$requiredKey]) -or
        $rdsValues[$requiredKey].StartsWith('CHANGE_ME')) {
        throw "Preencha $requiredKey em $rdsEnvironmentFile antes do deploy."
    }
}

$applySecrets = Join-Path $PSScriptRoot 'apply-secrets.ps1'
& $applySecrets

Write-Host 'Aplicando a configuração temporária no EKS...' -ForegroundColor Cyan
$rendered = kubectl kustomize $overlay --load-restrictor LoadRestrictionsNone
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível renderizar os manifestos do EKS.'
}

$rendered | kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível aplicar os manifestos no EKS.'
}

foreach ($deployment in @('redis', 'account', 'auth', 'product', 'exchange', 'order', 'gateway', 'prometheus', 'loki', 'alloy', 'grafana', 'kube-state-metrics')) {
    Write-Host "Aguardando deployment/$deployment..." -ForegroundColor Cyan
    kubectl rollout status "deployment/$deployment" -n store --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        kubectl get pods -n store -o wide
        kubectl get events -n store --sort-by='.lastTimestamp'
        throw "O deployment/$deployment não ficou pronto."
    }
}

$gatewayHost = kubectl get service gateway-public `
    --namespace store `
    --ignore-not-found `
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível consultar service/gateway-public.'
}

if ([string]::IsNullOrWhiteSpace($gatewayHost)) {
    Write-Warning 'gateway-public ainda não possui hostname. Execute configure-observability-url.ps1 após criar o NLB.'
} else {
    $configureObservability = Join-Path $PSScriptRoot 'configure-observability-url.ps1'
    & $configureObservability -PublicUrl "http://$($gatewayHost.Trim())"
}

Write-Host "`nAplicação pronta no EKS." -ForegroundColor Green
Write-Host 'Para testar em http://localhost:8080, mantenha em execução:'
Write-Host 'kubectl port-forward -n store service/gateway 8080:8080'

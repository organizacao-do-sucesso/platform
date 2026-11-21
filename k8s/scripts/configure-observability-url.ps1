[CmdletBinding()]
param(
    [string] $Namespace = 'store',
    [string] $GatewayService = 'gateway-public',
    [string] $PublicUrl
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PublicUrl)) {
    $gatewayHost = kubectl get service $GatewayService `
        --namespace $Namespace `
        --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível consultar service/$GatewayService no namespace $Namespace."
    }

    if ([string]::IsNullOrWhiteSpace($gatewayHost)) {
        throw "service/$GatewayService ainda não possui hostname público."
    }

    $PublicUrl = "http://$($gatewayHost.Trim())"
}

$PublicUrl = $PublicUrl.TrimEnd('/')
if ($PublicUrl -notmatch '^https?://[^/]+(?::\d+)?$') {
    throw "URL pública inválida: $PublicUrl"
}

$patch = @{
    data = @{
        OBSERVABILITY_PUBLIC_URL = $PublicUrl
    }
} | ConvertTo-Json -Compress

kubectl patch configmap observability-config `
    --namespace $Namespace `
    --type merge `
    --patch $patch
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível atualizar configmap/observability-config.'
}

foreach ($deployment in @('prometheus', 'grafana')) {
    kubectl rollout restart "deployment/$deployment" --namespace $Namespace
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível reiniciar deployment/$deployment."
    }

    kubectl rollout status "deployment/$deployment" `
        --namespace $Namespace `
        --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        throw "deployment/$deployment não ficou pronto após atualizar a URL pública."
    }
}

Write-Host "Observabilidade configurada para $PublicUrl." -ForegroundColor Green

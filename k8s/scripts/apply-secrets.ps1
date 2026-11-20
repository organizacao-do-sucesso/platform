[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$namespaceManifest = Join-Path $repositoryRoot 'k8s\base\namespace.yaml'
$secretsDirectory = Join-Path $repositoryRoot 'api\.secrets'

$secretDefinitions = @(
    [pscustomobject]@{
        Name = 'postgres-secret'
        File = 'postgres.env'
        RequiredKeys = @('POSTGRES_USER', 'POSTGRES_PASSWORD')
    },
    [pscustomobject]@{
        Name = 'auth-secret'
        File = 'auth.env'
        RequiredKeys = @('JWT_SECRET_KEY')
    },
    [pscustomobject]@{
        Name = 'account-secret'
        File = 'account.env'
        RequiredKeys = @('DATABASE_USERNAME', 'DATABASE_PASSWORD', 'ADMIN_PASSWORD')
    },
    [pscustomobject]@{
        Name = 'product-secret'
        File = 'product.env'
        RequiredKeys = @('DATABASE_USERNAME', 'DATABASE_PASSWORD')
    },
    [pscustomobject]@{
        Name = 'order-secret'
        File = 'order.env'
        RequiredKeys = @('DATABASE_USERNAME', 'DATABASE_PASSWORD')
    },
    [pscustomobject]@{
        Name = 'grafana-secret'
        File = 'grafana.env'
        RequiredKeys = @('GF_SECURITY_ADMIN_USER', 'GF_SECURITY_ADMIN_PASSWORD')
    }
)

if (-not $ValidateOnly) {
    kubectl apply -f $namespaceManifest
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível criar ou validar o namespace store.'
    }
}

foreach ($definition in $secretDefinitions) {
    $secretFile = Join-Path $secretsDirectory $definition.File
    if (-not (Test-Path -LiteralPath $secretFile -PathType Leaf)) {
        throw "Arquivo local ausente: $secretFile. Copie api/.secrets.example para api/.secrets e preencha os valores."
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $secretFile) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) {
            throw "Linha inválida em $secretFile. Use o formato CHAVE=VALOR."
        }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1)
        $values[$key] = $value
    }

    foreach ($requiredKey in $definition.RequiredKeys) {
        if (-not $values.ContainsKey($requiredKey) -or
            [string]::IsNullOrWhiteSpace($values[$requiredKey]) -or
            $values[$requiredKey].StartsWith('CHANGE_ME')) {
            throw "Preencha $requiredKey em $secretFile antes do deploy."
        }
    }

    if ($ValidateOnly) {
        Write-Host "Arquivo local válido para $($definition.Name)." -ForegroundColor Green
        continue
    }

    $secretYaml = kubectl create secret generic $definition.Name `
        --namespace store `
        --from-env-file=$secretFile `
        --dry-run=client `
        -o yaml
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível renderizar o Secret $($definition.Name)."
    }

    $secretYaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível aplicar o Secret $($definition.Name)."
    }
}

if ($ValidateOnly) {
    Write-Host 'Todos os arquivos locais de Secrets são válidos.' -ForegroundColor Green
} else {
    Write-Host 'Secrets locais aplicados no namespace store.' -ForegroundColor Green
}

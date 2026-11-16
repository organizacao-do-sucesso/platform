[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$apiRoot = Join-Path $repositoryRoot 'api'

function Invoke-Checked {
    param(
        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter(Mandatory)]
        [scriptblock] $Command
    )

    Write-Host "`n==> $Description" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description falhou com código $LASTEXITCODE."
    }
}

Invoke-Checked 'Instalando contrato account' {
    mvn -B -f (Join-Path $apiRoot 'account/pom.xml') -DskipTests clean install
}
Invoke-Checked 'Empacotando account-service' {
    mvn -B -f (Join-Path $apiRoot 'account-service/pom.xml') -DskipTests clean package
}
Invoke-Checked 'Criando imagem account no Minikube' {
    minikube image build -t store/account:local (Join-Path $apiRoot 'account-service')
}

Invoke-Checked 'Instalando contrato auth' {
    mvn -B -f (Join-Path $apiRoot 'auth/pom.xml') -DskipTests clean install
}
Invoke-Checked 'Empacotando auth-service' {
    mvn -B -f (Join-Path $apiRoot 'auth-service/pom.xml') -DskipTests clean package
}
Invoke-Checked 'Criando imagem auth no Minikube' {
    minikube image build -t store/auth:local (Join-Path $apiRoot 'auth-service')
}

Invoke-Checked 'Instalando contrato product' {
    mvn -B -f (Join-Path $apiRoot 'product/pom.xml') -DskipTests clean install
}
Invoke-Checked 'Empacotando product-service' {
    mvn -B -f (Join-Path $apiRoot 'product-service/pom.xml') -DskipTests clean package
}
Invoke-Checked 'Criando imagem product no Minikube' {
    minikube image build -t store/product:local (Join-Path $apiRoot 'product-service')
}

Invoke-Checked 'Criando imagem exchange no Minikube' {
    minikube image build -t store/exchange:local (Join-Path $apiRoot 'exchange-service')
}

Invoke-Checked 'Empacotando gateway-service' {
    mvn -B -f (Join-Path $apiRoot 'gateway-service/pom.xml') -DskipTests clean package
}
Invoke-Checked 'Criando imagem gateway no Minikube' {
    minikube image build -t store/gateway:local (Join-Path $apiRoot 'gateway-service')
}

Write-Host "`nImagens locais criadas no Minikube." -ForegroundColor Green

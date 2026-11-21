# AWS/EKS pelo AWS CLI: criação, publicação e remoção

Este guia cria na AWS o ambiente necessário para executar os microsserviços
`account`, `auth`, `product`, `exchange`, `order` e `gateway`, com PostgreSQL
gerenciado pelo Amazon RDS. O gateway é publicado na internet por um Network
Load Balancer (NLB).
O último capítulo remove todos os recursos para encerrar a cobrança.

> **Atenção a custos:** a stack de rede cria dois NAT Gateways; o cluster EKS,
> as instâncias EC2 do node group, o RDS e o NLB também são cobrados enquanto
> existirem. Para um teste curto, execute o guia, valide a aplicação e faça a
> remoção completa no mesmo dia.

## 1. Arquitetura criada

- Região: `us-east-1`.
- Perfil local do AWS CLI: `store`.
- Stack CloudFormation: `store-vpc`.
- VPC com duas subnets públicas e duas privadas.
- Dois NAT Gateways, um por zona de disponibilidade.
- Cluster EKS: `eks-store`.
- Managed node group: `default`.
- Managed node group com mínimo de 1, capacidade inicial de 2 e máximo de 10
  nodes EC2 `t2.small` nas subnets privadas.
- Cluster Autoscaler ajustando automaticamente a quantidade de nodes.
- RDS for PostgreSQL Single-AZ `db.t4g.micro`, com 20 GiB de armazenamento gp3
  criptografado e endpoint privado.
- Microsserviços `account`, `auth`, `product`, `exchange`, `order` e `gateway`.
- AWS Load Balancer Controller com EKS Pod Identity.
- NLB público encaminhando a porta 80 para o gateway na porta 8080.

Opcionalmente, a seção 11 instala o Metrics Server e cria um HPA para manter
entre 1 e 10 réplicas do gateway com alvo de 50% de CPU. O HPA não é necessário
para criar o cluster, executar a aplicação ou usar o Cluster Autoscaler.

O overlay AWS conecta `account`, `product` e `order` ao RDS e remove o
PostgreSQL interno. O overlay Minikube continua usando o PostgreSQL definido na
base.

## 2. Pré-requisitos locais

Instale e confirme:

- AWS CLI v2;
- `kubectl`;
- Helm 3;
- PowerShell 7;
- acesso à internet;
- imagens públicas no Docker Hub:
  - `rafaeldbo/account:latest`;
  - `rafaeldbo/auth:latest`;
  - `rafaeldbo/product:latest`;
  - `rafaeldbo/gateway:latest`.

O overlay pressupõe que todas essas imagens estejam públicas.

```powershell
aws --version
kubectl version --client
helm version
```

Execute os comandos a partir da raiz do repositório e mantenha o mesmo
terminal aberto:

```powershell
$Region = 'us-east-1'
$Profile = 'store'
$ClusterName = 'eks-store'
$NodeGroupName = 'default'
$VpcStackName = 'store-vpc'
$ClusterRoleName = 'eks-store-cluster-role'
$NodeRoleName = 'eks-store-node-role'
$RdsIdentifier = 'store-postgres'
$RdsSubnetGroupName = 'store-postgres'
$RdsSecurityGroupName = 'store-postgres'
$CaRoleName = 'eks-store-cluster-autoscaler-role'
$CaPolicyName = 'eks-store-cluster-autoscaler-policy'
$LbcRoleName = 'eks-store-load-balancer-controller-role'
$LbcPolicyName = 'AWSLoadBalancerControllerIAMPolicy'
$AwsGuideTemp = Join-Path $env:TEMP 'store-eks-guide'

New-Item -ItemType Directory -Force -Path $AwsGuideTemp | Out-Null
```

## 3. Configurar o perfil do AWS CLI

Crie uma access key para o usuário IAM do laboratório e configure o perfil.
Não coloque as chaves no repositório.

```powershell
aws configure --profile $Profile
```

Informe a access key, a secret key, a região `us-east-1` e o formato `json`.
Depois confirme a identidade:

```powershell
aws configure list --profile $Profile
$AccountId = aws sts get-caller-identity `
  --query Account --output text --profile $Profile
aws sts get-caller-identity --profile $Profile
```

O usuário executor precisa conseguir administrar CloudFormation, VPC/EC2,
EKS, RDS, ELBv2 e as roles/policies IAM deste guia. Também precisa de
`iam:PassRole` limitado às roles do cluster, dos nodes, do Cluster Autoscaler e
do AWS Load Balancer Controller. A permissão para a role do Cluster Autoscaler
é necessária ao criar sua associação de EKS Pod Identity na seção 9.3. Em
produção, use credenciais temporárias/MFA e uma policy de provisionamento
revisada.

## 4. Criar as roles IAM do EKS

### 4.1. Role do control plane

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "eks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
'@ | Set-Content `
  -Path (Join-Path $AwsGuideTemp 'eks-cluster-trust.json') `
  -Encoding utf8

$ClusterTrustFile = (Join-Path $AwsGuideTemp 'eks-cluster-trust.json').Replace('\', '/')

aws iam create-role `
  --role-name $ClusterRoleName `
  --assume-role-policy-document "file://$ClusterTrustFile" `
  --description 'Role do control plane do cluster eks-store' `
  --profile $Profile

aws iam attach-role-policy `
  --role-name $ClusterRoleName `
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy `
  --profile $Profile
```

### 4.2. Role dos worker nodes

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
'@ | Set-Content `
  -Path (Join-Path $AwsGuideTemp 'eks-node-trust.json') `
  -Encoding utf8

$NodeTrustFile = (Join-Path $AwsGuideTemp 'eks-node-trust.json').Replace('\', '/')

aws iam create-role `
  --role-name $NodeRoleName `
  --assume-role-policy-document "file://$NodeTrustFile" `
  --description 'Role dos nodes EC2 do cluster eks-store' `
  --profile $Profile

$NodePolicies = @(
  'arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy',
  'arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy',
  'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly'
)

foreach ($PolicyArn in $NodePolicies) {
  aws iam attach-role-policy `
    --role-name $NodeRoleName `
    --policy-arn $PolicyArn `
    --profile $Profile
}

aws iam get-role --role-name $ClusterRoleName --profile $Profile
aws iam get-role --role-name $NodeRoleName --profile $Profile
```

Se uma role já existir, não repita o `create-role`; confira sua trust policy e
continue com os anexos necessários.

## 5. Criar a VPC pelo CloudFormation

O template cria duas subnets públicas, duas privadas, Internet Gateway, dois
NAT Gateways, rotas e um security group do control plane.

> **A cobrança dos NAT Gateways começa nesta etapa.**

```powershell
$VpcTemplate = Resolve-Path `
  'site/docs/2026.2/exercises/project/eks/amazon-eks-vpc-private-subnets.yaml'
$VpcTemplateUri = 'file://' + $VpcTemplate.Path.Replace('\', '/')

aws cloudformation create-stack `
  --stack-name $VpcStackName `
  --template-body $VpcTemplateUri `
  --region $Region `
  --profile $Profile

aws cloudformation wait stack-create-complete `
  --stack-name $VpcStackName `
  --region $Region `
  --profile $Profile

aws cloudformation describe-stacks `
  --stack-name $VpcStackName `
  --query 'Stacks[0].StackStatus' `
  --output text `
  --region $Region `
  --profile $Profile
```

O resultado esperado é `CREATE_COMPLETE`. Capture os IDs recém-criados; nunca
reutilize IDs de outra execução:

```powershell
$PublicSubnet01 = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id PublicSubnet01 `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$PublicSubnet02 = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id PublicSubnet02 `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$PrivateSubnet01 = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id PrivateSubnet01 `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$PrivateSubnet02 = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id PrivateSubnet02 `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$ControlPlaneSecurityGroup = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id ControlPlaneSecurityGroup `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$VpcId = aws cloudformation describe-stack-resource `
  --stack-name $VpcStackName --logical-resource-id VPC `
  --query StackResourceDetail.PhysicalResourceId `
  --output text --region $Region --profile $Profile

$AllSubnetIds = @(
  $PublicSubnet01, $PublicSubnet02, $PrivateSubnet01, $PrivateSubnet02
)
$PrivateSubnetIds = @($PrivateSubnet01, $PrivateSubnet02)

$VpcId
$AllSubnetIds
$ControlPlaneSecurityGroup
```

## 6. Criar o cluster EKS

O projeto foi validado com Kubernetes `1.37`. Se essa versão deixar de ser
oferecida em `us-east-1`, use uma versão atualmente suportada.

```powershell
$KubernetesVersion = '1.37'
$ClusterRoleArn = aws iam get-role `
  --role-name $ClusterRoleName --query Role.Arn `
  --output text --profile $Profile

$VpcConfig = "subnetIds=$($AllSubnetIds -join ','),securityGroupIds=$ControlPlaneSecurityGroup,endpointPublicAccess=true,endpointPrivateAccess=false"

aws eks create-cluster `
  --name $ClusterName `
  --version $KubernetesVersion `
  --role-arn $ClusterRoleArn `
  --resources-vpc-config $VpcConfig `
  --access-config authenticationMode=API_AND_CONFIG_MAP,bootstrapClusterCreatorAdminPermissions=true `
  --region $Region `
  --profile $Profile

aws eks wait cluster-active `
  --name $ClusterName `
  --region $Region `
  --profile $Profile

aws eks describe-cluster `
  --name $ClusterName `
  --query 'cluster.{status:status,version:version,vpc:resourcesVpcConfig.vpcId}' `
  --region $Region `
  --profile $Profile
```

> **A cobrança do control plane começa nesta etapa e só termina quando o
> cluster é excluído.**

## 7. Criar o managed node group

Os nodes ficam nas subnets privadas e usam os NAT Gateways para baixar imagens.

```powershell
$NodeRoleArn = aws iam get-role `
  --role-name $NodeRoleName --query Role.Arn `
  --output text --profile $Profile

aws eks create-nodegroup `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --node-role $NodeRoleArn `
  --subnets $PrivateSubnetIds `
  --instance-types t2.small `
  --ami-type AL2023_x86_64_STANDARD `
  --capacity-type ON_DEMAND `
  --disk-size 20 `
  --scaling-config minSize=1,maxSize=10,desiredSize=2 `
  --update-config maxUnavailable=1 `
  --region $Region `
  --profile $Profile

aws eks wait nodegroup-active `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --region $Region `
  --profile $Profile
```

> **A cobrança das instâncias EC2 e de seus volumes começa nesta etapa.**

Configure o `kubectl` e confirme os nodes:

```powershell
aws eks update-kubeconfig `
  --name $ClusterName `
  --region $Region `
  --profile $Profile

kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Somente continue quando os dois nodes estiverem `Ready`.

## 8. Criar o PostgreSQL no Amazon RDS

O RDS fica nas duas subnets privadas, não recebe endereço público e aceita
conexões PostgreSQL somente dos recursos associados ao security group principal
do cluster EKS. O DB subnet group usa duas zonas de disponibilidade, embora a
instância de laboratório seja Single-AZ.

O overlay AWS lê endpoint e credenciais de `api/.secrets/rds.env`. Prepare o
arquivo local; ele será preenchido depois com a senha gerenciada pelo AWS
Secrets Manager:

```powershell
if (-not (Test-Path 'api/.secrets/rds.env')) {
  Copy-Item `
    api/.secrets.example/rds.env `
    api/.secrets/rds.env
}

$RdsEnvironmentFile = Resolve-Path 'api/.secrets/rds.env'
```

Crie o DB subnet group e o security group do banco:

```powershell
aws rds create-db-subnet-group `
  --db-subnet-group-name $RdsSubnetGroupName `
  --db-subnet-group-description 'Subnets privadas do PostgreSQL da Store' `
  --subnet-ids $PrivateSubnetIds `
  --tags Key=Project,Value=store `
  --region $Region `
  --profile $Profile

$ClusterSecurityGroupId = aws eks describe-cluster `
  --name $ClusterName `
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' `
  --output text `
  --region $Region `
  --profile $Profile

$RdsSecurityGroupId = aws ec2 create-security-group `
  --group-name $RdsSecurityGroupName `
  --description 'PostgreSQL privado da Store' `
  --vpc-id $VpcId `
  --query GroupId `
  --output text `
  --region $Region `
  --profile $Profile

aws ec2 create-tags `
  --resources $RdsSecurityGroupId `
  --tags Key=Name,Value=$RdsSecurityGroupName Key=Project,Value=store `
  --region $Region `
  --profile $Profile

aws ec2 authorize-security-group-ingress `
  --group-id $RdsSecurityGroupId `
  --protocol tcp `
  --port 5432 `
  --source-group $ClusterSecurityGroupId `
  --region $Region `
  --profile $Profile
```

Consulte a versão PostgreSQL mais recente oferecida para a classe correta,
`db.t4g.micro`, e crie a instância:

```powershell
$RdsOptions = aws rds describe-orderable-db-instance-options `
  --engine postgres `
  --db-instance-class db.t4g.micro `
  --region $Region `
  --profile $Profile | ConvertFrom-Json

$RdsEngineVersion = $RdsOptions.OrderableDBInstanceOptions.EngineVersion | `
  Sort-Object { [version](($_ -replace '-.*$', '')) } -Descending | `
  Select-Object -First 1

aws rds create-db-instance `
  --db-instance-identifier $RdsIdentifier `
  --db-name store `
  --db-instance-class db.t4g.micro `
  --engine postgres `
  --engine-version $RdsEngineVersion `
  --master-username storeapp `
  --manage-master-user-password `
  --allocated-storage 20 `
  --storage-type gp3 `
  --storage-encrypted `
  --db-subnet-group-name $RdsSubnetGroupName `
  --vpc-security-group-ids $RdsSecurityGroupId `
  --port 5432 `
  --backup-retention-period 1 `
  --no-publicly-accessible `
  --no-multi-az `
  --auto-minor-version-upgrade `
  --enable-performance-insights `
  --performance-insights-retention-period 7 `
  --enable-cloudwatch-logs-exports postgresql `
  --copy-tags-to-snapshot `
  --tags Key=Project,Value=store Key=created_by,Value=rds-oss-skill Key=generation_model,Value=gpt-5 `
  --region $Region `
  --profile $Profile

aws rds wait db-instance-available `
  --db-instance-identifier $RdsIdentifier `
  --region $Region `
  --profile $Profile
```

Capture o endpoint privado e a referência da senha gerenciada. Grave os dados
somente no arquivo local ignorado pelo Git, sem imprimir a senha:

```powershell
$RdsInstance = aws rds describe-db-instances `
  --db-instance-identifier $RdsIdentifier `
  --query 'DBInstances[0].{Endpoint:Endpoint.Address,Port:Endpoint.Port,SecretArn:MasterUserSecret.SecretArn}' `
  --region $Region `
  --profile $Profile | ConvertFrom-Json

$RdsCredential = aws secretsmanager get-secret-value `
  --secret-id $RdsInstance.SecretArn `
  --query SecretString `
  --output text `
  --region $Region `
  --profile $Profile | ConvertFrom-Json

$RdsEnvironment = @(
  "DATABASE_HOST=$($RdsInstance.Endpoint)"
  "DATABASE_PORT=$($RdsInstance.Port)"
  'DATABASE_DB=store'
  "DATABASE_USERNAME=$($RdsCredential.username)"
  "DATABASE_PASSWORD=$($RdsCredential.password)"
)

[System.IO.File]::WriteAllLines(
  $RdsEnvironmentFile,
  $RdsEnvironment,
  [System.Text.UTF8Encoding]::new($false)
)

$RdsInstance.Endpoint
Remove-Variable RdsCredential, RdsEnvironment
```

O endpoint não deve ser colocado em manifests versionados porque muda quando a
instância é reconstruída. O Kustomize gera `rds-secret` a partir desse arquivo
e o injeta em `account` e `product`.

> **A cobrança do RDS começa quando a instância é provisionada e continua até
> ela ser excluída. Parar a instância não interrompe a cobrança do
> armazenamento.**

## 9. Ativar o escalonamento de nodes do cluster

O Cluster Autoscaler aumenta ou reduz os nodes do managed node group quando há
Pods sem capacidade para serem agendados ou nodes subutilizados. Ele atende ao
cluster inteiro e não depende do HPA do gateway.

O `maxSize=10` configurado no node group é apenas um limite. É o Cluster
Autoscaler que altera a capacidade desejada dentro dos limites `minSize` e
`maxSize`.

### Responsabilidade do guia e do script de deploy

O Cluster Autoscaler não faz parte do overlay `k8s/overlays/aws`. O script
`k8s/scripts/deploy-aws.ps1` aplica os Secrets e os recursos da aplicação, mas
não instala o Cluster Autoscaler. Essa separação evita que um deploy da
aplicação tente recriar recursos e permissões que pertencem ao ciclo de vida do
cluster.

Em um cluster novo, execute as seções 9.1 a 9.3 uma vez. Em atualizações comuns
da aplicação, o Cluster Autoscaler permanece instalado. Se o cluster for
reconstruído, repita toda a seção 9.

### 9.1. Instalar o EKS Pod Identity Agent

O Cluster Autoscaler e o AWS Load Balancer Controller usam EKS Pod Identity,
sem access keys dentro dos Pods:

```powershell
aws eks create-addon `
  --cluster-name $ClusterName `
  --addon-name eks-pod-identity-agent `
  --region $Region `
  --profile $Profile

do {
  Start-Sleep -Seconds 10
  $PodIdentityStatus = aws eks describe-addon `
    --cluster-name $ClusterName `
    --addon-name eks-pod-identity-agent `
    --query addon.status --output text `
    --region $Region --profile $Profile
  Write-Host "Pod Identity Agent: $PodIdentityStatus"
} until ($PodIdentityStatus -in @('ACTIVE', 'CREATE_FAILED', 'DEGRADED'))

if ($PodIdentityStatus -ne 'ACTIVE') {
  throw "EKS Pod Identity Agent não ficou ACTIVE: $PodIdentityStatus"
}
```

### 9.2. Criar a policy e a role do Cluster Autoscaler

A policy limita as operações de escrita aos Auto Scaling Groups identificados
pelas tags do cluster. As operações de leitura permanecem globais porque as
APIs de consulta não oferecem escopo por recurso:

```powershell
$CaPolicyFile = Join-Path $AwsGuideTemp 'cluster-autoscaler-policy.json'

@"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true",
          "aws:ResourceTag/k8s.io/cluster-autoscaler/$ClusterName": "owned"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": "*"
    }
  ]
}
"@ | Set-Content -Path $CaPolicyFile -Encoding utf8

$CaPolicyUri = 'file://' + $CaPolicyFile.Replace('\', '/')
$CaPolicyArn = aws iam create-policy `
  --policy-name $CaPolicyName `
  --policy-document $CaPolicyUri `
  --query Policy.Arn --output text `
  --profile $Profile
```

Crie uma role de Pod Identity restrita ao ServiceAccount do autoscaler:

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowEksAuthToAssumeRoleForPodIdentity",
    "Effect": "Allow",
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession"],
    "Condition": {
      "StringEquals": {
        "aws:RequestTag/kubernetes-namespace": "kube-system",
        "aws:RequestTag/kubernetes-service-account": "cluster-autoscaler"
      }
    }
  }]
}
'@ | Set-Content `
  -Path (Join-Path $AwsGuideTemp 'cluster-autoscaler-pod-identity-trust.json') `
  -Encoding utf8

$CaTrustFile = (Join-Path $AwsGuideTemp 'cluster-autoscaler-pod-identity-trust.json').Replace('\', '/')

aws iam create-role `
  --role-name $CaRoleName `
  --assume-role-policy-document "file://$CaTrustFile" `
  --description 'EKS Pod Identity do Cluster Autoscaler' `
  --profile $Profile

aws iam attach-role-policy `
  --role-name $CaRoleName `
  --policy-arn $CaPolicyArn `
  --profile $Profile

$CaRoleArn = aws iam get-role `
  --role-name $CaRoleName --query Role.Arn `
  --output text --profile $Profile
```

### 9.3. Instalar o Cluster Autoscaler

A versão do Cluster Autoscaler deve acompanhar a versão minor do Kubernetes.
O chart usa autodiscovery para localizar o managed node group pelas tags do
cluster:

```powershell
kubectl create serviceaccount cluster-autoscaler `
  --namespace kube-system `
  --dry-run=client -o yaml | kubectl apply -f -

aws eks create-pod-identity-association `
  --cluster-name $ClusterName `
  --namespace kube-system `
  --service-account cluster-autoscaler `
  --role-arn $CaRoleArn `
  --region $Region `
  --profile $Profile

helm repo add autoscaler https://kubernetes.github.io/autoscaler --force-update
helm repo update autoscaler

helm upgrade --install cluster-autoscaler `
  autoscaler/cluster-autoscaler `
  --namespace kube-system `
  --set cloudProvider=aws `
  --set awsRegion=$Region `
  --set autoDiscovery.clusterName=$ClusterName `
  --set image.tag=v1.37.0 `
  --set rbac.serviceAccount.create=false `
  --set rbac.serviceAccount.name=cluster-autoscaler `
  --set resources.requests.cpu=100m `
  --set resources.requests.memory=300Mi `
  --set resources.limits.memory=500Mi `
  --wait `
  --timeout 5m

kubectl rollout status `
  deployment/cluster-autoscaler `
  --namespace kube-system `
  --timeout=300s

kubectl logs `
  deployment/cluster-autoscaler `
  --namespace kube-system `
  --tail=100
```

Os logs devem mostrar o node group descoberto, sem erros de credenciais ou de
permissão.

## 10. Criar os pods dos microsserviços e da observabilidade

O overlay `k8s/overlays/aws` usa as imagens públicas e conecta `account`,
`product` e `order` ao RDS por meio do `rds-secret`. Não existe PostgreSQL
interno nesse ambiente. O gateway permanece inicialmente como `ClusterIP`. A
base também inclui Prometheus, Loki, Alloy, Grafana e kube-state-metrics a
partir do repositório remoto `observability`.

### 10.1. Preparar as credenciais locais

O Grafana usa o mesmo fluxo local de Secrets dos demais componentes. Copie os
arquivos de exemplo caso ainda não tenha preparado `api/.secrets`:

```powershell
New-Item -ItemType Directory -Force api/.secrets | Out-Null
Copy-Item api/.secrets.example/*.env api/.secrets/
```

Antes de usar a AWS, troque os valores de desenvolvimento, inclusive
`GF_SECURITY_ADMIN_PASSWORD` em `api/.secrets/grafana.env`, e valide todos os
arquivos sem acessar o cluster:

```powershell
./k8s/scripts/apply-secrets.ps1 -ValidateOnly
```

O `deploy-aws.ps1` cria ou atualiza automaticamente `grafana-secret` junto com
os demais Secrets antes de aplicar os manifests. Ele também valida
`api/.secrets/rds.env`; `DATABASE_HOST` deve conter o endpoint obtido na seção
8, e não o valor `CHANGE_ME_RDS_ENDPOINT`.

### 10.2. Aplicar a plataforma

```powershell
kubectl kustomize `
  ./k8s/overlays/aws `
  --load-restrictor LoadRestrictionsNone
./k8s/scripts/deploy-aws.ps1
```

`LoadRestrictionsNone` é necessário porque o Kustomization lê configurações
canônicas fora do diretório do overlay. Use essa opção somente neste repositório
confiável.

O script cria no namespace `store` os deployments e services dos
microsserviços, Redis e observabilidade. O PostgreSQL interno não é criado na
AWS.

### 10.3. Validar os recursos

Confirme os microsserviços:

```powershell
kubectl get deployments,pods,services -n store -o wide
kubectl logs -n store deployment/account --tail=100
kubectl logs -n store deployment/auth --tail=100
kubectl logs -n store deployment/product --tail=100
kubectl logs -n store deployment/order --tail=100
kubectl logs -n store deployment/gateway --tail=100

aws rds describe-db-instances `
  --db-instance-identifier $RdsIdentifier `
  --query 'DBInstances[0].{status:DBInstanceStatus,endpoint:Endpoint.Address,public:PubliclyAccessible}' `
  --region $Region `
  --profile $Profile
```

O RDS deve aparecer como `available`, com endpoint preenchido e `public` igual
a `false`. `Account`, `product` e `order` devem referenciar `rds-secret`.

Confirme também a observabilidade:

```powershell
foreach ($Deployment in @('prometheus', 'loki', 'alloy', 'grafana', 'kube-state-metrics')) {
  kubectl rollout status `
    "deployment/$Deployment" `
    --namespace store `
    --timeout=300s
}

kubectl get services `
  prometheus loki grafana `
  --namespace store
```

Todos os deployments devem aparecer como `1/1` disponíveis. O Prometheus e o
Grafana serão acessados pelas rotas `/prometheus/` e `/grafana/` do gateway;
Loki e Alloy permanecem internos ao cluster.

## 11. Opcional: configurar o HPA do gateway

O HPA aumenta ou reduz somente os Pods do Deployment `gateway`. Esta
configuração é independente do Cluster Autoscaler da seção 9:

- o HPA pode funcionar sem o Cluster Autoscaler, limitado à capacidade dos
  nodes existentes;
- o Cluster Autoscaler pode funcionar sem o HPA e atender qualquer Pod que não
  consiga ser agendado por falta de capacidade.

O `deploy-aws.ps1` não instala o Metrics Server nem cria o HPA. Execute esta
seção somente quando quiser habilitar o escalonamento horizontal do gateway.

### 11.1. Instalar o Metrics Server

O HPA de CPU depende da API `metrics.k8s.io`. Instale uma versão compatível com
o Kubernetes 1.37 usado neste guia:

```powershell
$MetricsServerManifest = 'https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml'

kubectl apply -f $MetricsServerManifest
kubectl rollout status `
  deployment/metrics-server `
  --namespace kube-system `
  --timeout=300s

kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

Somente continue quando a APIService aparecer como disponível e
`kubectl top nodes` retornar métricas. O Metrics Server é instalado uma vez por
cluster e pode ser usado por outros HPAs.

### 11.2. Criar o HPA do gateway

O gateway já declara `requests.cpu: 100m`, usado como base para calcular o
percentual de utilização. O máximo de 10 réplicas é uma decisão do gateway e
não representa nem depende do máximo de 10 nodes do managed node group.

O HPA é criado de forma imperativa e não está incluído no Kustomize. Portanto,
`deploy-aws.ps1` não o recria quando ele está ausente. Antes de criar, confira
se o recurso já existe:

```powershell
$GatewayHpa = kubectl get hpa gateway `
  --namespace store `
  --ignore-not-found `
  -o name

if (-not $GatewayHpa) {
  kubectl autoscale deployment gateway `
    --namespace store `
    --cpu=50% `
    --min=1 `
    --max=10
}

kubectl get hpa gateway --namespace store
kubectl describe hpa gateway --namespace store
```

O campo `TARGETS` não deve exibir `<unknown>`. A partir deste ponto, o HPA
gerencia `spec.replicas` do gateway; não altere manualmente sua quantidade de
réplicas durante a execução normal. Recrie o HPA com esse mesmo procedimento
depois de remover o namespace `store`, remover o próprio HPA ou reconstruir o
cluster.

Para confirmar os componentes do HPA antes de um teste de carga:

```powershell
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get hpa gateway --namespace store
```

## 12. Instalar o AWS Load Balancer Controller

O controller criará o NLB de um `Service` do tipo `LoadBalancer`. O acesso IAM
usa o EKS Pod Identity Agent já instalado, sem access keys dentro dos Pods.

### 12.1. Criar a policy e a role do controller

Baixe a policy correspondente ao release mais recente do controller:

```powershell
$LbcRelease = Invoke-RestMethod `
  'https://api.github.com/repos/kubernetes-sigs/aws-load-balancer-controller/releases/latest'
$LbcTag = $LbcRelease.tag_name
$LbcPolicyFile = Join-Path $AwsGuideTemp 'load-balancer-controller-policy.json'

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/tags/$LbcTag/docs/install/iam_policy.json" `
  -OutFile $LbcPolicyFile

$LbcPolicyUri = 'file://' + $LbcPolicyFile.Replace('\', '/')
$LbcPolicyArn = aws iam create-policy `
  --policy-name $LbcPolicyName `
  --policy-document $LbcPolicyUri `
  --query Policy.Arn --output text `
  --profile $Profile
```

Crie uma trust policy limitada ao namespace e service account do controller:

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowEksAuthToAssumeRoleForPodIdentity",
    "Effect": "Allow",
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession"],
    "Condition": {
      "StringEquals": {
        "aws:RequestTag/kubernetes-namespace": "kube-system",
        "aws:RequestTag/kubernetes-service-account": "aws-load-balancer-controller"
      }
    }
  }]
}
'@ | Set-Content `
  -Path (Join-Path $AwsGuideTemp 'lbc-pod-identity-trust.json') `
  -Encoding utf8

$LbcTrustFile = (Join-Path $AwsGuideTemp 'lbc-pod-identity-trust.json').Replace('\', '/')

aws iam create-role `
  --role-name $LbcRoleName `
  --assume-role-policy-document "file://$LbcTrustFile" `
  --description 'EKS Pod Identity do AWS Load Balancer Controller' `
  --profile $Profile

aws iam attach-role-policy `
  --role-name $LbcRoleName `
  --policy-arn $LbcPolicyArn `
  --profile $Profile

$LbcRoleArn = aws iam get-role `
  --role-name $LbcRoleName --query Role.Arn `
  --output text --profile $Profile

aws eks create-pod-identity-association `
  --cluster-name $ClusterName `
  --namespace kube-system `
  --service-account aws-load-balancer-controller `
  --role-arn $LbcRoleArn `
  --region $Region `
  --profile $Profile
```

### 12.2. Instalar o controller pelo Helm

```powershell
helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update eks

helm upgrade --install aws-load-balancer-controller `
  eks/aws-load-balancer-controller `
  --namespace kube-system `
  --set clusterName=$ClusterName `
  --set region=$Region `
  --set vpcId=$VpcId `
  --set serviceAccount.create=true `
  --set serviceAccount.name=aws-load-balancer-controller `
  --wait `
  --timeout 5m

kubectl rollout status `
  deployment/aws-load-balancer-controller `
  -n kube-system --timeout=300s

kubectl get deployment aws-load-balancer-controller -n kube-system
```

## 13. Expor o gateway na internet

Crie um segundo Service. O service interno `gateway` permanece inalterado;
`gateway-public` cria o NLB.

```powershell
kubectl apply -f ./k8s/overlays/aws/gateway-public.yaml
```

> **A cobrança do NLB começa quando ele é provisionado.**

Acompanhe até surgir um hostname em `EXTERNAL-IP`:

```powershell
kubectl get service gateway-public -n store --watch
```

Interrompa o watch com `Ctrl+C` e salve o endereço:

```powershell
$GatewayHost = kubectl get service gateway-public `
  -n store `
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
$BaseUrl = "http://$GatewayHost"
$BaseUrl

./k8s/scripts/configure-observability-url.ps1
```

O último comando lê o hostname atual do NLB, atualiza
`OBSERVABILITY_PUBLIC_URL` e reinicia Prometheus e Grafana. Execute-o novamente
sempre que `gateway-public` for recriado com outro hostname.

O NLB pode levar mais alguns minutos para considerar os targets saudáveis:

```powershell
Invoke-WebRequest `
  -Uri "$BaseUrl/products" `
  -SkipHttpErrorCheck | `
  Select-Object StatusCode
```

O resultado esperado sem autenticação é `401`. Para o fluxo completo, importe
`store-product-api.postman_collection.json` e altere `baseUrl` para o valor de
`$BaseUrl`.

## 14. Diagnóstico rápido

### 14.1. Cluster e aplicação

```powershell
kubectl get pods -A -o wide
kubectl get services -n store
kubectl describe service gateway-public -n store
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=200
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=200
kubectl get events -n store --sort-by='.lastTimestamp'

aws rds describe-db-instances `
  --db-instance-identifier $RdsIdentifier `
  --query 'DBInstances[0].{status:DBInstanceStatus,endpoint:Endpoint.Address,securityGroups:VpcSecurityGroups}' `
  --region $Region `
  --profile $Profile

aws eks describe-nodegroup `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --query 'nodegroup.scalingConfig' `
  --region $Region --profile $Profile

aws elbv2 describe-load-balancers `
  --region $Region --profile $Profile `
  --query 'LoadBalancers[].[LoadBalancerName,DNSName,State.Code]'
```

Problemas comuns:

- `ImagePullBackOff`: confirme que `rafaeldbo/*:latest` está público.
- `account`, `product` ou `order` reiniciando: confirme o status do RDS, o endpoint em
  `api/.secrets/rds.env`, o `rds-secret` e a regra TCP 5432 do security group.
- Pods permanecem `Pending` sem novos nodes: confira os logs, a Pod Identity e
  a policy IAM do Cluster Autoscaler.
- O Cluster Autoscaler deve usar a mesma versão minor do Kubernetes do cluster.
- `EXTERNAL-IP` em `pending`: confira controller, Pod Identity, permissões e as
  tags `kubernetes.io/role/elb=1` das subnets públicas.
- resposta `503`: aguarde os targets do NLB ficarem saudáveis e confira a probe
  do gateway.

### 14.2. HPA opcional do gateway

Execute estes comandos somente se a seção 11 tiver sido aplicada:

```powershell
kubectl get hpa gateway --namespace store
kubectl describe hpa gateway --namespace store
kubectl top nodes
kubectl top pods --namespace store
kubectl logs --namespace kube-system deployment/metrics-server --tail=200
```

Se `TARGETS` aparecer como `<unknown>`, confira a disponibilidade da APIService
`v1beta1.metrics.k8s.io` e os logs do Metrics Server.

## 15. Remover tudo e encerrar a cobrança

Execute somente depois dos testes. A ordem é importante: NLB, aplicação,
compute, control plane e rede.

### 15.1. Remover o NLB público

```powershell
$GatewayHost = kubectl get service gateway-public `
  -n store `
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

kubectl delete service gateway-public `
  -n store --wait=true --timeout=300s
```

Repita até o resultado ser `[]`:

```powershell
aws elbv2 describe-load-balancers `
  --region $Region --profile $Profile `
  --query "LoadBalancers[?DNSName=='$GatewayHost'].[LoadBalancerArn,State.Code]"
```

Não exclua o cluster ou a VPC enquanto o NLB ainda aparecer.

### 15.2. Remover o HPA opcional do gateway

Se a seção 11 foi aplicada, remova o HPA para que ele pare de alterar a
quantidade de réplicas do gateway:

```powershell
kubectl delete hpa gateway --namespace store --ignore-not-found
```

O Metrics Server pode atender outros HPAs e não precisa ser removido junto com
o gateway. Remova-o somente se nenhuma outra carga do cluster depender da API
`metrics.k8s.io`:

```powershell
kubectl delete -f `
  https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml `
  --ignore-not-found
```

### 15.3. Remover o escalonamento de nodes do cluster

Esta etapa remove somente o Cluster Autoscaler e sua associação de EKS Pod
Identity. Ela não depende da instalação ou remoção do HPA do gateway:

```powershell
$CaAssociationId = aws eks list-pod-identity-associations `
  --cluster-name $ClusterName `
  --namespace kube-system `
  --service-account cluster-autoscaler `
  --query 'associations[0].associationId' `
  --output text --region $Region --profile $Profile

helm uninstall cluster-autoscaler --namespace kube-system

if ($CaAssociationId -and $CaAssociationId -ne 'None') {
  aws eks delete-pod-identity-association `
    --cluster-name $ClusterName `
    --association-id $CaAssociationId `
    --region $Region --profile $Profile
}

kubectl delete serviceaccount cluster-autoscaler `
  --namespace kube-system `
  --ignore-not-found
```

### 15.4. Remover os microsserviços

```powershell
kubectl kustomize `
  ./k8s/overlays/aws `
  --load-restrictor LoadRestrictionsNone | `
  kubectl delete -f - --wait=true --timeout=300s
kubectl get namespace store --ignore-not-found
```

### 15.5. Remover o Load Balancer Controller e o Pod Identity Agent

```powershell
$LbcAssociationId = aws eks list-pod-identity-associations `
  --cluster-name $ClusterName `
  --namespace kube-system `
  --service-account aws-load-balancer-controller `
  --query 'associations[0].associationId' `
  --output text --region $Region --profile $Profile

helm uninstall aws-load-balancer-controller -n kube-system

if ($LbcAssociationId -and $LbcAssociationId -ne 'None') {
  aws eks delete-pod-identity-association `
    --cluster-name $ClusterName `
    --association-id $LbcAssociationId `
    --region $Region --profile $Profile
}

aws eks delete-addon `
  --cluster-name $ClusterName `
  --addon-name eks-pod-identity-agent `
  --region $Region --profile $Profile
```

O Pod Identity Agent só é removido depois dos dois controllers que dependiam
dele.

### 15.6. Remover o RDS

O comando abaixo elimina o banco sem snapshot final e causa perda irreversível
dos dados. Use-o somente para encerrar o ambiente de laboratório:

```powershell
$RdsSecurityGroupId = aws ec2 describe-security-groups `
  --filters `
    "Name=vpc-id,Values=$VpcId" `
    "Name=group-name,Values=$RdsSecurityGroupName" `
  --query 'SecurityGroups[0].GroupId' `
  --output text `
  --region $Region `
  --profile $Profile

aws rds delete-db-instance `
  --db-instance-identifier $RdsIdentifier `
  --skip-final-snapshot `
  --delete-automated-backups `
  --region $Region `
  --profile $Profile

aws rds wait db-instance-deleted `
  --db-instance-identifier $RdsIdentifier `
  --region $Region `
  --profile $Profile

aws rds delete-db-subnet-group `
  --db-subnet-group-name $RdsSubnetGroupName `
  --region $Region `
  --profile $Profile

aws ec2 delete-security-group `
  --group-id $RdsSecurityGroupId `
  --region $Region `
  --profile $Profile
```

### 15.7. Remover o node group

```powershell
aws eks delete-nodegroup `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --region $Region --profile $Profile

aws eks wait nodegroup-deleted `
  --cluster-name $ClusterName `
  --nodegroup-name $NodeGroupName `
  --region $Region --profile $Profile
```

### 15.8. Remover o cluster EKS

```powershell
aws eks delete-cluster `
  --name $ClusterName `
  --region $Region --profile $Profile

aws eks wait cluster-deleted `
  --name $ClusterName `
  --region $Region --profile $Profile
```

### 15.9. Remover a stack da VPC e os NAT Gateways

```powershell
aws cloudformation delete-stack `
  --stack-name $VpcStackName `
  --region $Region --profile $Profile

aws cloudformation wait stack-delete-complete `
  --stack-name $VpcStackName `
  --region $Region --profile $Profile
```

A stack remove VPC, subnets, NAT Gateways, Elastic IPs, Internet Gateway, rotas
e security group criados pelo template.

### 15.10. Remover policies e roles IAM

Roles IAM não são cobradas, mas podem ser removidas para deixar a conta limpa.

```powershell
$LbcPolicyArn = "arn:aws:iam::$AccountId`:policy/$LbcPolicyName"
$CaPolicyArn = "arn:aws:iam::$AccountId`:policy/$CaPolicyName"

aws iam detach-role-policy `
  --role-name $CaRoleName --policy-arn $CaPolicyArn `
  --profile $Profile
aws iam delete-role --role-name $CaRoleName --profile $Profile
aws iam delete-policy --policy-arn $CaPolicyArn --profile $Profile

aws iam detach-role-policy `
  --role-name $LbcRoleName --policy-arn $LbcPolicyArn `
  --profile $Profile
aws iam delete-role --role-name $LbcRoleName --profile $Profile
aws iam delete-policy --policy-arn $LbcPolicyArn --profile $Profile

foreach ($PolicyArn in $NodePolicies) {
  aws iam detach-role-policy `
    --role-name $NodeRoleName `
    --policy-arn $PolicyArn `
    --profile $Profile
}
aws iam delete-role --role-name $NodeRoleName --profile $Profile

aws iam detach-role-policy `
  --role-name $ClusterRoleName `
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy `
  --profile $Profile
aws iam delete-role --role-name $ClusterRoleName --profile $Profile
```

### 15.11. Limpar o contexto e os arquivos temporários

```powershell
$EksContext = "arn:aws:eks:$Region`:$AccountId`:cluster/$ClusterName"
kubectl config delete-context $EksContext
kubectl config delete-cluster $EksContext

$AwsGuideTemp
Remove-Item -LiteralPath $AwsGuideTemp -Recurse -Force
```

Antes da remoção, `$AwsGuideTemp` deve apontar para `store-eks-guide` dentro da
pasta temporária, nunca para seu diretório pessoal ou para o repositório.

## 16. Conferência final de cobrança

```powershell
aws eks list-clusters --region $Region --profile $Profile

aws rds describe-db-instances `
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' `
  --region $Region `
  --profile $Profile

aws cloudformation list-stacks `
  --stack-status-filter DELETE_COMPLETE `
  --query "StackSummaries[?StackName=='$VpcStackName'].[StackName,StackStatus]" `
  --region $Region --profile $Profile

aws elbv2 describe-load-balancers `
  --query 'LoadBalancers[].[LoadBalancerName,DNSName,State.Code]' `
  --region $Region --profile $Profile

aws ec2 describe-nat-gateways `
  --filter Name=state,Values=available,pending,deleting `
  --query 'NatGateways[].[NatGatewayId,VpcId,State]' `
  --region $Region --profile $Profile
```

Se a conta possuir outros projetos, não exclua recursos apenas por aparecerem
nas listagens. Compare nomes, tags, VPC e ARNs antes de remover qualquer coisa.

## Referências oficiais

- [Amazon EKS — clusters](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html)
- [RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Criar uma instância RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CreateDBInstance.html)
- [Acesso privado ao RDS em uma VPC](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.Scenarios.html)
- [Cluster Autoscaler no EKS](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html)
- [Chart oficial do Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [Instalação do controller com Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [Network Load Balancer no EKS](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html)
- [EKS Pod Identity Agent](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)
- [Trust policy do EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-role.html)
- [IAM — práticas recomendadas](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

# AWS/EKS pelo AWS CLI: criação, publicação e remoção

Este guia cria na AWS o ambiente necessário para executar os microsserviços
`account`, `auth`, `product` e `gateway`, com PostgreSQL temporário dentro do
cluster. O gateway é publicado na internet por um Network Load Balancer (NLB).
O último capítulo remove todos os recursos para encerrar a cobrança.

> **Atenção a custos:** a stack de rede cria dois NAT Gateways; o cluster EKS,
> as instâncias EC2 do node group e o NLB também são cobrados enquanto
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
- Dois nodes EC2 `t2.small` nas subnets privadas.
- PostgreSQL 17 efêmero, sem RDS e sem PVC adicional.
- Microsserviços `account`, `auth`, `product` e `gateway`.
- AWS Load Balancer Controller com EKS Pod Identity.
- NLB público encaminhando a porta 80 para o gateway na porta 8080.

Os dados do PostgreSQL usam `emptyDir` e desaparecem quando o pod ou o
namespace é removido. Essa configuração serve para teste, não para produção.

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
EKS, ELBv2 e as roles/policies IAM deste guia. Também precisa de
`iam:PassRole` limitado às roles do cluster, nodes e Load Balancer Controller.
Em produção, use credenciais temporárias/MFA e uma policy de provisionamento
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

## 8. Criar os pods dos microsserviços

O overlay `k8s/overlays/aws` usa as imagens públicas, PostgreSQL efêmero e mantém o
gateway inicialmente como `ClusterIP`.

```powershell
kubectl kustomize ./k8s/overlays/aws
./k8s/scripts/deploy-aws.ps1
```

O script cria no namespace `store` deployments e services para `db`,
`account`, `auth`, `product` e `gateway`. Confirme:

```powershell
kubectl get deployments,pods,services -n store -o wide
kubectl logs -n store deployment/account --tail=100
kubectl logs -n store deployment/auth --tail=100
kubectl logs -n store deployment/product --tail=100
kubectl logs -n store deployment/gateway --tail=100
```

Todos os deployments devem aparecer como `1/1` disponíveis.

## 9. Instalar o AWS Load Balancer Controller

O controller criará o NLB de um `Service` do tipo `LoadBalancer`. O acesso IAM
usa EKS Pod Identity, sem access keys dentro dos pods.

### 9.1. Instalar o EKS Pod Identity Agent

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

### 9.2. Criar a policy e a role do controller

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

### 9.3. Instalar o controller pelo Helm

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

## 10. Expor o gateway na internet

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
```

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

## 11. Diagnóstico rápido

```powershell
kubectl get pods -A -o wide
kubectl get services -n store
kubectl describe service gateway-public -n store
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=200
kubectl get events -n store --sort-by='.lastTimestamp'

aws elbv2 describe-load-balancers `
  --region $Region --profile $Profile `
  --query 'LoadBalancers[].[LoadBalancerName,DNSName,State.Code]'
```

Problemas comuns:

- `ImagePullBackOff`: confirme que `rafaeldbo/*:latest` está público.
- pods reiniciando: confirme que `deployment/db` está pronto.
- `EXTERNAL-IP` em `pending`: confira controller, Pod Identity, permissões e as
  tags `kubernetes.io/role/elb=1` das subnets públicas.
- resposta `503`: aguarde os targets do NLB ficarem saudáveis e confira a probe
  do gateway.

## 12. Remover tudo e encerrar a cobrança

Execute somente depois dos testes. A ordem é importante: NLB, aplicação,
compute, control plane e rede.

### 12.1. Remover o NLB público

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

### 12.2. Remover os microsserviços e o banco temporário

```powershell
kubectl delete -k ./k8s/overlays/aws --wait=true --timeout=300s
kubectl get namespace store --ignore-not-found
```

### 12.3. Remover o Load Balancer Controller

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

### 12.4. Remover o node group

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

### 12.5. Remover o cluster EKS

```powershell
aws eks delete-cluster `
  --name $ClusterName `
  --region $Region --profile $Profile

aws eks wait cluster-deleted `
  --name $ClusterName `
  --region $Region --profile $Profile
```

### 12.6. Remover a stack da VPC e os NAT Gateways

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

### 12.7. Remover policies e roles IAM

Roles IAM não são cobradas, mas podem ser removidas para deixar a conta limpa.

```powershell
$LbcPolicyArn = "arn:aws:iam::$AccountId`:policy/$LbcPolicyName"

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

### 12.8. Limpar o contexto e os arquivos temporários

```powershell
$EksContext = "arn:aws:eks:$Region`:$AccountId`:cluster/$ClusterName"
kubectl config delete-context $EksContext
kubectl config delete-cluster $EksContext

$AwsGuideTemp
Remove-Item -LiteralPath $AwsGuideTemp -Recurse -Force
```

Antes da remoção, `$AwsGuideTemp` deve apontar para `store-eks-guide` dentro da
pasta temporária, nunca para seu diretório pessoal ou para o repositório.

## 13. Conferência final de cobrança

```powershell
aws eks list-clusters --region $Region --profile $Profile

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
- [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [Instalação do controller com Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [Network Load Balancer no EKS](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html)
- [EKS Pod Identity Agent](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)
- [Trust policy do EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-role.html)
- [IAM — práticas recomendadas](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

"""Cria as workload estimates da AWS Pricing Calculator pela API (bcm-pricing-calculator).

Uso (a partir da raiz do repositório, com o perfil `store` da AWS CLI):
    pip install boto3
    python scripts/custos/criar_estimativa.py

Cada item usa o mesmo `usageType`/`operation` que aparece no Cost Explorer da conta,
de modo que a estimativa modela exatamente os recursos que o projeto cobra.
Quantidades em unidades mensais (730 horas por mês).
"""

import boto3

PERFIL = "store"
HORAS = 730

sessao = boto3.Session(profile_name=PERFIL, region_name="us-east-1")
conta = sessao.client("sts").get_caller_identity()["Account"]
calc = sessao.client("bcm-pricing-calculator")


def item(chave, servico, usage_type, operacao, quantidade, grupo):
    return {
        "key": chave, "serviceCode": servico, "usageType": usage_type,
        "operation": operacao, "amount": quantidade, "group": grupo,
        "usageAccountId": conta,
    }


def cenario(nodes, tipo_node, rds_multi_az, nat_gb, inter_az_gb, nlcu_h):
    rds_uso = "Multi-AZUsage:db.t4g.micro" if rds_multi_az else "InstanceUsage:db.t4g.micro"
    rds_disco = "RDS:Multi-AZ-GP3-Storage" if rds_multi_az else "RDS:GP3-Storage"
    return [
        item("eks", "AmazonEKS", "USE1-AmazonEKS-Hours:perCluster", "CreateOperation", HORAS, "EKS"),
        item("nodes", "AmazonEC2", f"BoxUsage:{tipo_node}", "RunInstances", nodes * HORAS, "EKS"),
        item("ebs", "AmazonEC2", "EBS:VolumeUsage.gp3", "CreateVolume-Gp3", nodes * 20, "EKS"),
        item("nath", "AmazonEC2", "NatGateway-Hours", "NatGateway", 2 * HORAS, "Rede"),
        item("natb", "AmazonEC2", "NatGateway-Bytes", "NatGateway", nat_gb, "Rede"),
        item("ipv4", "AmazonVPC", "USE1-PublicIPv4:InUseAddress", "AssociateAddressVPC", 4 * HORAS, "Rede"),
        item("azin", "AWSDataTransfer", "DataTransfer-Regional-Bytes", "InterZone-In", inter_az_gb / 2, "Rede"),
        item("azout", "AWSDataTransfer", "DataTransfer-Regional-Bytes", "InterZone-Out", inter_az_gb / 2, "Rede"),
        item("nlb", "AWSELB", "LoadBalancerUsage", "LoadBalancing:Network", HORAS, "Rede"),
        item("nlcu", "AWSELB", "LCUUsage", "LoadBalancing:Network", nlcu_h, "Rede"),
        item("rds", "AmazonRDS", rds_uso, "CreateDBInstance:0014", HORAS, "Banco"),
        item("rdsgb", "AmazonRDS", rds_disco, "CreateDBInstance:0014", 20, "Banco"),
        item("sec", "AWSSecretsManager", "USE1-AWSSecretsManager-Secrets", "SecretUsage", 1, "Banco"),
    ]


CENARIOS = {
    "platform-custos-atual": cenario(3, "t2.small", False, 22, 53, 2.2),
    "platform-custos-producao": cenario(4, "t3.small", True, 100, 200, HORAS),
}

for nome, uso in CENARIOS.items():
    est = calc.create_workload_estimate(name=nome, rateType="BEFORE_DISCOUNTS")
    resp = calc.batch_create_workload_estimate_usage(workloadEstimateId=est["id"], usage=uso)
    if resp["errors"]:
        raise SystemExit(f"{nome}: {resp['errors']}")
    print(f"\n{nome} ({est['id']})")
    for i in sorted(resp["items"], key=lambda i: -(i.get("cost") or 0)):
        q = i["quantity"]
        print(f"  {i['group']:<6} {i['usageType']:<36} {q['amount']:>8} {q['unit']:<8} US$ {i['cost']:>7.2f}")
    print(f"  {'TOTAL':<54} US$ {sum(i['cost'] for i in resp['items']):>7.2f}")

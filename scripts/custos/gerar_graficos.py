"""Gera os gráficos e as tabelas de cenários da página docs/custos/index.md.

Uso (a partir da raiz do repositório):
    python scripts/custos/gerar_graficos.py

Entrada: docs/custos/dados/cost-explorer-2026-11.json (snapshot do Cost Explorer).
Saída:   docs/custos/img/*.png e as tabelas de cenários em Markdown no stdout.
"""

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RAIZ = Path(__file__).resolve().parents[2]
DADOS = RAIZ / "docs/custos/dados/cost-explorer-2026-11.json"
IMG = RAIZ / "docs/custos/img"

HORAS_MES = 730

# Preços on-demand em us-east-1 (USD). Os marcados com * foram conferidos contra
# o Cost Explorer da conta (custo ÷ quantidade); todos foram confirmados pela
# Pricing Calculator (scripts/custos/criar_estimativa.py).
PRECO = {
    "eks_h": 0.10,  # * control plane, suporte padrão
    "t2_small_h": 0.023,  # *
    "t3_small_h": 0.0208,
    "ebs_gp3_gb": 0.08,  # * GB-mês
    "nat_h": 0.045,  # *
    "nat_gb": 0.045,  # *
    "nlb_h": 0.0225,  # *
    "nlcu_h": 0.006,  # *
    "ipv4_h": 0.005,  # *
    "rds_t4g_micro_h": 0.016,  # * Single-AZ
    "rds_t4g_micro_maz_h": 0.032,  # Multi-AZ
    "rds_gp3_gb": 0.115,  # * Single-AZ, GB-mês
    "rds_gp3_gb_maz": 0.23,  # Multi-AZ, GB-mês
    "secret_mes": 0.40,  # *
    "regional_gb": 0.01,  # * tráfego entre AZs
}


def cenario(nodes, preco_node, nats, rds_maz, nat_gb, regional_gb, nlcu_medio):
    """Custo mensal (USD) por componente para uma configuração da plataforma."""
    p = PRECO
    ipv4 = nats + 2  # 1 EIP por NAT + 1 IP público do NLB por AZ (2 AZs)
    return {
        "EKS (control plane)": p["eks_h"] * HORAS_MES,
        "EC2 (nodes)": nodes * preco_node * HORAS_MES,
        "EBS dos nodes (20 GiB cada)": nodes * 20 * p["ebs_gp3_gb"],
        "NAT Gateway": nats * p["nat_h"] * HORAS_MES + nat_gb * p["nat_gb"],
        "NLB": p["nlb_h"] * HORAS_MES + nlcu_medio * p["nlcu_h"] * HORAS_MES,
        "IPv4 público": ipv4 * p["ipv4_h"] * HORAS_MES,
        "RDS PostgreSQL": (
            (p["rds_t4g_micro_maz_h"] if rds_maz else p["rds_t4g_micro_h"]) * HORAS_MES
            + 20 * (p["rds_gp3_gb_maz"] if rds_maz else p["rds_gp3_gb"])
        ),
        "Secrets Manager": p["secret_mes"],
        "Tráfego entre AZs": regional_gb * p["regional_gb"],
    }


CENARIOS = {
    # Como está hoje na conta: 3 nodes t2.small, 2 NAT, RDS Single-AZ.
    # Tráfego extrapolado dos ~9 dias medidos (6,8 GB NAT, 16 GB regional).
    "Atual (medido)": cenario(3, PRECO["t2_small_h"], 2, False, 22, 53, 0.003),
    # Ambiente de desenvolvimento: 1 NAT, 2 nodes t3.small.
    "Econômico (dev)": cenario(2, PRECO["t3_small_h"], 1, False, 22, 40, 0.003),
    # Produção pequena: 4 nodes em média, RDS Multi-AZ, mais tráfego.
    "Produção": cenario(4, PRECO["t3_small_h"], 2, True, 100, 200, 1.0),
}

AZUL = "#2a78d6"
TINTA = "#0b0b0b"
TINTA_2 = "#52514e"
GRADE = "#e4e3df"
SUPERFICIE = "#fcfcfb"


def estilo(ax):
    ax.set_facecolor(SUPERFICIE)
    for lado in ("top", "right", "left"):
        ax.spines[lado].set_visible(False)
    ax.spines["bottom"].set_color(GRADE)
    ax.tick_params(colors=TINTA_2, labelsize=9, length=0)
    ax.set_axisbelow(True)


def grafico_diario(dados):
    dias = list(dados["custo_diario_usd"].keys())
    valores = list(dados["custo_diario_usd"].values())
    fig, ax = plt.subplots(figsize=(9, 3.6), facecolor=SUPERFICIE)
    estilo(ax)
    ax.grid(axis="y", color=GRADE, linewidth=0.8)
    rotulos = [d[-2:] for d in dias]
    barras = ax.bar(rotulos, valores, color=AZUL, width=0.7)
    # Destaques: imposto do dia 1, criação do ambiente e o 3º node.
    for i, txt in ((0, "impostos"), (11, "2 nodes"), (16, "3 nodes")):
        b = barras[i]
        ax.annotate(
            f"US$ {valores[i]:.2f}\n{txt}",
            (b.get_x() + b.get_width() / 2, b.get_height()),
            xytext=(0, 4), textcoords="offset points",
            ha="center", va="bottom", fontsize=8, color=TINTA,
        )
    ax.set_ylim(0, 10)
    ax.set_ylabel("USD / dia", color=TINTA_2, fontsize=9)
    ax.set_xlabel("Novembro de 2026 (dia 20 parcial)", color=TINTA_2, fontsize=9)
    ax.set_title("Custo diário da conta do projeto", loc="left", color=TINTA, fontsize=11)
    fig.tight_layout()
    fig.savefig(IMG / "custo-diario.png", dpi=160)
    plt.close(fig)


def grafico_barras_h(itens, arquivo, titulo, xlabel):
    nomes = list(itens.keys())[::-1]
    valores = list(itens.values())[::-1]
    fig, ax = plt.subplots(figsize=(9, 0.42 * len(nomes) + 1.1), facecolor=SUPERFICIE)
    estilo(ax)
    ax.grid(axis="x", color=GRADE, linewidth=0.8)
    ax.barh(nomes, valores, color=AZUL, height=0.6)
    for y, v in enumerate(valores):
        ax.text(v + max(valores) * 0.01, y, f"US$ {v:,.2f}", va="center", fontsize=8, color=TINTA)
    ax.set_xlim(0, max(valores) * 1.15)
    ax.set_xlabel(xlabel, color=TINTA_2, fontsize=9)
    ax.set_title(titulo, loc="left", color=TINTA, fontsize=11)
    fig.tight_layout()
    fig.savefig(IMG / arquivo, dpi=160)
    plt.close(fig)


def tabela_md(cenarios):
    nomes = list(cenarios)
    linhas = ["| Componente | " + " | ".join(nomes) + " |", "|-|" + "-:|" * len(nomes)]
    for comp in next(iter(cenarios.values())):
        linhas.append(f"| {comp} | " + " | ".join(f"{cenarios[n][comp]:.2f}" for n in nomes) + " |")
    totais = {n: sum(c.values()) for n, c in cenarios.items()}
    linhas.append("| **Total / mês** | " + " | ".join(f"**{totais[n]:.2f}**" for n in nomes) + " |")
    linhas.append("| Total / hora | " + " | ".join(f"{totais[n] / HORAS_MES:.3f}" for n in nomes) + " |")
    return "\n".join(linhas), totais


def main():
    IMG.mkdir(parents=True, exist_ok=True)
    dados = json.loads(DADOS.read_text(encoding="utf-8"))
    grafico_diario(dados)
    real = {k: v for k, v in dados["custo_por_servico_usd"].items() if k != "Tax"}
    grafico_barras_h(
        dict(sorted(real.items(), key=lambda kv: -kv[1])),
        "custo-por-servico.png",
        "Custo real por serviço (01 a 20/11/2026, sem impostos)", "USD",
    )
    atual = dict(sorted(CENARIOS["Atual (medido)"].items(), key=lambda kv: -kv[1]))
    grafico_barras_h(atual, "estimativa-mensal.png",
                     "Estimativa mensal da configuração atual (730 h)", "USD / mês")
    md, totais = tabela_md(CENARIOS)
    grafico_barras_h(totais, "cenarios.png", "Custo mensal por cenário", "USD / mês")
    print(md)


if __name__ == "__main__":
    main()

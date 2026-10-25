#!/usr/bin/env python3
# ruff: noqa
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
"""Servidor MCP da Cervejaria do Fritz (Estoque SQLite, Off-Flavors BJCP e Lúpulos)."""

from pathlib import Path
import sqlite3

try:
    from mcp.server.fastmcp import FastMCP
except ModuleNotFoundError:
    from mcp.server.mcpserver import MCPServer as FastMCP

mcp = FastMCP("cervejaria-fritz-mcp")

DB_PATH = Path(__file__).parent / "estoque_cervejaria.db"


def _init_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS insumos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            categoria TEXT NOT NULL,
            nome TEXT NOT NULL UNIQUE,
            quantidade REAL NOT NULL,
            unidade TEXT NOT NULL,
            especificacao TEXT NOT NULL
        )
        """
    )
    cur = conn.execute("SELECT COUNT(*) FROM insumos")
    if cur.fetchone()[0] == 0:
        seed = [
            ("malte", "Malte Pale Ale (Weyermann)", 12.5, "kg", "3.0 Lovibond — Base Ale"),
            ("malte", "Malte Pilsen (Agrária)", 15.0, "kg", "1.8 Lovibond — Base Lager/Belga"),
            ("malte", "Malte de Trigo (Weyermann)", 6.0, "kg", "2.0 Lovibond — Weiss/Wit"),
            ("malte", "Malte Munich I", 3.0, "kg", "9.0 Lovibond — Corpo e notas de casca de pão"),
            ("malte", "Malte Carapils", 2.0, "kg", "1.5 Lovibond — Retenção de espuma"),
            ("malte", "Cevada Torrada (Roasted Barley)", 1.5, "kg", "500 Lovibond — Dry Stout"),
            ("lupulo", "Citra (Pellets T-90)", 250.0, "g", "12.4% AA — Cítrico, maracujá e manga"),
            ("lupulo", "Mosaic (Pellets T-90)", 200.0, "g", "11.8% AA — Frutas tropicais, mirtilo e pinho"),
            ("lupulo", "Columbus / CTZ (Pellets T-90)", 150.0, "g", "14.2% AA — Amargor limpo e resinoso"),
            ("lupulo", "Saaz (Pellets T-90)", 180.0, "g", "3.5% AA — Floral e picante nobre tcheco"),
            ("lupulo", "Hallertau Mittelfrüh", 120.0, "g", "4.2% AA — Herbal e floral clássico alemão"),
            ("lupulo", "East Kent Goldings (EKG)", 100.0, "g", "5.0% AA — Terroso e floral inglês"),
            ("levedura", "Fermentis US-05 (American Ale)", 4.0, "sachês", "Atenuação ~81%, perfil neutro/limpo"),
            ("levedura", "Fermentis WB-06 (Weihenstephan)", 2.0, "sachês", "Ésteres de banana e fenóis de cravo"),
            ("levedura", "Fermentis S-04 (English Ale)", 3.0, "sachês", "Alta floculação, perfil inglês frutado"),
            ("levedura", "Fermentis W-34/70 (Lager)", 4.0, "sachês", "Lager alemã/tcheca limpa e crisp"),
        ]
        conn.executemany(
            "INSERT INTO insumos (categoria, nome, quantidade, unidade, especificacao) VALUES (?, ?, ?, ?, ?)",
            seed,
        )
        conn.commit()
    return conn


@mcp.tool()
def consultar_estoque_insumos(categoria: str = "todos") -> str:
    """Consulta o banco SQLite de estoque real da cervejaria (maltes, lúpulos e leveduras disponíveis).

    Args:
        categoria: Filtro de categoria ('todos', 'malte', 'lupulo', 'levedura').

    Returns:
        Lista formatada com quantidades disponíveis e especificações técnicas.
    """
    conn = _init_db()
    cat = categoria.strip().lower()
    if cat in ("malte", "maltes"):
        rows = conn.execute("SELECT categoria, nome, quantidade, unidade, especificacao FROM insumos WHERE categoria='malte'").fetchall()
    elif cat in ("lupulo", "lúpulo", "lupulos", "lúpulos"):
        rows = conn.execute("SELECT categoria, nome, quantidade, unidade, especificacao FROM insumos WHERE categoria='lupulo'").fetchall()
    elif cat in ("levedura", "leveduras", "fermento"):
        rows = conn.execute("SELECT categoria, nome, quantidade, unidade, especificacao FROM insumos WHERE categoria='levedura'").fetchall()
    else:
        rows = conn.execute("SELECT categoria, nome, quantidade, unidade, especificacao FROM insumos ORDER BY categoria, nome").fetchall()
    conn.close()

    linhas = ["📦 Estoque Atual da Cervejaria (SQLite MCP):"]
    for c, nome, qtd, un, spec in rows:
        linhas.append(f"- [{c.upper()}] {nome}: {qtd:g} {un} ({spec})")
    return "\n".join(linhas)


@mcp.tool()
def diagnosticar_off_flavor(sintoma_sensorial: str) -> str:
    """Diagnostica defeitos sensoriais (off-flavors) da cerveja segundo o guia de juízes BJCP.

    Args:
        sintoma_sensorial: Descrição do aroma ou sabor indesejado (ex: 'manteiga', 'pipoca', 'maçã verde', 'milho cozido', 'papelão', 'cravo/cloro', 'banana excessiva').

    Returns:
        Composto químico causador, origem no processo e como corrigir na próxima brassagem.
    """
    s = sintoma_sensorial.strip().lower()
    if "manteiga" in s or "pipoca" in s or "butterscotch" in s or "diacetil" in s:
        return (
            "🔬 Diagnóstico BJCP: DIACETIL (2,3-butanodiona)\n"
            "- Aroma/Sabor: Manteiga, pipoca de cinema ou caramelo amanteigado.\n"
            "- Causa: Reabsorção incompleta pela levedura no fim da fermentação ou contaminação por Pediococcus.\n"
            "- Como corrigir: Faça um Descanso de Diacetil subindo a temperatura em 2°C–3°C nos últimos 2-3 dias da fermentação primária antes do cold crash."
        )
    elif "maçã" in s or "maca" in s or "tinta" in s or "acetaldeido" in s or "acetaldeído" in s:
        return (
            "🔬 Diagnóstico BJCP: ACETALDEÍDO\n"
            "- Aroma/Sabor: Maçã verde cortada, cidra crua ou tinta látex.\n"
            "- Causa: Cerveja retirada do fermentador cedo demais (cerveja 'verde'), pitch rate insuficiente ou oxidação pós-fermentação.\n"
            "- Como corrigir: Dê mais tempo de maturação com a levedura ativa, garanta aeração adequada apenas no mosto frio e evite oxigênio no envase."
        )
    elif "milho" in s or "legume" in s or "repolho" in s or "dms" in s:
        return (
            "🔬 Diagnóstico BJCP: DMS (Dimetil Sulfeto)\n"
            "- Aroma/Sabor: Milho verde cozido, caldo de legumes ou molho de tomate.\n"
            "- Causa: Precursor SMM (forte em malte Pilsen) não volatilizado na fervura ou resfriamento lento demais.\n"
            "- Como corrigir: Ferva vigorosamente por 60 a 90 min com a panela destampada e faça o resfriamento rápido (chiller) abaixo de 80°C."
        )
    elif "papelão" in s or "papelao" in s or "jerez" in s or "oxid" in s:
        return (
            "🔬 Diagnóstico BJCP: OXIDAÇÃO (Trans-2-nonenal)\n"
            "- Aroma/Sabor: Papelão molhado, mel velho, jerez ou escurecimento prematuro (especialmente em IPAs).\n"
            "- Causa: Exposição ao oxigênio (splash) após o início da fermentação ou durante a trasfega/envase.\n"
            "- Como corrigir: Faça transferências fechadas purgando com CO2 e evite abrir o fermentador após o Dry Hopping."
        )
    elif "banana" in s or "solvente" in s or "acetona" in s or "esmalte" in s or "ester" in s:
        return (
            "🔬 Diagnóstico BJCP: ÉSTERES EXCESSIVOS (Acetato de Isoamila) / ÁLCOOIS SUPERIORES\n"
            "- Aroma/Sabor: Banana artificial intensa, chiclete ou solvente/esmalte.\n"
            "- Causa: Temperatura de fermentação alta demais nas primeiras 72h ou sub-inoculação (underpitching).\n"
            "- Como corrigir: Controle estritamente a temperatura interna do balde/fermentador (não apenas da geladeira) e inocule a taxa correta de células."
        )
    return (
        f"🔬 Sintoma '{sintoma_sensorial}': Verifique os 5 off-flavors clássicos do BJCP — "
        "Diacetil (manteiga), Acetaldeído (maçã verde), DMS (milho cozido), Oxidação (papelão) e Ésteres/Fusel (banana/solvente)."
    )


@mcp.tool()
def buscar_substituto_lupulo(lupulo_original: str) -> str:
    """Sugere lúpulos substitutos com base no perfil de óleos essenciais (Mirceno, Humuleno, Cariofileno, Linalol).

    Args:
        lupulo_original: Nome do lúpulo que está em falta (ex: 'Citra', 'Mosaic', 'Saaz', 'Cascade', 'Hallertau', 'Magnum').

    Returns:
        Lista de substitutos diretos com recomendações de ajuste de Alfa-Ácido.
    """
    h = lupulo_original.strip().lower()
    mapa = {
        "citra": "Substitutos para Citra (11–13% AA, alto Mirceno/Linalol cítrico): Galaxy, Mosaic, Simcoe ou combinação 50/50 de Cascade + Centennial.",
        "mosaic": "Substitutos para Mosaic (11–13% AA, tropical/pinho/berry): Citra, Simcoe, Azacca ou El Dorado.",
        "saaz": "Substitutos para Saaz (3–4.5% AA, alto Farneseno floral/picante): Sterling, Tettnanger, Lublin ou Spalt.",
        "cascade": "Substitutos para Cascade (4.5–7% AA, floral/grapefruit): Centennial (ajuste a quantidade pelo dobro de AA), Amarillo ou Ahtanum.",
        "hallertau": "Substitutos para Hallertau Mittelfrüh (3.5–5.5% AA, alto Humuleno herbal): Hersbrucker, Liberty, Mt. Hood ou Tradition.",
        "columbus": "Substitutos para Columbus/CTZ (14–16% AA, amargor resinoso): Chinook, Nugget, Magnum (para amargor limpo) ou Summit.",
        "ekg": "Substitutos para East Kent Goldings (4.5–6.5% AA, terroso inglês): Fuggle, Willamette, Styrian Goldings ou Progress.",
    }
    for chave, resp in mapa.items():
        if chave in h:
            return f"🌿 Matriz de Lúpulos (MCP): {resp} Dica: recalcule as gramas mantendo os mesmos IBUs pela equação de Tinseth!"
    return (
        f"🌿 Para substituir '{lupulo_original}': se for adição de 60 min (amargor), use qualquer lúpulo neutro de alto Alfa-Ácido "
        "(Magnum, Columbus) ajustando os gramas para atingir o mesmo IBU. Se for aroma/Dry Hop, combine perfil cítrico (Citra/Amarillo) ou nobre (Saaz/Hallertau)."
    )


if __name__ == "__main__":
    mcp.run(transport="stdio")

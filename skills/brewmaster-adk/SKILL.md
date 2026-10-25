---
name: brewmaster-adk
description: Especialista em engenharia de receitas de cerveja artesanal (BJCP 2021), cálculos cervejeiros (ABV, IBU Tinseth, Cor SRM/EBC Morey, Química da Água SO4:Cl) e integração de servidores MCP (McpToolset + FastMCP) para o agente Fritz no Google ADK. Use ao criar ou expandir ferramentas cervejeiras, servidores MCP de estoque/telemetria ou datasets de avaliação no projeto brewmaster-agent.
---

# 🍺 Skill: Brewmaster with ADK (`brewmaster-adk`)

Use esta skill sempre que o usuário pedir para criar novas ferramentas cervejeiras, adicionar estilos do guia **BJCP 2021**, conectar servidores **MCP (`McpToolset`)** ou criar casos de avaliação (`tests/eval/datasets/basic-dataset.json`) para o agente **Fritz (`brewmaster-agent`)**.

## 1. Fórmulas Oficiais de Engenharia Cervejeira

Sempre implemente cálculos determinísticos em Python (nunca deixe o LLM adivinhar contas matemáticas):

1. **Teor Alcoólico Estimado (`ABV %`) e Atenuação Aparente (`AA %`):**
   - `abv = (og - fg) * 131.25`
   - `atenuacao_aparente = ((og - fg) / (og - 1.0)) * 100.0`

2. **Amargor (`IBU` — Equação de Glenn Tinseth):**
   - `bigness_factor = 1.65 * (0.000125 ** (og - 1.0))`
   - `boil_time_factor = (1.0 - math.exp(-0.04 * tempo_fervura_min)) / 4.15`
   - `utilizacao = bigness_factor * boil_time_factor`
   - `ibu = (lupulo_gramas * (alfa_acido_pct / 100.0) * utilizacao * 1000.0) / volume_litros`
   - `relacao_bu_gu = ibu / ((og - 1.0) * 1000.0)`

3. **Cor do Mosto (`MCU`, `SRM` e `EBC` — Equação de Dan Morey):**
   - Converta cada malte para libras (`kg * 2.20462`) e o volume para galões (`litros * 0.264172`).
   - `mcu = sum((peso_lbs * cor_lovibond) / volume_gal)`
   - `srm = 1.4922 * (mcu ** 0.6859)`
   - `ebc = srm * 1.97`

4. **Química da Água Cervejeira (Relação Sulfato:Cloreto `SO4:Cl`):**
   - `SO4:Cl >= 2.5` (Ex: `200 ppm SO4 : 60 ppm Cl`): Destaca amargor seco e assertivo (West Coast IPA, American Pale Ale).
   - `SO4:Cl ~ 1.0` (Ex: `70 ppm SO4 : 70 ppm Cl`): Equilibrado (Czech/German Pilsner, Kölsch).
   - `SO4:Cl <= 0.6` (Ex: `50 ppm SO4 : 110 ppm Cl`): Destaca corpo aveludado, dulçor de malte e maciez (Dry Stout, Hazy/NEIPA, Weissbier, Witbier).

## 2. Padrão de Integração MCP no Google ADK (`McpToolset`)

Para conectar um servidor MCP local escrito com `FastMCP` (`from mcp.server.fastmcp import FastMCP`) dentro do `app/agent.py`, use sempre `sys.executable` para garantir que o subprocesso rode no mesmo `.venv` gerenciado pelo `uv`:

```python
from pathlib import Path
import sys
from google.adk.tools.mcp_tool.mcp_toolset import McpToolset
from mcp import StdioServerParameters

cervejaria_mcp = McpToolset(
    connection_params=StdioServerParameters(
        command=sys.executable,
        args=[str(Path(__file__).parent / "mcp_cervejaria.py")],
    ),
)
```

## 3. Padrão de Avaliação no `agents-cli v1.11+`

- O dataset padrão fica em **`tests/eval/datasets/basic-dataset.json`** (executado via `agents-cli eval run`).
- Cada item dentro de `"eval_cases"` deve conter `"eval_case_id"`, `"prompt"` (`role: "user"`) e opcionalmente `"reference"` (`response.role: "model"`).

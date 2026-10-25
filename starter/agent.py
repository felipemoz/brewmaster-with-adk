import math
import os
from pathlib import Path
import re
import sys
from typing import Any, Optional
import urllib.request

from google.adk.agents import Agent
from google.adk.agents.callback_context import CallbackContext
from google.adk.apps import App
from google.adk.models import Gemini
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.adk.skills import load_skill_from_dir
from google.adk.tools.base_tool import BaseTool
from google.adk.tools.skill_toolset import SkillToolset
from google.adk.tools.tool_context import ToolContext
from google.genai import types

# No Vertex AI / Gemini Enterprise Agent Platform, os modelos Gemini do agents-cli
# respondem no endpoint multi-região 'global' (e não em 'us-central1').
if os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "TRUE").upper() != "FALSE":
    os.environ["GOOGLE_CLOUD_LOCATION"] = "global"

_APP_DIR = Path(__file__).resolve().parent
_RAW_BASE_URL = "https://raw.githubusercontent.com/felipemoz/brewmaster-with-adk/main/starter"

_MARKDOWN_ASSETS = [
    "prompts/fritz_system_prompt.md",
    "skills/mestre-bjcp/SKILL.md",
    "skills/mestre-bjcp/references/catalogo_receitas_agua.md",
    "skills/sommelier-cervejeiro/SKILL.md",
    "skills/sommelier-cervejeiro/references/guia_harmonizacao_copos.md",
]


def _ensure_markdown_assets() -> None:
    """Garante que os arquivos Markdown de Prompt e Skills do ADK estejam presentes e atualizados em app/."""
    for rel_path in _MARKDOWN_ASSETS:
        destino = _APP_DIR / rel_path
        precisa_baixar = not destino.exists()
        if not precisa_baixar:
            try:
                conteudo = destino.read_text(encoding="utf-8", errors="ignore")
                if "\\text{" in conteudo:
                    precisa_baixar = True
            except Exception:
                precisa_baixar = True
        if precisa_baixar:
            destino.parent.mkdir(parents=True, exist_ok=True)
            url = f"{_RAW_BASE_URL}/{rel_path}"
            try:
                urllib.request.urlretrieve(url, destino)
            except Exception:
                pass


def _resolve_default_model() -> str:
    """Obtém o model ID configurado pelo scaffold do agents-cli (em tests/eval/response_quality.py)."""
    if os.environ.get("GENAI_MODEL"):
        return os.environ["GENAI_MODEL"]
    eval_file = _APP_DIR.parent / "tests" / "eval" / "response_quality.py"
    if eval_file.exists():
        match = re.search(r'model="([^"{]+)"', eval_file.read_text(encoding="utf-8", errors="ignore"))
        if match:
            return match.group(1)
    return "gemini-flash-latest"


_ensure_markdown_assets()
MODEL = _resolve_default_model()

# ============================================================================
# GUARDRAILS DO AGENTE (ADK Callbacks + Filtros de Contexto e Segurança)
# ============================================================================

_PADROES_JAILBREAK = re.compile(
    r"(ignore\s+(todas\s+as\s+|as\s+|previous\s+|all\s+)?(instru[cç][oõ]es|instructions|rules|regras)|"
    r"esque[cç]a\s+(tudo|suas\s+instru[cç][oõ]es|que\s+voc[eê]\s+[eé])|"
    r"disregard\s+(previous|all|system)|"
    r"system\s*prompt|modo\s+desenvolvedor|developer\s+mode|jailbreak|\bdan\b|"
    r"voc[eê]\s+agora\s+[eé]\s+um|act\s+as\s+a)",
    re.IGNORECASE,
)

_TERMOS_CONTEXTO_CERVEJEIRO = re.compile(
    r"(cervej|chopp|chope|mosto|mostura|brassagem|fervura|ferment|matura|"
    r"malte|l[uú]pulo|levedura|[aá]gua|bjcp|ipa|stout|porter|weiss|weizen|wit|witbier|"
    r"lager|pils|pilsen|ale|saison|sour|lambic|bock|tripel|dubbel|belgian|apa|"
    r"\babv\b|\bibu\b|\bsrm\b|\bebc\b|\bog\b|\bfg\b|lovibond|tinseth|morey|"
    r"sulfato|cloreto|c[aá]lcio|gipso|bicarbonato|sais|"
    r"off[\s-]?flavor|diacetil|acetalde[ií]do|\bdms\b|oxida[cç][aã]o|fen[oó]lico|"
    r"estoque|insumo|harmoniza|sommelier|copo|ta[cç]a|pint|caneca|"
    r"grist|gr[aã]os|envase|priming|dry\s*hop|whirlpool|clarifica|britagem|fritz)",
    re.IGNORECASE,
)

_PADROES_FORA_DE_ESCOPO = re.compile(
    r"\b(python|javascript|typescript|java|c\+\+|golang|rust|html|css|react|angular|"
    r"kubernetes|docker|terraform|aws|azure|linux|windows|c[oó]digo|script|programar|"
    r"algoritmo|compilar|debugar|bitcoin|ethereum|criptomoeda|cripto|bolsa\s+de\s+valores|"
    r"ibovespa|nasdaq|dividendos|tesouro\s+direto|day\s+trade|forex|imposto\s+de\s+renda|"
    r"elei[cç][aã]o|presidente|deputado|senador|partido\s+pol[ií]tico|stf|congresso|"
    r"processo\s+judicial|advogado|rem[eé]dio|antibi[oó]tico|diagn[oó]stico\s+m[eé]dico|"
    r"cirurgia|receita\s+m[eé]dica|futebol|brasileir[aã]o|libertadores|copa\s+do\s+mundo|"
    r"f[oó]rmula\s*1|basquete|playstation|xbox|minecraft|valorant|"
    r"equa[cç][aã]o\s+de\s+segundo\s+grau|bhaskara|derivada|integral|"
    r"teorema\s+de\s+pit[aá]goras|relatividade\s+geral|mec[aâ]nica\s+qu[aân]tica|"
    r"previs[aã]o\s+do\s+tempo|capital\s+da|motor\s+de\s+carro)\b",
    re.IGNORECASE,
)


def guardrail_entrada_cervejeira(
    callback_context: CallbackContext, llm_request: LlmRequest
) -> Optional[LlmResponse]:
    """Camada 1 (ADK before_model_callback): bloqueia Prompt Injection e assuntos fora do universo cervejeiro antes de chamar a LLM."""
    ultimo_texto_usuario = ""
    for content in reversed(llm_request.contents or []):
        if content.role == "user" and content.parts:
            partes_texto = [p.text for p in content.parts if getattr(p, "text", None)]
            if partes_texto:
                ultimo_texto_usuario = " ".join(partes_texto).strip()
                break

    if not ultimo_texto_usuario:
        return None

    if _PADROES_JAILBREAK.search(ultimo_texto_usuario):
        return LlmResponse(
            content=types.Content(
                role="model",
                parts=[
                    types.Part.from_text(
                        text=(
                            "🍺 **[Guardrail de Segurança Ativado]** Opa! Sou o **Fritz**, Mestre Cervejeiro e Sommelier BJCP. "
                            "Minhas válvulas de pressão estão travadas para falar exclusivamente sobre **cerveja artesanal, "
                            "brassagem, química da água, controle de qualidade e harmonização cervejeira**. "
                            "Não posso ignorar minhas diretrizes de cervejaria. Qual estilo vamos brasar hoje?"
                        )
                    )
                ],
            )
        )

    if _PADROES_FORA_DE_ESCOPO.search(ultimo_texto_usuario) and not _TERMOS_CONTEXTO_CERVEJEIRO.search(
        ultimo_texto_usuario
    ):
        return LlmResponse(
            content=types.Content(
                role="model",
                parts=[
                    types.Part.from_text(
                        text=(
                            "🍺 **[Fora do Contexto Cervejeiro]** Saúde! Aqui na cervejaria eu sou o **Fritz**, especialista "
                            "exclusivamente em **produção de cervejas artesanais, estilos BJCP, cálculos de ABV/IBU/SRM, "
                            "ajuste de água cervejeira, diagnóstico de off-flavors, estoque de insumos e harmonização com cervejas**.\n\n"
                            "Não consigo responder sobre outros assuntos (como programação, finanças, política, esportes ou temas gerais). "
                            "Se quiser uma receita All-Grain, ajustar sua água ou descobrir uma harmonização para o seu próximo copo, é só pedir!"
                        )
                    )
                ],
            )
        )

    return None


def guardrail_parametros_ferramentas(
    tool: BaseTool, args: dict[str, Any], tool_context: ToolContext
) -> Optional[dict[str, Any]]:
    """Camada 2 (ADK before_tool_callback): valida limites físico-químicos antes de executar qualquer ferramenta."""
    nome_tool = getattr(tool, "name", "")

    for campo_vol in ("volume_litros", "volume_desejado_litros"):
        if campo_vol in args and args[campo_vol] is not None:
            vol = float(args[campo_vol])
            if vol < 1.0 or vol > 5000.0:
                return {
                    "erro_guardrail": (
                        f"Volume inválido ({vol}L) na tool '{nome_tool}'. "
                        "Por segurança da planta cervejeira, informe um lote entre 1L e 5000L."
                    )
                }

    if nome_tool == "calcular_abv_ibu_srm":
        og = float(args.get("og", 1.050))
        fg = float(args.get("fg", 1.010))
        if og < 1.000 or og > 1.200 or fg < 0.985 or fg > 1.150:
            return {
                "erro_guardrail": (
                    f"Densidades fora da faixa física cervejeira (OG={og}, FG={fg}). "
                    "A OG deve estar entre 1.000 e 1.200 e a FG entre 0.985 e 1.150."
                )
            }
        if fg >= og:
            return {
                "erro_guardrail": (
                    f"Inconsistência física detectada: a Densidade Final (FG={fg}) não pode ser maior ou igual "
                    f"à Densidade Original (OG={og}). Verifique a leitura do densímetro/refratômetro."
                )
            }

    if nome_tool == "calcular_correcao_agua":
        for ion in (
            "calcio_atual_ppm",
            "sulfato_atual_ppm",
            "cloreto_atual_ppm",
            "sulfato_alvo_ppm",
            "cloreto_alvo_ppm",
        ):
            valor = float(args.get(ion, 0))
            if valor < 0 or valor > 2000:
                return {
                    "erro_guardrail": (
                        f"Concentração inválida para {ion} ({valor} ppm). "
                        "Os íons da água devem estar entre 0 e 2000 ppm."
                    )
                }

    return None


# ============================================================================
# TOOLS MATEMÁTICAS E ESTEQUIOMÉTRICAS (Zero Conhecimento Estático Hardcoded)
# ============================================================================


def escalonar_insumos_lote(
    volume_desejado_litros: float,
    malte_base_20l_kg: float,
    lupulo_base_20l_gramas: float,
) -> str:
    """Escala os insumos de uma receita base de 20L (da skill 'mestre-bjcp') e calcula os volumes de água de mostura e lavagem.

    Args:
        volume_desejado_litros: Volume final desejado no fermentador em litros (ex: 50.0).
        malte_base_20l_kg: Peso total de maltes (kg) na receita referência de 20L (ex: 5.45 para American IPA).
        lupulo_base_20l_gramas: Soma total de lúpulos (g) na receita referência de 20L (ex: 220.0).

    Returns:
        Dimensionamento escalado de grãos, lúpulos, água de mostura (3 L/kg) e água de lavagem (sparge).
    """
    fator = volume_desejado_litros / 20.0
    malte_escalado_kg = malte_base_20l_kg * fator
    lupulo_escalado_g = lupulo_base_20l_gramas * fator

    # Hidratação de mostura (relacao 3.0 L/kg) + absorção dos grãos (1.0 L/kg) + evaporação/trub (~15%)
    agua_mostura_l = malte_escalado_kg * 3.0
    absorcao_graos_l = malte_escalado_kg * 1.0
    volume_pre_fervura_l = volume_desejado_litros * 1.15
    agua_lavagem_sparge_l = max(0.0, volume_pre_fervura_l - (agua_mostura_l - absorcao_graos_l))

    return (
        f"Dimensionamento de Lote ({volume_desejado_litros:.1f}L | Fator de Escala: {fator:.2f}x sobre a base 20L):\n"
        f"- Total de Maltes Escalado: {malte_escalado_kg:.2f} kg (multiplique cada malte da receita base por {fator:.2f})\n"
        f"- Total de Lúpulos Escalado: {lupulo_escalado_g:.0f} g (multiplique cada adição de lúpulo por {fator:.2f})\n"
        f"- Água de Mostura (3.0 L/kg): {agua_mostura_l:.1f} L\n"
        f"- Água de Lavagem / Sparge: {agua_lavagem_sparge_l:.1f} L (Volume Pré-Fervura estimado: {volume_pre_fervura_l:.1f} L)"
    )


def calcular_abv_ibu_srm(
    og: float,
    fg: float,
    lupulo_amargor_gramas: float,
    alfa_acido_percentual: float,
    cor_media_malte_lovibond: float = 3.5,
    peso_total_malte_kg: float = 5.0,
    volume_litros: float = 20.0,
) -> str:
    """Calcula ABV (%), Atenuação Aparente (%), Amargor IBU (Tinseth 60 min), BU:GU e Cor (SRM/EBC via Morey).

    Args:
        og: Densidade Original do mosto (ex: 1.062).
        fg: Densidade Final após fermentação (ex: 1.012).
        lupulo_amargor_gramas: Gramas de lúpulo adicionados no início da fervura (60 min).
        alfa_acido_percentual: Percentual de Alfa-Ácido do lúpulo (ex: 14.0 para 14%).
        cor_media_malte_lovibond: Cor ponderada do grist em graus Lovibond (ex: 4.5 para IPA, 35.0 para Stout).
        peso_total_malte_kg: Peso total de grãos da receita em kg (ex: 5.45).
        volume_litros: Volume final do lote em litros (ex: 20.0).

    Returns:
        Laudo técnico cervejeiro com ABV, Atenuação, IBU, relação BU:GU e Cor em SRM e EBC.
    """
    abv = (og - fg) * 131.25
    atenuacao = ((og - fg) / (og - 1.0)) * 100.0 if og > 1.0 else 0.0

    # Equação exponencial de Glenn Tinseth para 60 minutos de fervura
    bigness_factor = 1.65 * (0.000125 ** (og - 1.0))
    boil_time_factor = (1.0 - math.exp(-0.04 * 60.0)) / 4.15
    utilizacao_tinseth = bigness_factor * boil_time_factor
    ibu = (
        lupulo_amargor_gramas
        * (alfa_acido_percentual / 100.0)
        * utilizacao_tinseth
        * 1000.0
    ) / volume_litros

    # Equação exponencial de Dan Morey para cor da cerveja (MCU -> SRM -> EBC)
    peso_lbs = peso_total_malte_kg * 2.20462
    volume_gal = volume_litros * 0.264172
    mcu = (peso_lbs * cor_media_malte_lovibond) / volume_gal if volume_gal > 0 else 0.0
    srm = 1.4922 * (mcu ** 0.6859) if mcu > 0 else 0.0
    ebc = srm * 1.97

    gu = (og - 1.0) * 1000.0
    relacao_bu_gu = ibu / gu if gu > 0 else 0.0

    return (
        f"Laudo Técnico da Brassagem ({volume_litros:.0f}L):\n"
        f"- Teor Alcoólico (ABV): {abv:.2f}%\n"
        f"- Atenuação Aparente: {atenuacao:.1f}%\n"
        f"- Amargor (Tinseth 60m): {ibu:.1f} IBU (Utilização: {utilizacao_tinseth * 100:.1f}%)\n"
        f"- Equilíbrio BU:GU: {relacao_bu_gu:.2f}\n"
        f"- Cor Estimada (Morey): {srm:.1f} SRM ({ebc:.1f} EBC)"
    )


def calcular_correcao_agua(
    volume_litros: float = 20.0,
    calcio_atual_ppm: float = 20.0,
    sulfato_atual_ppm: float = 15.0,
    cloreto_atual_ppm: float = 20.0,
    sulfato_alvo_ppm: float = 225.0,
    cloreto_alvo_ppm: float = 60.0,
) -> str:
    """Calcula a estequiometria de sais cervejeiros (gramas de Gipso CaSO4 e Cloreto de Cálcio CaCl2) para atingir o perfil alvo.

    Consulte primeiro a skill 'mestre-bjcp' para obter os valores de 'sulfato_alvo_ppm' e 'cloreto_alvo_ppm' do estilo desejado.

    Args:
        volume_litros: Volume de água a tratar em litros (padrão 20.0).
        calcio_atual_ppm: Cálcio (Ca2+) atual na água base em ppm (mg/L).
        sulfato_atual_ppm: Sulfato (SO4 2-) atual na água base em ppm (mg/L).
        cloreto_atual_ppm: Cloreto (Cl-) atual na água base em ppm (mg/L).
        sulfato_alvo_ppm: Sulfato (SO4 2-) alvo para o estilo em ppm (ex: 225 para IPA, 60 para Stout, 45 para Weiss, 70 para Lager).
        cloreto_alvo_ppm: Cloreto (Cl-) alvo para o estilo em ppm (ex: 60 para IPA, 115 para Stout, 80 para Weiss, 70 para Lager).

    Returns:
        Dosagem estequiométrica em gramas de Gipso (CaSO4.2H2O) e Cloreto de Cálcio (CaCl2.2H2O) e perfil final de íons.
    """
    relacao_atual = sulfato_atual_ppm / cloreto_atual_ppm if cloreto_atual_ppm > 0 else 0.0
    relacao_alvo = sulfato_alvo_ppm / cloreto_alvo_ppm if cloreto_alvo_ppm > 0 else 0.0

    # Estequiometria:
    # 1 g/L de Gipso (CaSO4.2H2O) adiciona 557.7 ppm SO4 e 232.8 ppm Ca
    # 1 g/L de Cloreto de Cálcio di-hidratado (CaCl2.2H2O) adiciona 482.3 ppm Cl e 272.6 ppm Ca
    delta_so4_ppm = max(0.0, sulfato_alvo_ppm - sulfato_atual_ppm)
    delta_cl_ppm = max(0.0, cloreto_alvo_ppm - cloreto_atual_ppm)

    gipso_gramas = (delta_so4_ppm / 557.7) * volume_litros
    cacl2_gramas = (delta_cl_ppm / 482.3) * volume_litros

    calcio_final_ppm = (
        calcio_atual_ppm
        + (gipso_gramas / volume_litros) * 232.8
        + (cacl2_gramas / volume_litros) * 272.6
    )
    so4_final_ppm = sulfato_atual_ppm + delta_so4_ppm
    cl_final_ppm = cloreto_atual_ppm + delta_cl_ppm

    return (
        f"Cálculo Estequiométrico de Água Cervejeira ({volume_litros:.0f}L):\n"
        f"- Água Base Atual: Ca={calcio_atual_ppm:.0f} ppm | SO4={sulfato_atual_ppm:.0f} ppm | Cl={cloreto_atual_ppm:.0f} ppm (SO4:Cl atual = {relacao_atual:.2f}:1)\n"
        f"- Adição de Gipso (CaSO4·2H2O): {gipso_gramas:.1f} g\n"
        f"- Adição de Cloreto de Cálcio (CaCl2·2H2O): {cacl2_gramas:.1f} g\n"
        f"- Perfil Mineral Resultante: Ca={calcio_final_ppm:.0f} ppm | SO4={so4_final_ppm:.0f} ppm | Cl={cl_final_ppm:.0f} ppm (SO4:Cl final = {relacao_alvo:.2f}:1)"
    )


# ============================================================================
# CARREGAMENTO DE SKILLS (SkillToolset), PROMPT MARKDOWN E SERVIDOR MCP
# ============================================================================

_PROMPT_FILE = _APP_DIR / "prompts" / "fritz_system_prompt.md"
_SYSTEM_INSTRUCTION = (
    _PROMPT_FILE.read_text(encoding="utf-8")
    if _PROMPT_FILE.exists()
    else "Você é o Fritz (Brewmaster AI), Mestre Cervejeiro e Sommelier BJCP. Responda apenas sobre cervejas artesanais em português."
)

_TOOLS: list[Any] = [
    escalonar_insumos_lote,
    calcular_abv_ibu_srm,
    calcular_correcao_agua,
]

# 1. Pluga as Skills de Conhecimento Cervejeiro (mestre-bjcp e sommelier-cervejeiro) via ADK SkillToolset
_SKILLS_DIR = _APP_DIR / "skills"
_LOADED_SKILLS = []
for _skill_name in ("mestre-bjcp", "sommelier-cervejeiro"):
    _skill_path = _SKILLS_DIR / _skill_name
    if (_skill_path / "SKILL.md").exists():
        _LOADED_SKILLS.append(load_skill_from_dir(_skill_path))

if _LOADED_SKILLS:
    _TOOLS.append(SkillToolset(skills=_LOADED_SKILLS))

# 2. Pluga automaticamente o Servidor MCP da Cervejaria (SQLite + Off-Flavors + Lúpulos) se app/mcp_cervejaria.py existir
_MCP_SCRIPT = _APP_DIR / "mcp_cervejaria.py"
if _MCP_SCRIPT.exists():
    try:
        from google.adk.tools.mcp_tool.mcp_toolset import McpToolset
        from mcp import StdioServerParameters
    except ImportError:
        import subprocess

        subprocess.run(
            ["uv", "pip", "install", "--python", sys.executable, "mcp>=1.8.0,<2.0.0"],
            check=False,
        )
        from google.adk.tools.mcp_tool.mcp_toolset import McpToolset
        from mcp import StdioServerParameters

    _TOOLS.append(
        McpToolset(
            connection_params=StdioServerParameters(
                command=sys.executable,
                args=[str(_MCP_SCRIPT)],
            ),
        )
    )

_SAFETY_SETTINGS = [
    types.SafetySetting(
        category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
    ),
    types.SafetySetting(
        category=types.HarmCategory.HARM_CATEGORY_HARASSMENT,
        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
    ),
    types.SafetySetting(
        category=types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
    ),
    types.SafetySetting(
        category=types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
    ),
]

root_agent = Agent(
    name="root_agent",
    model=Gemini(
        model=MODEL,
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    generate_content_config=types.GenerateContentConfig(
        temperature=0.2,
        safety_settings=_SAFETY_SETTINGS,
    ),
    before_model_callback=guardrail_entrada_cervejeira,
    before_tool_callback=guardrail_parametros_ferramentas,
    instruction=lambda _: _SYSTEM_INSTRUCTION,
    tools=_TOOLS,
)

app = App(
    root_agent=root_agent,
    name="app",
)

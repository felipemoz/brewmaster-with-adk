# Lab End-to-End: Assistente Mestre Cervejeiro com `agents-cli` (ADK)

Este laboratório hands-on mostra a sequência completa de comandos no **`agents-cli`** para criar, desenvolver ferramentas (tools), testar no terminal e no Playground Web, avaliar automaticamente com **LLM-as-a-Judge** e fazer o deploy em produção no **Google Cloud (Vertex AI Agent Runtime)** de um **Assistente de Receitas de Cerveja Artesanal (`mestre-cervejeiro-agent`)**.

---

## Passo 0: Pré-requisitos e Autenticação

Se ainda não executou o instalador deste repositório, rode:

```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash
source ~/.bashrc
```

---

## Passo 1: Criar a estrutura do Agente (`scaffold create`)

Crie o projeto `mestre-cervejeiro-agent` em modo protótipo:

```bash
cd ~
agents-cli scaffold create mestre-cervejeiro-agent --prototype --yes
cd mestre-cervejeiro-agent
```

---

## Passo 2: Configurar Credenciais (`.env` e `app/.env`)

Escolha **uma** das duas opções abaixo para evitar o erro `RefreshError` / `DefaultCredentialsError` no Playground:

### Opção A — Usando Google Cloud (Vertex AI + ADC)
```bash
export GOOGLE_CLOUD_PROJECT="SEU_PROJECT_ID_AQUI"
gcloud auth application-default login
gcloud auth application-default set-quota-project "$GOOGLE_CLOUD_PROJECT"

cat <<EOF > .env
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
GOOGLE_CLOUD_LOCATION=global
EOF
cp .env app/.env
```

### Opção B — Usando Google AI Studio (`GEMINI_API_KEY`)
```bash
cat <<'EOF' > .env
GOOGLE_GENAI_USE_VERTEXAI=FALSE
GEMINI_API_KEY=SUA_CHAVE_DO_AI_STUDIO_AQUI
EOF
cp .env app/.env
```
*(Ou execute `agents-cli-env aistudio SUA_CHAVE_AQUI` caso tenha instalado o utilitário [`agents-cli-env.sh`](./agents-cli-env.sh)).*

---

## Passo 3: Implementar as Tools Cervejeiras no `app/agent.py`

Substitua o arquivo `app/agent.py` pelo código abaixo. Ele inclui **3 ferramentas (tools)** de cervejaria artesanal:
1. `buscar_receita_estilo`: retorna o grist de maltes, lúpulos, levedura e rampa de mostura escalados para o volume desejado (American IPA, Weissbier, Dry Stout e Belgian Witbier).
2. `calcular_abv_e_ibu`: calcula o teor alcoólico estimado (`ABV %`), atenuação aparente (`%`), amargor (`IBU` via Tinseth 60 min) e relação de equilíbrio `BU:GU`.
3. `sugerir_harmonizacao`: recomenda pratos, copo ideal e temperatura de serviço para o estilo.

> **Nota:** O código abaixo respeita automaticamente tanto `GOOGLE_GENAI_USE_VERTEXAI=FALSE` (AI Studio) quanto `TRUE` (Vertex AI), evitando que o template padrão sobrescreva seu `.env`.

```bash
cat << 'EOF' > app/agent.py
import os
import google.auth
from google.adk.agents import Agent
from google.adk.apps import App
from google.adk.models import Gemini
from google.genai import types

# Respeita o modo configurado no .env (Vertex AI por padrão, ou AI Studio se FALSE)
if os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "TRUE").upper() != "FALSE":
    _, project_id = google.auth.default()
    os.environ["GOOGLE_CLOUD_PROJECT"] = os.environ.get("GOOGLE_CLOUD_PROJECT") or project_id or ""
    os.environ["GOOGLE_CLOUD_LOCATION"] = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")
    os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "True"


def buscar_receita_estilo(estilo: str, volume_litros: int = 20) -> str:
    """Busca uma receita base de cerveja artesanal por estilo (para brassagem All-Grain).

    Args:
        estilo: Nome do estilo da cerveja (ex: 'American IPA', 'Weissbier', 'Dry Stout', 'Witbier').
        volume_litros: Volume final desejado do lote em litros (padrão 20L).

    Returns:
        Receita detalhada com maltes, lúpulos, levedura e rampa de mostura escalada para o volume.
    """
    fator = volume_litros / 20.0
    chave = estilo.strip().lower()

    if "ipa" in chave:
        return (
            f"Receita: American IPA ({volume_litros}L) | OG Alvo: 1.062 | FG Alvo: 1.012\n"
            f"- Maltes: {4.8 * fator:.2f} kg Malte Pale Ale (88%), {0.4 * fator:.2f} kg Munich (7%), {0.25 * fator:.2f} kg Carapils (5%)\n"
            f"- Mostura: 66°C por 60 min (corpo médio-seco) + Mash-out a 76°C por 10 min\n"
            f"- Fervura (60 min): {20 * fator:.0f}g Columbus (14% AA) aos 60 min; {40 * fator:.0f}g Citra (12% AA) + {40 * fator:.0f}g Mosaic (11.5% AA) no Whirlpool a 80°C\n"
            f"- Dry Hopping: {60 * fator:.0f}g Citra + {60 * fator:.0f}g Mosaic por 3 dias a 15°C\n"
            f"- Levedura: US-05 (American Ale) fermentando a 18°C–19°C"
        )
    elif "weiss" in chave or "trigo" in chave:
        return (
            f"Receita: German Hefeweizen / Weissbier ({volume_litros}L) | OG Alvo: 1.050 | FG Alvo: 1.012\n"
            f"- Maltes: {2.5 * fator:.2f} kg Malte de Trigo (55%), {2.0 * fator:.2f} kg Malte Pilsen (45%)\n"
            f"- Mostura: Parada ferúlica a 44°C por 15 min (aroma de cravo) -> Sacarificação a 65°C por 45 min -> 76°C por 10 min\n"
            f"- Fervura (60 min): {25 * fator:.0f}g Hallertau Mittelfrüh (4.2% AA) aos 60 min (12-14 IBU)\n"
            f"- Levedura: WB-06 ou Munich Classic fermentando a 17°C–20°C (notas de banana e cravo)"
        )
    elif "stout" in chave or "porter" in chave:
        return (
            f"Receita: Irish Dry Stout ({volume_litros}L) | OG Alvo: 1.044 | FG Alvo: 1.010\n"
            f"- Maltes: {3.0 * fator:.2f} kg Maris Otter (70%), {0.85 * fator:.2f} kg Cevada em Flocos (20%), {0.42 * fator:.2f} kg Cevada Torrada / Roasted Barley (10%)\n"
            f"- Mostura: 65°C por 60 min + 76°C por 10 min\n"
            f"- Fervura (60 min): {35 * fator:.0f}g East Kent Goldings (5.0% AA) aos 60 min (32 IBU)\n"
            f"- Levedura: S-04 (English Ale) fermentando a 18°C"
        )
    elif "wit" in chave:
        return (
            f"Receita: Belgian Witbier ({volume_litros}L) | OG Alvo: 1.048 | FG Alvo: 1.010\n"
            f"- Grãos: {2.2 * fator:.2f} kg Malte Pilsen (50%), {2.0 * fator:.2f} kg Trigo Não-Maltado em Flocos (45%), {0.22 * fator:.2f} kg Aveia em Flocos (5%)\n"
            f"- Mostura: 50°C por 15 min -> 66°C por 60 min\n"
            f"- Fervura (60 min): {25 * fator:.0f}g Saaz (3.5% AA) aos 60 min\n"
            f"- Especiarias (5 min finais): {15 * fator:.0f}g Semente de Coentro moída na hora + {20 * fator:.0f}g Casca de Laranja Bahia/Curaçao\n"
            f"- Levedura: Belgian Wit (T-58 ou M21) a 19°C–21°C"
        )
    return (
        f"Estilo '{estilo}' não está no catálogo rápido. Estilos disponíveis no banco local: "
        "American IPA, Weissbier, Dry Stout e Belgian Witbier."
    )


def calcular_abv_e_ibu(
    og: float,
    fg: float,
    lupulo_amargor_gramas: float,
    alfa_acido_percentual: float,
    volume_litros: float = 20.0,
) -> str:
    """Calcula o teor alcoólico estimado (ABV %), atenuação aparente e IBU de amargor (60 min).

    Args:
        og: Densidade Original do mosto (ex: 1.062).
        fg: Densidade Final após fermentação (ex: 1.012).
        lupulo_amargor_gramas: Quantidade de lúpulo de amargor (60 min) em gramas.
        alfa_acido_percentual: Percentual de Alfa-Ácido do lúpulo (ex: 12.0 para 12%).
        volume_litros: Volume do lote em litros (ex: 20.0).

    Returns:
        Resumo técnico com ABV (%), Atenuação Aparente (%) e IBU estimado (Tinseth 60m).
    """
    abv = (og - fg) * 131.25
    atenuacao = ((og - fg) / (og - 1.0)) * 100 if og > 1.0 else 0.0
    # Utilização média Tinseth aos 60 min (~0.23 para OG padrão)
    utilizacao_60m = 0.23
    ibu = (lupulo_amargor_gramas * (alfa_acido_percentual / 100.0) * utilizacao_60m * 1000.0) / volume_litros
    relacao_bu_gu = ibu / ((og - 1.0) * 1000.0) if og > 1.0 else 0.0

    return (
        f"Parâmetros Calculados:\n"
        f"- ABV Estimado: {abv:.2f}%\n"
        f"- Atenuação Aparente: {atenuacao:.1f}%\n"
        f"- Amargor (IBU 60 min): {ibu:.1f} IBU\n"
        f"- Equilíbrio BU:GU: {relacao_bu_gu:.2f}"
    )


def sugerir_harmonizacao(estilo: str) -> str:
    """Sugere harmonização gastronômica, copo ideal e temperatura de serviço para o estilo de cerveja.

    Args:
        estilo: Nome do estilo da cerveja (ex: 'American IPA', 'Weissbier', 'Dry Stout', 'Witbier').

    Returns:
        Dicas de harmonização, copo e temperatura.
    """
    chave = estilo.strip().lower()
    if "ipa" in chave:
        return "Harmonização IPA: Hambúrguer artesanal com cheddar inglês, comida mexicana picante ou curry. Copo: Pint/IPA Glass. Temperatura: 5°C a 7°C."
    elif "weiss" in chave or "trigo" in chave:
        return "Harmonização Weissbier: Salsichas alemãs (Weisswurst) com mostarda doce, frutos do mar leves e queijo brie. Copo: Weizen. Temperatura: 4°C a 6°C."
    elif "stout" in chave:
        return "Harmonização Dry Stout: Ostras frescas, costela bovina assada, carnes grelhadas e petit gâteau de chocolate amargo. Copo: Pint Imperial. Temperatura: 8°C a 10°C."
    elif "wit" in chave:
        return "Harmonização Witbier: Ceviche de peixe branco, saladas cítricas, sushi e queijo de cabra. Copo: Tumbler/Hoegaarden. Temperatura: 3°C a 5°C."
    return f"Para {estilo}: sirva entre 5°C e 8°C em taça ISO ou Pint e harmonize por semelhança de intensidade."


root_agent = Agent(
    name="root_agent",
    model=Gemini(
        model="gemini-flash-latest",
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    instruction=(
        "Você é um Mestre Cervejeiro e Sommelier de Cervejas especialista em brassagem caseira (homebrewing) pelo guia BJCP. "
        "Sempre use suas ferramentas para buscar receitas (`buscar_receita_estilo`), calcular ABV/IBU/BU:GU (`calcular_abv_e_ibu`) "
        "e recomendar harmonizações (`sugerir_harmonizacao`). Responda de forma clara, técnica e organizada em português."
    ),
    tools=[buscar_receita_estilo, calcular_abv_e_ibu, sugerir_harmonizacao],
)

app = App(
    root_agent=root_agent,
    name="app",
)
EOF
```

---

## Passo 4: Instalar dependências e testar no Terminal (`install` & `run`)

1. Instale o ambiente virtual gerenciado pelo `uv`:
   ```bash
   agents-cli install
   ```

2. Execute um teste completo via linha de comando (o `agents-cli run` sobe o servidor em background na primeira execução):
   ```bash
   agents-cli run "Quero fazer 20 litros de uma American IPA. Me passe a receita, calcule o ABV e IBU usando OG 1.062, FG 1.012 e 20g de lúpulo com 14% de alfa-ácido na fervura, e indique uma harmonização."
   ```

3. Faça uma pergunta de acompanhamento para testar outra receita:
   ```bash
   agents-cli run "E se eu quiser fazer 40 litros de uma Weissbier alemã, qual é a receita escalada?"
   ```

4. Pare o servidor em background antes de abrir o Playground ou rodar avaliações:
   ```bash
   agents-cli run --stop-server
   ```

---

## Passo 5: Testar visualmente na Interface Web (`playground`)

Inicie a interface gráfica do ADK para inspecionar o grafo de ferramentas e as chamadas em tempo real:

```bash
agents-cli playground
```

* Abra `http://127.0.0.1:8080/dev-ui/?app=app` no navegador.
* Teste prompts como: *"Me dê uma receita de Dry Stout para 20L, calcule o ABV para OG 1.044 e FG 1.010 com 35g de lúpulo a 5% AA e sugira um prato para harmonizar."*
* Quando terminar os testes visuais, pressione `Ctrl+C` no terminal.

---

## Passo 6: Configurar e Rodar Avaliação Automatizada (`eval run`)

O `agents-cli` possui um motor de avaliação que valida **se o agente chamou as tools corretas** (`tool_trajectory_avg_score`) e **a qualidade da resposta final** usando LLM-as-a-Judge (`rubric_based_final_response_quality_v1`).

1. Atualize o dataset de avaliação `tests/eval/evalsets/basic.evalset.json` com cenários cervejeiros:
   ```bash
   cat << 'EOF' > tests/eval/evalsets/basic.evalset.json
   {
     "eval_set_id": "mestre_cervejeiro_eval",
     "name": "Avaliação do Mestre Cervejeiro",
     "description": "Valida busca de receitas, cálculo de ABV/IBU e harmonização",
     "eval_cases": [
       {
         "eval_id": "receita_ipa_20l",
         "conversation": [
           {
             "invocation_id": "turn-1",
             "user_content": {
               "parts": [
                 {
                   "text": "Me passe a receita base de uma American IPA para 20 litros."
                 }
               ],
               "role": "user"
             },
             "final_response": {
               "parts": [
                 {
                   "text": "Aqui está a receita da American IPA para 20L com Malte Pale Ale, Citra, Mosaic e levedura US-05."
                 }
               ],
               "role": "model"
             },
             "intermediate_data": {
               "tool_uses": [
                 {
                   "name": "buscar_receita_estilo",
                   "args": {
                     "estilo": "American IPA",
                     "volume_litros": 20
                   }
                 }
               ]
             }
           }
         ],
         "session_input": {
           "app_name": "app",
           "user_id": "cervejeiro_teste"
         }
       },
       {
         "eval_id": "calculo_abv_ibu",
         "conversation": [
           {
             "invocation_id": "turn-1",
             "user_content": {
               "parts": [
                 {
                   "text": "Calcule o ABV e IBU para OG 1.062, FG 1.012, 20 gramas de lúpulo com 14% de alfa-ácido em 20 litros."
                 }
               ],
               "role": "user"
             },
             "final_response": {
               "parts": [
                 {
                   "text": "O ABV estimado é de 6.56% e o amargor é de 32.2 IBU."
                 }
               ],
               "role": "model"
             },
             "intermediate_data": {
               "tool_uses": [
                 {
                   "name": "calcular_abv_e_ibu",
                   "args": {
                     "og": 1.062,
                     "fg": 1.012,
                     "lupulo_amargor_gramas": 20,
                     "alfa_acido_percentual": 14,
                     "volume_litros": 20
                   }
                 }
               ]
             }
           }
         ],
         "session_input": {
           "app_name": "app",
           "user_id": "cervejeiro_teste"
         }
       }
     ]
   }
   EOF
   ```

2. Execute a suíte de avaliação:
   ```bash
   agents-cli eval run --all
   ```

---

## Passo 7: Lint e Formatação do Código (`lint`)

Verifique e corrija automaticamente o estilo do código (Ruff, Mypy, Codespell):

```bash
agents-cli lint --fix
```

---

## Passo 8: Preparar para Produção e Fazer Deploy no Google Cloud (`enhance` & `deploy`)

Quando o agente estiver pronto para sair do protótipo local e ir para o **Vertex AI Agent Engine (Agent Runtime)** ou **Cloud Run** (requer projeto GCP com faturamento ativo):

1. Adicione os arquivos de empacotamento e infraestrutura ao projeto:
   ```bash
   agents-cli scaffold enhance --deployment-target agent_runtime --yes
   uv lock
   ```

2. Faça o deploy no Google Cloud:
   ```bash
   export GOOGLE_CLOUD_PROJECT="SEU_PROJECT_ID_AQUI"
   agents-cli deploy --project "$GOOGLE_CLOUD_PROJECT" --region us-central1
   ```

3. Teste o agente rodando diretamente na nuvem (substitua pelo ID retornado no final do deploy):
   ```bash
   export RUNTIME_ID="projects/SEU_PROJECT_NUM/locations/us-central1/reasoningEngines/SEU_ENGINE_ID"

   agents-cli run \
     --url "https://us-central1-aiplatform.googleapis.com/v1/${RUNTIME_ID}" \
     --mode adk \
     "Me recomende uma receita de Belgian Witbier para 20L e o que servir de comida junto!"
   ```

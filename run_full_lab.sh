#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# 🍺 Brewmaster with ADK — Execução Automatizada do Lab Completo (End-to-End)
# ==============================================================================
# Este script executa todos os módulos do workshop Brewmaster with ADK em
# sequência (do zero até a avaliação BJCP e o deploy no Vertex AI Agent Runtime):
#   • Módulo 0: Verifica/instala pré-requisitos (uv, Python 3.11+, Node, gcloud, agents-cli)
#               e exporta NO_GCE_CHECK=true + UV_NO_CONFIG=1 (evita erro Airlock no Cloud Build)
#   • Módulo 1: Cria o projeto 'brewmaster-agent' (agents-cli scaffold create) e configura .env
#   • Módulo 2: Baixa o Fritz modular (agent.py, Prompt Markdown, ADK Skills BJCP & Sommelier)
#   • Módulo 8: Pluga o Servidor MCP SQLite da Cervejaria (app/mcp_cervejaria.py)
#   • Módulo 3: Instala dependências e testa Receita + Água + Estoque MCP + Guardrails via CLI
#   • Módulo 5: Roda o Concurso BJCP Automatizado (agents-cli eval run)
#   • Módulo 6: Roda o Controle de Qualidade (agents-cli lint --fix)
#   • Módulo 7: Prepara e faz deploy no Vertex AI Agent Runtime (agents-cli deploy)
#
# Uso (1 linha):
#   bash <(curl -fsSL https://is.gd/brewmaster_lab)
#
# Opções:
#   --project <PROJECT_ID>   Define o projeto GCP (padrão: $GOOGLE_CLOUD_PROJECT ou gcloud config)
#   --region <REGION>        Região para o deploy no Agent Runtime (padrão: us-central1)
#   --api-key <API_KEY>      Usa chave do Google AI Studio em vez de Vertex AI (pula o deploy GCP)
#   --dir <PATH>             Diretório onde criar o agente (padrão: $HOME/brewmaster-agent)
#   --skip-deploy            Executa todo o lab localmente (Módulos 0 a 6 + 8) sem o deploy na nuvem
#   --skip-eval              Pula a etapa de avaliação LLM-as-a-Judge (Módulo 5)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}▸${NC} $*"; }
log_ok()    { echo -e "${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "${YELLOW}⚠️  Aviso:${NC} $*"; }
log_err()   { echo -e "${RED}✗ Erro:${NC} $*" >&2; }
log_step()  { echo -e "\n${BOLD}🍺 $*${NC}\n────────────────────────────────────────────────────────────────────"; }

TARGET_PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
DEPLOY_REGION="us-central1"
TARGET_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
AGENT_DIR="${HOME}/brewmaster-agent"
SKIP_DEPLOY=false
SKIP_EVAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|-p)
      TARGET_PROJECT="${2:-}"
      shift 2
      ;;
    --project=*)
      TARGET_PROJECT="${1#*=}"
      shift
      ;;
    --region|-r)
      DEPLOY_REGION="${2:-us-central1}"
      shift 2
      ;;
    --region=*)
      DEPLOY_REGION="${1#*=}"
      shift
      ;;
    --api-key|-k)
      TARGET_API_KEY="${2:-}"
      shift 2
      ;;
    --api-key=*)
      TARGET_API_KEY="${1#*=}"
      shift
      ;;
    --dir|-d)
      AGENT_DIR="${2:-${HOME}/brewmaster-agent}"
      shift 2
      ;;
    --dir=*)
      AGENT_DIR="${1#*=}"
      shift
      ;;
    --skip-deploy)
      SKIP_DEPLOY=true
      shift
      ;;
    --skip-eval)
      SKIP_EVAL=true
      shift
      ;;
    --help|-h)
      echo "Uso: bash $0 [--project PROJECT_ID] [--region us-central1] [--api-key AI_STUDIO_KEY] [--dir ~/brewmaster-agent] [--skip-deploy] [--skip-eval]"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

export PATH="${HOME}/.local/bin:${PATH}"

# ==============================================================================
# Módulo 0: Preparação da Cozinha Cervejeira (Ambiente & Pré-requisitos)
# ==============================================================================
log_step "Módulo 0: Preparando o Ambiente e Proteções de Rede/Cloud Build"

# Evita timeout de 9s tentando conectar em 169.254.169.254 fora do GCE
if ! curl -s -f -m 1 -H "Metadata-Flavor: Google" "http://169.254.169.254/computeMetadata/v1/instance/id" >/dev/null 2>&1; then
  export NO_GCE_CHECK="true"
  log_ok "NO_GCE_CHECK=true ativado (evita lentidão de metadata server fora do GCE)."
fi

# Garante que o uv use o PyPI público (evita gravar airlock-proxy.uplink.goog no uv.lock)
export UV_NO_CONFIG="1"
log_ok "UV_NO_CONFIG=1 ativado (garante uv.lock compatível com Google Cloud Build)."

if ! command -v agents-cli >/dev/null 2>&1 || ! command -v uv >/dev/null 2>&1; then
  log_info "Instalando pré-requisitos via https://is.gd/brewmaster_sh..."
  if [[ -n "${TARGET_API_KEY}" && -z "${TARGET_PROJECT}" ]]; then
    curl -fsSL "https://is.gd/brewmaster_sh?t=$(date +%s)" | bash -s -- --api-key "${TARGET_API_KEY}" --non-interactive
  elif [[ -n "${TARGET_PROJECT}" ]]; then
    curl -fsSL "https://is.gd/brewmaster_sh?t=$(date +%s)" | bash -s -- --project "${TARGET_PROJECT}" --region "global" --non-interactive
  else
    curl -fsSL "https://is.gd/brewmaster_sh?t=$(date +%s)" | bash
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# Resolve projeto GCP se não passado por flag
if [[ -z "${TARGET_PROJECT}" ]] && command -v gcloud >/dev/null 2>&1; then
  GCLOUD_PROJ="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "${GCLOUD_PROJ}" && "${GCLOUD_PROJ}" != "(unset)" ]]; then
    TARGET_PROJECT="${GCLOUD_PROJ}"
  fi
fi

if [[ -z "${TARGET_PROJECT}" && -z "${TARGET_API_KEY}" ]]; then
  if [[ -t 0 || -e /dev/tty ]]; then
    echo -en "${BLUE}▸${NC} Informe seu Google Cloud Project ID (ou pressione ENTER para usar AI Studio API Key): " >/dev/tty
    read -r TARGET_PROJECT </dev/tty || true
    if [[ -z "${TARGET_PROJECT}" ]]; then
      echo -en "${BLUE}▸${NC} Cole sua GEMINI_API_KEY do Google AI Studio: " >/dev/tty
      read -r TARGET_API_KEY </dev/tty || true
    fi
  fi
fi

# ==============================================================================
# Módulo 1: Moagem do Malte (Scaffold & Credenciais)
# ==============================================================================
log_step "Módulo 1: Criando o Projeto 'brewmaster-agent' em ${AGENT_DIR}"

PARENT_DIR="$(dirname "${AGENT_DIR}")"
AGENT_NAME="$(basename "${AGENT_DIR}")"
mkdir -p "${PARENT_DIR}"

if [[ -d "${AGENT_DIR}" ]]; then
  BACKUP_DIR="${AGENT_DIR}.bak.$(date +%H%M%S)"
  log_warn "Diretório ${AGENT_DIR} já existe. Movendo backup para ${BACKUP_DIR}..."
  mv "${AGENT_DIR}" "${BACKUP_DIR}"
fi

(
  cd "${PARENT_DIR}"
  agents-cli scaffold create "${AGENT_NAME}" --prototype --yes
)
cd "${AGENT_DIR}"
log_ok "Projeto criado com sucesso em: $(pwd)"

# Configura .env e app/.env
for env_file in ".env" "app/.env"; do
  if [[ -n "${TARGET_API_KEY}" && -z "${TARGET_PROJECT}" ]]; then
    cat << EOF > "${env_file}"
GOOGLE_GENAI_USE_VERTEXAI=FALSE
GEMINI_API_KEY=${TARGET_API_KEY}
GOOGLE_API_KEY=${TARGET_API_KEY}
EOF
    log_ok "Configurado ${env_file} para Google AI Studio (GOOGLE_GENAI_USE_VERTEXAI=FALSE)."
  else
    export GOOGLE_CLOUD_PROJECT="${TARGET_PROJECT}"
    export GOOGLE_CLOUD_LOCATION="global"
    export GOOGLE_GENAI_USE_VERTEXAI="TRUE"
    cat << EOF > "${env_file}"
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=${TARGET_PROJECT}
GOOGLE_CLOUD_LOCATION=global
EOF
    log_ok "Configurado ${env_file} para Vertex AI (PROJECT=${TARGET_PROJECT}, LOCATION=global)."
  fi
done

# ==============================================================================
# Módulos 2 & 8: Brassagem Modular (Agent + Prompt MD + ADK Skills + MCP SQLite)
# ==============================================================================
log_step "Módulos 2 & 8: Baixando Fritz, Prompt Markdown, ADK Skills e Servidor MCP SQLite"

RAW_BASE="https://raw.githubusercontent.com/felipemoz/brewmaster-with-adk/main/starter"
TS="$(date +%s)"

mkdir -p \
  "app/prompts" \
  "app/skills/mestre-bjcp/references" \
  "app/skills/sommelier-cervejeiro/references" \
  "tests/eval/datasets"

curl -fsSL "${RAW_BASE}/agent.py?t=${TS}" -o "app/agent.py"
curl -fsSL "${RAW_BASE}/mcp_cervejaria.py?t=${TS}" -o "app/mcp_cervejaria.py"
curl -fsSL "${RAW_BASE}/prompts/fritz_system_prompt.md?t=${TS}" -o "app/prompts/fritz_system_prompt.md"
curl -fsSL "${RAW_BASE}/skills/mestre-bjcp/SKILL.md?t=${TS}" -o "app/skills/mestre-bjcp/SKILL.md"
curl -fsSL "${RAW_BASE}/skills/mestre-bjcp/references/catalogo_receitas_agua.md?t=${TS}" -o "app/skills/mestre-bjcp/references/catalogo_receitas_agua.md"
curl -fsSL "${RAW_BASE}/skills/sommelier-cervejeiro/SKILL.md?t=${TS}" -o "app/skills/sommelier-cervejeiro/SKILL.md"
curl -fsSL "${RAW_BASE}/skills/sommelier-cervejeiro/references/guia_harmonizacao_copos.md?t=${TS}" -o "app/skills/sommelier-cervejeiro/references/guia_harmonizacao_copos.md"
curl -fsSL "${RAW_BASE}/basic-dataset.json?t=${TS}" -o "tests/eval/datasets/basic-dataset.json"

log_ok "Arquitetura modular instalada (app/agent.py, app/prompts/, app/skills/, app/mcp_cervejaria.py)."

# ==============================================================================
# Módulo 3: Instalação & Prova de Mosto no Terminal (Tools + Skills + MCP + Guardrail)
# ==============================================================================
log_step "Módulo 3: Instalando Dependências e Testando o Fritz no Terminal"

rm -f uv.lock
uv add --no-config "mcp>=1.8.0,<2.0.0"
uv lock --no-config
agents-cli install
log_ok "Dependências e pacote MCP instalados com uv.lock limpo (PyPI público)."

log_info "Teste 1/2 — Brassagem Completa (ADK Skills + Tools Matemáticas + Estoque SQLite MCP):"
agents-cli run "Fritz, consulte o estoque da cervejaria no banco SQLite, veja se tenho insumos para 20L de uma American IPA, ajuste minha água base (Ca 20, SO4 15, Cl 20 ppm) para o perfil Burton e me diga que off-flavor causa gosto de maçã verde!"

log_info "Teste 2/2 — Guardrail de Escopo (bloqueio determinístico antes do LLM):"
agents-cli run "Escreva um script em Python para investir em Bitcoin na bolsa de valores"

agents-cli run --stop-server || true
log_ok "Testes locais de terminal e Guardrails concluídos!"

# ==============================================================================
# Módulo 5: Concurso BJCP Automatizado (LLM-as-a-Judge Evaluation)
# ==============================================================================
if [[ "${SKIP_EVAL}" == "false" ]]; then
  log_step "Módulo 5: Executando Concurso BJCP Automatizado (agents-cli eval run)"
  agents-cli eval run || log_warn "Avaliação finalizou com alertas; verifique o relatório acima."
else
  log_info "Pulando Módulo 5 (--skip-eval)."
fi

# ==============================================================================
# Módulo 6: Controle de Qualidade da Cervejaria (Lint & Format)
# ==============================================================================
log_step "Módulo 6: Controle de Qualidade do Código (agents-cli lint --fix)"
agents-cli lint --fix || true
log_ok "Verificação de qualidade concluída!"

# ==============================================================================
# Módulo 7: Envase e Distribuição na Nuvem (Scaffold Enhance & Deploy)
# ==============================================================================
if [[ "${SKIP_DEPLOY}" == "false" && -n "${TARGET_PROJECT}" ]]; then
  log_step "Módulo 7: Envase na Nuvem — Deploy no Vertex AI Agent Runtime (${TARGET_PROJECT} / ${DEPLOY_REGION})"
  agents-cli scaffold enhance --deployment-target agent_runtime --yes
  rm -f uv.lock
  uv add --no-config "mcp>=1.8.0,<2.0.0"
  uv lock --no-config
  log_ok "Artefatos de deploy gerados e uv.lock higienizado para o Cloud Build."

  UV_NO_CONFIG=1 agents-cli deploy --project "${TARGET_PROJECT}" --region "${DEPLOY_REGION}"
  log_ok "Deploy no Vertex AI Agent Runtime concluído com sucesso!"
else
  log_step "Módulo 7: Preparando Artefatos de Deploy (Deploy na nuvem pulado)"
  agents-cli scaffold enhance --deployment-target agent_runtime --yes
  rm -f uv.lock
  uv add --no-config "mcp>=1.8.0,<2.0.0"
  uv lock --no-config
  if [[ -z "${TARGET_PROJECT}" ]]; then
    log_warn "Deploy no GCP pulado pois nenhum Project ID foi informado (modo AI Studio)."
  else
    log_info "Deploy no GCP pulado (--skip-deploy). Para fazer deploy depois, rode:"
    echo -e "  ${BOLD}cd ${AGENT_DIR} && UV_NO_CONFIG=1 agents-cli deploy --project ${TARGET_PROJECT} --region ${DEPLOY_REGION}${NC}"
  fi
fi

log_step "🎉 Lab Brewmaster with ADK Concluído com Sucesso!"
echo -e "  📂 Diretório do projeto: ${BOLD}${AGENT_DIR}${NC}"
echo -e "  🌐 Para abrir o Playground Visual Web agora, execute:"
echo -e "     ${BOLD}cd ${AGENT_DIR} && agents-cli playground${NC}"
echo -e "  🍻 Prost! Boas brassagens com o Fritz!"

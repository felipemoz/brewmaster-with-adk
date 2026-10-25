#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# Google Agents CLI (ADK) — Linux & macOS Prerequisites & Onboarding Script
# ==============================================================================
# Installs and configures everything required by Google Agents CLI & ADK on
# Linux (x86_64 / arm64) and macOS (Apple Silicon arm64 / Intel x86_64):
#   1. Base tools (curl, git, unzip, tar, xz)
#   2. uv / uvx (Astral Python package & tool manager)
#   3. Python >= 3.11 (via system/Homebrew or managed by uv)
#   4. Node.js LTS + npm + npx (required for `npx skills add google/agents-cli`)
#   5. Coding Agent check (Antigravity / Claude Code / Codex)
#   6. Google Cloud CLI (gcloud) + Terraform
#   7. GCE Metadata Server timeout fix (`NO_GCE_CHECK=true` on non-GCE hosts)
#   8. Live Credential Token Refresh Check (`gcloud auth application-default print-access-token`)
#      so expired/RAPT tokens (`google.auth.exceptions.RefreshError`) are caught
#      and re-authenticated automatically before running `agents-cli playground`!
#   9. Project Selection, Quota Project Alignment, API Enablement (`aiplatform`,
#      `generativelanguage`, `run`, `cloudbuild`, `cloudtrace`, `secretmanager`),
#      and `.env` sync across scaffolded agent projects.
#  10. Runs `uvx google-agents-cli setup`
#
# Usage:
#   bash <(curl -fsSL https://is.gd/brewmaster_setup_sh)
#   bash scripts/setup_agents_cli.sh [--project PROJECT_ID] [--region us-central1]
#                            [--api-key AI_STUDIO_KEY] [--non-interactive]
#                            [--skip-gcloud-auth] [--skip-apis]
# ==============================================================================

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}▸${NC} $*"; }
log_ok()    { echo -e "${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "${YELLOW}⚠️  Warning:${NC} $*"; }
log_err()   { echo -e "${RED}✗ Error:${NC} $*" >&2; }
log_step()  { echo -e "\n${BOLD}$*${NC}\n────────────────────────────────────────────────────────────"; }

INTERACTIVE=true
SKIP_GCLOUD_AUTH=false
SKIP_APIS=false
TARGET_PROJECT="${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-}}"
TARGET_REGION="${GOOGLE_CLOUD_LOCATION:-global}"
TARGET_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"

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
      TARGET_REGION="${2:-us-central1}"
      shift 2
      ;;
    --region=*)
      TARGET_REGION="${1#*=}"
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
    --non-interactive|-y)
      INTERACTIVE=false
      shift
      ;;
    --skip-gcloud-auth)
      SKIP_GCLOUD_AUTH=true
      shift
      ;;
    --skip-apis)
      SKIP_APIS=true
      shift
      ;;
    --help|-h)
      echo "Usage: bash $0 [--project PROJECT_ID] [--region REGION] [--api-key AI_STUDIO_KEY] [--non-interactive|-y] [--skip-gcloud-auth] [--skip-apis]"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Check if /dev/tty is available so interactive prompts work even via `curl ... | bash`
HAS_TTY=false
if [[ "${INTERACTIVE}" == "true" ]] && [[ -t 0 || -e /dev/tty ]]; then
  if ( exec </dev/tty ) 2>/dev/null; then
    HAS_TTY=true
  fi
fi

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "${OS_RAW}" in
  Linux*)  OS_NAME="linux" ;;
  Darwin*) OS_NAME="darwin" ;;
  *)
    log_err "Unsupported operating system: ${OS_RAW}. Please use Google Cloud Shell, Linux, or macOS."
    exit 1
    ;;
esac

# Helper to persist environment exports across bash and zsh profiles (idempotent)
persist_env_var() {
  local var_name="$1"
  local var_value="$2"
  local rc_files=("${HOME}/.bashrc" "${HOME}/.zshrc")
  for rc in "${rc_files[@]}"; do
    if [[ -f "${rc}" ]] || [[ "${OS_NAME}" == "darwin" && "${rc}" == "${HOME}/.zshrc" ]]; then
      touch "${rc}"
      if grep -q "^export ${var_name}=" "${rc}" 2>/dev/null; then
        local tmp_rc="${rc}.tmp.$$"
        grep -v "^export ${var_name}=" "${rc}" > "${tmp_rc}" || true
        echo "export ${var_name}=\"${var_value}\"" >> "${tmp_rc}"
        mv "${tmp_rc}" "${rc}"
      else
        echo "export ${var_name}=\"${var_value}\"" >> "${rc}"
      fi
    fi
  done
}

# Helper to update .env or app/.env inside current dir and existing ADK agent folders in $HOME
sync_agent_dotenv_files() {
  local mode="$1" # "aistudio" or "vertex"
  local candidate_files=()
  [[ -f ".env" ]]     && candidate_files+=(".env")
  [[ -f "app/.env" ]] && candidate_files+=("app/.env")

  # Also discover scaffolded agent projects in $HOME (e.g. ~/brewmaster-agent/.env)
  for f in "${HOME}"/*/.env "${HOME}"/*/app/.env; do
    if [[ -f "${f}" ]] && grep -q -E "GOOGLE_GENAI_USE_VERTEXAI|GOOGLE_CLOUD_PROJECT|GEMINI_API_KEY" "${f}" 2>/dev/null; then
      candidate_files+=("${f}")
    fi
  done

  for ef in "${candidate_files[@]}"; do
    log_info "Updating agent environment file '${ef}' for ${mode} mode..."
    local tmp_ef="${ef}.tmp.$$"
    grep -v -E "^(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_LOCATION|GOOGLE_GENAI_USE_VERTEXAI|GEMINI_API_KEY|GOOGLE_API_KEY)=" "${ef}" > "${tmp_ef}" || true
    if [[ "${mode}" == "aistudio" ]]; then
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=FALSE"
        echo "GEMINI_API_KEY=${TARGET_API_KEY}"
        echo "GOOGLE_API_KEY=${TARGET_API_KEY}"
        [[ -n "${TARGET_PROJECT}" ]] && echo "# GOOGLE_CLOUD_PROJECT=${TARGET_PROJECT}"
        [[ -n "${TARGET_REGION}" ]]  && echo "# GOOGLE_CLOUD_LOCATION=${TARGET_REGION}"
      } >> "${tmp_ef}"
    else
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
        echo "GOOGLE_CLOUD_PROJECT=${TARGET_PROJECT}"
        echo "GOOGLE_CLOUD_LOCATION=${TARGET_REGION}"
        [[ -n "${TARGET_API_KEY}" ]] && echo "# GEMINI_API_KEY=${TARGET_API_KEY}"
      } >> "${tmp_ef}"
    fi
    mv "${tmp_ef}" "${ef}"
    log_ok "Synced '${ef}' (${mode} credentials ready for 'agents-cli playground')."
  done
}

# Ensure ~/.local/bin is in PATH for the current session and persisted
mkdir -p "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
  if [[ -f "${rc}" ]] || [[ "${OS_NAME}" == "darwin" && "${rc}" == "${HOME}/.zshrc" ]]; then
    touch "${rc}"
    if ! grep -q 'HOME/.local/bin' "${rc}" 2>/dev/null; then
      echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${rc}"
    fi
  fi
done

# Helper to run privileged commands when not root
run_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    log_err "Root privileges or 'sudo' required to run: $*"
    return 1
  fi
}

# ==============================================================================
# 0. Detect GCE / Google Cloud Shell vs Non-GCE Environment (Fix 169.254.169.254 Timeout)
# ==============================================================================
log_step "0. Checking Compute Engine / Cloud Shell Environment (${OS_NAME}/${ARCH_RAW})"

IS_CLOUD_SHELL=false
if [[ "${CLOUD_SHELL:-}" == "true" ]] || [[ -n "${DEVSHELL_PROJECT_ID:-}" ]]; then
  IS_CLOUD_SHELL=true
  unset NO_GCE_CHECK || true
  log_ok "Google Cloud Shell detected (DEVSHELL_PROJECT_ID=${DEVSHELL_PROJECT_ID:-(unset)})."
elif [[ "${OS_NAME}" == "linux" ]] && curl -s -f -m 1 -H "Metadata-Flavor: Google" "http://169.254.169.254/computeMetadata/v1/instance/id" >/dev/null 2>&1; then
  log_ok "Running on a Google Compute Engine VM (Metadata server reachable)."
else
  log_info "Non-GCE host detected (${OS_NAME}). Setting NO_GCE_CHECK=true to skip 169.254.169.254 probes."
  export NO_GCE_CHECK="true"
  persist_env_var "NO_GCE_CHECK" "true"
  log_ok "Exported NO_GCE_CHECK=true (eliminates the 3x3s metadata server connection timeouts)."
fi

# Always set UV_NO_CONFIG=1 (prevents corporate proxies from leaking into uv.lock for Cloud Build)
# and GOOGLE_API_USE_CLIENT_CERTIFICATE=false (prevents mTLS client cert errors)
export UV_NO_CONFIG="1"
export GOOGLE_API_USE_CLIENT_CERTIFICATE="false"
persist_env_var "UV_NO_CONFIG" "1"
persist_env_var "GOOGLE_API_USE_CLIENT_CERTIFICATE" "false"
log_ok "Exported UV_NO_CONFIG=1 and GOOGLE_API_USE_CLIENT_CERTIFICATE=false."

# Warn if running as root when a standard user exists
if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  log_warn "You are running this script with sudo/root (SUDO_USER=${SUDO_USER})."
  log_warn "Skills and uv tools will install into /root instead of your user home directory."
  log_warn "Recommended: run as your regular user without sudo."
fi

# ==============================================================================
# 1. Base System Packages (git, curl, unzip, tar)
# ==============================================================================
log_step "1. Verifying Base System Utilities (git, curl, unzip)"

MISSING_BASE=()
for cmd in curl git unzip tar; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING_BASE+=("$cmd")
done

if [[ ${#MISSING_BASE[@]} -gt 0 ]]; then
  log_info "Installing missing base utilities: ${MISSING_BASE[*]}"
  if [[ "${OS_NAME}" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install "${MISSING_BASE[@]}"
    else
      log_info "Triggering macOS Xcode Command Line Tools check for git/curl..."
      xcode-select --install 2>/dev/null || true
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    run_sudo apt-get update -y
    run_sudo apt-get install -y curl git unzip tar xz-utils ca-certificates gnupg
  elif command -v dnf >/dev/null 2>&1; then
    run_sudo dnf install -y curl git unzip tar xz ca-certificates gnupg2
  elif command -v yum >/dev/null 2>&1; then
    run_sudo yum install -y curl git unzip tar xz ca-certificates gnupg2
  else
    log_err "Unsupported package manager. Please install manually: ${MISSING_BASE[*]}"
    exit 1
  fi
fi
log_ok "Base utilities available (git: $(git --version | awk '{print $3}'))."

# ==============================================================================
# 2. Install uv & uvx
# ==============================================================================
log_step "2. Checking uv (Astral Python Package & Tool Manager)"

if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
  log_ok "uv is already installed ($(uv --version))."
else
  log_info "Installing uv via https://astral.sh/uv/install.sh..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
  log_ok "Installed uv ($(uv --version))."
fi

# ==============================================================================
# 3. Verify Python >= 3.11
# ==============================================================================
log_step "3. Checking Python >= 3.11"

check_python_311() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null
    return $?
  fi
  return 1
}

if check_python_311; then
  PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
  log_ok "System Python ${PY_VER} meets requirement (>= 3.11)."
else
  log_info "System Python < 3.11 or missing. Installing Python 3.12 via uv..."
  uv python install 3.12 --default
  export PATH="${HOME}/.local/bin:${PATH}"
  PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
  log_ok "Installed Python ${PY_VER} via uv."
fi

# ==============================================================================
# 4. Verify Node.js & npx (Required for `npx skills add google/agents-cli`)
# ==============================================================================
log_step "4. Checking Node.js, npm, and npx"

if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
  log_ok "Node.js ($(node --version)) and npx ($(npx --version)) are installed."
else
  log_info "npx is missing (note: standalone IDE node binaries often lack npm/npx)."
  log_info "Installing standalone Node.js LTS (v22) into ~/.local/node-lts..."

  case "${ARCH_RAW}" in
    x86_64)        NODE_ARCH="x64" ;;
    aarch64|arm64) NODE_ARCH="arm64" ;;
    *) log_err "Unsupported architecture for Node.js tarball: ${ARCH_RAW}"; exit 1 ;;
  esac

  NODE_VERSION="v22.14.0"
  NODE_INSTALL_DIR="${HOME}/.local/node-lts"
  rm -rf "${NODE_INSTALL_DIR}"
  mkdir -p "${NODE_INSTALL_DIR}"

  if [[ "${OS_NAME}" == "darwin" ]]; then
    NODE_DIST="node-${NODE_VERSION}-darwin-${NODE_ARCH}"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}.tar.gz"
    curl -fsSL "${NODE_URL}" | tar -xz -C "${NODE_INSTALL_DIR}" --strip-components=1
  else
    NODE_DIST="node-${NODE_VERSION}-linux-${NODE_ARCH}"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}.tar.xz"
    curl -fsSL "${NODE_URL}" | tar -xJ -C "${NODE_INSTALL_DIR}" --strip-components=1
  fi

  ln -sf "${NODE_INSTALL_DIR}/bin/node" "${HOME}/.local/bin/node"
  ln -sf "${NODE_INSTALL_DIR}/bin/npm"  "${HOME}/.local/bin/npm"
  ln -sf "${NODE_INSTALL_DIR}/bin/npx"  "${HOME}/.local/bin/npx"
  export PATH="${HOME}/.local/bin:${NODE_INSTALL_DIR}/bin:${PATH}"

  log_ok "Installed Node.js ($(node --version)), npm ($(npm --version)), and npx ($(npx --version))."
fi

# ==============================================================================
# 5. Check Coding Agent (Antigravity, Claude Code, or Codex)
# ==============================================================================
log_step "5. Checking Coding Agent Environment"

DETECTED_AGENTS=()
command -v agy >/dev/null 2>&1          && DETECTED_AGENTS+=("Antigravity (agy)")
command -v antigravity >/dev/null 2>&1  && DETECTED_AGENTS+=("Antigravity")
command -v claude >/dev/null 2>&1       && DETECTED_AGENTS+=("Claude Code")
command -v codex >/dev/null 2>&1        && DETECTED_AGENTS+=("Codex")
[[ -d "${HOME}/.antigravity" || -d "${HOME}/.gemini" ]] && DETECTED_AGENTS+=("Antigravity/Gemini CLI config")

if [[ ${#DETECTED_AGENTS[@]} -gt 0 ]]; then
  log_ok "Detected coding agent(s): ${DETECTED_AGENTS[*]}"
else
  log_warn "No coding agent CLI (antigravity, claude, codex) detected on PATH."
  log_info "You can install one via:"
  log_info "  • Antigravity: https://antigravity.google/"
  log_info "  • Claude Code: npm install -g @anthropic-ai/claude-code"
  log_info "  • OpenAI Codex: npm install -g @openai/codex"
fi

# ==============================================================================
# 6. Check Google Cloud CLI (gcloud)
# ==============================================================================
log_step "6. Checking Google Cloud CLI (gcloud)"

if command -v gcloud >/dev/null 2>&1; then
  GCLOUD_VER="$(gcloud --version 2>/dev/null | head -n 1)"
  log_ok "${GCLOUD_VER} is installed."
else
  log_info "Installing Google Cloud CLI into ${HOME}/.local/google-cloud-sdk..."
  case "${ARCH_RAW}" in
    x86_64)        GCLOUD_ARCH="x86_64" ;;
    aarch64|arm64) GCLOUD_ARCH="arm" ;;
    *) log_err "Unsupported architecture for gcloud: ${ARCH_RAW}"; exit 1 ;;
  esac

  GCLOUD_TAR="google-cloud-cli-${OS_NAME}-${GCLOUD_ARCH}.tar.gz"
  curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_TAR}" -o "/tmp/${GCLOUD_TAR}"
  rm -rf "${HOME}/.local/google-cloud-sdk"
  tar -xzf "/tmp/${GCLOUD_TAR}" -C "${HOME}/.local"
  rm -f "/tmp/${GCLOUD_TAR}"
  "${HOME}/.local/google-cloud-sdk/install.sh" --quiet --path-update=true
  ln -sf "${HOME}/.local/google-cloud-sdk/bin/gcloud" "${HOME}/.local/bin/gcloud"
  ln -sf "${HOME}/.local/google-cloud-sdk/bin/bq"     "${HOME}/.local/bin/bq"
  ln -sf "${HOME}/.local/google-cloud-sdk/bin/gsutil" "${HOME}/.local/bin/gsutil"
  export PATH="${HOME}/.local/google-cloud-sdk/bin:${PATH}"
  log_ok "Installed Google Cloud CLI ($(gcloud --version | head -n 1))."
fi

# ==============================================================================
# 7. Check Terraform (Required for Cloud Deployment)
# ==============================================================================
log_step "7. Checking Terraform"

if command -v terraform >/dev/null 2>&1; then
  TF_VER="$(terraform version | head -n 1)"
  log_ok "${TF_VER} is installed."
else
  log_info "Installing Terraform into ~/.local/bin..."
  case "${ARCH_RAW}" in
    x86_64)        TF_ARCH="amd64" ;;
    aarch64|arm64) TF_ARCH="arm64" ;;
    *) log_err "Unsupported architecture for Terraform: ${ARCH_RAW}"; exit 1 ;;
  esac

  TF_VERSION="1.11.2"
  TF_ZIP="terraform_${TF_VERSION}_${OS_NAME}_${TF_ARCH}.zip"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_ZIP}" -o "/tmp/${TF_ZIP}"
  unzip -o -q "/tmp/${TF_ZIP}" -d "${HOME}/.local/bin"
  rm -f "/tmp/${TF_ZIP}"
  chmod +x "${HOME}/.local/bin/terraform"
  log_ok "Installed $(terraform version | head -n 1)."
fi

# ==============================================================================
# 8. Credentials & Project Setup (Vertex AI ADC vs. Google AI Studio API Key)
# ==============================================================================
log_step "8. Credentials & Project Setup (Playground & Cloud Deployment)"

ADC_FILE="${CLOUDSDK_CONFIG:-${HOME}/.config/gcloud}/application_default_credentials.json"
AUTH_MODE="vertex"

if [[ -n "${TARGET_API_KEY}" && -z "${TARGET_PROJECT}" ]]; then
  AUTH_MODE="aistudio"
elif [[ "${HAS_TTY}" == "true" && "${SKIP_GCLOUD_AUTH}" == "false" && -z "${TARGET_PROJECT}" && -z "${TARGET_API_KEY}" ]]; then
  echo -e "How would you like to authenticate your ADK agents (e.g. for ${BOLD}agents-cli playground${NC})?"
  echo -e "  ${BOLD}[1]${NC} Google Cloud / Vertex AI (gcloud ADC + GCP Project + auto-enable APIs) ${GREEN}[Default]${NC}"
  echo -e "  ${BOLD}[2]${NC} Google AI Studio API Key (GEMINI_API_KEY from https://aistudio.google.com/apikey)"
  echo -e "  ${BOLD}[3]${NC} Both (Configure GCP Project/APIs AND set an AI Studio API Key)"
  echo -en "${BLUE}▸${NC} Choose [1/2/3] (default: 1): " >/dev/tty
  read -r AUTH_CHOICE </dev/tty || true
  case "${AUTH_CHOICE}" in
    2) AUTH_MODE="aistudio" ;;
    3) AUTH_MODE="both" ;;
    *) AUTH_MODE="vertex" ;;
  esac
fi

# --- 8A. Google AI Studio API Key Configuration ---
if [[ "${AUTH_MODE}" == "aistudio" || "${AUTH_MODE}" == "both" ]]; then
  if [[ -z "${TARGET_API_KEY}" && "${HAS_TTY}" == "true" ]]; then
    echo -en "${BLUE}▸${NC} Paste your Google AI Studio API Key (from https://aistudio.google.com/apikey): " >/dev/tty
    read -r TARGET_API_KEY </dev/tty || true
  fi
  if [[ -n "${TARGET_API_KEY}" ]]; then
    export GEMINI_API_KEY="${TARGET_API_KEY}"
    export GOOGLE_API_KEY="${TARGET_API_KEY}"
    persist_env_var "GEMINI_API_KEY" "${TARGET_API_KEY}"
    persist_env_var "GOOGLE_API_KEY" "${TARGET_API_KEY}"
    if [[ "${AUTH_MODE}" == "aistudio" ]]; then
      export GOOGLE_GENAI_USE_VERTEXAI="FALSE"
      persist_env_var "GOOGLE_GENAI_USE_VERTEXAI" "FALSE"
      sync_agent_dotenv_files "aistudio"
      log_ok "Configured AI Studio API Key (GEMINI_API_KEY & GOOGLE_API_KEY) with GOOGLE_GENAI_USE_VERTEXAI=FALSE."
    else
      log_ok "Saved AI Studio API Key (GEMINI_API_KEY & GOOGLE_API_KEY)."
    fi
  else
    log_warn "No AI Studio API Key provided."
  fi
fi

# --- 8B. Google Cloud / Vertex AI Project, Live ADC Token Check & APIs ---
if [[ "${SKIP_GCLOUD_AUTH}" == "false" ]] && [[ "${AUTH_MODE}" == "vertex" || "${AUTH_MODE}" == "both" ]]; then
  # 1. Verify active gcloud user login AND that its token is not expired!
  ACTIVE_ACCOUNT="$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n 1 || true)"
  if [[ -n "${ACTIVE_ACCOUNT}" ]] && CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth print-access-token >/dev/null 2>&1; then
    log_ok "Active gcloud account verified (token valid): ${ACTIVE_ACCOUNT}"
  elif [[ "${HAS_TTY}" == "true" ]]; then
    if [[ -n "${ACTIVE_ACCOUNT}" ]]; then
      log_warn "gcloud session for '${ACTIVE_ACCOUNT}' is expired or requires reauthentication."
    else
      log_info "No active gcloud account found."
    fi
    log_info "Launching 'gcloud auth login'..."
    gcloud auth login </dev/tty
    ACTIVE_ACCOUNT="$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n 1 || true)"
    log_ok "Authenticated gcloud as: ${ACTIVE_ACCOUNT}"
  else
    log_warn "gcloud authentication missing or expired and no interactive TTY available. Run 'gcloud auth login' manually."
  fi

  # 2. Verify Application Default Credentials (ADC) AND test live token refresh!
  #    IMPORTANT: Even in Cloud Shell, the local metadata server token lacks the
  #    'cloud-platform' scope required by Vertex AI (`aiplatform.*` returns 403 PERMISSION_DENIED)!
  #    Therefore, an explicit `$ADC_FILE` from `gcloud auth application-default login` is ALWAYS required!
  ADC_VALID=false
  if [[ -f "${ADC_FILE}" ]] && CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth application-default print-access-token >/dev/null 2>&1; then
    ADC_VALID=true
  fi

  if [[ "${ADC_VALID}" == "true" ]]; then
    log_ok "Application Default Credentials (ADC) verified at ${ADC_FILE} (live token refresh succeeded)."
  elif [[ "${HAS_TTY}" == "true" ]]; then
    if [[ -f "${ADC_FILE}" ]]; then
      log_warn "ADC file exists at ${ADC_FILE}, but its token is EXPIRED (causes RefreshError in playground)."
    elif [[ "${IS_CLOUD_SHELL}" == "true" ]]; then
      log_info "Cloud Shell default metadata credentials lack 'cloud-platform' scope for Vertex AI (causes 403 PERMISSION_DENIED)."
    else
      log_info "Application Default Credentials (ADC) not found."
    fi
    log_info "Launching 'gcloud auth application-default login'..."
    gcloud auth application-default login </dev/tty
    log_ok "Fresh Application Default Credentials configured at ${ADC_FILE}."
  else
    log_warn "ADC missing or expired at ${ADC_FILE}. Run 'gcloud auth application-default login' manually."
  fi

  # 3. Resolve & Configure Google Cloud Project ID (including AI Studio cloud projects)
  if [[ -z "${TARGET_PROJECT}" ]]; then
    CURRENT_GCLOUD_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ "${CURRENT_GCLOUD_PROJECT}" != "(unset)" && -n "${CURRENT_GCLOUD_PROJECT}" ]]; then
      TARGET_PROJECT="${CURRENT_GCLOUD_PROJECT}"
    fi
  fi

  if [[ "${HAS_TTY}" == "true" ]]; then
    if [[ -n "${TARGET_PROJECT}" ]]; then
      echo -en "${BLUE}▸${NC} Current GCP Project is '${BOLD}${TARGET_PROJECT}${NC}'. Press ENTER to keep it, or type a different Project ID: " >/dev/tty
      read -r USER_PROJECT_INPUT </dev/tty || true
      if [[ -n "${USER_PROJECT_INPUT}" ]]; then
        TARGET_PROJECT="${USER_PROJECT_INPUT}"
      fi
    else
      log_info "Listing your available Google Cloud / AI Studio projects (top 15):"
      CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud projects list --format="table(projectId,name)" --limit=15 2>/dev/null || true
      echo -en "${BLUE}▸${NC} Enter the Google Cloud Project ID to use for Agents CLI / ADK: " >/dev/tty
      read -r TARGET_PROJECT </dev/tty || true
    fi
  fi

  if [[ -n "${TARGET_PROJECT}" && "${TARGET_PROJECT}" != "(unset)" ]]; then
    log_info "Setting active Google Cloud project to '${TARGET_PROJECT}'..."
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud config set project "${TARGET_PROJECT}" --quiet >/dev/null 2>&1 || true

    export GOOGLE_CLOUD_PROJECT="${TARGET_PROJECT}"
    export GOOGLE_CLOUD_LOCATION="${TARGET_REGION}"
    export GOOGLE_GENAI_USE_VERTEXAI="TRUE"

    persist_env_var "GOOGLE_CLOUD_PROJECT" "${TARGET_PROJECT}"
    persist_env_var "GOOGLE_CLOUD_LOCATION" "${TARGET_REGION}"
    persist_env_var "GOOGLE_GENAI_USE_VERTEXAI" "TRUE"
    sync_agent_dotenv_files "vertex"
    log_ok "Configured GOOGLE_CLOUD_PROJECT=${TARGET_PROJECT}, GOOGLE_CLOUD_LOCATION=${TARGET_REGION}, GOOGLE_GENAI_USE_VERTEXAI=TRUE"

    # Check if billing is enabled on the project (AI Studio free-tier projects often lack billing for Vertex AI)
    BILLING_ENABLED="$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud billing projects describe "${TARGET_PROJECT}" --format="value(billingEnabled)" 2>/dev/null || true)"
    if [[ "${BILLING_ENABLED}" == "False" ]]; then
      log_warn "Billing is NOT enabled on project '${TARGET_PROJECT}' (common for new AI Studio projects)."
      log_warn "Vertex AI (aiplatform.googleapis.com) requires a billing account, OR use Mode [2] (AI Studio API Key)."
      log_warn "Link billing at: https://console.cloud.google.com/billing/linkedaccount?project=${TARGET_PROJECT}"
    fi

    # 4. Enable Required Google Cloud APIs (including generativelanguage.googleapis.com for AI Studio projects)
    if [[ "${SKIP_APIS}" == "false" ]]; then
      log_info "Enabling core prerequisite APIs (serviceusage, cloudresourcemanager) on '${TARGET_PROJECT}'..."
      CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud services enable \
        serviceusage.googleapis.com \
        cloudresourcemanager.googleapis.com \
        --project="${TARGET_PROJECT}" --quiet 2>/dev/null || log_warn "Could not enable serviceusage/cloudresourcemanager APIs."

      REQUIRED_APIS=(
        "generativelanguage.googleapis.com"
        "aiplatform.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudtrace.googleapis.com"
        "secretmanager.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "iam.googleapis.com"
        "iamcredentials.googleapis.com"
        "storage.googleapis.com"
      )
      log_info "Enabling ADK, AI Studio & Agent Platform APIs (${#REQUIRED_APIS[@]} services) on '${TARGET_PROJECT}' (takes ~20-45s)..."
      if CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud services enable "${REQUIRED_APIS[@]}" --project="${TARGET_PROJECT}" --quiet; then
        log_ok "All required Google Cloud & Gemini APIs are enabled on '${TARGET_PROJECT}'."
      else
        log_warn "Some APIs could not be enabled automatically (if this is an unbilled AI Studio project, use --api-key YOUR_AI_STUDIO_KEY)."
      fi
    fi

    # 5. Align ADC Quota Project (prevents 403 QUOTA_EXCEEDED / credentials error in playground!)
    if [[ -f "${ADC_FILE}" ]]; then
      log_info "Setting ADC quota project to '${TARGET_PROJECT}'..."
      if CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth application-default set-quota-project "${TARGET_PROJECT}" --quiet >/dev/null 2>&1; then
        log_ok "ADC quota project aligned to '${TARGET_PROJECT}'."
      else
        log_warn "Could not set ADC quota project automatically (run: gcloud auth application-default set-quota-project ${TARGET_PROJECT})."
      fi
    fi
  else
    log_warn "No Google Cloud project selected. Pass '--project YOUR_PROJECT_ID' or '--api-key YOUR_AI_STUDIO_KEY'."
  fi
fi

# Install helper utility `agents-cli-env` in ~/.local/bin so users can configure `.env` inside any agent project
SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "${SCRIPT_DIR_LOCAL}" && -f "${SCRIPT_DIR_LOCAL}/agents-cli-env.sh" ]]; then
  cp "${SCRIPT_DIR_LOCAL}/agents-cli-env.sh" "${HOME}/.local/bin/agents-cli-env"
else
  curl -fsSL "https://raw.githubusercontent.com/felipemoz/brewmaster-with-adk/main/scripts/agents-cli-env.sh?t=$(date +%s)" -o "${HOME}/.local/bin/agents-cli-env"
fi
chmod +x "${HOME}/.local/bin/agents-cli-env"

# ==============================================================================
# 9. Install / Upgrade `google-agents-cli` & Run Setup
# ==============================================================================
log_step "9. Installing Latest Google Agents CLI & Running Setup"

log_info "Installing/upgrading google-agents-cli into ~/.local/bin (overrides older pre-installed Cloud Shell versions)..."
uv tool install --upgrade --force google-agents-cli
export PATH="${HOME}/.local/bin:${PATH}"
hash -r 2>/dev/null || true

SETUP_ARGS=("setup")
if ! CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth application-default print-access-token >/dev/null 2>&1; then
  if [[ "${AUTH_MODE}" == "aistudio" ]] || [[ "${SKIP_GCLOUD_AUTH}" == "true" ]] || [[ "${HAS_TTY}" == "false" ]]; then
    SETUP_ARGS+=("--skip-auth")
  else
    SETUP_ARGS+=("--interactive")
  fi
fi

log_info "Running: NO_GCE_CHECK=${NO_GCE_CHECK:-false} agents-cli ${SETUP_ARGS[*]}"
if [[ "${HAS_TTY}" == "true" ]]; then
  "${HOME}/.local/bin/agents-cli" "${SETUP_ARGS[@]}" </dev/tty
else
  "${HOME}/.local/bin/agents-cli" "${SETUP_ARGS[@]}"
fi

# ==============================================================================
# 10. Pre-configure MCP Package & Brewmaster Skill (Zero-Friction MCP in ADK)
# ==============================================================================
log_step "10. Pre-configuring MCP Support (FastMCP / McpToolset) & Brewmaster Skill"

# 10A. Install the brewmaster-adk skill from github.com/felipemoz/brewmaster-with-adk
if command -v npx >/dev/null 2>&1; then
  log_info "Installing 'brewmaster-adk' skill into ~/.agents/skills..."
  npx -y skills add https://github.com/felipemoz/brewmaster-with-adk -y --all -g >/dev/null 2>&1 || true
  log_ok "Installed 'brewmaster-adk' skill."
fi

# 10B. Inject 'mcp>=1.8.0' into google-agents-cli's ADK templateconfig.yaml so every
#      future `agents-cli scaffold create <name>` includes `mcp` in pyproject.toml!
python3 - << 'PYEOF' 2>/dev/null || true
import glob, os
uv_tools = os.path.expanduser("~/.local/share/uv/tools/google-agents-cli")
for cfg in glob.glob(os.path.join(uv_tools, "**/scaffold/agents/adk/.template/templateconfig.yaml"), recursive=True):
    txt = open(cfg).read()
    if '"mcp>=' not in txt:
        txt = txt.replace(
            '- "a2a-sdk[http-server]>=1.0,<2"',
            '- "a2a-sdk[http-server]>=1.0,<2"\n    - "mcp>=1.8.0"',
        )
        open(cfg, "w").write(txt)
PYEOF
log_ok "Patched agents-cli ADK template to include 'mcp>=1.8.0' by default on every new scaffold."

# 10C. Ensure any existing ADK agent projects in current dir or $HOME have `mcp` installed
for proj_toml in "./pyproject.toml" "${HOME}"/*/pyproject.toml; do
  if [[ -f "${proj_toml}" ]] && grep -q "google-adk" "${proj_toml}" 2>/dev/null; then
    proj_dir="$(dirname "${proj_toml}")"
    if ! grep -q '"mcp' "${proj_toml}" 2>/dev/null; then
      log_info "Adding 'mcp' package to existing ADK project '${proj_dir}'..."
      (cd "${proj_dir}" && uv add mcp >/dev/null 2>&1) || true
      log_ok "Installed 'mcp' in '${proj_dir}'."
    fi
  fi
done

log_step "Setup Complete!"
echo -e "  ${GREEN}✓${NC} OS / Arch:    ${OS_NAME} (${ARCH_RAW})"
echo -e "  ${GREEN}✓${NC} Python:       $(python3 --version)"
echo -e "  ${GREEN}✓${NC} uv:           $(uv --version)"
echo -e "  ${GREEN}✓${NC} Node / npx:   $(node --version) / npx $(npx --version)"
echo -e "  ${GREEN}✓${NC} gcloud:       $(gcloud --version 2>/dev/null | head -n 1)"
echo -e "  ${GREEN}✓${NC} Terraform:    $(terraform version | head -n 1)"
echo -e "  ${GREEN}✓${NC} GCP Project:  ${GOOGLE_CLOUD_PROJECT:-(not set)} (${GOOGLE_CLOUD_LOCATION:-us-central1})"
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo -e "  ${GREEN}✓${NC} AI Studio:    API Key configured (GOOGLE_GENAI_USE_VERTEXAI=${GOOGLE_GENAI_USE_VERTEXAI:-FALSE})"
fi
echo -e "  ${GREEN}✓${NC} Helper CLI:   agents-cli-env (fixes .env & app/.env and verifies ADC token)"
echo -e "  ${GREEN}✓${NC} agents-cli:   $(uv tool run --from google-agents-cli agents-cli --version 2>/dev/null || echo 'installed')"
if [[ "${OS_NAME}" == "darwin" ]]; then
  echo -e "\nRun ${BOLD}source ~/.zshrc${NC} (or open a new terminal) and verify with: ${BOLD}agents-cli info${NC}"
else
  echo -e "\nRun ${BOLD}source ~/.bashrc${NC} (or open a new terminal) and verify with: ${BOLD}agents-cli info${NC}"
fi

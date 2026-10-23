#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# Google Agents CLI (ADK) — Linux & macOS Prerequisites & Onboarding Installer
# ==============================================================================
# Installs and verifies all prerequisites required by Google Agents CLI on
# Linux (x86_64 / arm64) and macOS (Apple Silicon arm64 / Intel x86_64):
#   1. Base tools (curl, git, unzip, tar, xz)
#   2. uv / uvx (Astral Python package & tool manager)
#   3. Python >= 3.11 (via system/Homebrew or managed by uv)
#   4. Node.js LTS + npm + npx (required for `npx skills add google/agents-cli`)
#   5. Google Cloud CLI (gcloud) + Application Default Credentials (ADC)
#   6. Terraform (HashiCorp IaC CLI for agent deployment)
#   7. Coding Agent check (Antigravity / Claude Code / Codex)
#   8. GCE Metadata Server timeout fix (`NO_GCE_CHECK=true` on non-GCE hosts)
#   9. Runs `uvx google-agents-cli setup`
#
# Usage:
#   bash setup_agents_cli.sh [--non-interactive] [--skip-gcloud-auth]
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

for arg in "$@"; do
  case "$arg" in
    --non-interactive|-y) INTERACTIVE=false ;;
    --skip-gcloud-auth)   SKIP_GCLOUD_AUTH=true ;;
    --help|-h)
      echo "Usage: bash $0 [--non-interactive|-y] [--skip-gcloud-auth]"
      exit 0
      ;;
  esac
done

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "${OS_RAW}" in
  Linux*)  OS_NAME="linux" ;;
  Darwin*) OS_NAME="darwin" ;;
  *)
    log_err "Unsupported operating system: ${OS_RAW}. For Windows, use setup_agents_cli.ps1."
    exit 1
    ;;
esac

# Helper to persist environment exports across bash and zsh profiles
persist_rc_line() {
  local marker="$1"
  local line="$2"
  local rc_files=("${HOME}/.bashrc" "${HOME}/.zshrc")
  for rc in "${rc_files[@]}"; do
    if [[ -f "${rc}" ]] || [[ "${OS_NAME}" == "darwin" && "${rc}" == "${HOME}/.zshrc" ]]; then
      touch "${rc}"
      if ! grep -q "${marker}" "${rc}" 2>/dev/null; then
        echo "${line}" >> "${rc}"
      fi
    fi
  done
}

# Ensure ~/.local/bin is in PATH for the current session and persisted
mkdir -p "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"
persist_rc_line 'HOME/.local/bin' 'export PATH="${HOME}/.local/bin:${PATH}"'

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
# 0. Detect GCE vs Non-GCE Environment (Fix 169.254.169.254 Timeout)
# ==============================================================================
log_step "0. Checking Compute Engine Metadata Server & Environment (${OS_NAME}/${ARCH_RAW})"

if [[ "${OS_NAME}" == "linux" ]] && curl -s -f -m 1 -H "Metadata-Flavor: Google" "http://169.254.169.254/computeMetadata/v1/instance/id" >/dev/null 2>&1; then
  log_ok "Running on a Google Compute Engine VM (Metadata server reachable)."
else
  log_info "Non-GCE host detected (${OS_NAME}). Setting NO_GCE_CHECK=true to skip 169.254.169.254 probes."
  export NO_GCE_CHECK="true"
  persist_rc_line "export NO_GCE_CHECK=" 'export NO_GCE_CHECK="true"'
  log_ok "Exported NO_GCE_CHECK=true (eliminates the 3x3s metadata server connection timeouts)."
fi

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
# 8. Verify Application Default Credentials (ADC) & Run `agents-cli setup`
# ==============================================================================
log_step "8. Configuring Authentication & Running agents-cli setup"

ADC_FILE="${CLOUDSDK_CONFIG:-${HOME}/.config/gcloud}/application_default_credentials.json"
SETUP_ARGS=("setup")

if [[ -f "${ADC_FILE}" ]]; then
  log_ok "Application Default Credentials (ADC) found at ${ADC_FILE}."
elif [[ "${SKIP_GCLOUD_AUTH}" == "false" ]] && [[ "${INTERACTIVE}" == "true" ]]; then
  log_warn "No Application Default Credentials found at ${ADC_FILE}."
  log_info "Passing --interactive (-i) to 'agents-cli setup' so you can authenticate interactively."
  SETUP_ARGS+=("--interactive")
else
  log_warn "No ADC file found. Run 'gcloud auth application-default login' or 'agents-cli setup -i' later."
fi

log_info "Running: NO_GCE_CHECK=${NO_GCE_CHECK:-false} uvx google-agents-cli ${SETUP_ARGS[*]}"
uvx google-agents-cli "${SETUP_ARGS[@]}"

log_step "Setup Complete!"
echo -e "  ${GREEN}✓${NC} OS / Arch:  ${OS_NAME} (${ARCH_RAW})"
echo -e "  ${GREEN}✓${NC} Python:     $(python3 --version)"
echo -e "  ${GREEN}✓${NC} uv:         $(uv --version)"
echo -e "  ${GREEN}✓${NC} Node / npx: $(node --version) / npx $(npx --version)"
echo -e "  ${GREEN}✓${NC} gcloud:     $(gcloud --version 2>/dev/null | head -n 1)"
echo -e "  ${GREEN}✓${NC} Terraform:  $(terraform version | head -n 1)"
echo -e "  ${GREEN}✓${NC} agents-cli: $(uv tool run --from google-agents-cli agents-cli --version 2>/dev/null || echo 'installed')"
if [[ "${OS_NAME}" == "darwin" ]]; then
  echo -e "\nRun ${BOLD}source ~/.zshrc${NC} (or open a new terminal) and verify with: ${BOLD}agents-cli info${NC}"
else
  echo -e "\nRun ${BOLD}source ~/.bashrc${NC} (or open a new terminal) and verify with: ${BOLD}agents-cli info${NC}"
fi

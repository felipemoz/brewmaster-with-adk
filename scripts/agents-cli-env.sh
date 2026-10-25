#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# agents-cli-env — Configura ou alterna o projeto ADK (.env e app/.env) entre
# Google Cloud Vertex AI (ADC) e Google AI Studio (API Key), garante que o
# arquivo ADC exista com escopo do Vertex AI (mesmo no Cloud Shell) e habilita
# todas as APIs necessárias no projeto GCP.
# ==============================================================================
# Uso:
#   agents-cli-env vertex [PROJECT_ID] [REGION]
#   agents-cli-env aistudio <SUA_CHAVE_AI_STUDIO>
# ==============================================================================

set -euo pipefail

FILES=()
[[ -f ".env" ]]     && FILES+=(".env")
[[ -f "app/.env" ]] && FILES+=("app/.env")
if [[ ${#FILES[@]} -eq 0 ]]; then
  if [[ -d "app" ]]; then FILES=(".env" "app/.env"); else FILES=(".env"); fi
fi

MODE="${1:-status}"

case "${MODE}" in
  aistudio)
    KEY="${2:-${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}}"
    if [[ -z "${KEY}" ]]; then
      echo "Uso: agents-cli-env aistudio <SUA_CHAVE_AI_STUDIO>"
      exit 1
    fi
    for TARGET_ENV in "${FILES[@]}"; do
      touch "${TARGET_ENV}"
      grep -v -E "^(GOOGLE_GENAI_USE_VERTEXAI|GEMINI_API_KEY|GOOGLE_API_KEY|GOOGLE_API_USE_CLIENT_CERTIFICATE)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=FALSE"
        echo "GEMINI_API_KEY=${KEY}"
        echo "GOOGLE_API_KEY=${KEY}"
        echo "GOOGLE_API_USE_CLIENT_CERTIFICATE=false"
      } >> "${TARGET_ENV}.tmp"
      mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
      echo "✓ Configurado ${TARGET_ENV} para Google AI Studio (GOOGLE_GENAI_USE_VERTEXAI=FALSE)."
    done
    echo "  Agora execute: agents-cli playground"
    ;;
  vertex)
    PROJ="${2:-${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}}"
    LOC="${3:-global}"
    if [[ -z "${PROJ}" || "${PROJ}" == "(unset)" ]]; then
      echo "Uso: agents-cli-env vertex <PROJECT_ID> [REGION]"
      exit 1
    fi

    CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud config set project "${PROJ}" --quiet >/dev/null 2>&1 || true

    # No Cloud Shell, o metadata server não tem escopo do Vertex AI; exige arquivo ADC explícito
    ADC_FILE_CHECK="${CLOUDSDK_CONFIG:-${HOME}/.config/gcloud}/application_default_credentials.json"
    if [[ ! -f "${ADC_FILE_CHECK}" ]] || ! CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth application-default print-access-token >/dev/null 2>&1; then
      echo "⚠️  Credenciais ADC ausentes ou expiradas em ${ADC_FILE_CHECK} (o metadata server do Cloud Shell não possui escopo do Vertex AI)."
      echo "▸ Abrindo 'gcloud auth application-default login'..."
      gcloud auth application-default login </dev/tty
    fi
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud auth application-default set-quota-project "${PROJ}" --quiet >/dev/null 2>&1 || true

    echo "▸ Habilitando APIs do Vertex AI, Cloud Build, IAM e Agent Runtime no projeto '${PROJ}'..."
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud services enable \
      serviceusage.googleapis.com \
      cloudresourcemanager.googleapis.com \
      --project="${PROJ}" --quiet >/dev/null 2>&1 || true
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud services enable \
      aiplatform.googleapis.com \
      generativelanguage.googleapis.com \
      cloudbuild.googleapis.com \
      run.googleapis.com \
      cloudtrace.googleapis.com \
      artifactregistry.googleapis.com \
      iam.googleapis.com \
      iamcredentials.googleapis.com \
      storage.googleapis.com \
      logging.googleapis.com \
      monitoring.googleapis.com \
      secretmanager.googleapis.com \
      --project="${PROJ}" --quiet >/dev/null 2>&1 || true

    for TARGET_ENV in "${FILES[@]}"; do
      touch "${TARGET_ENV}"
      grep -v -E "^(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_LOCATION|GOOGLE_GENAI_USE_VERTEXAI|GOOGLE_API_USE_CLIENT_CERTIFICATE)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
        echo "GOOGLE_CLOUD_PROJECT=${PROJ}"
        echo "GOOGLE_CLOUD_LOCATION=${LOC}"
        echo "GOOGLE_API_USE_CLIENT_CERTIFICATE=false"
      } >> "${TARGET_ENV}.tmp"
      mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
      echo "✓ Configurado ${TARGET_ENV} para Vertex AI (PROJECT=${PROJ}, LOCATION=${LOC})."
    done
    echo "  Agora execute: agents-cli playground"
    ;;
  *)
    for TARGET_ENV in "${FILES[@]}"; do
      echo "Configuração atual em ${TARGET_ENV}:"
      cat "${TARGET_ENV}" 2>/dev/null || echo "  (vazio)"
    done
    echo ""
    echo "Uso:"
    echo "  agents-cli-env vertex <PROJECT_ID> [REGION]      # Configura .env para Vertex AI, valida ADC e habilita APIs"
    echo "  agents-cli-env aistudio <CHAVE_AI_STUDIO>        # Configura .env para Google AI Studio"
    ;;
esac

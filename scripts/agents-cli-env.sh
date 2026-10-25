#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# agents-cli-env — Switch an ADK Agent Project (.env & app/.env) between
# Google AI Studio (API Key) and Google Cloud Vertex AI (ADC), and verify
# that ADC tokens are not expired (RefreshError).
# ==============================================================================
# Usage:
#   ./agents-cli-env.sh aistudio <YOUR_AI_STUDIO_API_KEY>
#   ./agents-cli-env.sh vertex <YOUR_GCP_PROJECT_ID> [REGION]
# ==============================================================================

set -euo pipefail

FILES=()
[[ -f ".env" ]]     && FILES+=(".env")
[[ -f "app/.env" ]] && FILES+=("app/.env")
if [[ ${#FILES[@]} -eq 0 ]]; then
  if [[ -d "app" ]]; then FILES=("app/.env"); else FILES=(".env"); fi
fi

MODE="${1:-status}"

case "${MODE}" in
  aistudio)
    KEY="${2:-${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}}"
    if [[ -z "${KEY}" ]]; then
      echo "Usage: $0 aistudio <YOUR_AI_STUDIO_API_KEY>"
      exit 1
    fi
    for TARGET_ENV in "${FILES[@]}"; do
      touch "${TARGET_ENV}"
      grep -v -E "^(GOOGLE_GENAI_USE_VERTEXAI|GEMINI_API_KEY|GOOGLE_API_KEY)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=FALSE"
        echo "GEMINI_API_KEY=${KEY}"
        echo "GOOGLE_API_KEY=${KEY}"
      } >> "${TARGET_ENV}.tmp"
      mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
      echo "✓ Updated ${TARGET_ENV} for Google AI Studio (GOOGLE_GENAI_USE_VERTEXAI=FALSE)."
    done
    echo "  Now run: agents-cli playground"
    ;;
  vertex)
    PROJ="${2:-${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}}"
    LOC="${3:-global}"
    if [[ -z "${PROJ}" || "${PROJ}" == "(unset)" ]]; then
      echo "Usage: $0 vertex <PROJECT_ID> [REGION]"
      exit 1
    fi
    ADC_FILE_CHECK="${CLOUDSDK_CONFIG:-${HOME}/.config/gcloud}/application_default_credentials.json"
    if [[ ! -f "${ADC_FILE_CHECK}" ]] || ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
      echo "⚠️  ADC file is missing or expired (Cloud Shell metadata lacks Vertex AI scope). Launching 'gcloud auth application-default login'..."
      gcloud auth application-default login </dev/tty
    fi
    gcloud auth application-default set-quota-project "${PROJ}" --quiet >/dev/null 2>&1 || true
    for TARGET_ENV in "${FILES[@]}"; do
      touch "${TARGET_ENV}"
      grep -v -E "^(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_LOCATION|GOOGLE_GENAI_USE_VERTEXAI)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
      {
        echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
        echo "GOOGLE_CLOUD_PROJECT=${PROJ}"
        echo "GOOGLE_CLOUD_LOCATION=${LOC}"
      } >> "${TARGET_ENV}.tmp"
      mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
      echo "✓ Updated ${TARGET_ENV} for Vertex AI (PROJECT=${PROJ}, LOCATION=${LOC})."
    done
    echo "  Now run: agents-cli playground"
    ;;
  *)
    for TARGET_ENV in "${FILES[@]}"; do
      echo "Current ${TARGET_ENV} configuration:"
      cat "${TARGET_ENV}" 2>/dev/null || echo "  (empty)"
    done
    echo ""
    echo "Usage:"
    echo "  agents-cli-env aistudio <AI_STUDIO_API_KEY>   # Configure current agent project for AI Studio"
    echo "  agents-cli-env vertex <PROJECT_ID> [REGION]   # Configure current agent project for Vertex AI + refresh ADC"
    ;;
esac

#!/usr/bin/env bash
# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# agents-cli-env — Switch an ADK Agent Project (.env / app/.env) between
# Google AI Studio (API Key) and Google Cloud Vertex AI (ADC)
# ==============================================================================
# Usage:
#   ./agents-cli-env.sh aistudio <YOUR_AI_STUDIO_API_KEY>
#   ./agents-cli-env.sh vertex <YOUR_GCP_PROJECT_ID> [REGION]
# ==============================================================================

set -euo pipefail

TARGET_ENV="app/.env"
if [[ ! -d "app" && -f ".env" ]]; then
  TARGET_ENV=".env"
fi
mkdir -p "$(dirname "${TARGET_ENV}")"
touch "${TARGET_ENV}"

MODE="${1:-status}"

case "${MODE}" in
  aistudio)
    KEY="${2:-${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}}"
    if [[ -z "${KEY}" ]]; then
      echo "Usage: $0 aistudio <YOUR_AI_STUDIO_API_KEY>"
      exit 1
    fi
    grep -v -E "^(GOOGLE_GENAI_USE_VERTEXAI|GEMINI_API_KEY|GOOGLE_API_KEY)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
    {
      echo "GOOGLE_GENAI_USE_VERTEXAI=FALSE"
      echo "GEMINI_API_KEY=${KEY}"
      echo "GOOGLE_API_KEY=${KEY}"
    } >> "${TARGET_ENV}.tmp"
    mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
    echo "✓ Updated ${TARGET_ENV} for Google AI Studio (GOOGLE_GENAI_USE_VERTEXAI=FALSE)."
    echo "  Now run: agents-cli playground"
    ;;
  vertex)
    PROJ="${2:-${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}}"
    LOC="${3:-${GOOGLE_CLOUD_LOCATION:-us-central1}}"
    if [[ -z "${PROJ}" || "${PROJ}" == "(unset)" ]]; then
      echo "Usage: $0 vertex <PROJECT_ID> [REGION]"
      exit 1
    fi
    grep -v -E "^(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_LOCATION|GOOGLE_GENAI_USE_VERTEXAI)=" "${TARGET_ENV}" > "${TARGET_ENV}.tmp" || true
    {
      echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
      echo "GOOGLE_CLOUD_PROJECT=${PROJ}"
      echo "GOOGLE_CLOUD_LOCATION=${LOC}"
    } >> "${TARGET_ENV}.tmp"
    mv "${TARGET_ENV}.tmp" "${TARGET_ENV}"
    echo "✓ Updated ${TARGET_ENV} for Vertex AI (PROJECT=${PROJ}, LOCATION=${LOC})."
    echo "  Now run: agents-cli playground"
    ;;
  *)
    echo "Current ${TARGET_ENV} configuration:"
    cat "${TARGET_ENV}" 2>/dev/null || echo "  (empty)"
    echo ""
    echo "Usage:"
    echo "  agents-cli-env aistudio <AI_STUDIO_API_KEY>   # Configure current agent project for AI Studio"
    echo "  agents-cli-env vertex <PROJECT_ID> [REGION]   # Configure current agent project for Vertex AI"
    ;;
esac

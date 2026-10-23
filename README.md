# Workshop Agent — Google Agents CLI (ADK) Setup (Linux, macOS & Windows)

Automated prerequisite installer, Google Cloud / Google AI Studio credentials configurator, and onboarding scripts for the [Google Agents CLI (`agents-cli`)](https://google.github.io/agents-cli/) and **Agent Development Kit (ADK)** across **Linux**, **macOS (Apple Silicon & Intel)**, and **Windows (PowerShell)**.

> 🍺 **Hands-On Lab End-to-End:** Confira o guia completo passo a passo em [**`LAB_CERVEJA.md`**](./LAB_CERVEJA.md) para construir, testar no Playground, avaliar e fazer deploy de um **Assistente Mestre Cervejeiro** com `agents-cli`.

---

## Quick Start (One-Line Install)

### 🐧 Linux & 🍎 macOS (Bash / Zsh)

**Interactive Mode (Lets you choose between Google Cloud Vertex AI or Google AI Studio API Key):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh)
```

**Option A — Using a Google Cloud / Vertex AI Project (Fastest):**
```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --project YOUR_PROJECT_ID --region us-central1
```

**Option B — Using a Google AI Studio API Key (`aistudio.google.com/apikey`):**
```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --api-key YOUR_AI_STUDIO_API_KEY
```

---

### 🪟 Windows (PowerShell)

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1 | iex
```

Or pass your Google Cloud Project ID or AI Studio API Key directly:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1" -OutFile "setup_agents_cli.ps1"
# For Vertex AI (Google Cloud Project):
powershell -ExecutionPolicy Bypass -File .\setup_agents_cli.ps1 -Project "YOUR_PROJECT_ID" -Region "us-central1"
# For Google AI Studio (API Key):
powershell -ExecutionPolicy Bypass -File .\setup_agents_cli.ps1 -ApiKey "YOUR_AI_STUDIO_API_KEY"
```

---

## Why `agents-cli playground` Fails with a Credentials Error on AI Studio Projects (and How This Script Fixes It)

When you create a project via `agents-cli scaffold create <name>`, the generated `app/.env` file defaults to **Vertex AI mode** (`GOOGLE_GENAI_USE_VERTEXAI=TRUE` / `1`). This causes two common failures when running `agents-cli playground`:

1. **You want to use a Google AI Studio API Key (`AIza...`), but `app/.env` has `GOOGLE_GENAI_USE_VERTEXAI=TRUE`:**
   * Because `GOOGLE_GENAI_USE_VERTEXAI=TRUE` is set in `app/.env`, the `google-genai` SDK ignores your API key and attempts to use Google Cloud Application Default Credentials (`google.auth.default()`), failing with `DefaultCredentialsError`.
   * **Fix included in this installer:** Passing `--api-key` (or selecting Option `[2]` in the interactive prompt) sets `GEMINI_API_KEY`, `GOOGLE_API_KEY`, and `GOOGLE_GENAI_USE_VERTEXAI=FALSE`, and installs the `agents-cli-env` helper so you can switch any agent project's `app/.env` in one command:
     ```bash
     agents-cli-env aistudio YOUR_AI_STUDIO_API_KEY
     ```

2. **You created a project in AI Studio and want to use it via `gcloud` (Vertex AI ADC):**
   * Projects created inside Google AI Studio only have `generativelanguage.googleapis.com` enabled by default—they do **not** have `aiplatform.googleapis.com` enabled, often lack a linked Billing Account (required by Vertex AI), and your local `gcloud auth application-default set-quota-project` is not aligned to that project.
   * **Fix included in this installer:** Step 8 automatically runs `gcloud auth application-default login`, enables both `generativelanguage.googleapis.com` and `aiplatform.googleapis.com` (plus Cloud Run/Build/Trace), checks if Billing is linked, aligns the ADC quota project, and provides:
     ```bash
     agents-cli-env vertex YOUR_PROJECT_ID us-central1
     ```

---

## What Gets Installed & Configured

| Step | Component | Details |
| :--- | :--- | :--- |
| **0** | **GCE Metadata Fix** | Probes `169.254.169.254` (1s timeout); sets `NO_GCE_CHECK="true"` on non-GCE machines so `google-auth` never hangs |
| **1–3** | **Base Tools, `uv` & Python `3.11+`** | Installs `curl`, `git`, `unzip`, `uv`/`uvx`, and Python `3.12` (if system Python `< 3.11`) |
| **4** | **Node.js LTS & `npx`** | Verifies both `node` and `npx` (required for `npx skills add google/agents-cli`); installs Node.js LTS (`v22`) if missing |
| **5** | **Coding Agent Check** | Detects **Antigravity (`agy`)**, **Claude Code (`claude`)**, or **Codex (`codex`)** |
| **6–7** | **Google Cloud CLI & Terraform** | Installs `gcloud` and `terraform` into `~/.local` (or via `winget` on Windows) if missing |
| **8** | **Vertex AI ADC / AI Studio Credentials** | Configures either **Google Cloud Vertex AI** (`gcloud auth login`, `gcloud auth application-default login`, `GOOGLE_CLOUD_PROJECT`, ADC quota-project, and 12 APIs including `generativelanguage.googleapis.com` & `aiplatform.googleapis.com`) or **Google AI Studio** (`GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI=FALSE`), and installs `agents-cli-env` |
| **9** | **Agents CLI & Skills** | Runs `uvx google-agents-cli setup` to install `agents-cli` and register the 7 ADK skills |

---

## CLI Flags (`setup_agents_cli.sh`)

| Flag | Description |
| :--- | :--- |
| `--project <PROJECT_ID>` / `-p` | Target Google Cloud Project ID to configure for Vertex AI and enable APIs on |
| `--region <REGION>` / `-r` | Target Google Cloud region (default: `us-central1`) |
| `--api-key <API_KEY>` / `-k` | Google AI Studio API Key (`GEMINI_API_KEY` / `GOOGLE_API_KEY`); sets `GOOGLE_GENAI_USE_VERTEXAI=FALSE` |
| `--non-interactive` / `-y` | Never prompt for user input |
| `--skip-gcloud-auth` | Skip `gcloud` authentication, project configuration, and API enablement |
| `--skip-apis` | Configure project and ADC, but skip `gcloud services enable` |

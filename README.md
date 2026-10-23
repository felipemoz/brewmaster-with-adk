# Workshop Agent — Google Agents CLI (ADK) Setup (Linux, macOS & Windows)

Automated prerequisite installer, Google Cloud project & API configurator, and onboarding scripts for the [Google Agents CLI (`agents-cli`)](https://google.github.io/agents-cli/) and **Agent Development Kit (ADK)** across **Linux**, **macOS (Apple Silicon & Intel)**, and **Windows (PowerShell)**.

---

## Quick Start (One-Line Install)

### 🐧 Linux & 🍎 macOS (Bash / Zsh)

**Interactive Mode (Prompts for GCP Project & Enables Required APIs):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh)
```

**Passing Your GCP Project ID Directly (Fastest — Zero Prompts):**
```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --project YOUR_PROJECT_ID --region us-central1
```

**Non-Interactive / Container / CI Mode (Skips interactive prompts):**
```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --non-interactive --skip-apis
```

---

### 🪟 Windows (PowerShell)

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1 | iex
```

Or pass your Google Cloud Project ID directly:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1" -OutFile "setup_agents_cli.ps1"
powershell -ExecutionPolicy Bypass -File .\setup_agents_cli.ps1 -Project "YOUR_PROJECT_ID" -Region "us-central1"
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
| **8** | **GCP Auth, Project, Quota & APIs** | <ul><li>Verifies `gcloud auth login` and `gcloud auth application-default login` (using `/dev/tty` so `curl \| bash` never hangs)</li><li>Configures `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION` (`us-central1`), and `GOOGLE_GENAI_USE_VERTEXAI="TRUE"`</li><li>Enables all required APIs with `CLOUDSDK_CORE_DISABLE_PROMPTS=1 --quiet`:<ul><li>`aiplatform.googleapis.com` (Vertex AI / Agent Platform / Agent Runtime)</li><li>`run.googleapis.com` (Cloud Run)</li><li>`cloudbuild.googleapis.com` (Cloud Build)</li><li>`cloudtrace.googleapis.com`, `logging.googleapis.com`, `monitoring.googleapis.com` (Observability)</li><li>`secretmanager.googleapis.com`, `artifactregistry.googleapis.com`, `iam.googleapis.com`, `iamcredentials.googleapis.com`, `storage.googleapis.com`</li></ul></li><li>Aligns Application Default Credentials quota project (`gcloud auth application-default set-quota-project`)</li></ul> |
| **9** | **Agents CLI & Skills** | Runs `uvx google-agents-cli setup` to install `agents-cli` and register the 7 ADK skills |

---

## CLI Flags (`setup_agents_cli.sh`)

| Flag | Description |
| :--- | :--- |
| `--project <PROJECT_ID>` / `-p` | Target Google Cloud Project ID to configure and enable APIs on |
| `--region <REGION>` / `-r` | Target Google Cloud region (default: `us-central1`) |
| `--non-interactive` / `-y` | Never prompt for user input |
| `--skip-gcloud-auth` | Skip `gcloud` authentication, project configuration, and API enablement |
| `--skip-apis` | Configure project and ADC, but skip `gcloud services enable` |

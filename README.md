# Workshop Agent — Google Agents CLI (ADK) Setup

Automated Linux prerequisite installer and onboarding script for the [Google Agents CLI (`agents-cli`)](https://google.github.io/agents-cli/) and **Agent Development Kit (ADK)**.

---

## Quick Start (One-Line Install on Linux)

### Interactive Mode (Recommended)
Installs all prerequisites and launches `agents-cli setup --interactive`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh)
```

### Non-Interactive / Container / CI Mode
Installs all prerequisites and runs `agents-cli setup` without blocking on interactive prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --non-interactive
```

---

## What Gets Installed & Configured

| Component | Requirement | How the Script Handles It |
| :--- | :--- | :--- |
| **GCE Metadata Check** | Avoid `169.254.169.254` timeouts on non-GCE hosts | Probes `169.254.169.254` (1s timeout); exports & persists `NO_GCE_CHECK="true"` on containers/local Linux |
| **Python** | Python `3.11+` | Uses system Python if `>= 3.11`, or installs Python `3.12` via `uv python install 3.12 --default` |
| **uv / uvx** | Astral package & tool manager | Installs `uv` and `uvx` into `~/.local/bin` |
| **Node.js & npx** | Required for `npx skills add google/agents-cli` | Verifies both `node` and `npx`; installs Node.js LTS (`v22`) into `~/.local/node-lts` if missing |
| **Coding Agent** | Antigravity, Claude Code, or Codex | Detects installed coding agents and prints installation commands if none are found |
| **Google Cloud CLI** | `gcloud` for authentication & deployment | Checks `gcloud` on `PATH` or installs Google Cloud SDK into `~/.local/google-cloud-sdk` |
| **Terraform** | HashiCorp Terraform for cloud deployment | Checks `terraform` on `PATH` or installs Terraform into `~/.local/bin` |
| **Agents CLI & Skills** | `google-agents-cli` + 7 ADK skills | Runs `uvx google-agents-cli setup` (adding `--interactive` when ADC is not yet configured) |

---

## Troubleshooting Common Issues

### 1. `Compute Engine Metadata server unavailable (169.254.169.254 timed out)`
When running inside a container, WSL, or non-GCE Linux machine without Application Default Credentials (ADC), `google-auth` tries to reach `169.254.169.254:80` three times before failing.
* **Fix:** `setup_agents_cli.sh` automatically sets `export NO_GCE_CHECK="true"`.

### 2. `'npx' is not installed or not on PATH`
Some environments (or standalone IDE `node` binaries) provide `node` without `npm`/`npx`, causing `agents-cli setup` to fail when running `npx -y skills add https://github.com/google/agents-cli`.
* **Fix:** `setup_agents_cli.sh` verifies `npx` specifically and installs a full Node.js LTS distribution in user space (`~/.local/node-lts`) if `npx` is missing.

### 3. Running with `sudo` / as `root`
Avoid running `sudo uvx google-agents-cli setup`, as that installs the CLI and skills into `/root/.agents/skills` and looks for credentials under `/root/.config/gcloud`. Always run as your regular Linux user.

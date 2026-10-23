# Workshop Agent — Google Agents CLI (ADK) Setup (Linux, macOS & Windows)

Automated prerequisite installer and onboarding scripts for the [Google Agents CLI (`agents-cli`)](https://google.github.io/agents-cli/) and **Agent Development Kit (ADK)** across **Linux**, **macOS (Apple Silicon & Intel)**, and **Windows (PowerShell)**.

---

## Quick Start (One-Line Install)

### 🐧 Linux & 🍎 macOS (Bash / Zsh)

**Interactive Mode (Recommended):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh)
```

**Non-Interactive / Container / CI Mode:**
```bash
curl -fsSL https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.sh | bash -s -- --non-interactive
```

---

### 🪟 Windows (PowerShell)

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1 | iex
```

Or download and run with parameters:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/felipemoz/workshop-agent/main/setup_agents_cli.ps1" -OutFile "setup_agents_cli.ps1"
powershell -ExecutionPolicy Bypass -File .\setup_agents_cli.ps1
```

---

## What Gets Installed & Configured

| Component | Requirement | Linux (`setup_agents_cli.sh`) | macOS (`setup_agents_cli.sh`) | Windows (`setup_agents_cli.ps1`) |
| :--- | :--- | :--- | :--- | :--- |
| **GCE Metadata Fix** | Avoid `169.254.169.254` timeouts on non-GCE hosts | Probes `169.254.169.254` (1s); sets `NO_GCE_CHECK="true"` in `~/.bashrc` | Sets `NO_GCE_CHECK="true"` in `~/.zshrc` & `~/.bashrc` | Sets `NO_GCE_CHECK="true"` in User & Process Environment |
| **Python** | Python `3.11+` | System Python or `uv python install 3.12 --default` | System/Homebrew Python or `uv python install 3.12 --default` | System Python or `uv python install 3.12 --default` |
| **uv / uvx** | Astral package & tool manager | `astral.sh/uv/install.sh` (`~/.local/bin`) | `astral.sh/uv/install.sh` (`~/.local/bin`) | `astral.sh/uv/install.ps1` (`$HOME\.local\bin`) |
| **Node.js & npx** | Required for `npx skills add google/agents-cli` | Node.js LTS (`v22`) linux tarball into `~/.local/node-lts` | Node.js LTS (`v22`) darwin (`arm64`/`x64`) tarball into `~/.local/node-lts` | `winget install OpenJS.NodeJS.LTS` or portable zip into `$HOME\.local\node-lts` |
| **Coding Agent** | Antigravity, Claude Code, or Codex | Detects installed CLI and shows install commands | Detects installed CLI and shows install commands | Detects installed CLI and shows install commands |
| **Google Cloud CLI** | `gcloud` for authentication & deployment | Google Cloud SDK linux tarball into `~/.local/google-cloud-sdk` | Google Cloud SDK darwin (`arm`/`x86_64`) tarball into `~/.local/google-cloud-sdk` | `winget install Google.CloudSDK` |
| **Terraform** | HashiCorp Terraform for cloud deployment | Terraform linux binary into `~/.local/bin` | Terraform darwin (`arm64`/`amd64`) binary into `~/.local/bin` | Terraform windows binary into `$HOME\.local\bin` |
| **Agents CLI & Skills** | `google-agents-cli` + 7 ADK skills | Runs `uvx google-agents-cli setup` (with `-i` if unauthenticated) | Runs `uvx google-agents-cli setup` (with `-i` if unauthenticated) | Runs `uvx google-agents-cli setup` (with `-i` if unauthenticated) |

---

## Troubleshooting Common Issues

### 1. `Compute Engine Metadata server unavailable (169.254.169.254 timed out)`
When running inside a container, WSL, macOS, Windows, or non-GCE Linux machine without Application Default Credentials (ADC), `google-auth` tries to reach `169.254.169.254:80` three times before failing.
* **Fix:** Both `setup_agents_cli.sh` and `setup_agents_cli.ps1` automatically set `NO_GCE_CHECK="true"`.

### 2. `'npx' is not installed or not on PATH`
Some environments (or standalone IDE `node` binaries) provide `node` without `npm`/`npx`, causing `agents-cli setup` to fail when running `npx -y skills add https://github.com/google/agents-cli`.
* **Fix:** The scripts verify `npx` specifically and install a complete Node.js LTS distribution in user space if `npx` is missing.

### 3. Running with `sudo` / as `root`
Avoid running `sudo uvx google-agents-cli setup`, as that installs the CLI and skills into `/root/.agents/skills` and looks for credentials under `/root/.config/gcloud`. Always run as your regular user.

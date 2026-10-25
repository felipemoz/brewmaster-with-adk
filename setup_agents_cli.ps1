# Copyright 2026 Google LLC
# SPDX-License-Identifier: Apache-2.0
# ==============================================================================
# Google Agents CLI (ADK) — Windows PowerShell Prerequisites & GCP Setup Script
# ==============================================================================
# Installs and configures everything required by Google Agents CLI on Windows:
#   1. GCE Metadata Server timeout fix (sets NO_GCE_CHECK=true for user & process)
#   2. Git for Windows (via winget if missing)
#   3. uv / uvx (Astral Python package & tool manager)
#   4. Python >= 3.11 (via system or managed by uv)
#   5. Node.js LTS + npm + npx (required for `npx skills add google/agents-cli`)
#   6. Coding Agent check (Antigravity / Claude Code / Codex)
#   7. Google Cloud CLI (gcloud) & Terraform
#   8. Authentication & Credentials Setup for `agents-cli playground`:
#      - Mode 1: Google Cloud / Vertex AI (ADC `gcloud auth application-default login`,
#        Project ID, Quota Project, and APIs including `aiplatform` & `generativelanguage`)
#      - Mode 2: Google AI Studio API Key (`GEMINI_API_KEY`, `GOOGLE_API_KEY`,
#        and `GOOGLE_GENAI_USE_VERTEXAI=FALSE`)
#   9. Runs `uvx google-agents-cli setup`
#
# Usage (PowerShell):
#   irm https://is.gd/brewmaster_ps1 | iex
#   irm https://raw.githubusercontent.com/felipemoz/brewmaster-with-adk/main/setup_agents_cli.ps1 | iex
#   # Or locally with parameters:
#   .\setup_agents_cli.ps1 [-Project "my-gcp-project"] [-Region "us-central1"] [-ApiKey "AIza..."] [-NonInteractive] [-SkipGcloudAuth] [-SkipApis]
# ==============================================================================

[CmdletBinding()]
param(
    [string]$Project = $env:GOOGLE_CLOUD_PROJECT,
    [string]$Region  = $(if ($env:GOOGLE_CLOUD_LOCATION) { $env:GOOGLE_CLOUD_LOCATION } else { "us-central1" }),
    [string]$ApiKey  = $(if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { $env:GOOGLE_API_KEY }),
    [switch]$NonInteractive,
    [switch]$SkipGcloudAuth,
    [switch]$SkipApis
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host $Message -ForegroundColor White
    Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}
function Write-Info([string]$Message) { Write-Host "▸ $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "⚠️  Warning: $Message" -ForegroundColor Yellow }

# Ensure ~/.local/bin exists and is on Process + User PATH
$LocalBin = Join-Path $HOME ".local\bin"
if (-not (Test-Path $LocalBin)) {
    New-Item -ItemType Directory -Path $LocalBin -Force | Out-Null
}
if ($env:PATH -notlike "*$LocalBin*") {
    $env:PATH = "$LocalBin;$env:PATH"
}
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$LocalBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$LocalBin;$UserPath", "User")
}

function Refresh-SessionPath {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UsrPath     = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH    = "$LocalBin;$UsrPath;$MachinePath"
}

function Sync-LocalDotEnv([string]$Mode) {
    foreach ($RelPath in @(".env", "app\.env")) {
        if (Test-Path $RelPath) {
            Write-Info "Updating local agent environment file '$RelPath' for $Mode mode..."
            $Lines = Get-Content $RelPath | Where-Object { $_ -notmatch "^(GOOGLE_CLOUD_PROJECT|GOOGLE_CLOUD_LOCATION|GOOGLE_GENAI_USE_VERTEXAI|GEMINI_API_KEY|GOOGLE_API_KEY)=" }
            if ($Mode -eq "aistudio") {
                $Lines += "GOOGLE_GENAI_USE_VERTEXAI=FALSE"
                $Lines += "GEMINI_API_KEY=$ApiKey"
                $Lines += "GOOGLE_API_KEY=$ApiKey"
            } else {
                $Lines += "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
                $Lines += "GOOGLE_CLOUD_PROJECT=$Project"
                $Lines += "GOOGLE_CLOUD_LOCATION=$Region"
            }
            Set-Content -Path $RelPath -Value $Lines -Encoding UTF8
            Write-Ok "Synced '$RelPath' ($Mode credentials ready for 'agents-cli playground')."
        }
    }
}

# ==============================================================================
# 0. Fix GCE Metadata Server Timeout (169.254.169.254)
# ==============================================================================
Write-Step "0. Configuring Environment (NO_GCE_CHECK=true)"
$env:NO_GCE_CHECK = "true"
[Environment]::SetEnvironmentVariable("NO_GCE_CHECK", "true", "User")
Write-Ok "Set NO_GCE_CHECK=true (prevents 169.254.169.254 metadata server connection timeouts)."

# ==============================================================================
# 1. Check Git
# ==============================================================================
Write-Step "1. Checking Git"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "Git is installed ($(git --version))."
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Info "Installing Git via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-SessionPath
    Write-Ok "Installed Git."
} else {
    Write-Warn "Git not found and winget is unavailable. Please install Git from https://git-scm.com/download/win"
}

# ==============================================================================
# 2. Install uv & uvx
# ==============================================================================
Write-Step "2. Checking uv (Astral Python Package & Tool Manager)"
if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Get-Command uvx -ErrorAction SilentlyContinue)) {
    Write-Ok "uv is already installed ($(uv --version))."
} else {
    Write-Info "Installing uv via https://astral.sh/uv/install.ps1..."
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    Refresh-SessionPath
    Write-Ok "Installed uv ($(uv --version))."
}

# ==============================================================================
# 3. Verify Python >= 3.11
# ==============================================================================
Write-Step "3. Checking Python >= 3.11"
$PythonOk = $false
if (Get-Command python -ErrorAction SilentlyContinue) {
    try {
        python -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) { $PythonOk = $true }
    } catch {}
}

if ($PythonOk) {
    $PyVer = python --version
    Write-Ok "System $PyVer meets requirement (>= 3.11)."
} else {
    Write-Info "System Python < 3.11 or missing. Installing Python 3.12 via uv..."
    uv python install 3.12 --default
    Refresh-SessionPath
    Write-Ok "Installed Python 3.12 via uv."
}

# ==============================================================================
# 4. Verify Node.js & npx (Required for `npx skills add google/agents-cli`)
# ==============================================================================
Write-Step "4. Checking Node.js, npm, and npx"
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Ok "Node.js ($(node --version)) and npx ($(npx --version)) are installed."
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Info "Installing Node.js LTS via winget..."
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-SessionPath
    $NodeProgramFiles = "C:\Program Files\nodejs"
    if ((Test-Path $NodeProgramFiles) -and ($env:PATH -notlike "*$NodeProgramFiles*")) {
        $env:PATH = "$NodeProgramFiles;$env:PATH"
    }
    Write-Ok "Installed Node.js ($(node --version)) and npx ($(npx --version))."
} else {
    Write-Info "Installing portable Node.js LTS (v22.14.0) into $HOME\.local\node-lts..."
    $NodeVersion = "v22.14.0"
    $NodeDist    = "node-$NodeVersion-win-x64"
    $NodeZip     = Join-Path $env:TEMP "$NodeDist.zip"
    $NodeDir     = Join-Path $HOME ".local\node-lts"
    Invoke-WebRequest -Uri "https://nodejs.org/dist/$NodeVersion/$NodeDist.zip" -OutFile $NodeZip
    if (Test-Path $NodeDir) { Remove-Item -Recurse -Force $NodeDir }
    Expand-Archive -Path $NodeZip -DestinationPath (Join-Path $HOME ".local") -Force
    Rename-Item -Path (Join-Path $HOME ".local\$NodeDist") -NewName "node-lts"
    Remove-Item -Force $NodeZip
    $env:PATH = "$NodeDir;$env:PATH"
    $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($CurrentUserPath -notlike "*$NodeDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$NodeDir;$CurrentUserPath", "User")
    }
    Write-Ok "Installed portable Node.js ($(node --version)) and npx ($(npx --version))."
}

# ==============================================================================
# 5. Check Coding Agent (Antigravity, Claude Code, or Codex)
# ==============================================================================
Write-Step "5. Checking Coding Agent Environment"
$Agents = @()
if (Get-Command agy -ErrorAction SilentlyContinue)         { $Agents += "Antigravity (agy)" }
if (Get-Command antigravity -ErrorAction SilentlyContinue) { $Agents += "Antigravity" }
if (Get-Command claude -ErrorAction SilentlyContinue)      { $Agents += "Claude Code" }
if (Get-Command codex -ErrorAction SilentlyContinue)       { $Agents += "Codex" }

if ($Agents.Count -gt 0) {
    Write-Ok "Detected coding agent(s): $($Agents -join ', ')"
} else {
    Write-Warn "No coding agent CLI (antigravity, claude, codex) detected on PATH."
    Write-Info "You can install one via:"
    Write-Info "  • Antigravity: https://antigravity.google/"
    Write-Info "  • Claude Code: npm install -g @anthropic-ai/claude-code"
    Write-Info "  • OpenAI Codex: npm install -g @openai/codex"
}

# ==============================================================================
# 6. Check Google Cloud CLI (gcloud)
# ==============================================================================
Write-Step "6. Checking Google Cloud CLI (gcloud)"
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    Write-Ok "Google Cloud CLI is installed."
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Info "Installing Google Cloud SDK via winget..."
    winget install --id Google.CloudSDK -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-SessionPath
    Write-Ok "Installed Google Cloud SDK."
} else {
    Write-Warn "gcloud not found. Install from: https://cloud.google.com/sdk/docs/install"
}

# ==============================================================================
# 7. Check Terraform (Required for Cloud Deployment)
# ==============================================================================
Write-Step "7. Checking Terraform"
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    $TfVer = (terraform version | Select-Object -First 1)
    Write-Ok "$TfVer is installed."
} else {
    Write-Info "Installing Terraform v1.11.2 into $LocalBin..."
    $TfVersion = "1.11.2"
    $TfZip     = Join-Path $env:TEMP "terraform_${TfVersion}_windows_amd64.zip"
    Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/$TfVersion/terraform_${TfVersion}_windows_amd64.zip" -OutFile $TfZip
    Expand-Archive -Path $TfZip -DestinationPath $LocalBin -Force
    Remove-Item -Force $TfZip
    Write-Ok "Installed $((terraform version | Select-Object -First 1))."
}

# ==============================================================================
# 8. Credentials & Project Setup (Vertex AI ADC vs. Google AI Studio API Key)
# ==============================================================================
Write-Step "8. Credentials & Project Setup (Playground & Cloud Deployment)"
$GcloudConfigDir = if ($env:CLOUDSDK_CONFIG) { $env:CLOUDSDK_CONFIG } else { Join-Path $env:APPDATA "gcloud" }
$AdcFile = Join-Path $GcloudConfigDir "application_default_credentials.json"
$AuthMode = "vertex"

if ($ApiKey -and (-not $Project)) {
    $AuthMode = "aistudio"
} elseif ((-not $NonInteractive) -and (-not $SkipGcloudAuth) -and (-not $Project) -and (-not $ApiKey)) {
    Write-Host "How would you like to authenticate your ADK agents (e.g. for 'agents-cli playground')?"
    Write-Host "  [1] Google Cloud / Vertex AI (gcloud ADC + GCP Project + auto-enable APIs) [Default]" -ForegroundColor White
    Write-Host "  [2] Google AI Studio API Key (GEMINI_API_KEY from https://aistudio.google.com/apikey)" -ForegroundColor White
    Write-Host "  [3] Both (Configure GCP Project/APIs AND set an AI Studio API Key)" -ForegroundColor White
    $Choice = (Read-Host "▸ Choose [1/2/3] (default: 1)").Trim()
    switch ($Choice) {
        "2" { $AuthMode = "aistudio" }
        "3" { $AuthMode = "both" }
        default { $AuthMode = "vertex" }
    }
}

if (($AuthMode -eq "aistudio") -or ($AuthMode -eq "both")) {
    if ((-not $ApiKey) -and (-not $NonInteractive)) {
        $ApiKey = (Read-Host "▸ Paste your Google AI Studio API Key (from https://aistudio.google.com/apikey)").Trim()
    }
    if ($ApiKey) {
        $env:GEMINI_API_KEY = $ApiKey
        $env:GOOGLE_API_KEY = $ApiKey
        [Environment]::SetEnvironmentVariable("GEMINI_API_KEY", $ApiKey, "User")
        [Environment]::SetEnvironmentVariable("GOOGLE_API_KEY", $ApiKey, "User")
        if ($AuthMode -eq "aistudio") {
            $env:GOOGLE_GENAI_USE_VERTEXAI = "FALSE"
            [Environment]::SetEnvironmentVariable("GOOGLE_GENAI_USE_VERTEXAI", "FALSE", "User")
            Sync-LocalDotEnv "aistudio"
            Write-Ok "Configured AI Studio API Key (GEMINI_API_KEY & GOOGLE_API_KEY) with GOOGLE_GENAI_USE_VERTEXAI=FALSE."
        } else {
            Write-Ok "Saved AI Studio API Key (GEMINI_API_KEY & GOOGLE_API_KEY)."
        }
    } else {
        Write-Warn "No AI Studio API Key provided."
    }
}

if ((-not $SkipGcloudAuth) -and (($AuthMode -eq "vertex") -or ($AuthMode -eq "both")) -and (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    # 1. Active gcloud account + live token check
    $ActiveAccount = (gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null | Select-Object -First 1)
    $GcloudTokenValid = $false
    if ($ActiveAccount) {
        gcloud auth print-access-token 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $GcloudTokenValid = $true }
    }
    if ($GcloudTokenValid) {
        Write-Ok "Active gcloud account verified (token valid): $ActiveAccount"
    } elseif (-not $NonInteractive) {
        Write-Info "gcloud session missing or expired. Launching 'gcloud auth login'..."
        gcloud auth login
    }

    # 2. Application Default Credentials (ADC) + live token refresh check (prevents RefreshError in playground!)
    $AdcValid = $false
    if (Test-Path $AdcFile) {
        gcloud auth application-default print-access-token 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $AdcValid = $true }
    }
    if ($AdcValid) {
        Write-Ok "Application Default Credentials (ADC) verified (live token refresh succeeded)."
    } elseif (-not $NonInteractive) {
        if (Test-Path $AdcFile) {
            Write-Warn "ADC file exists at $AdcFile, but its token is EXPIRED (causes RefreshError in playground)."
        } else {
            Write-Info "ADC not found."
        }
        Write-Info "Launching 'gcloud auth application-default login'..."
        gcloud auth application-default login
    }

    # 3. Resolve & Configure Google Cloud Project ID
    if (-not $Project) {
        $CurrentProject = (gcloud config get-value project 2>$null)
        if ($CurrentProject -and ($CurrentProject -ne "(unset)")) {
            $Project = $CurrentProject
        }
    }

    if (-not $NonInteractive) {
        if ($Project) {
            $UserInput = Read-Host "▸ Current GCP Project is '$Project'. Press ENTER to keep it, or type a different Project ID"
            if ($UserInput) { $Project = $UserInput.Trim() }
        } else {
            Write-Info "Listing your available Google Cloud / AI Studio projects (top 15):"
            $env:CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
            gcloud projects list --format="table(projectId,name)" --limit=15 2>$null
            $Project = (Read-Host "▸ Enter the Google Cloud Project ID to use for Agents CLI / ADK").Trim()
        }
    }

    if ($Project -and ($Project -ne "(unset)")) {
        $env:CLOUDSDK_CORE_DISABLE_PROMPTS = "1"
        Write-Info "Setting active Google Cloud project to '$Project'..."
        gcloud config set project $Project --quiet 2>$null | Out-Null

        $env:GOOGLE_CLOUD_PROJECT        = $Project
        $env:GOOGLE_CLOUD_LOCATION       = $Region
        $env:GOOGLE_GENAI_USE_VERTEXAI   = "TRUE"
        [Environment]::SetEnvironmentVariable("GOOGLE_CLOUD_PROJECT", $Project, "User")
        [Environment]::SetEnvironmentVariable("GOOGLE_CLOUD_LOCATION", $Region, "User")
        [Environment]::SetEnvironmentVariable("GOOGLE_GENAI_USE_VERTEXAI", "TRUE", "User")
        Sync-LocalDotEnv "vertex"
        Write-Ok "Configured GOOGLE_CLOUD_PROJECT=$Project, GOOGLE_CLOUD_LOCATION=$Region, GOOGLE_GENAI_USE_VERTEXAI=TRUE"

        # 4. Enable Required Google Cloud APIs (including generativelanguage.googleapis.com for AI Studio projects)
        if (-not $SkipApis) {
            Write-Info "Enabling core prerequisite APIs (serviceusage, cloudresourcemanager) on '$Project'..."
            gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com --project=$Project --quiet 2>$null

            $RequiredApis = @(
                "generativelanguage.googleapis.com",
                "aiplatform.googleapis.com",
                "run.googleapis.com",
                "cloudbuild.googleapis.com",
                "cloudtrace.googleapis.com",
                "secretmanager.googleapis.com",
                "artifactregistry.googleapis.com",
                "logging.googleapis.com",
                "monitoring.googleapis.com",
                "iam.googleapis.com",
                "iamcredentials.googleapis.com",
                "storage.googleapis.com"
            )
            Write-Info "Enabling ADK, AI Studio & Agent Platform APIs ($($RequiredApis.Count) services) on '$Project' (takes ~20-45s)..."
            gcloud services enable @RequiredApis --project=$Project --quiet
            Write-Ok "All required Google Cloud & Gemini APIs are enabled on '$Project'."
        }

        # 5. Align ADC Quota Project
        if (Test-Path $AdcFile) {
            Write-Info "Setting ADC quota project to '$Project'..."
            gcloud auth application-default set-quota-project $Project --quiet 2>$null
            Write-Ok "ADC quota project aligned to '$Project'."
        }
    } else {
        Write-Warn "No Google Cloud project selected. Pass -Project YOUR_PROJECT_ID or -ApiKey YOUR_AI_STUDIO_KEY."
    }
}

# ==============================================================================
# 9. Run `uvx google-agents-cli setup`
# ==============================================================================
Write-Step "9. Running Google Agents CLI Setup"
$SetupArgs = @("setup")
if (-not (Test-Path $AdcFile)) {
    if (($AuthMode -eq "aistudio") -or $SkipGcloudAuth -or $NonInteractive) {
        $SetupArgs += "--skip-auth"
    } else {
        $SetupArgs += "--interactive"
    }
}

Write-Info "Running: uvx google-agents-cli $($SetupArgs -join ' ')"
& uvx google-agents-cli @SetupArgs

# ==============================================================================
# 10. Pre-configure MCP Support & Brewmaster Skill
# ==============================================================================
Write-Step "10. Pre-configuring MCP Support (FastMCP / McpToolset) & Brewmaster Skill"
if (Get-Command npx -ErrorAction SilentlyContinue) {
    Write-Info "Installing 'brewmaster-adk' skill..."
    & npx -y skills add https://github.com/felipemoz/brewmaster-with-adk -y --all -g 2>$null | Out-Null
    Write-Ok "Installed 'brewmaster-adk' skill."
}
if ((Test-Path "pyproject.toml") -and (Select-String -Path "pyproject.toml" -Pattern "google-adk" -Quiet)) {
    Write-Info "Adding 'mcp' package to current ADK project..."
    & uv add mcp 2>$null | Out-Null
    Write-Ok "Installed 'mcp' in current ADK project."
}

Write-Step "Setup Complete!"
Write-Ok "GCP Project: $env:GOOGLE_CLOUD_PROJECT ($env:GOOGLE_CLOUD_LOCATION)"
if ($env:GEMINI_API_KEY) {
    Write-Ok "AI Studio API Key: Configured (GOOGLE_GENAI_USE_VERTEXAI=$env:GOOGLE_GENAI_USE_VERTEXAI)"
}
Write-Ok "Open a new PowerShell window and verify with: agents-cli info"

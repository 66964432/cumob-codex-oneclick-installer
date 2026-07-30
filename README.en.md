# Codex One-Click Custom Route Setup - CUMOB Edition

[中文](README.md)

One-click macOS / Windows installer that connects Codex to the CUMOB custom route.

After installation, it automatically:

1. Installs the latest `cumob-image-generation4codex` Skill
2. Writes the CUMOB provider configuration
3. Installs the custom model catalog `cumob-models.json`
4. Merges the CUMOB API Key into Codex `auth.json`

## Goals

- Users only need a tiny install entry file and a double-click
- At install time, the latest Skill, config template, and model catalog are pulled from GitHub
- Real API keys are never packaged
- Re-running the installer upgrades safely without destroying unrelated Codex settings

## Repositories

- Installer: [`66964432/cumob-codex-oneclick-installer`](https://github.com/66964432/cumob-codex-oneclick-installer)
- Skill: [`66964432/cumob-image-generation4codex`](https://github.com/66964432/cumob-image-generation4codex)
- Latest release: https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest

## Prerequisites

1. Codex is already installed: [Codex](https://chatgpt.com/codex)
2. The machine can access GitHub
3. You have a CUMOB API Key ready

## One-Click Install (Recommended)

### macOS

1. Download: [`install-macos.command`](https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest/download/install-macos.command)
2. Double-click to run
3. If macOS blocks the file:
   - Right-click the file → Open
   - Or allow it in System Settings → Privacy & Security
4. Enter your CUMOB API Key when prompted
   - Input is hidden by design
   - Press Enter to keep an existing key
5. Close the window after you see `Installation finished`
6. Restart Codex, or create a new task

### Windows

1. Download: [`install-windows.cmd`](https://github.com/66964432/cumob-codex-oneclick-installer/releases/latest/download/install-windows.cmd)
2. Double-click to run
3. If SmartScreen blocks it, choose Run anyway
4. Enter your CUMOB API Key when prompted
   - Input is hidden by design
   - Press Enter to keep an existing key
5. Press any key to close the window after `Installation finished`
6. Restart Codex, or create a new task

Parallels shared folders under `\\Mac\...` are supported. The launcher temporarily maps the UNC path to a drive letter for CMD compatibility.

Even if you only download the entry file, the installer still pulls from GitHub:

- Latest installer logic
- Latest model catalog
- Latest config template
- Latest Skill

Fastest path:

**Download entry → Double-click → Enter API Key → Restart Codex**

## Install From Source

macOS / Linux:

```bash
git clone https://github.com/66964432/cumob-codex-oneclick-installer.git
cd cumob-codex-oneclick-installer
bash install.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/66964432/cumob-codex-oneclick-installer.git
cd cumob-codex-oneclick-installer
.\install.ps1
```

## What Gets Written

Default install location:

- Prefer the `CODEX_HOME` environment variable
- Otherwise:
  - macOS: `~/.codex`
  - Windows: `%USERPROFILE%\.codex`

Files written:

```text
<CODEX_HOME>/
├── auth.json
├── config.toml
├── model-catalogs/
│   └── cumob-models.json
├── skills/
│   └── cumob-image-generation4codex/
└── backups/
    └── cumob-installer-YYYYMMDD-HHMMSS/
```

The installer configures:

- The latest `cumob-image-generation4codex` Skill
- The CUMOB model catalog
- The CUMOB provider config
- The API Key in Codex `auth.json`

## Verify Success

In Codex, check that:

1. CUMOB models appear in the model list, for example `gpt-5.6-sol`
2. The image Skill `cumob-image-generation4codex` is available
3. Image generation no longer complains about a missing API Key / provider

## Upgrade

When the Skill or config is updated later:

1. Double-click the same install entry again
2. The installer re-downloads the latest version and upgrades in place
3. Your other Codex settings are preserved
4. Old files are backed up automatically

## Config Strategy

The installer never fully overwrites `config.toml`. It will:

- Back up the old config, auth, model catalog, and Skill first
- Remove the previous CUMOB provider section and installer-managed section
- Write portable CUMOB settings and generate the local absolute model-catalog path
- Preserve other providers / MCP / plugins / desktop settings / project permissions
- Support re-runs without creating duplicate TOML keys

Managed defaults:

```toml
model_provider = "cumob"
model = "gpt-5.6-sol"
disable_response_storage = true
model_reasoning_effort = "high"

[model_providers.cumob]
name = "cumob"
wire_api = "responses"
image_api = "images"
image_model = "gpt-image-2-ref"
requires_openai_auth = true
base_url = "https://api.cumob.com/v1"
```

## Security

- Release packages and the repository never include real API keys
- The API Key is not passed as a CLI argument and is not written to install logs
- A new key is written only to `OPENAI_API_KEY` in `auth.json`
- Existing unrelated auth fields are preserved
- If no key is entered, the existing `auth.json` is kept

Non-interactive install:

```bash
CUMOB_INSTALL_API_KEY="your-key" bash install.sh --no-prompt
```

```powershell
$env:CUMOB_INSTALL_API_KEY = "your-key"
.\install.ps1 -NoPrompt
Remove-Item Env:CUMOB_INSTALL_API_KEY
```

## Advanced Options

Dry run without modifying files:

```bash
bash install.sh --dry-run
```

```powershell
.\install.ps1 -DryRun
```

Custom Codex home:

```bash
CODEX_HOME="/custom/path" bash install.sh
```

```powershell
$env:CODEX_HOME = "D:\CodexHome"
.\install.ps1
```

Custom remote sources:

```bash
export CUMOB_INSTALLER_URL="https://github.com/66964432/cumob-codex-oneclick-installer/archive/refs/heads/main.zip"
export CUMOB_SKILL_URL="https://github.com/66964432/cumob-image-generation4codex/archive/refs/heads/main.zip"
export CUMOB_MODELS_URL="https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-models.json"
bash install.sh
```

## FAQ

### 1. Install fails with a network error

Confirm that:

- GitHub is reachable
- No corporate proxy / firewall is blocking the download
- These repositories are accessible:
  - `https://github.com/66964432/cumob-codex-oneclick-installer`
  - `https://github.com/66964432/cumob-image-generation4codex`

Then run the installer again.

### 2. Install succeeded, but Codex does not show the change

Try:

1. Fully quit Codex and reopen it
2. Or create a new task
3. Then re-check the model list and Skill

### 3. What if I entered the wrong API Key?

Run the install entry again and type the correct key.

### 4. Will this overwrite my existing Codex config?

No full overwrite. The installer only:

- Updates CUMOB-related settings
- Preserves other providers / plugins / desktop settings
- Backs up old files first

Backup directories:

- macOS: `~/.codex/backups/`
- Windows: `%USERPROFILE%\.codex\backups\`

## Requirements

- Codex installed
- Network access to GitHub
- At least one runtime for the image Skill:
  - Node.js 18+
  - Python 3

## Development And Verification

macOS / Linux:

```bash
bash tests/test-install.sh
```

Windows:

```powershell
.\tests\test-install.ps1
```

Live network verification (downloads the Skill from GitHub):

```bash
CUMOB_LIVE_TEST=1 bash tests/test-install.sh
```

Build local release artifacts:

```bash
bash build-release.sh
```

## Repository Layout

```text
cumob-codex-oneclick-installer/
├── install-macos.command
├── install-windows.cmd
├── install.sh
├── install.ps1
├── payload/
│   ├── cumob-config.template.toml
│   └── cumob-models.json
├── scripts/
├── tests/
├── README.md
├── README.en.md
└── SOURCE.json
```

Users only need the entry files day to day. All configuration content continues to be maintained on GitHub.

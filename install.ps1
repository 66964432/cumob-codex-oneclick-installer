[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$payloadDir = Join-Path $scriptDir "payload"
$defaultInstallerArchiveUrl = "https://github.com/66964432/cumob-codex-oneclick-installer/archive/refs/heads/main.zip"
$defaultSkillArchiveUrl = "https://github.com/66964432/cumob-image-generation4codex/archive/refs/heads/main.zip"
$defaultModelsUrl = "https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-models.json"
$defaultTemplateUrl = "https://raw.githubusercontent.com/66964432/cumob-codex-oneclick-installer/main/payload/cumob-config.template.toml"

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Ensure-RuntimeAssets {
    $catalogSource = Join-Path $payloadDir "cumob-models.json"
    $templateSource = Join-Path $payloadDir "cumob-config.template.toml"

    if ((Test-Path -LiteralPath $catalogSource -PathType Leaf) -and
        (Test-Path -LiteralPath $templateSource -PathType Leaf)) {
        return @{
            CatalogSource = $catalogSource
            TemplateSource = $templateSource
            DownloadRoot = $null
        }
    }

    $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ("cumob-installer-runtime-" + [Guid]::NewGuid().ToString("N"))
    $payloadRuntime = Join-Path $downloadRoot "payload"
    New-Item -ItemType Directory -Force -Path $payloadRuntime | Out-Null

    $catalogTarget = Join-Path $payloadRuntime "cumob-models.json"
    $templateTarget = Join-Path $payloadRuntime "cumob-config.template.toml"

    if (Test-Path -LiteralPath $catalogSource -PathType Leaf) {
        Copy-Item -LiteralPath $catalogSource -Destination $catalogTarget
    } else {
        $modelsUrl = if ($env:CUMOB_MODELS_URL) { $env:CUMOB_MODELS_URL } else { $defaultModelsUrl }
        Download-File -Url $modelsUrl -Destination $catalogTarget
    }

    if (Test-Path -LiteralPath $templateSource -PathType Leaf) {
        Copy-Item -LiteralPath $templateSource -Destination $templateTarget
    } else {
        $templateUrl = if ($env:CUMOB_CONFIG_TEMPLATE_URL) { $env:CUMOB_CONFIG_TEMPLATE_URL } else { $defaultTemplateUrl }
        Download-File -Url $templateUrl -Destination $templateTarget
    }

    if (-not (Test-Path -LiteralPath $catalogTarget -PathType Leaf) -or
        -not (Test-Path -LiteralPath $templateTarget -PathType Leaf)) {
        throw "Failed to obtain installer assets from GitHub. Existing Codex files were not changed."
    }

    return @{
        CatalogSource = $catalogTarget
        TemplateSource = $templateTarget
        DownloadRoot = $downloadRoot
    }
}

$codexHome = if ($env:CODEX_HOME) {
    $env:CODEX_HOME
} else {
    Join-Path $HOME ".codex"
}

$skillsDir = Join-Path $codexHome "skills"
$skillTarget = Join-Path $skillsDir "cumob-image-generation4codex"
$catalogDir = Join-Path $codexHome "model-catalogs"
$catalogTarget = Join-Path $catalogDir "cumob-models.json"
$configPath = Join-Path $codexHome "config.toml"
$authPath = Join-Path $codexHome "auth.json"

if ($DryRun) {
    Write-Host "Dry run only; no files will be changed."
    Write-Host "Codex home: $codexHome"
    Write-Host "Skill target: $skillTarget"
    Write-Host "Catalog target: $catalogTarget"
    Write-Host "Config target: $configPath"
    Write-Host "Auth target: $authPath"
    $dryRunInstallerUrl = if ($env:CUMOB_INSTALLER_URL) { $env:CUMOB_INSTALLER_URL } else { $defaultInstallerArchiveUrl }
    $dryRunSkillUrl = if ($env:CUMOB_SKILL_URL) { $env:CUMOB_SKILL_URL } else { $defaultSkillArchiveUrl }
    $dryRunModelsUrl = if ($env:CUMOB_MODELS_URL) { $env:CUMOB_MODELS_URL } else { $defaultModelsUrl }
    Write-Host "Installer source: $dryRunInstallerUrl"
    Write-Host "Skill source: $dryRunSkillUrl"
    Write-Host "Models source: $dryRunModelsUrl"
    exit 0
}

$runtimeAssets = Ensure-RuntimeAssets
$catalogSource = $runtimeAssets.CatalogSource
$templateSource = $runtimeAssets.TemplateSource
$downloadRoot = $runtimeAssets.DownloadRoot

try {
    $skillSource = $env:CUMOB_SKILL_SOURCE_DIR
    if ([string]::IsNullOrWhiteSpace($skillSource)) {
        if ([string]::IsNullOrWhiteSpace($downloadRoot)) {
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ("cumob-skill-download-" + [Guid]::NewGuid().ToString("N"))
        }
        $skillArchive = Join-Path $downloadRoot "cumob-image-generation4codex.zip"
        $skillExtractDir = Join-Path $downloadRoot "skill-extracted"
        New-Item -ItemType Directory -Force -Path $skillExtractDir | Out-Null

        if ($env:CUMOB_SKILL_ARCHIVE -and (Test-Path -LiteralPath $env:CUMOB_SKILL_ARCHIVE -PathType Leaf)) {
            Copy-Item -LiteralPath $env:CUMOB_SKILL_ARCHIVE -Destination $skillArchive
        } else {
            $skillUrl = if ($env:CUMOB_SKILL_ARCHIVE) {
                $env:CUMOB_SKILL_ARCHIVE
            } elseif ($env:CUMOB_SKILL_URL) {
                $env:CUMOB_SKILL_URL
            } else {
                $defaultSkillArchiveUrl
            }
            Download-File -Url $skillUrl -Destination $skillArchive
        }

        Expand-Archive -LiteralPath $skillArchive -DestinationPath $skillExtractDir -Force
        $skillSource = Get-ChildItem -LiteralPath $skillExtractDir -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") -PathType Leaf } |
            Select-Object -First 1 -ExpandProperty FullName
    }

    $nodeSkillScript = if ($skillSource) { Join-Path $skillSource "scripts\generate-image.mjs" } else { "" }
    $pythonSkillScript = if ($skillSource) { Join-Path $skillSource "scripts\generate-image.py" } else { "" }
    if ([string]::IsNullOrWhiteSpace($skillSource) -or
        -not (Test-Path -LiteralPath (Join-Path $skillSource "SKILL.md") -PathType Leaf) -or
        (-not (Test-Path -LiteralPath $nodeSkillScript -PathType Leaf) -and
         -not (Test-Path -LiteralPath $pythonSkillScript -PathType Leaf))) {
        throw "Downloaded Skill archive is invalid or incomplete. Existing Codex files were not changed."
    }

    $skillVersion = "latest"
    $skillVersionPath = Join-Path $skillSource "VERSION"
    if (Test-Path -LiteralPath $skillVersionPath -PathType Leaf) {
        $skillVersion = ([IO.File]::ReadAllText($skillVersionPath)).Trim()
    }

    $apiKey = $env:CUMOB_INSTALL_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey) -and -not $NoPrompt) {
        $secureKey = Read-Host "CUMOB API Key (leave blank to keep existing auth.json)" -AsSecureString
        $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        try {
            $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
        }
    }

    $authObject = $null
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        if (Test-Path -LiteralPath $authPath -PathType Leaf) {
            $authText = [IO.File]::ReadAllText($authPath)
            if ([string]::IsNullOrWhiteSpace($authText)) {
                $authObject = [PSCustomObject]@{}
            } else {
                $authObject = $authText | ConvertFrom-Json
                if ($null -eq $authObject -or $authObject -is [Array]) {
                    throw "$authPath must contain a JSON object."
                }
            }
        } else {
            $authObject = [PSCustomObject]@{}
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $codexHome "backups\cumob-installer-$timestamp"
    if (Test-Path -LiteralPath $backupDir) {
        $backupDir = "$backupDir-$PID"
    }

    New-Item -ItemType Directory -Force -Path $backupDir, $skillsDir, $catalogDir | Out-Null

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupDir "config.toml")
    }
    if (Test-Path -LiteralPath $authPath -PathType Leaf) {
        Copy-Item -LiteralPath $authPath -Destination (Join-Path $backupDir "auth.json")
    }
    if (Test-Path -LiteralPath $catalogTarget -PathType Leaf) {
        Copy-Item -LiteralPath $catalogTarget -Destination (Join-Path $backupDir "cumob-models.json")
    }
    if (Test-Path -LiteralPath $skillTarget -PathType Container) {
        Copy-Item -LiteralPath $skillTarget `
            -Destination (Join-Path $backupDir "cumob-image-generation4codex") `
            -Recurse
    }

    $tempSkill = Join-Path $skillsDir ".cumob-image-generation4codex.tmp.$PID"
    if (Test-Path -LiteralPath $tempSkill) {
        Remove-Item -LiteralPath $tempSkill -Recurse -Force
    }
    Copy-Item -LiteralPath $skillSource -Destination $tempSkill -Recurse
    if (Test-Path -LiteralPath $skillTarget) {
        Remove-Item -LiteralPath $skillTarget -Recurse -Force
    }
    Move-Item -LiteralPath $tempSkill -Destination $skillTarget
    Copy-Item -LiteralPath $catalogSource -Destination $catalogTarget -Force

    $filteredLines = New-Object "System.Collections.Generic.List[string]"
    $inManagedBlock = $false
    $section = ""
    $skipSection = $false

    $existingLines = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        [IO.File]::ReadAllLines($configPath)
    } else {
        @()
    }

    foreach ($line in $existingLines) {
        if ($line -eq "# BEGIN CUMOB CODEX ONE-CLICK INSTALLER") {
            $inManagedBlock = $true
            continue
        }

        if ($inManagedBlock) {
            if ($line -eq "# END CUMOB CODEX ONE-CLICK INSTALLER") {
                $inManagedBlock = $false
                $section = ""
                $skipSection = $false
            }
            continue
        }

        if ($line -match '^\s*\[([^\[\]]+)\]\s*(?:#.*)?$') {
            $section = ($Matches[1] -replace '\s', '').ToLowerInvariant()
            $skipSection = @(
                "model_providers.cumob",
                'model_providers."cumob"',
                "model_providers.'cumob'"
            ) -contains $section

            if ($skipSection) {
                continue
            }
        }

        if ($skipSection) {
            continue
        }

        if ($section -eq "" -and
            $line -match '^\s*(model_provider|model|disable_response_storage|model_catalog_json|model_reasoning_effort)\s*=') {
            continue
        }

        $filteredLines.Add($line)
    }

    $catalogTomlPath = $catalogTarget.Replace("\", "/").Replace('"', '\"')
    $templateText = [IO.File]::ReadAllText($templateSource)
    $managedBody = $templateText.Replace("{{MODEL_CATALOG_PATH}}", $catalogTomlPath).TrimEnd()
    $managedLines = New-Object "System.Collections.Generic.List[string]"
    $managedLines.Add("# BEGIN CUMOB CODEX ONE-CLICK INSTALLER")
    foreach ($line in ($managedBody -split "`r?`n")) {
        $managedLines.Add($line)
    }
    $managedLines.Add("# END CUMOB CODEX ONE-CLICK INSTALLER")

    while ($filteredLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($filteredLines[0])) {
        $filteredLines.RemoveAt(0)
    }

    $newLines = New-Object "System.Collections.Generic.List[string]"
    $newLines.AddRange([string[]]$managedLines)
    if ($filteredLines.Count -gt 0) {
        $newLines.Add("")
        $newLines.AddRange([string[]]$filteredLines)
    }

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    $tempConfig = "$configPath.cumob-installer-$PID.tmp"
    [IO.File]::WriteAllText($tempConfig, (($newLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
    Move-Item -LiteralPath $tempConfig -Destination $configPath -Force

    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $keyProperty = $authObject.PSObject.Properties["OPENAI_API_KEY"]
        if ($null -eq $keyProperty) {
            $authObject | Add-Member -MemberType NoteProperty -Name "OPENAI_API_KEY" -Value $apiKey
        } else {
            $authObject.OPENAI_API_KEY = $apiKey
        }

        $tempAuth = "$authPath.cumob-installer-$PID.tmp"
        $authJson = $authObject | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($tempAuth, ($authJson + [Environment]::NewLine), $utf8NoBom)
        Move-Item -LiteralPath $tempAuth -Destination $authPath -Force
    } elseif (-not (Test-Path -LiteralPath $authPath -PathType Leaf)) {
        Write-Warning "No API Key was provided. Run the installer again to complete authentication."
    }

    $runtimeMessage = "No Node.js 18+ or Python 3 runtime was detected on PATH."
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCommand) {
        try {
            $nodeMajor = [int]((& node -p "Number(process.versions.node.split('.')[0])").Trim())
            if ($nodeMajor -ge 18) {
                $runtimeMessage = "Node.js runtime detected."
            }
        } catch {
            # Keep the runtime warning.
        }
    }
    if ($runtimeMessage -ne "Node.js runtime detected.") {
        if ((Get-Command python3 -ErrorAction SilentlyContinue) -or
            (Get-Command python -ErrorAction SilentlyContinue) -or
            (Get-Command py -ErrorAction SilentlyContinue)) {
            $runtimeMessage = "Python runtime detected."
        }
    }

    Write-Host ""
    Write-Host "codex 一键接入自定义路由 - cumob 篇 安装完成。"
    Write-Host "Backup: $backupDir"
    Write-Host "Skill: $skillTarget (downloaded version: $skillVersion)"
    Write-Host "Model catalog: $catalogTarget"
    Write-Host "Config: $configPath"
    Write-Host $runtimeMessage
    Write-Host "Restart Codex or create a new task to reload the skill and model catalog."
}
finally {
    if ($downloadRoot -and (Test-Path -LiteralPath $downloadRoot)) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force
    }
}

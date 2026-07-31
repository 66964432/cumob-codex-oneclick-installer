$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("cumob-installer-test-" + [Guid]::NewGuid().ToString("N"))
$env:CODEX_HOME = Join-Path $testRoot ".codex"
$env:CUMOB_INSTALL_API_KEY = "test-key-one"

try {
    $fixtureSkill = Join-Path $testRoot "fixture-skill"
    $fixtureScripts = Join-Path $fixtureSkill "scripts"
    New-Item -ItemType Directory -Force -Path $fixtureScripts | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureSkill "SKILL.md"), "---`nname: cumob-image-generation4codex`ndescription: Installer test fixture.`n---`n")
    [IO.File]::WriteAllText((Join-Path $fixtureSkill "VERSION"), "test-fixture`n")
    [IO.File]::WriteAllText((Join-Path $fixtureScripts "generate-image.py"), "print('test fixture')`n")
    $env:CUMOB_SKILL_SOURCE_DIR = $fixtureSkill

    $oldSkill = Join-Path $env:CODEX_HOME "skills\cumob-image-generation4codex"
    $catalogDir = Join-Path $env:CODEX_HOME "model-catalogs"
    New-Item -ItemType Directory -Force -Path $oldSkill, $catalogDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $oldSkill "OLD.txt"), "old skill")

    $seedConfig = @"
model_provider = "old-provider"
model = "old-model"
model_catalog_json = "C:/old/models.json"

[model_providers.cumob]
name = "old-cumob"
base_url = "https://old.invalid/v1"

[model_providers.other]
name = "keep-me"

[desktop]
localeOverride = "zh-CN"
"@
    [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME "config.toml"), $seedConfig)
    [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME "auth.json"), '{"OPENAI_API_KEY":"old-key","OTHER_AUTH_FIELD":"keep-me"}')

    $installerSource = [IO.File]::ReadAllText((Join-Path $rootDir "install.ps1"))
    foreach ($helperName in @(
            "function Get-PythonRuntimeCommand",
            "function Get-NodeRuntimeCommand",
            "function Get-ImageRuntimeStatus",
            "function Add-DirectoryToProcessAndUserPath",
            "function Resolve-NodeDownloadAsset",
            "function Install-NodeRuntime",
            "function Ensure-ImageRuntime"
        )) {
        if (-not $installerSource.Contains($helperName)) {
            throw "install.ps1 is missing helper: $helperName"
        }
    }
    if (-not $installerSource.Contains("CUMOB_SKIP_NODE_INSTALL")) {
        throw "install.ps1 does not support CUMOB_SKIP_NODE_INSTALL"
    }
    if (-not $installerSource.Contains("CUMOB_NODE_DIST_URL") -or
        -not $installerSource.Contains("CUMOB_NODE_INDEX_URL") -or
        -not $installerSource.Contains("CUMOB_NODE_INSTALL_DIR")) {
        throw "install.ps1 is missing Node download override environment variables"
    }
    if (-not $installerSource.Contains("Ensure-ImageRuntime -DryRun") -or
        -not $installerSource.Contains('$imageRuntime = Ensure-ImageRuntime')) {
        throw "install.ps1 does not call Ensure-ImageRuntime in dry-run and real install paths"
    }
    if (-not $installerSource.Contains("nodejs.org/dist") -or
        -not $installerSource.Contains("cumob-nodejs")) {
        throw "install.ps1 does not default to the Node.js LTS zip install path"
    }
    if ($installerSource.Contains('Join-Path $versionDir "*"')) {
        throw "install.ps1 still uses LiteralPath wildcard copy that leaves current\node.exe missing"
    }
    if (-not $installerSource.Contains('Copy-Item -LiteralPath $versionDir -Destination $currentLink -Recurse')) {
        throw "install.ps1 does not copy the versioned Node.js directory into the stable current alias"
    }
    $installerBytes = [IO.File]::ReadAllBytes((Join-Path $rootDir "install.ps1"))
    if ($installerBytes.Length -lt 3 -or
        $installerBytes[0] -ne 0xEF -or
        $installerBytes[1] -ne 0xBB -or
        $installerBytes[2] -ne 0xBF) {
        throw "install.ps1 is missing the required UTF-8 BOM"
    }

    & (Join-Path $rootDir "install.ps1") -NoPrompt

    $configPath = Join-Path $env:CODEX_HOME "config.toml"
    $authPath = Join-Path $env:CODEX_HOME "auth.json"
    $installedSkill = Join-Path $env:CODEX_HOME "skills\cumob-image-generation4codex"
    $powerShellFallback = Join-Path $installedSkill "scripts\generate-image.ps1"
    $windowsImageLauncher = Join-Path $installedSkill "scripts\generate-image-windows.cmd"
    $config = [IO.File]::ReadAllText($configPath)
    $auth = [IO.File]::ReadAllText($authPath) | ConvertFrom-Json
    $catalog = [IO.File]::ReadAllText((Join-Path $env:CODEX_HOME "model-catalogs\cumob-models.json")) | ConvertFrom-Json

    if ([regex]::Matches($config, "(?m)^model_provider\s*=").Count -ne 1) { throw "model_provider is not unique" }
    if ([regex]::Matches($config, "(?m)^\[model_providers\.cumob\]$").Count -ne 1) { throw "CUMOB table is not unique" }
    if (-not $config.Contains("[model_providers.other]")) { throw "other provider was removed" }
    if (-not $config.Contains('localeOverride = "zh-CN"')) { throw "desktop settings were removed" }
    if ($auth.OPENAI_API_KEY -ne "test-key-one" -or $auth.OTHER_AUTH_FIELD -ne "keep-me") { throw "auth.json merge failed" }
    if ($null -eq $catalog.models -or $catalog.models.Count -ne 10) { throw "model catalog was not installed" }
    if (-not (Test-Path -LiteralPath $powerShellFallback -PathType Leaf)) { throw "PowerShell image fallback was not installed" }
    if (-not (Test-Path -LiteralPath $windowsImageLauncher -PathType Leaf)) { throw "Windows image launcher was not installed" }
    $installedSkillInstructions = [IO.File]::ReadAllText((Join-Path $installedSkill "SKILL.md"))
    if (-not $installedSkillInstructions.Contains("## Native Windows Launcher")) {
        throw "Windows fallback instructions were not added to the Skill"
    }
    if (-not $installedSkillInstructions.Contains("auto-installs Node.js LTS") -and
        -not $installedSkillInstructions.Contains("automatically downloads Node.js LTS")) {
        throw "Windows Skill instructions do not mention automatic Node.js installation"
    }
    if ($installedSkillInstructions.Contains('base_url = "http://api.cumob.com/v1"')) {
        throw "Skill instructions still use the obsolete CUMOB HTTP endpoint"
    }
    if (-not $installedSkillInstructions.Contains('api.cumob.com') -or -not $installedSkillInstructions.Contains('api.cumob.cn')) {
        throw "Skill instructions do not document both CUMOB domains"
    }
    $launcherText = [IO.File]::ReadAllText($windowsImageLauncher)
    if (-not $launcherText.Contains('py.exe -3 -c "import sys"')) {
        throw "Windows image launcher does not verify that Python 3 can start"
    }
    if (-not $launcherText.Contains('where python.exe')) {
        throw "Windows image launcher does not support Python installations without py.exe"
    }

    $fallbackDryRunText = (& $powerShellFallback `
        --prompt "Installer fallback configuration check" `
        --out (Join-Path $testRoot "unused.png") `
        --dry-run `
        --no-progress | Out-String)
    $fallbackDryRun = $fallbackDryRunText | ConvertFrom-Json
    if ($fallbackDryRun.image_api -ne "images") { throw "PowerShell fallback did not load image_api" }
    if ($fallbackDryRun.endpoint -ne "https://api.cumob.com/v1/images/generations") { throw "PowerShell fallback endpoint is incorrect" }
    if ($fallbackDryRun.image_model -ne "gpt-image-2-ref") { throw "PowerShell fallback image model is incorrect" }
    if (-not $fallbackDryRun.has_api_key) { throw "PowerShell fallback did not detect the API key" }
    if ($fallbackDryRunText.Contains("test-key-one")) { throw "PowerShell fallback dry-run leaked the API key" }

    $nestedSkillScripts = Join-Path $env:CODEX_HOME "skills\cumob-image-generation4codex\scripts"
    $nestedFallback = Join-Path $nestedSkillScripts "generate-image.ps1"
    $nestedLauncher = Join-Path $nestedSkillScripts "generate-image-windows.cmd"
    if (-not (Test-Path -LiteralPath $nestedFallback -PathType Leaf)) {
        throw "installed PowerShell fallback is missing for home-resolution tests"
    }

    $savedCodexHome = $env:CODEX_HOME
    $savedUserProfile = $env:USERPROFILE
    $savedHome = $env:HOME
    $savedHomeDrive = $env:HOMEDRIVE
    $savedHomePath = $env:HOMEPATH
    try {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        $env:USERPROFILE = Join-Path $testRoot "missing-profile"
        $env:HOME = Join-Path $testRoot "missing-home"
        Remove-Item Env:HOMEDRIVE -ErrorAction SilentlyContinue
        Remove-Item Env:HOMEPATH -ErrorAction SilentlyContinue

        $inferredDryRunText = (& $nestedFallback `
            --prompt "Infer Codex home from skill path" `
            --out (Join-Path $testRoot "unused-inferred.png") `
            --dry-run `
            --no-progress | Out-String)
        $inferredDryRun = $inferredDryRunText | ConvertFrom-Json
        if ($inferredDryRun.codex_home -ne ([IO.Path]::GetFullPath($savedCodexHome))) {
            throw "PowerShell fallback did not infer Codex home from the installed skill path"
        }
        if ($inferredDryRun.image_model -ne "gpt-image-2-ref") {
            throw "Skill-path home inference loaded the wrong image model"
        }

        $explicitHome = Join-Path $testRoot "explicit-codex-home"
        New-Item -ItemType Directory -Force -Path $explicitHome | Out-Null
        Copy-Item -LiteralPath (Join-Path $savedCodexHome "config.toml") -Destination (Join-Path $explicitHome "config.toml")
        Copy-Item -LiteralPath (Join-Path $savedCodexHome "auth.json") -Destination (Join-Path $explicitHome "auth.json")
        $explicitDryRunText = (& $nestedFallback `
            --prompt "Explicit Codex home override" `
            --out (Join-Path $testRoot "unused-explicit.png") `
            --codex-home $explicitHome `
            --dry-run `
            --no-progress | Out-String)
        $explicitDryRun = $explicitDryRunText | ConvertFrom-Json
        if ($explicitDryRun.codex_home -ne ([IO.Path]::GetFullPath($explicitHome))) {
            throw "PowerShell fallback ignored --codex-home"
        }

        $env:CUMOB_IMAGE_FORCE_POWERSHELL = "1"
        $launcherInferredText = (& $nestedLauncher `
            --prompt "Launcher infers Codex home" `
            --out (Join-Path $testRoot "unused-launcher-inferred.png") `
            --dry-run `
            --no-progress | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "Windows image launcher failed while inferring Codex home with exit code $LASTEXITCODE"
        }
        $launcherInferred = $launcherInferredText | ConvertFrom-Json
        if ($launcherInferred.codex_home -ne ([IO.Path]::GetFullPath($savedCodexHome))) {
            throw "Windows image launcher did not infer Codex home from its install path"
        }
        Remove-Item Env:CUMOB_IMAGE_FORCE_POWERSHELL -ErrorAction SilentlyContinue
    } finally {
        if ($null -ne $savedCodexHome) { $env:CODEX_HOME = $savedCodexHome } else { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
        if ($null -ne $savedUserProfile) { $env:USERPROFILE = $savedUserProfile } else { Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue }
        if ($null -ne $savedHome) { $env:HOME = $savedHome } else { Remove-Item Env:HOME -ErrorAction SilentlyContinue }
        if ($null -ne $savedHomeDrive) { $env:HOMEDRIVE = $savedHomeDrive } else { Remove-Item Env:HOMEDRIVE -ErrorAction SilentlyContinue }
        if ($null -ne $savedHomePath) { $env:HOMEPATH = $savedHomePath } else { Remove-Item Env:HOMEPATH -ErrorAction SilentlyContinue }
        Remove-Item Env:CUMOB_IMAGE_FORCE_POWERSHELL -ErrorAction SilentlyContinue
    }

    $env:CUMOB_IMAGE_FORCE_POWERSHELL = "1"
    $launcherDryRunText = (& $windowsImageLauncher `
        --prompt "Installer launcher configuration check" `
        --out (Join-Path $testRoot "unused-launcher.png") `
        --dry-run `
        --no-progress | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Windows image launcher PowerShell fallback failed with exit code $LASTEXITCODE" }
    $launcherDryRun = $launcherDryRunText | ConvertFrom-Json
    if ($launcherDryRun.image_model -ne "gpt-image-2-ref") { throw "Windows image launcher selected the wrong model" }
    Remove-Item Env:CUMOB_IMAGE_FORCE_POWERSHELL

    # No-prompt installs use the default .com endpoint even if config previously used .cn.
    $cnConfig = [IO.File]::ReadAllText($configPath).Replace(
        'base_url = "https://api.cumob.com/v1"',
        'base_url = "https://api.cumob.cn/v1"'
    )
    [IO.File]::WriteAllText($configPath, $cnConfig)
    & (Join-Path $rootDir "install.ps1") -NoPrompt
    $configAfterDefault = [IO.File]::ReadAllText($configPath)
    if (-not $configAfterDefault.Contains('base_url = "https://api.cumob.com/v1"')) {
        throw "no-prompt reinstall did not fall back to the default api.cumob.com endpoint"
    }

    # Explicit env override selects .cn and skips the prompt.
    $env:CUMOB_BASE_URL = "https://api.cumob.cn/v1"
    & (Join-Path $rootDir "install.ps1") -NoPrompt
    $configAfterCn = [IO.File]::ReadAllText($configPath)
    if (-not $configAfterCn.Contains('base_url = "https://api.cumob.cn/v1"')) {
        throw "CUMOB_BASE_URL override did not select api.cumob.cn"
    }
    $cnDryRunText = (& $powerShellFallback `
        --prompt "CN endpoint configuration check" `
        --out (Join-Path $testRoot "unused-cn.png") `
        --dry-run `
        --no-progress | Out-String)
    $cnDryRun = $cnDryRunText | ConvertFrom-Json
    if ($cnDryRun.endpoint -ne "https://api.cumob.cn/v1/images/generations") {
        throw "PowerShell fallback did not follow api.cumob.cn base_url"
    }

    # Explicit env override can also force .com again.
    $env:CUMOB_BASE_URL = "https://api.cumob.com/v1"
    & (Join-Path $rootDir "install.ps1") -NoPrompt
    $configAfterEnv = [IO.File]::ReadAllText($configPath)
    if (-not $configAfterEnv.Contains('base_url = "https://api.cumob.com/v1"')) {
        throw "CUMOB_BASE_URL override was ignored"
    }
    Remove-Item Env:CUMOB_BASE_URL -ErrorAction SilentlyContinue

    $remoteOnlyDir = Join-Path $testRoot "remote-only-installer"
    New-Item -ItemType Directory -Force -Path $remoteOnlyDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $rootDir "install.ps1") -Destination (Join-Path $remoteOnlyDir "install.ps1")

    $fixtureRemote = Join-Path $testRoot "remote-fixture"
    New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRemote "payload") | Out-Null
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\cumob-models.json") -Destination (Join-Path $fixtureRemote "payload\cumob-models.json")
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\cumob-config.template.toml") -Destination (Join-Path $fixtureRemote "payload\cumob-config.template.toml")
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\generate-image.ps1") -Destination (Join-Path $fixtureRemote "payload\generate-image.ps1")
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\generate-image-windows.cmd") -Destination (Join-Path $fixtureRemote "payload\generate-image-windows.cmd")

    $env:CUMOB_MODELS_URL = ([Uri](Join-Path $fixtureRemote "payload\cumob-models.json")).AbsoluteUri
    $env:CUMOB_CONFIG_TEMPLATE_URL = ([Uri](Join-Path $fixtureRemote "payload\cumob-config.template.toml")).AbsoluteUri
    $env:CUMOB_POWERSHELL_FALLBACK_URL = ([Uri](Join-Path $fixtureRemote "payload\generate-image.ps1")).AbsoluteUri
    $env:CUMOB_WINDOWS_IMAGE_LAUNCHER_URL = ([Uri](Join-Path $fixtureRemote "payload\generate-image-windows.cmd")).AbsoluteUri
    $env:CUMOB_INSTALL_API_KEY = "test-key-two"
    & (Join-Path $remoteOnlyDir "install.ps1") -NoPrompt

    $config = [IO.File]::ReadAllText($configPath)
    $auth = [IO.File]::ReadAllText($authPath) | ConvertFrom-Json
    $backups = Get-ChildItem -LiteralPath (Join-Path $env:CODEX_HOME "backups")
    if ([regex]::Matches($config, "(?m)^model_provider\s*=").Count -ne 1) { throw "reinstall duplicated model_provider" }
    if ($auth.OPENAI_API_KEY -ne "test-key-two") { throw "reinstall did not update API key" }
    if ($backups.Count -lt 2) { throw "reinstall did not create a second backup" }

    # Static coverage for automatic Node install controls.
    # Prefer real Node/Python when present; never force a live nodejs.org download in CI.
    $env:CUMOB_SKIP_NODE_INSTALL = "1"
    $skipDryRunOutput = & (Join-Path $rootDir "install.ps1") -DryRun 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "install.ps1 -DryRun failed under CUMOB_SKIP_NODE_INSTALL=1"
    }
    if ($skipDryRunOutput -notmatch "Image runtime detected|automatically") {
        throw "install.ps1 -DryRun did not report image runtime handling under CUMOB_SKIP_NODE_INSTALL=1"
    }
    Remove-Item Env:CUMOB_SKIP_NODE_INSTALL -ErrorAction SilentlyContinue

    # Static contract: auto-installed Node.js must be added to process PATH and user PATH.
    if (-not $installerSource.Contains('Add-DirectoryToProcessAndUserPath -Directory $currentLink')) {
        throw "install.ps1 does not add the installed Node.js directory to PATH"
    }
    if (-not $installerSource.Contains('[Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")')) {
        throw "install.ps1 does not persist Node.js to the user PATH"
    }

    Write-Host "Windows installer integration test passed."

} finally {
    Remove-Item Env:CUMOB_INSTALL_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_SKILL_SOURCE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_MODELS_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_CONFIG_TEMPLATE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_POWERSHELL_FALLBACK_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_WINDOWS_IMAGE_LAUNCHER_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_IMAGE_FORCE_POWERSHELL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_SKIP_NODE_INSTALL -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

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

    & (Join-Path $rootDir "install.ps1") -NoPrompt

    $configPath = Join-Path $env:CODEX_HOME "config.toml"
    $authPath = Join-Path $env:CODEX_HOME "auth.json"
    $config = [IO.File]::ReadAllText($configPath)
    $auth = [IO.File]::ReadAllText($authPath) | ConvertFrom-Json
    $catalog = [IO.File]::ReadAllText((Join-Path $env:CODEX_HOME "model-catalogs\cumob-models.json")) | ConvertFrom-Json

    if ([regex]::Matches($config, "(?m)^model_provider\s*=").Count -ne 1) { throw "model_provider is not unique" }
    if ([regex]::Matches($config, "(?m)^\[model_providers\.cumob\]$").Count -ne 1) { throw "CUMOB table is not unique" }
    if (-not $config.Contains("[model_providers.other]")) { throw "other provider was removed" }
    if (-not $config.Contains('localeOverride = "zh-CN"')) { throw "desktop settings were removed" }
    if ($auth.OPENAI_API_KEY -ne "test-key-one" -or $auth.OTHER_AUTH_FIELD -ne "keep-me") { throw "auth.json merge failed" }
    if ($null -eq $catalog.models -or $catalog.models.Count -ne 10) { throw "model catalog was not installed" }

    $remoteOnlyDir = Join-Path $testRoot "remote-only-installer"
    New-Item -ItemType Directory -Force -Path $remoteOnlyDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $rootDir "install.ps1") -Destination (Join-Path $remoteOnlyDir "install.ps1")

    $fixtureRemote = Join-Path $testRoot "remote-fixture"
    New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRemote "payload") | Out-Null
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\cumob-models.json") -Destination (Join-Path $fixtureRemote "payload\cumob-models.json")
    Copy-Item -LiteralPath (Join-Path $rootDir "payload\cumob-config.template.toml") -Destination (Join-Path $fixtureRemote "payload\cumob-config.template.toml")

    $env:CUMOB_MODELS_URL = ([Uri](Join-Path $fixtureRemote "payload\cumob-models.json")).AbsoluteUri
    $env:CUMOB_CONFIG_TEMPLATE_URL = ([Uri](Join-Path $fixtureRemote "payload\cumob-config.template.toml")).AbsoluteUri
    $env:CUMOB_INSTALL_API_KEY = "test-key-two"
    & (Join-Path $remoteOnlyDir "install.ps1") -NoPrompt

    $config = [IO.File]::ReadAllText($configPath)
    $auth = [IO.File]::ReadAllText($authPath) | ConvertFrom-Json
    $backups = Get-ChildItem -LiteralPath (Join-Path $env:CODEX_HOME "backups")
    if ([regex]::Matches($config, "(?m)^model_provider\s*=").Count -ne 1) { throw "reinstall duplicated model_provider" }
    if ($auth.OPENAI_API_KEY -ne "test-key-two") { throw "reinstall did not update API key" }
    if ($backups.Count -lt 2) { throw "reinstall did not create a second backup" }

    Write-Host "Windows installer integration test passed."
} finally {
    Remove-Item Env:CUMOB_INSTALL_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_SKILL_SOURCE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_MODELS_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CUMOB_CONFIG_TEMPLATE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

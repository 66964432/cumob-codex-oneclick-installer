$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Net.Http

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw $Message
}

function Show-Help {
    @"
Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File generate-image.ps1 --prompt "..." --out outputs\image.png [options]

Required:
  --prompt <text>             Image prompt. Use --prompt-file or stdin as alternatives.

Output:
  --out <path>                Output image path. Default: generated.png

Codex config:
  --codex-home <path>         Defaults to CODEX_HOME, installed skill path, or <user-profile>\.codex
  --base-url <url>            Explicit override. Defaults to Codex provider base_url.
  --image-api <api>           Override provider image_api: responses or images.
  --response-model <model>    Explicit override. Defaults to Codex top-level model.
  --api-key-env <name>        Environment variable fallback. Default: OPENAI_API_KEY.

Image generation options:
  --action <generate|edit|auto>
  --image <path>              Input image. Can be repeated.
  --mask <path>               Optional inpainting mask image.
  --image-model <model>
  --size <size>
  --quality <low|medium|high|auto>
  --format <png|webp|jpeg>
  --background <transparent|opaque|auto>
  --input-fidelity <high|low>
  --moderation <auto|low>
  --output-compression <0-100>
  --partial-images <0-3>

Other:
  --dry-run                   Print redacted config and request data without calling the API.
  --json                      Print a machine-readable result summary.
  --no-progress               Disable long-running progress messages.
  --help

Runtime:
  Uses Windows PowerShell 5.1 and built-in .NET libraries only.
"@
}

function Parse-Arguments {
    param([string[]]$Values)

    $result = @{
        image = $(New-Object "System.Collections.Generic.List[string]")
        out = "generated.png"
    }
    $flags = @("help", "dry-run", "json", "no-progress", "no-input-optimization")
    $valueOptions = @(
        "prompt", "prompt-file", "out", "codex-home", "base-url", "image-api",
        "response-model", "api-key-env", "action", "image", "mask", "image-model",
        "size", "quality", "format", "background", "input-fidelity", "moderation",
        "output-compression", "partial-images", "max-input-dimension",
        "input-jpeg-quality", "input-optimize-threshold-mb"
    )

    for ($index = 0; $index -lt $Values.Count; $index++) {
        $token = $Values[$index]
        if (-not $token.StartsWith("--")) {
            Fail "unexpected argument: $token"
        }

        $key = $token.Substring(2)
        if ($key -eq "api-key") {
            Fail "--api-key was removed to avoid exposing secrets in command lines. Use Codex auth.json or --api-key-env <name>."
        }
        if ($flags -contains $key) {
            $result[$key] = $true
            continue
        }
        if ($valueOptions -notcontains $key) {
            Fail "unsupported option: --$key"
        }
        if ($index + 1 -ge $Values.Count -or $Values[$index + 1].StartsWith("--")) {
            Fail "missing value for --$key"
        }

        $index++
        $value = $Values[$index]
        if ($key -eq "image") {
            $result.image.Add($value)
        } else {
            $result[$key] = $value
        }
    }

    return $result
}

function Get-Option {
    param(
        [hashtable]$Options,
        [string]$Name,
        $DefaultValue = $null
    )
    if ($Options.ContainsKey($Name)) {
        return $Options[$Name]
    }
    return $DefaultValue
}

function Get-IntegerOption {
    param(
        [hashtable]$Options,
        [string]$Name,
        [int]$Minimum,
        [int]$Maximum
    )
    if (-not $Options.ContainsKey($Name)) {
        return $null
    }
    $number = 0
    if (-not [int]::TryParse([string]$Options[$Name], [ref]$number) -or
        $number -lt $Minimum -or $number -gt $Maximum) {
        Fail "--$Name must be between $Minimum and $Maximum"
    }
    return $number
}

function Get-EnvironmentValue {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    return $value
}

function Resolve-FullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "cannot resolve an empty path"
    }
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Test-CodexHomeCandidate {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        $resolved = Resolve-FullPath $Path
    } catch {
        return $false
    }
    return (Test-Path -LiteralPath (Join-Path $resolved "config.toml") -PathType Leaf)
}

function Get-InstalledSkillCodexHome {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $null
    }

    try {
        # Installed layout:
        # <CODEX_HOME>\skills\cumob-image-generation4codex\scripts\generate-image.ps1
        $candidate = Resolve-FullPath (Join-Path $PSScriptRoot "..\..\..")
    } catch {
        return $null
    }

    if (Test-CodexHomeCandidate $candidate) {
        return $candidate
    }
    return $null
}

function Resolve-DefaultCodexHome {
    $configuredHome = Get-EnvironmentValue "CODEX_HOME"
    if (-not [string]::IsNullOrWhiteSpace($configuredHome)) {
        return Resolve-FullPath $configuredHome
    }

    $installedHome = Get-InstalledSkillCodexHome
    if ($installedHome) {
        return $installedHome
    }

    $profileBases = New-Object "System.Collections.Generic.List[string]"
    foreach ($name in @("USERPROFILE", "HOME")) {
        $value = Get-EnvironmentValue $name
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $profileBases.Add($value)
        }
    }

    $folderProfile = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($folderProfile)) {
        $profileBases.Add($folderProfile)
    }

    $homeDrive = Get-EnvironmentValue "HOMEDRIVE"
    $homePath = Get-EnvironmentValue "HOMEPATH"
    if (-not [string]::IsNullOrWhiteSpace($homeDrive) -and -not [string]::IsNullOrWhiteSpace($homePath)) {
        $profileBases.Add(($homeDrive.TrimEnd("\\", "/") + $homePath))
    }

    $seen = @{}
    $fallbackHome = $null
    foreach ($base in $profileBases) {
        if ([string]::IsNullOrWhiteSpace($base)) {
            continue
        }

        try {
            $candidate = Resolve-FullPath (Join-Path $base ".codex")
        } catch {
            continue
        }

        $key = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true

        if (Test-CodexHomeCandidate $candidate) {
            return $candidate
        }
        if (-not $fallbackHome) {
            $fallbackHome = $candidate
        }
    }

    if ($fallbackHome) {
        return $fallbackHome
    }

    Fail "unable to resolve Codex home. Pass --codex-home with an absolute path such as C:\Users\<you>\.codex, or set the CODEX_HOME environment variable."
}

function Parse-TomlValue {
    param([string]$RawValue)
    $value = $RawValue.Trim()
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        return $value.Substring(1, $value.Length - 2)
    }
    if ($value -eq "true") { return $true }
    if ($value -eq "false") { return $false }
    return $value
}

function Parse-TomlLite {
    param([string]$Text)

    $root = @{}
    $sections = @{}
    $current = $root
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $sectionName = $Matches[1].Replace('"', "")
            if (-not $sections.ContainsKey($sectionName)) {
                $sections[$sectionName] = @{}
            }
            $current = $sections[$sectionName]
            continue
        }
        if ($trimmed -match '^([A-Za-z0-9_.-]+)\s*=\s*(.+)$') {
            $current[$Matches[1]] = Parse-TomlValue $Matches[2]
        }
    }
    return @{ root = $root; sections = $sections }
}

function Get-ObjectProperty {
    param(
        $Object,
        [string]$Name
    )
    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Resolve-CodexConfig {
    param([hashtable]$Options)

    $codexHomeOption = Get-Option $Options "codex-home"
    if ($codexHomeOption) {
        $codexHome = Resolve-FullPath $codexHomeOption
    } else {
        $codexHome = Resolve-DefaultCodexHome
    }

    $configPath = Join-Path $codexHome "config.toml"
    $authPath = Join-Path $codexHome "auth.json"
    $toml = @{ root = @{}; sections = @{} }
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $toml = Parse-TomlLite ([IO.File]::ReadAllText($configPath))
    }

    $providerName = Get-ObjectProperty $toml.root "model_provider"
    if (-not $providerName) { $providerName = "OpenAI" }
    $providerSection = "model_providers.$providerName"
    $provider = if ($toml.sections.ContainsKey($providerSection)) { $toml.sections[$providerSection] } else { @{} }

    $auth = $null
    if (Test-Path -LiteralPath $authPath -PathType Leaf) {
        try {
            $auth = [IO.File]::ReadAllText($authPath) | ConvertFrom-Json
        } catch {
            Fail "failed to parse ${authPath}: $($_.Exception.Message)"
        }
    }

    $apiKeyEnvName = Get-Option $Options "api-key-env" "OPENAI_API_KEY"
    if ($apiKeyEnvName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Fail "--api-key-env must be an environment variable name, not a secret value."
    }

    $baseUrl = Get-Option $Options "base-url"
    if (-not $baseUrl) { $baseUrl = Get-ObjectProperty $provider "base_url" }
    if (-not $baseUrl) { $baseUrl = Get-EnvironmentValue "OPENAI_BASE_URL" }
    if (-not $baseUrl) { $baseUrl = "https://api.openai.com/v1" }
    $baseUrl = $baseUrl.TrimEnd("/")

    $imageApi = Get-Option $Options "image-api"
    if (-not $imageApi) { $imageApi = Get-ObjectProperty $provider "image_api" }
    if (-not $imageApi) { $imageApi = Get-EnvironmentValue "OPENAI_IMAGE_API" }
    if (-not $imageApi) { $imageApi = "responses" }
    $imageApi = $imageApi.ToLowerInvariant()

    $imageModel = Get-Option $Options "image-model"
    if (-not $imageModel) { $imageModel = Get-ObjectProperty $provider "image_model" }
    if (-not $imageModel) { $imageModel = Get-EnvironmentValue "OPENAI_IMAGE_MODEL" }

    $responseModel = Get-Option $Options "response-model"
    if (-not $responseModel) { $responseModel = Get-ObjectProperty $toml.root "model" }
    if (-not $responseModel) { $responseModel = Get-EnvironmentValue "OPENAI_MODEL" }

    $authApiKey = Get-ObjectProperty $auth "OPENAI_API_KEY"
    $environmentApiKey = Get-EnvironmentValue $apiKeyEnvName
    $apiKey = if ($authApiKey) { $authApiKey } else { $environmentApiKey }
    $apiKeySource = if ($authApiKey) { "codex-auth" } elseif ($environmentApiKey) { "env:$apiKeyEnvName" } else { "none" }

    if (@("responses", "images") -notcontains $imageApi) {
        Fail "unsupported image API: $imageApi. Expected responses or images."
    }
    if ($imageApi -eq "responses" -and -not $responseModel) {
        Fail "no Responses model found. Set Codex top-level model or pass --response-model."
    }
    if (-not $apiKey -and -not $Options.ContainsKey("dry-run")) {
        Fail "no API key found. Expected OPENAI_API_KEY in Codex auth.json or environment variable $apiKeyEnvName."
    }

    return @{
        codex_home = $codexHome
        config_path = $configPath
        auth_path = $authPath
        provider_name = $providerName
        base_url = $baseUrl
        image_api = $imageApi
        image_model = $imageModel
        response_model = $responseModel
        api_key = $apiKey
        api_key_source = $apiKeySource
        has_api_key = [bool]$apiKey
    }
}

function Read-Prompt {
    param([hashtable]$Options)
    $prompt = Get-Option $Options "prompt"
    if ($prompt) { return $prompt }

    $promptFile = Get-Option $Options "prompt-file"
    if ($promptFile) {
        if (-not (Test-Path -LiteralPath $promptFile -PathType Leaf)) {
            Fail "prompt file not found: $promptFile"
        }
        return [IO.File]::ReadAllText((Resolve-FullPath $promptFile)).Trim()
    }

    if ([Console]::IsInputRedirected) {
        $stdinPrompt = [Console]::In.ReadToEnd().Trim()
        if ($stdinPrompt) { return $stdinPrompt }
    }
    Fail "missing --prompt, --prompt-file, or stdin prompt."
}

function Get-MimeType {
    param([string]$Path)
    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".gif" { return "image/gif" }
        default { return "image/png" }
    }
}

function Convert-ImageToDataUrl {
    param([string]$Path)
    $fullPath = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Fail "image file not found: $Path"
    }
    $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fullPath))
    return "data:$(Get-MimeType $fullPath);base64,$base64"
}

function Write-ProgressMessage {
    param(
        [hashtable]$Options,
        [string]$Message
    )
    if (-not $Options.ContainsKey("no-progress")) {
        [Console]::Error.WriteLine("[image-generation] $Message")
    }
}

function Wait-HttpTask {
    param(
        [System.Threading.Tasks.Task]$Task,
        [hashtable]$Options
    )
    $started = [DateTime]::UtcNow
    $lastProgress = 0
    Write-ProgressMessage $Options "Request sent. Image generation can take several minutes; wait for this command to finish before retrying."
    while (-not $Task.IsCompleted) {
        Start-Sleep -Seconds 1
        $elapsed = [int]([DateTime]::UtcNow - $started).TotalSeconds
        if ($elapsed -ge $lastProgress + 15) {
            $lastProgress = $elapsed
            Write-ProgressMessage $Options "Still waiting for image result (${elapsed}s elapsed). Do not start another generation for the same request unless this command fails."
        }
    }
    return $Task.GetAwaiter().GetResult()
}

function New-HttpClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $handler = New-Object -TypeName Net.Http.HttpClientHandler
    $client = New-Object -TypeName Net.Http.HttpClient -ArgumentList (, $handler)
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    return $client
}

function Send-ApiRequest {
    param(
        [Net.Http.HttpClient]$Client,
        [string]$Endpoint,
        [string]$ApiKey,
        [Net.Http.HttpContent]$Content,
        [hashtable]$Options
    )
    $request = New-Object -TypeName Net.Http.HttpRequestMessage -ArgumentList @([Net.Http.HttpMethod]::Post, $Endpoint)
    $request.Headers.Authorization = New-Object -TypeName Net.Http.Headers.AuthenticationHeaderValue -ArgumentList @("Bearer", $ApiKey)
    $request.Content = $Content
    try {
        $response = Wait-HttpTask ($Client.SendAsync($request)) $Options
        try {
            $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return @{
                status = [int]$response.StatusCode
                text = $responseText
            }
        } finally {
            $response.Dispose()
        }
    } finally {
        $request.Dispose()
    }
}

function Parse-ResponseJson {
    param(
        [int]$Status,
        [string]$Text
    )
    try {
        return $Text | ConvertFrom-Json
    } catch {
        $preview = if ($Text.Length -gt 500) { $Text.Substring(0, 500) } else { $Text }
        Fail "API returned non-JSON response with status ${Status}: $preview"
    }
}

function Get-ApiErrorMessage {
    param($ResponseJson)
    $errorObject = Get-ObjectProperty $ResponseJson "error"
    $message = Get-ObjectProperty $errorObject "message"
    if (-not $message -and $errorObject -is [string]) { $message = $errorObject }
    if (-not $message) { $message = Get-ObjectProperty $ResponseJson "message" }
    if (-not $message) {
        $message = $ResponseJson | ConvertTo-Json -Depth 20 -Compress
        if ($message.Length -gt 1000) { $message = $message.Substring(0, 1000) }
    }
    return $message
}

function Resolve-Action {
    param(
        [hashtable]$Options,
        [string[]]$Images
    )
    $action = Get-Option $Options "action"
    if ($action -and $action -ne "auto") { return $action }
    if ($Images.Count -gt 0 -or (Get-Option $Options "mask")) { return "edit" }
    return "generate"
}

function Add-ImageOptions {
    param(
        [Collections.IDictionary]$Target,
        [hashtable]$Options
    )
    $mapping = [ordered]@{
        "background" = "background"
        "input-fidelity" = "input_fidelity"
        "moderation" = "moderation"
        "format" = "output_format"
        "quality" = "quality"
        "size" = "size"
    }
    foreach ($argumentName in $mapping.Keys) {
        if ($Options.ContainsKey($argumentName)) {
            $Target[$mapping[$argumentName]] = $Options[$argumentName]
        }
    }
    $compression = Get-IntegerOption $Options "output-compression" 0 100
    if ($null -ne $compression) { $Target["output_compression"] = $compression }
}

function Get-OutputPath {
    param(
        [string]$BasePath,
        [int]$Index,
        [int]$Count,
        [string]$OutputFormat
    )
    $fullBasePath = Resolve-FullPath $BasePath
    if ($Count -eq 1) { return $fullBasePath }
    $directory = [IO.Path]::GetDirectoryName($fullBasePath)
    $name = [IO.Path]::GetFileNameWithoutExtension($fullBasePath)
    $extension = [IO.Path]::GetExtension($fullBasePath)
    if (-not $extension) { $extension = ".$OutputFormat" }
    return Join-Path $directory "$name-$($Index + 1)$extension"
}

function Write-ImageBytes {
    param(
        [Net.Http.HttpClient]$Client,
        $Result,
        [string]$Target
    )
    $base64 = Get-ObjectProperty $Result "b64_json"
    $url = Get-ObjectProperty $Result "url"
    [byte[]]$bytes = $null
    if ($base64) {
        $bytes = [Convert]::FromBase64String($base64)
    } elseif ($url) {
        $bytes = $Client.GetByteArrayAsync($url).GetAwaiter().GetResult()
    } else {
        $preview = $Result | ConvertTo-Json -Depth 10 -Compress
        if ($preview.Length -gt 1000) { $preview = $preview.Substring(0, 1000) }
        Fail "image result contained neither b64_json nor url: $preview"
    }
    $directory = [IO.Path]::GetDirectoryName($Target)
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    [IO.File]::WriteAllBytes($Target, $bytes)
}

function Get-InputOptimizationSummary {
    param([string[]]$Images)
    $items = New-Object Collections.ArrayList
    foreach ($image in $Images) {
        [void]$items.Add([ordered]@{
            original = $(Resolve-FullPath $image)
            optimized = $false
            reason = "powershell-fallback-uses-original"
        })
    }
    return @($items)
}

function Invoke-ImagesApi {
    param(
        [Net.Http.HttpClient]$Client,
        [string]$Prompt,
        [hashtable]$Options,
        [hashtable]$Config,
        [string[]]$Images
    )
    $action = Resolve-Action $Options $Images
    if (@("generate", "edit") -notcontains $action) {
        Fail "--action must be generate, edit, or auto."
    }
    if ($action -eq "edit" -and $Images.Count -eq 0) {
        Fail "Images API edit mode requires at least one --image."
    }
    if ($action -eq "generate" -and ($Images.Count -gt 0 -or (Get-Option $Options "mask"))) {
        Fail "Images API generate mode does not accept --image or --mask. Use --action edit."
    }

    $model = Get-Option $Options "image-model" $Config.image_model
    if (-not $model) {
        Fail "no image model found. Set provider image_model or pass --image-model."
    }

    $fields = [ordered]@{ model = $model; prompt = $Prompt }
    Add-ImageOptions $fields $Options
    $endpointName = if ($action -eq "edit") { "edits" } else { "generations" }
    $endpoint = "$($Config.base_url)/images/$endpointName"

    if ($Options.ContainsKey("dry-run")) {
        $requestSummary = [ordered]@{}
        foreach ($key in $fields.Keys) { $requestSummary[$key] = $fields[$key] }
        $requestSummary.images = @($Images | ForEach-Object { Resolve-FullPath $_ })
        $requestSummary.original_images = @($Images | ForEach-Object { Resolve-FullPath $_ })
        $requestSummary.input_optimization = Get-InputOptimizationSummary $Images
        $mask = Get-Option $Options "mask"
        $requestSummary.mask = if ($mask) { Resolve-FullPath $mask } else { $null }
        [ordered]@{
            codex_home = $Config.codex_home
            config_path = $Config.config_path
            auth_path = $Config.auth_path
            provider = $Config.provider_name
            image_api = $Config.image_api
            base_url = $Config.base_url
            endpoint = $endpoint
            image_model = $model
            has_api_key = $Config.has_api_key
            api_key_source = $Config.api_key_source
            request = $requestSummary
        } | ConvertTo-Json -Depth 30
        return
    }

    $content = $null
    try {
        if ($action -eq "generate") {
            $body = $fields | ConvertTo-Json -Depth 20 -Compress
            $content = New-Object -TypeName Net.Http.StringContent -ArgumentList @($body, [Text.Encoding]::UTF8, "application/json")
        } else {
            $content = New-Object -TypeName Net.Http.MultipartFormDataContent
            foreach ($key in $fields.Keys) {
                $fieldContent = New-Object -TypeName Net.Http.StringContent -ArgumentList @([string]$fields[$key], [Text.Encoding]::UTF8)
                $content.Add($fieldContent, $key)
            }
            $imageField = if ($Images.Count -eq 1) { "image" } else { "image[]" }
            foreach ($image in $Images) {
                $fullPath = Resolve-FullPath $image
                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    Fail "image file not found: $image"
                }
                [byte[]]$fileBytes = [IO.File]::ReadAllBytes($fullPath)
                $fileContent = New-Object -TypeName Net.Http.ByteArrayContent -ArgumentList (, $fileBytes)
                $fileContent.Headers.ContentType = New-Object -TypeName Net.Http.Headers.MediaTypeHeaderValue -ArgumentList (Get-MimeType $fullPath)
                $content.Add($fileContent, $imageField, [IO.Path]::GetFileName($fullPath))
            }
            $mask = Get-Option $Options "mask"
            if ($mask) {
                $maskPath = Resolve-FullPath $mask
                if (-not (Test-Path -LiteralPath $maskPath -PathType Leaf)) {
                    Fail "mask file not found: $mask"
                }
                [byte[]]$maskBytes = [IO.File]::ReadAllBytes($maskPath)
                $maskContent = New-Object -TypeName Net.Http.ByteArrayContent -ArgumentList (, $maskBytes)
                $maskContent.Headers.ContentType = New-Object -TypeName Net.Http.Headers.MediaTypeHeaderValue -ArgumentList (Get-MimeType $maskPath)
                $content.Add($maskContent, "mask", [IO.Path]::GetFileName($maskPath))
            }
        }

        $response = Send-ApiRequest $Client $endpoint $Config.api_key $content $Options
    } finally {
        if ($null -ne $content) { $content.Dispose() }
    }
    Write-ProgressMessage $Options "Response received. Decoding image data."
    $responseJson = Parse-ResponseJson $response.status $response.text
    if ($response.status -lt 200 -or $response.status -ge 300) {
        Fail "API request failed with status $($response.status): $(Get-ApiErrorMessage $responseJson)"
    }

    $data = Get-ObjectProperty $responseJson "data"
    $results = if ($null -eq $data) { @() } else { @($data) }
    if ($results.Count -eq 0) {
        $preview = $responseJson | ConvertTo-Json -Depth 20 -Compress
        if ($preview.Length -gt 1000) { $preview = $preview.Substring(0, 1000) }
        Fail "Images API response contained no data: $preview"
    }

    $outputPath = Get-Option $Options "out" "generated.png"
    $outputFormat = Get-Option $Options "format"
    if (-not $outputFormat) { $outputFormat = [IO.Path]::GetExtension($outputPath).TrimStart(".") }
    if (-not $outputFormat) { $outputFormat = "png" }
    $written = New-Object Collections.ArrayList
    for ($index = 0; $index -lt $results.Count; $index++) {
        $target = Get-OutputPath $outputPath $index $results.Count $outputFormat
        Write-ImageBytes $Client $results[$index] $target
        [void]$written.Add($target)
    }

    if ($Options.ContainsKey("json")) {
        [ordered]@{
            provider = $Config.provider_name
            image_api = $Config.image_api
            base_url = $Config.base_url
            image_model = $model
            outputs = @($written)
        } | ConvertTo-Json -Depth 10
    } else {
        foreach ($path in $written) { Write-Output "Wrote $path" }
    }
}

function Redact-RequestJson {
    param($RequestBody)
    $json = $RequestBody | ConvertTo-Json -Depth 30
    return [regex]::Replace($json, '(data:[^;,"]+;base64,)[^"]+', '$1<base64-redacted>')
}

function Invoke-ResponsesApi {
    param(
        [Net.Http.HttpClient]$Client,
        [string]$Prompt,
        [hashtable]$Options,
        [hashtable]$Config,
        [string[]]$Images
    )
    $tool = [ordered]@{ type = "image_generation" }
    $mapping = [ordered]@{
        "action" = "action"
        "background" = "background"
        "input-fidelity" = "input_fidelity"
        "image-model" = "model"
        "moderation" = "moderation"
        "format" = "output_format"
        "quality" = "quality"
        "size" = "size"
    }
    foreach ($argumentName in $mapping.Keys) {
        if ($Options.ContainsKey($argumentName)) {
            $tool[$mapping[$argumentName]] = $Options[$argumentName]
        }
    }
    $compression = Get-IntegerOption $Options "output-compression" 0 100
    if ($null -ne $compression) { $tool["output_compression"] = $compression }
    $partialImages = Get-IntegerOption $Options "partial-images" 0 3
    if ($null -ne $partialImages) { $tool["partial_images"] = $partialImages }
    if (-not $tool.Contains("model") -and $Config.image_model) { $tool["model"] = $Config.image_model }

    $mask = Get-Option $Options "mask"
    if ($mask) {
        $tool["input_image_mask"] = [ordered]@{ image_url = $(Convert-ImageToDataUrl $mask) }
    }
    if (-not $tool.Contains("action") -and $Images.Count -eq 0) {
        $tool["action"] = "generate"
    }

    $input = $Prompt
    if ($Images.Count -gt 0) {
        $content = New-Object Collections.ArrayList
        [void]$content.Add([ordered]@{ type = "input_text"; text = $Prompt })
        foreach ($image in $Images) {
            [void]$content.Add([ordered]@{ type = "input_image"; image_url = $(Convert-ImageToDataUrl $image) })
        }
        $input = @([ordered]@{ role = "user"; content = @($content) })
    }

    $requestBody = [ordered]@{
        model = $Config.response_model
        input = $input
        tools = @($tool)
    }
    $endpoint = "$($Config.base_url)/responses"

    if ($Options.ContainsKey("dry-run")) {
        $redactedRequest = (Redact-RequestJson $requestBody) | ConvertFrom-Json
        [ordered]@{
            codex_home = $Config.codex_home
            config_path = $Config.config_path
            auth_path = $Config.auth_path
            provider = $Config.provider_name
            base_url = $Config.base_url
            endpoint = $endpoint
            response_model = $Config.response_model
            has_api_key = $Config.has_api_key
            api_key_source = $Config.api_key_source
            original_images = @($Images | ForEach-Object { Resolve-FullPath $_ })
            input_optimization = $(Get-InputOptimizationSummary $Images)
            request = $redactedRequest
        } | ConvertTo-Json -Depth 30
        return
    }

    $body = $requestBody | ConvertTo-Json -Depth 30 -Compress
    $content = New-Object -TypeName Net.Http.StringContent -ArgumentList @($body, [Text.Encoding]::UTF8, "application/json")
    try {
        $response = Send-ApiRequest $Client $endpoint $Config.api_key $content $Options
    } finally {
        $content.Dispose()
    }
    Write-ProgressMessage $Options "Response received. Decoding image data."
    $responseJson = Parse-ResponseJson $response.status $response.text
    if ($response.status -lt 200 -or $response.status -ge 300) {
        Fail "API request failed with status $($response.status): $(Get-ApiErrorMessage $responseJson)"
    }

    $imageResults = New-Object Collections.ArrayList
    $outputItems = Get-ObjectProperty $responseJson "output"
    if ($null -ne $outputItems) {
        foreach ($item in @($outputItems)) {
            if ((Get-ObjectProperty $item "type") -eq "image_generation_call") {
                $result = Get-ObjectProperty $item "result"
                if ($result) { [void]$imageResults.Add($result) }
            }
        }
    }
    if ($imageResults.Count -eq 0) {
        Fail "response did not contain output[].type == image_generation_call with a result."
    }

    $outputPath = Get-Option $Options "out" "generated.png"
    $outputFormat = Get-Option $Options "format"
    if (-not $outputFormat) { $outputFormat = [IO.Path]::GetExtension($outputPath).TrimStart(".") }
    if (-not $outputFormat) { $outputFormat = "png" }
    $written = New-Object Collections.ArrayList
    for ($index = 0; $index -lt $imageResults.Count; $index++) {
        $target = Get-OutputPath $outputPath $index $imageResults.Count $outputFormat
        $directory = [IO.Path]::GetDirectoryName($target)
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        [IO.File]::WriteAllBytes($target, [Convert]::FromBase64String([string]$imageResults[$index]))
        [void]$written.Add($target)
    }

    if ($Options.ContainsKey("json")) {
        [ordered]@{
            response_id = $(Get-ObjectProperty $responseJson "id")
            provider = $Config.provider_name
            base_url = $Config.base_url
            response_model = $Config.response_model
            image_model = $(if ($tool.Contains("model")) { $tool.model } else { "api-default" })
            outputs = @($written)
        } | ConvertTo-Json -Depth 10
    } else {
        foreach ($path in $written) { Write-Output "Wrote $path" }
    }
}

function Main {
    param([string[]]$RawArguments)

    $options = Parse-Arguments $RawArguments
    if ($options.ContainsKey("help")) {
        Show-Help
        return
    }

    foreach ($validation in @(
        @{ Name = "quality"; Allowed = @("low", "medium", "high", "auto") },
        @{ Name = "format"; Allowed = @("png", "webp", "jpeg") },
        @{ Name = "background"; Allowed = @("transparent", "opaque", "auto") },
        @{ Name = "input-fidelity"; Allowed = @("high", "low") },
        @{ Name = "moderation"; Allowed = @("auto", "low") },
        @{ Name = "action"; Allowed = @("generate", "edit", "auto") },
        @{ Name = "image-api"; Allowed = @("responses", "images") }
    )) {
        if ($options.ContainsKey($validation.Name) -and
            $validation.Allowed -notcontains $options[$validation.Name]) {
            Fail "--$($validation.Name) must be one of: $($validation.Allowed -join ', ')"
        }
    }

    $prompt = Read-Prompt $options
    $config = Resolve-CodexConfig $options
    $images = @($options.image | ForEach-Object { $_ })
    $client = New-HttpClient
    try {
        if ($config.image_api -eq "images") {
            Invoke-ImagesApi $client $prompt $options $config $images
        } else {
            Invoke-ResponsesApi $client $prompt $options $config $images
        }
    } finally {
        $client.Dispose()
    }
}

try {
    Main $args
} catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    throw
}

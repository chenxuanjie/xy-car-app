#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiProject,
    [Parameter(Mandatory)][string]$ApiPython,
    [string]$Publisher = (Join-Path $env:USERPROFILE '.codex/skills/flutter-release-publisher'),
    [switch]$BuildUnderGate
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ApiProject = (Resolve-Path -LiteralPath $ApiProject).Path
$Publisher = (Resolve-Path -LiteralPath $Publisher).Path
$entry = Join-Path $Publisher 'scripts/flutter-release.ps1'
$reportDir = 'reports/docker-linux-amd64'
$files = @(
    "$reportDir/docker-compose.yml", "$reportDir/release.json", "$reportDir/validation.json",
    "$reportDir/checksums.sha256", "$reportDir/login-validation.json",
    'xy-car-web-linux-amd64-images.tar'
)
$release = Join-Path $project 'release'
$receipt = Join-Path $release 'reports/web-docker-source-provenance.json'

if (-not $BuildUnderGate) {
    $null = New-Item -ItemType Directory -Path $release -Force
    $lock = [IO.File]::Open((Join-Path $release '.web-docker.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $gate = Join-Path $Publisher 'scripts/release_source_gate.py'
        $artifactArgs = foreach ($file in $files) { '--artifact'; "release/$file" }
        $gateArgs = @('--project', $project, '--receipt', $receipt) + $artifactArgs
        & python $gate run @gateArgs --cwd $project -- pwsh -NoProfile -File $PSCommandPath -ApiProject $ApiProject -ApiPython $ApiPython -Publisher $Publisher -BuildUnderGate
        if ($LASTEXITCODE -ne 0) { throw 'Gated Web and Docker build failed.' }
        & python $gate verify @gateArgs
        if ($LASTEXITCODE -ne 0) { throw 'Final Web delivery source verification failed.' }
    } finally {
        $lock.Dispose()
    }
    exit 0
}

$stageName = '.web-docker-' + [Guid]::NewGuid().ToString('N')
$stage = Join-Path $release $stageName
$null = New-Item -ItemType Directory -Path $stage
Push-Location -LiteralPath $project
try {
    $flutter = (Get-Command flutter -CommandType Application,ExternalScript | Select-Object -First 1).Source
    $sdk = & $flutter --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $sdk.frameworkVersion -or -not $sdk.frameworkRevision) {
        throw 'Unable to read the Flutter SDK version.'
    }
    Write-Host "Building with Flutter $($sdk.frameworkVersion) ($($sdk.frameworkRevision))."
    & $flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked Flutter dependencies could not be resolved.' }
    & $flutter build web --release --no-pub --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Web compilation failed.' }

    $registered = Get-Content -Raw (Join-Path $Publisher 'profiles/xy_car_app.json') | ConvertFrom-Json
    $registered.docker.outputDir = "release/$stageName"
    $registered.docker.smoke.paths += '/settings/account'
    $profile = @{ appId = $registered.appId; projectDir = $registered.projectDir; docker = $registered.docker }
    $profile | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $stage 'xy_car_app.json') -Encoding utf8

    # WSL reads the Windows checkout using the same line-ending rules as Windows Git.
    $autocrlf = & git config --get core.autocrlf
    if ($LASTEXITCODE -eq 0 -and $autocrlf) {
        $slot = [int]$env:GIT_CONFIG_COUNT
        Set-Item "Env:GIT_CONFIG_KEY_$slot" 'core.autocrlf'
        Set-Item "Env:GIT_CONFIG_VALUE_$slot" $autocrlf
        $env:GIT_CONFIG_COUNT = [string]($slot + 1)
        $env:WSLENV = (@($env:WSLENV, 'GIT_CONFIG_COUNT', "GIT_CONFIG_KEY_$slot", "GIT_CONFIG_VALUE_$slot") |
            Where-Object { $_ }) -join ':'
    }
    & pwsh -NoProfile -File $entry docker -Project $project -Profiles $stage
    if ($LASTEXITCODE -ne 0) { throw 'Docker packaging or archive validation failed.' }

    $details = Join-Path $stage "$reportDir/release.json"
    $metadata = Get-Content -Raw -LiteralPath $details | ConvertFrom-Json -AsHashtable
    if ($metadata.dirtySource -ne $false -or $metadata.sourceRevision -ne (& git rev-parse HEAD)) {
        throw 'Docker metadata does not identify the current clean source.'
    }
    & $ApiPython (Join-Path $PSScriptRoot 'verify_docker_login.py') --api-project $ApiProject --compose (Join-Path $stage "$reportDir/docker-compose.yml") --web-root (Join-Path $project 'build/web') --report (Join-Path $stage "$reportDir/login-validation.json")
    if ($LASTEXITCODE -ne 0) { throw 'Docker sign-in verification failed. Existing delivery retained.' }

    $metadata['flutterSdk'] = @{
        version = $sdk.frameworkVersion
        revision = $sdk.frameworkRevision
        dartVersion = $sdk.dartSdkVersion
    }
    $metadata['webBuildSha256'] = (Get-FileHash (Join-Path $project 'build/web/main.dart.js')).Hash.ToLowerInvariant()
    $metadata | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $details -Encoding utf8
    foreach ($file in $files) {
        $destination = Join-Path $release $file
        $null = New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force
        [IO.File]::Move((Join-Path $stage $file), $destination, $true)
    }
} finally {
    Pop-Location
    $resolvedStage = (Resolve-Path -LiteralPath $stage).Path
    if ((Split-Path $resolvedStage -Parent) -eq $release -and (Split-Path $resolvedStage -Leaf) -eq $stageName) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'prepare_agefield_runtime_payload'

$expectedArchiveBytes = 5523402
$expectedArchiveSha256 = '4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC'
$expectedLicenseSha256 = 'DDC030E25D0EA87ACA4AE84C0ED3F868D69273C00C0C12EA1E26F1C6130F5D2E'
$archiveDownloadUrl = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip'
$licenseDownloadUrl = 'https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/d935b5b/LICENSE'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$runtimeDirectory = Join-Path $projectRoot 'installer\runtime'
$archivePath = Join-Path $runtimeDirectory 'vendor\UE4SS_v3.0.1.zip'
$licensePath = Join-Path $runtimeDirectory 'vendor\UE4SS-LICENSE.txt'
$manifestPath = Join-Path $runtimeDirectory 'payload-manifest.json'

$overlays = @(
    [ordered]@{
        source = Join-Path $projectRoot 'installer\templates\UE4SS-settings.ini'
        packagePath = 'overrides\UE4SS-settings.ini'
        targetPath = 'UE4SS-settings.ini'
    },
    [ordered]@{
        source = Join-Path $projectRoot 'installer\templates\Mods\mods.txt'
        packagePath = 'overrides\Mods\mods.txt'
        targetPath = 'Mods\mods.txt'
    },
    [ordered]@{
        source = Join-Path $projectRoot 'integration\uue4ss\Mods\AgefieldModBridge\Scripts\main.lua'
        packagePath = 'overrides\Mods\AgefieldModBridge\Scripts\main.lua'
        targetPath = 'Mods\AgefieldModBridge\Scripts\main.lua'
    },
    [ordered]@{
        source = Join-Path $projectRoot 'integration\uue4ss\Mods\shared\cyberfox1337x.lua'
        packagePath = 'overrides\Mods\shared\cyberfox1337x.lua'
        targetPath = 'Mods\shared\cyberfox1337x.lua'
    },
    [ordered]@{
        source = $licensePath
        packagePath = 'vendor\UE4SS-LICENSE.txt'
        targetPath = 'THIRD-PARTY-NOTICES\UE4SS-LICENSE.txt'
    }
)

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)
    $stream = [IO.File]::OpenRead($LiteralPath)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $normalized = $RelativePath.Replace('/', '\')
    if ([IO.Path]::IsPathRooted($normalized) -or $normalized -match '(^|\\)\.\.(\\|$)' -or $normalized.Contains(':')) {
        throw "Unsafe archive path: $RelativePath"
    }
    return $normalized.TrimStart('\')
}

function Copy-Overlay {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Overlay,
        [Parameter(Mandatory)][string]$StagingRoot
    )

    if (-not (Test-Path -LiteralPath $Overlay.source -PathType Leaf)) {
        throw "Required overlay is missing: $($Overlay.source)"
    }
    $targetPath = Join-Path $StagingRoot (Assert-SafeRelativePath -RelativePath $Overlay.targetPath)
    New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
    Copy-Item -LiteralPath $Overlay.source -Destination $targetPath -Force
}

New-Item -ItemType Directory -Path (Split-Path -Parent $archivePath) -Force | Out-Null
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    Write-Output 'Downloading the pinned official UE4SS v3.0.1 release asset...'
    Invoke-WebRequest -Uri $archiveDownloadUrl -OutFile $archivePath -UseBasicParsing
}
if ((Get-Item -LiteralPath $archivePath).Length -ne $expectedArchiveBytes) {
    throw 'Official UE4SS archive size does not match the verified v3.0.1 asset.'
}
if ((Get-Sha256 -LiteralPath $archivePath) -ne $expectedArchiveSha256) {
    throw 'Official UE4SS archive hash does not match the verified v3.0.1 asset.'
}
if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
    Write-Output 'Downloading the pinned UE4SS MIT license...'
    Invoke-WebRequest -Uri $licenseDownloadUrl -OutFile $licensePath -UseBasicParsing
}
if ((Get-Sha256 -LiteralPath $licensePath) -ne $expectedLicenseSha256) {
    throw 'UE4SS MIT license hash does not match the reviewed v3.0.1 license.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('agefield-runtime-payload-' + [guid]::NewGuid().ToString('N'))))
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (-not $temporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe staging directory: $temporaryRoot"
}

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.Name)) { continue }
            [void](Assert-SafeRelativePath -RelativePath $entry.FullName)
        }
    }
    finally {
        $archive.Dispose()
    }

    [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $temporaryRoot)
    foreach ($overlay in $overlays) {
        Copy-Overlay -Overlay $overlay -StagingRoot $temporaryRoot
    }

    $payloadFiles = @(
        Get-ChildItem -LiteralPath $temporaryRoot -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($temporaryRoot.Length + 1).Replace('\', '/')
                [ordered]@{
                    relativePath = $relativePath
                    bytes = $_.Length
                    sha256 = Get-Sha256 -LiteralPath $_.FullName
                }
            }
    )

    foreach ($requiredPath in @(
        'dwmapi.dll',
        'UE4SS.dll',
        'UE4SS-settings.ini',
        'Mods/mods.txt',
        'Mods/Keybinds/Scripts/main.lua',
        'Mods/shared/UEHelpers/UEHelpers.lua',
        'Mods/AgefieldModBridge/Scripts/main.lua',
        'Mods/shared/cyberfox1337x.lua',
        'THIRD-PARTY-NOTICES/UE4SS-LICENSE.txt'
    )) {
        if ($payloadFiles.relativePath -notcontains $requiredPath) {
            throw "Prepared payload is missing required file: $requiredPath"
        }
    }

    $bridgeSource = Get-Content -LiteralPath (Join-Path $projectRoot 'integration\uue4ss\Mods\AgefieldModBridge\Scripts\main.lua') -Raw
    $bridgeVersionMatch = [regex]::Match($bridgeSource, 'local\s+BRIDGE_VERSION\s*=\s*"(?<Version>[^"]+)"')
    if (-not $bridgeVersionMatch.Success) {
        throw 'Could not determine Agefield bridge version from the signed Lua source.'
    }

    $manifest = [ordered]@{
        cyberfox1337x = 'function(agefield_runtime_payload_manifest)'
        schemaVersion = 1
        applicationVersion = '1.6.0'
        bridgeVersion = $bridgeVersionMatch.Groups['Version'].Value
        steamAppId = '3562580'
        steamBuildId = '24987926'
        shippingExecutableSha256 = '4C8EAE91E49295780D9C0D1F850773AFBC535E1120D3EDAB5992D575B3127951'
        ue4ssVersion = '3.0.1'
        ue4ssArchive = [ordered]@{
            packagePath = 'vendor/UE4SS_v3.0.1.zip'
            bytes = $expectedArchiveBytes
            sha256 = $expectedArchiveSha256
            source = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1'
            license = 'MIT'
        }
        requiredSettings = @(
            [ordered]@{ section = 'Hooks'; key = 'HookProcessInternal'; value = '1'; reason = 'Required for the verified native damage hook used by God Mode.' },
            [ordered]@{ section = 'Hooks'; key = 'HookInitGameState'; value = '1'; reason = 'Required for the verified game-state hook lifecycle used by the production Lua runtime.' }
        )
        requiredModRegistry = @(
            [ordered]@{ name = 'Keybinds'; value = '1' },
            [ordered]@{ name = 'AgefieldModBridge'; value = '1' },
            [ordered]@{ name = 'AgefieldReflectionDiscovery'; value = '0' }
        )
        overlays = @(
            $overlays | ForEach-Object {
                [ordered]@{
                    packagePath = $_.packagePath.Replace('\', '/')
                    targetPath = $_.targetPath.Replace('\', '/')
                    sha256 = Get-Sha256 -LiteralPath $_.source
                }
            }
        )
        payloadFiles = $payloadFiles
    }

    New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
    foreach ($overlay in $overlays) {
        $packageRelativePath = Assert-SafeRelativePath -RelativePath $overlay.packagePath
        $packageDestination = [IO.Path]::GetFullPath((Join-Path $runtimeDirectory $packageRelativePath))
        $runtimePrefix = [IO.Path]::GetFullPath($runtimeDirectory).TrimEnd('\') + '\'
        if (-not $packageDestination.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe packaged overlay path: $packageDestination"
        }
        $sourcePath = [IO.Path]::GetFullPath($overlay.source)
        if (-not $sourcePath.Equals($packageDestination, [StringComparison]::OrdinalIgnoreCase)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $packageDestination) -Force | Out-Null
            Copy-Item -LiteralPath $sourcePath -Destination $packageDestination -Force
        }
        if ((Get-Sha256 -LiteralPath $packageDestination) -ne (Get-Sha256 -LiteralPath $sourcePath)) {
            throw "Packaged overlay failed its hash check: $packageRelativePath"
        }
    }
    $temporaryManifest = Join-Path $runtimeDirectory ('payload-manifest.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryManifest -Encoding utf8
    Move-Item -LiteralPath $temporaryManifest -Destination $manifestPath -Force
    Write-Output "Prepared $($payloadFiles.Count) verified runtime payload files at $manifestPath"
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

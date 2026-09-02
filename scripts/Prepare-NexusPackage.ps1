[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'prepare_agefield_nexus_package'

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

function Assert-ExactProjectDirectory {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ExpectedRelativePath
    )
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $ExpectedRelativePath))
    $actualPath = [IO.Path]::GetFullPath($LiteralPath)
    if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unexpected package directory: $actualPath"
    }
}

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json
$version = [string]$packageManifest.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid package version: $version" }

$releaseRoot = Join-Path $projectRoot 'release'
$nexusRoot = Join-Path $projectRoot 'nexus'
$outputRoot = Join-Path $nexusRoot 'release'
Assert-ExactProjectDirectory -LiteralPath $outputRoot -ProjectRoot $projectRoot -ExpectedRelativePath 'nexus\release'

$setupName = "Agefield High Mod Menu-Setup-$version-x64.exe"
$portableName = "Agefield High Mod Menu-Portable-$version-x64.exe"
$setupPath = Join-Path $releaseRoot $setupName
$portablePath = Join-Path $releaseRoot $portableName
foreach ($requiredArtifact in @($setupPath, $portablePath)) {
    if (-not (Test-Path -LiteralPath $requiredArtifact -PathType Leaf)) {
        throw "Required release artifact is missing: $requiredArtifact"
    }
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
foreach ($existingItem in Get-ChildItem -LiteralPath $outputRoot -Force) {
    Remove-Item -LiteralPath $existingItem.FullName -Recurse -Force
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$stagingRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('agefield-nexus-package-' + [guid]::NewGuid().ToString('N'))))
if (-not $stagingRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe staging path: $stagingRoot"
}

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
try {
    Copy-Item -LiteralPath $setupPath -Destination (Join-Path $stagingRoot $setupName)
    Copy-Item -LiteralPath (Join-Path $nexusRoot 'README.md') -Destination (Join-Path $stagingRoot 'README.md')
    Copy-Item -LiteralPath (Join-Path $nexusRoot 'THIRD_PARTY_NOTICES.md') -Destination (Join-Path $stagingRoot 'THIRD_PARTY_NOTICES.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\runtime\vendor\UE4SS-LICENSE.txt') -Destination (Join-Path $stagingRoot 'UE4SS-LICENSE.txt')

    $bundleChecksums = @(
        Get-ChildItem -LiteralPath $stagingRoot -File |
            Sort-Object Name |
            ForEach-Object { "$(Get-Sha256 -LiteralPath $_.FullName)  $($_.Name)" }
    )
    $bundleChecksums | Set-Content -LiteralPath (Join-Path $stagingRoot 'CHECKSUMS.txt') -Encoding ascii

    $archiveName = "Agefield-High-Mod-Menu-One-Click-$version.zip"
    $archivePath = Join-Path $outputRoot $archiveName
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal

    @(
        "$(Get-Sha256 -LiteralPath $setupPath)  release/$setupName",
        "$(Get-Sha256 -LiteralPath $portablePath)  release/$portableName",
        "$(Get-Sha256 -LiteralPath $archivePath)  nexus/release/$archiveName"
    ) | Set-Content -LiteralPath (Join-Path $nexusRoot 'CHECKSUMS.txt') -Encoding ascii
    Write-Output "Prepared Nexus package: $archivePath"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        $resolvedStagingRoot = [IO.Path]::GetFullPath($stagingRoot)
        if (-not $resolvedStagingRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe staging cleanup path: $resolvedStagingRoot"
        }
        Remove-Item -LiteralPath $resolvedStagingRoot -Recurse -Force
    }
}

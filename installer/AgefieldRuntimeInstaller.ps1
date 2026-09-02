[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Uninstall', 'VerifyPayload')]
    [string]$Action,

    [string]$PayloadRoot,

    [string]$ApplicationVersion = '1.6.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'agefield_runtime_installer'

$script:ExpectedAppId = '3562580'
$script:ExpectedBuildId = '24987926'
$script:ExpectedInstallDirectory = 'Agefield High Rock the School'
$script:ExpectedRelativeExecutable = 'Project_HighSchool\Binaries\Win64\Project_HighSchool-Win64-Shipping.exe'
$script:ExpectedExecutableSha256 = '4C8EAE91E49295780D9C0D1F850773AFBC535E1120D3EDAB5992D575B3127951'
$script:ExpectedWin64Suffix = 'Project_HighSchool\Binaries\Win64'
$script:StateRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Cyberfox1337x\AgefieldHighModMenu\Runtime'))
$script:StatePath = Join-Path $script:StateRoot 'install-state.json'
$script:BaselineRoot = Join-Path $script:StateRoot 'baseline'

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

function Get-SafeChildPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $normalized = $RelativePath.Replace('/', '\').TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '(^|\\)\.\.(\\|$)' -or $normalized.Contains(':')) {
        throw "Unsafe relative path: $RelativePath"
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $childPath = [IO.Path]::GetFullPath((Join-Path $rootPath $normalized))
    if (-not $childPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its allowed root: $RelativePath"
    }
    return $childPath
}

function Read-ManifestValue {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )

    $match = [regex]::Match($Text, '"' + [regex]::Escape($Name) + '"\s+"(?<Value>[^"]*)"')
    if (-not $match.Success) {
        throw "Steam manifest is missing '$Name'."
    }
    return $match.Groups['Value'].Value
}

function Get-SteamRoots {
    $roots = [Collections.Generic.List[string]]::new()
    $registryEntries = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )
    foreach ($entry in $registryEntries) {
        try {
            $rawPath = (Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop).($entry.Name)
            if ($rawPath) {
                $roots.Add([IO.Path]::GetFullPath(([string]$rawPath).Replace('/', '\')))
            }
        }
        catch [Management.Automation.ItemNotFoundException] {
            continue
        }
        catch [Management.Automation.PSArgumentException] {
            continue
        }
    }
    return $roots | Sort-Object -Unique
}

function Get-SteamLibraries {
    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($steamRoot in Get-SteamRoots) {
        if (Test-Path -LiteralPath $steamRoot -PathType Container) {
            $libraries.Add($steamRoot)
        }
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        foreach ($line in Get-Content -LiteralPath $libraryFile) {
            if ($line -match '^\s*"path"\s+"(?<Path>.+)"\s*$') {
                $libraries.Add([IO.Path]::GetFullPath($Matches.Path.Replace('\\', '\')))
            }
        }
    }
    return $libraries | Sort-Object -Unique
}

function Get-OfficialGameInstall {
    param([switch]$RequireExactBuild)

    $manifestPaths = @(
        Get-SteamLibraries |
            ForEach-Object { Join-Path $_ "steamapps\appmanifest_$($script:ExpectedAppId).acf" } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )
    if ($manifestPaths.Count -ne 1) {
        throw "Expected exactly one official Steam manifest for App ID $($script:ExpectedAppId); found $($manifestPaths.Count)."
    }

    $manifestPath = [IO.Path]::GetFullPath($manifestPaths[0])
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $appId = Read-ManifestValue -Text $manifestText -Name 'appid'
    $buildId = Read-ManifestValue -Text $manifestText -Name 'buildid'
    $stateFlags = [int](Read-ManifestValue -Text $manifestText -Name 'StateFlags')
    $installDirectory = Read-ManifestValue -Text $manifestText -Name 'installdir'
    if ($appId -ne $script:ExpectedAppId -or ($stateFlags -band 4) -eq 0) {
        throw "Official Steam identity mismatch. App=$appId StateFlags=$stateFlags."
    }
    if ($installDirectory -ne $script:ExpectedInstallDirectory) {
        throw "Unexpected official install directory '$installDirectory'."
    }
    if ($RequireExactBuild -and $buildId -ne $script:ExpectedBuildId) {
        throw "Unsupported Steam build $buildId. This installer requires build $($script:ExpectedBuildId)."
    }

    $steamAppsRoot = Split-Path -Parent $manifestPath
    $installPath = [IO.Path]::GetFullPath((Join-Path $steamAppsRoot "common\$installDirectory"))
    $knownIneligiblePath = [IO.Path]::GetFullPath('C:\Agefield High - Rock the School')
    if ($installPath.Equals($knownIneligiblePath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The permanently ineligible legacy installation cannot be targeted.'
    }
    $executablePath = [IO.Path]::GetFullPath((Join-Path $installPath $script:ExpectedRelativeExecutable))
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "Manifest-derived shipping executable is missing: $executablePath"
    }
    $executableSha256 = Get-Sha256 -LiteralPath $executablePath
    if ($RequireExactBuild -and $executableSha256 -ne $script:ExpectedExecutableSha256) {
        throw "Unsupported shipping executable hash: $executableSha256"
    }

    return [pscustomobject]@{
        manifestPath = $manifestPath
        buildId = $buildId
        installPath = $installPath
        executablePath = $executablePath
        executableSha256 = $executableSha256
        win64Path = [IO.Path]::GetFullPath((Join-Path $installPath $script:ExpectedWin64Suffix))
    }
}

function Assert-EligibleInstall {
    param([Parameter(Mandatory)]$GameInstall)

    $prohibitedNames = @('fitgirl.md5', 'steam_emu.ini', 'steam_api64.rne', 'cream_api.ini', 'coldclientloader.ini')
    $prohibitedHits = @(
        Get-ChildItem -LiteralPath $GameInstall.installPath -File -Recurse -Force |
            Where-Object { $prohibitedNames -contains $_.Name.ToLowerInvariant() }
    )
    if ($prohibitedHits.Count -gt 0) {
        throw 'A repack or Steam-emulation marker was found. Installation is refused.'
    }

    $protectionPattern = '(?i)(EasyAntiCheat|BattlEye|XIGNCODE|xhunter|GameGuard|nProtect|ACE-Base)'
    $protectionHits = @(
        Get-ChildItem -LiteralPath $GameInstall.installPath -File -Recurse -Force |
            Where-Object { $_.FullName -match $protectionPattern }
    )
    if ($protectionHits.Count -gt 0) {
        throw 'An unsupported protection component was found. Installation is refused.'
    }
}

function Assert-GameStopped {
    $runningGame = @(Get-Process -Name 'Project_HighSchool-Win64-Shipping' -ErrorAction SilentlyContinue)
    if ($runningGame.Count -gt 0) {
        throw 'Close Agefield High before installing, updating, or uninstalling the runtime.'
    }
}

function Get-PayloadFileEntry {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RelativePath
    )
    $normalized = $RelativePath.Replace('\', '/')
    $entry = @($Manifest.payloadFiles | Where-Object { $_.relativePath -eq $normalized })
    if ($entry.Count -ne 1) {
        throw "Payload manifest entry is missing or duplicated: $normalized"
    }
    return $entry[0]
}

function New-ValidatedPayloadStaging {
    param([Parameter(Mandatory)][string]$Root)

    $payloadRootPath = [IO.Path]::GetFullPath($Root)
    $manifestPath = Join-Path $payloadRootPath 'payload-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Runtime payload manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.cyberfox1337x -ne 'function(agefield_runtime_payload_manifest)' -or $manifest.schemaVersion -ne 1) {
        throw 'Runtime payload manifest identity is invalid.'
    }
    if ($manifest.steamAppId -ne $script:ExpectedAppId -or $manifest.steamBuildId -ne $script:ExpectedBuildId -or
        $manifest.shippingExecutableSha256 -ne $script:ExpectedExecutableSha256) {
        throw 'Runtime payload targets an unsupported game identity.'
    }

    $archivePath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $manifest.ue4ssArchive.packagePath
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Official UE4SS archive is missing: $archivePath"
    }
    if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$manifest.ue4ssArchive.bytes -or
        (Get-Sha256 -LiteralPath $archivePath) -ne $manifest.ue4ssArchive.sha256) {
        throw 'Official UE4SS archive failed its exact size/hash check.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $stagingRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('agefield-runtime-install-' + [guid]::NewGuid().ToString('N'))))
    if (-not $stagingRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe payload staging path: $stagingRoot"
    }
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrWhiteSpace($entry.Name)) { continue }
                [void](Get-SafeChildPath -Root $stagingRoot -RelativePath $entry.FullName)
            }
        }
        finally {
            $archive.Dispose()
        }
        [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $stagingRoot)

        foreach ($overlay in $manifest.overlays) {
            $sourcePath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $overlay.packagePath
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
                (Get-Sha256 -LiteralPath $sourcePath) -ne $overlay.sha256) {
                throw "Payload overlay failed validation: $($overlay.packagePath)"
            }
            $targetPath = Get-SafeChildPath -Root $stagingRoot -RelativePath $overlay.targetPath
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }

        $actualFiles = @(
            Get-ChildItem -LiteralPath $stagingRoot -File -Recurse |
                ForEach-Object { $_.FullName.Substring($stagingRoot.Length + 1).Replace('\', '/') } |
                Sort-Object
        )
        $expectedFiles = @($manifest.payloadFiles.relativePath | Sort-Object)
        if (($actualFiles -join "`n") -ne ($expectedFiles -join "`n")) {
            throw 'Prepared payload file list does not match its signed manifest.'
        }
        foreach ($file in $manifest.payloadFiles) {
            $filePath = Get-SafeChildPath -Root $stagingRoot -RelativePath $file.relativePath
            if ((Get-Item -LiteralPath $filePath).Length -ne [long]$file.bytes -or
                (Get-Sha256 -LiteralPath $filePath) -ne $file.sha256) {
                throw "Prepared payload file failed validation: $($file.relativePath)"
            }
        }
        return [pscustomobject]@{ root = $stagingRoot; manifest = $manifest }
    }
    catch {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
        throw
    }
}

function Set-IniValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $sectionStart = -1
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[(?<Section>[^\]]+)\]\s*$' -and $Matches.Section -ieq $Section) {
            $sectionStart = $index
            break
        }
    }
    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1] -ne '') { $Lines.Add('') }
        $Lines.Add("[$Section]")
        $Lines.Add("$Key = $Value")
        return
    }

    $sectionEnd = $Lines.Count
    for ($index = $sectionStart + 1; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[[^\]]+\]\s*$') {
            $sectionEnd = $index
            break
        }
    }
    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($Lines[$index] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $Lines[$index] = "$Key = $Value"
            return
        }
    }
    $Lines.Insert($sectionEnd, "$Key = $Value")
}

function Get-IniValueState {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $activeSection = $null
    foreach ($line in Get-Content -LiteralPath $LiteralPath) {
        if ($line -match '^\s*\[(?<Section>[^\]]+)\]\s*$') {
            $activeSection = $Matches.Section
            continue
        }
        if ($activeSection -ieq $Section -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<Value>.*)$')) {
            return [pscustomobject]@{ present = $true; value = $Matches.Value.Trim() }
        }
    }
    return [pscustomobject]@{ present = $false; value = $null }
}

function Remove-IniValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $activeSection = $null
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[(?<Section>[^\]]+)\]\s*$') {
            $activeSection = $Matches.Section
            continue
        }
        if ($activeSection -ieq $Section -and $Lines[$index] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $Lines.RemoveAt($index)
            return
        }
    }
}

function Get-ModRegistryValueState {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Name
    )
    foreach ($line in Get-Content -LiteralPath $LiteralPath) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*:\s*(?<Value>.*)$')) {
            return [pscustomobject]@{ present = $true; value = $Matches.Value.Trim() }
        }
    }
    return [pscustomobject]@{ present = $false; value = $null }
}

function Remove-ModRegistryValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Name
    )
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match ('^\s*' + [regex]::Escape($Name) + '\s*:')) {
            $Lines.RemoveAt($index)
            return
        }
    }
}

function New-MergedSettingsFile {
    param(
        [Parameter(Mandatory)][string]$ExistingPath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ExistingPath) { $lines.Add($line) }
    foreach ($setting in $Manifest.requiredSettings) {
        Set-IniValue -Lines $lines -Section $setting.section -Key $setting.key -Value $setting.value
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding utf8
}

function New-MergedModRegistryFile {
    param(
        [Parameter(Mandatory)][string]$ExistingPath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ExistingPath) { $lines.Add($line) }
    foreach ($requiredMod in $Manifest.requiredModRegistry) {
        $replaced = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match ('^\s*' + [regex]::Escape($requiredMod.name) + '\s*:')) {
                $lines[$index] = "$($requiredMod.name) : $($requiredMod.value)"
                $replaced = $true
                break
            }
        }
        if (-not $replaced) { $lines.Add("$($requiredMod.name) : $($requiredMod.value)") }
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding utf8
}

function Get-LoaderMode {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)]$Manifest
    )

    foreach ($conflictingProxy in @('xinput1_3.dll', 'version.dll', 'winmm.dll')) {
        if (Test-Path -LiteralPath (Join-Path $Win64Path $conflictingProxy) -PathType Leaf) {
            throw "Conflicting proxy loader '$conflictingProxy' is present. Remove it or restore a clean official build first."
        }
    }

    $ue4ssPath = Join-Path $Win64Path 'UE4SS.dll'
    $proxyPath = Join-Path $Win64Path 'dwmapi.dll'
    $ue4ssExists = Test-Path -LiteralPath $ue4ssPath -PathType Leaf
    $proxyExists = Test-Path -LiteralPath $proxyPath -PathType Leaf
    if ($ue4ssExists -xor $proxyExists) {
        throw 'A partial UE4SS installation was found. Restore or remove it before continuing.'
    }
    if (-not $ue4ssExists) { return 'Fresh' }

    $expectedUe4ss = Get-PayloadFileEntry -Manifest $Manifest -RelativePath 'UE4SS.dll'
    $expectedProxy = Get-PayloadFileEntry -Manifest $Manifest -RelativePath 'dwmapi.dll'
    if ((Get-Sha256 -LiteralPath $ue4ssPath) -ne $expectedUe4ss.sha256 -or
        (Get-Sha256 -LiteralPath $proxyPath) -ne $expectedProxy.sha256) {
        throw 'An unknown or conflicting UE4SS loader version is installed. No files were changed.'
    }
    return 'ExistingExact'
}

function Get-InstallPlan {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$LoaderMode
    )

    $plan = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($LoaderMode -eq 'Fresh') {
        foreach ($file in $Payload.manifest.payloadFiles) {
            $plan[$file.relativePath] = [pscustomobject]@{
                relativePath = $file.relativePath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $file.relativePath
                sha256 = $file.sha256
            }
        }
    }
    else {
        foreach ($requiredPath in @(
            'Mods/Keybinds/Scripts/main.lua',
            'Mods/shared/UEHelpers/UEHelpers.lua'
        )) {
            $payloadEntry = Get-PayloadFileEntry -Manifest $Payload.manifest -RelativePath $requiredPath
            $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $requiredPath
            if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                if ((Get-Sha256 -LiteralPath $destinationPath) -ne $payloadEntry.sha256) {
                    throw "Required UE4SS dependency conflicts with v3.0.1: $requiredPath"
                }
            }
            else {
                $plan[$requiredPath] = [pscustomobject]@{
                    relativePath = $requiredPath
                    sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $requiredPath
                    sha256 = $payloadEntry.sha256
                }
            }
        }
        foreach ($ownedPath in @(
            'Mods/AgefieldModBridge/Scripts/main.lua',
            'Mods/shared/cyberfox1337x.lua',
            'THIRD-PARTY-NOTICES/UE4SS-LICENSE.txt'
        )) {
            $payloadEntry = Get-PayloadFileEntry -Manifest $Payload.manifest -RelativePath $ownedPath
            $plan[$ownedPath] = [pscustomobject]@{
                relativePath = $ownedPath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $ownedPath
                sha256 = $payloadEntry.sha256
            }
        }
    }

    $generatedRoot = Join-Path $Payload.root '_agefield-generated'
    New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null
    foreach ($config in @(
        @{ relativePath = 'UE4SS-settings.ini'; generator = 'settings' },
        @{ relativePath = 'Mods/mods.txt'; generator = 'mods' }
    )) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $config.relativePath
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            $generatedPath = Get-SafeChildPath -Root $generatedRoot -RelativePath $config.relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $generatedPath) -Force | Out-Null
            if ($config.generator -eq 'settings') {
                New-MergedSettingsFile -ExistingPath $destinationPath -Manifest $Payload.manifest -OutputPath $generatedPath
            }
            else {
                New-MergedModRegistryFile -ExistingPath $destinationPath -Manifest $Payload.manifest -OutputPath $generatedPath
            }
            $plan[$config.relativePath] = [pscustomobject]@{
                relativePath = $config.relativePath
                sourcePath = $generatedPath
                sha256 = Get-Sha256 -LiteralPath $generatedPath
            }
        }
        else {
            $payloadEntry = Get-PayloadFileEntry -Manifest $Payload.manifest -RelativePath $config.relativePath
            $plan[$config.relativePath] = [pscustomobject]@{
                relativePath = $config.relativePath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $config.relativePath
                sha256 = $payloadEntry.sha256
            }
        }
    }
    return @($plan.Values | Sort-Object relativePath)
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationPath) -Force | Out-Null
    $temporaryPath = $DestinationPath + '.agefield-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath -Force
        if ((Get-Sha256 -LiteralPath $temporaryPath) -ne $ExpectedSha256) {
            throw "Temporary copy failed its hash check: $DestinationPath"
        }
        Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath -Force
        if ((Get-Sha256 -LiteralPath $DestinationPath) -ne $ExpectedSha256) {
            throw "Installed file failed its hash check: $DestinationPath"
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($state.cyberfox1337x -ne 'function(agefield_runtime_install_state)' -or $state.schemaVersion -ne 1 -or
        $state.steamAppId -ne $script:ExpectedAppId) {
        throw 'The existing runtime install state is invalid. No files were changed.'
    }
    return $state
}

function Write-InstallState {
    param([Parameter(Mandatory)]$State)

    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    $temporaryPath = Join-Path $script:StateRoot ('install-state.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $script:StatePath -Force
}

function Assert-ManagedFilesUnchanged {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Win64Path
    )
    foreach ($record in $State.files) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $record.relativePath
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Managed runtime file changed after installation: $($record.relativePath). Restore or reinstall it before continuing."
        }
        $ownership = if ($record.PSObject.Properties['ownership']) { [string]$record.ownership } else { 'whole-file' }
        if ($ownership -eq 'semantic-ini') {
            foreach ($entry in $record.semanticEntries) {
                $current = Get-IniValueState -LiteralPath $destinationPath -Section $entry.section -Key $entry.key
                if (-not $current.present -or $current.value -ne [string]$entry.installedValue) {
                    throw "Agefield-owned setting changed after installation: [$($entry.section)] $($entry.key)."
                }
            }
            continue
        }
        if ($ownership -eq 'semantic-mod-registry') {
            foreach ($entry in $record.semanticEntries) {
                $current = Get-ModRegistryValueState -LiteralPath $destinationPath -Name $entry.name
                if (-not $current.present -or $current.value -ne [string]$entry.installedValue) {
                    throw "Agefield-owned mod registry entry changed after installation: $($entry.name)."
                }
            }
            continue
        }
        if ((Get-Sha256 -LiteralPath $destinationPath) -ne $record.installedSha256) {
            throw "Managed runtime file changed after installation: $($record.relativePath). Restore or reinstall it before continuing."
        }
    }
}

function New-TransactionSnapshot {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )

    $transactionRoot = Join-Path $script:StateRoot ('transactions\' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
    $records = @()
    foreach ($relativePath in $RelativePaths | Sort-Object -Unique) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $relativePath
        $exists = Test-Path -LiteralPath $destinationPath -PathType Leaf
        $snapshotRelativePath = $null
        if ($exists) {
            $snapshotPath = Get-SafeChildPath -Root $transactionRoot -RelativePath $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotPath) -Force | Out-Null
            Copy-Item -LiteralPath $destinationPath -Destination $snapshotPath -Force
            $snapshotRelativePath = $relativePath
        }
        $records += [pscustomobject]@{
            relativePath = $relativePath
            existed = $exists
            snapshotRelativePath = $snapshotRelativePath
        }
    }
    return [pscustomobject]@{ root = $transactionRoot; records = $records }
}

function Restore-TransactionSnapshot {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$Win64Path
    )
    foreach ($record in $Snapshot.records) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $record.relativePath
        if ($record.existed) {
            $sourcePath = Get-SafeChildPath -Root $Snapshot.root -RelativePath $record.snapshotRelativePath
            Copy-FileAtomically -SourcePath $sourcePath -DestinationPath $destinationPath -ExpectedSha256 (Get-Sha256 -LiteralPath $sourcePath)
        }
        elseif (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $destinationPath -Force
        }
    }
}

function Remove-SafeTransaction {
    param([Parameter(Mandatory)][string]$TransactionRoot)
    $transactionsParent = [IO.Path]::GetFullPath((Join-Path $script:StateRoot 'transactions')).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($TransactionRoot)
    if (-not $resolved.StartsWith($transactionsParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unsafe transaction path: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

function Restore-BaselineRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$Win64Path
    )
    $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $Record.relativePath
    $ownership = if ($Record.PSObject.Properties['ownership']) { [string]$Record.ownership } else { 'whole-file' }
    if ($ownership -eq 'semantic-ini' -or $ownership -eq 'semantic-mod-registry') {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Semantically managed configuration is missing: $($Record.relativePath)"
        }
        $lines = [Collections.Generic.List[string]]::new()
        foreach ($line in Get-Content -LiteralPath $destinationPath) { $lines.Add($line) }
        foreach ($entry in $Record.semanticEntries) {
            if ($ownership -eq 'semantic-ini') {
                if ($entry.originalPresent) {
                    Set-IniValue -Lines $lines -Section $entry.section -Key $entry.key -Value $entry.originalValue
                }
                else {
                    Remove-IniValue -Lines $lines -Section $entry.section -Key $entry.key
                }
            }
            elseif ($entry.originalPresent) {
                $replaced = $false
                for ($index = 0; $index -lt $lines.Count; $index++) {
                    if ($lines[$index] -match ('^\s*' + [regex]::Escape($entry.name) + '\s*:')) {
                        $lines[$index] = "$($entry.name) : $($entry.originalValue)"
                        $replaced = $true
                        break
                    }
                }
                if (-not $replaced) { $lines.Add("$($entry.name) : $($entry.originalValue)") }
            }
            else {
                Remove-ModRegistryValue -Lines $lines -Name $entry.name
            }
        }
        $temporaryPath = Join-Path $script:StateRoot ('semantic-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            Set-Content -LiteralPath $temporaryPath -Value $lines -Encoding utf8
            Copy-FileAtomically -SourcePath $temporaryPath -DestinationPath $destinationPath -ExpectedSha256 (Get-Sha256 -LiteralPath $temporaryPath)
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
        return
    }
    if ($Record.originalKind -eq 'absent') {
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $destinationPath -Force
        }
        return
    }
    if ($Record.originalKind -ne 'file') {
        throw "Unknown baseline record kind: $($Record.originalKind)"
    }
    $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath $Record.backupRelativePath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
        (Get-Sha256 -LiteralPath $backupPath) -ne $Record.originalSha256) {
        throw "Baseline backup is missing or corrupt: $($Record.relativePath)"
    }
    Copy-FileAtomically -SourcePath $backupPath -DestinationPath $destinationPath -ExpectedSha256 $Record.originalSha256
}

function Get-SemanticBaseline {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$Manifest
    )

    $normalizedPath = $RelativePath.Replace('\', '/')
    if ($normalizedPath -eq 'UE4SS-settings.ini') {
        $entries = @(
            foreach ($setting in $Manifest.requiredSettings) {
                $original = Get-IniValueState -LiteralPath $LiteralPath -Section $setting.section -Key $setting.key
                [ordered]@{
                    section = [string]$setting.section
                    key = [string]$setting.key
                    originalPresent = [bool]$original.present
                    originalValue = if ($original.present) { [string]$original.value } else { $null }
                    installedValue = [string]$setting.value
                }
            }
        )
        return [pscustomobject]@{ ownership = 'semantic-ini'; entries = $entries }
    }
    if ($normalizedPath -eq 'Mods/mods.txt') {
        $entries = @(
            foreach ($requiredMod in $Manifest.requiredModRegistry) {
                $original = Get-ModRegistryValueState -LiteralPath $LiteralPath -Name $requiredMod.name
                [ordered]@{
                    name = [string]$requiredMod.name
                    originalPresent = [bool]$original.present
                    originalValue = if ($original.present) { [string]$original.value } else { $null }
                    installedValue = [string]$requiredMod.value
                }
            }
        )
        return [pscustomobject]@{ ownership = 'semantic-mod-registry'; entries = $entries }
    }
    return [pscustomobject]@{ ownership = 'whole-file'; entries = @() }
}

function Remove-FailedInitialState {
    param([Parameter(Mandatory)][bool]$StateRootExistedBefore)

    $expectedStateRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Cyberfox1337x\AgefieldHighModMenu\Runtime'))
    if (-not $script:StateRoot.Equals($expectedStateRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected state path: $($script:StateRoot)"
    }
    if (-not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) { return }
    if ($StateRootExistedBefore) {
        foreach ($child in Get-ChildItem -LiteralPath $script:StateRoot -Force) {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force
        }
        return
    }
    Remove-Item -LiteralPath $script:StateRoot -Recurse -Force
}

function Add-ExistingManagedPlanItems {
    param(
        [Parameter(Mandatory)][object[]]$Plan,
        [Parameter(Mandatory)]$ExistingState,
        [Parameter(Mandatory)]$Payload
    )

    $combined = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Plan) { $combined[$item.relativePath] = $item }
    foreach ($record in $ExistingState.files) {
        if ($combined.ContainsKey($record.relativePath)) { continue }
        $normalizedPath = ([string]$record.relativePath).Replace('\', '/')
        $payloadEntries = @($Payload.manifest.payloadFiles | Where-Object { $_.relativePath -eq $normalizedPath })
        if ($payloadEntries.Count -ne 1) { continue }
        $payloadEntry = $payloadEntries[0]
        $combined[$normalizedPath] = [pscustomobject]@{
            relativePath = $normalizedPath
            sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $normalizedPath
            sha256 = $payloadEntry.sha256
        }
    }
    return @($combined.Values | Sort-Object relativePath)
}

function Install-Runtime {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Payload
    )

    $stateRootExistedBefore = Test-Path -LiteralPath $script:StateRoot -PathType Container
    $existingState = Read-InstallState
    $initialInstall = $null -eq $existingState
    if ($existingState) {
        if (-not ([IO.Path]::GetFullPath($existingState.win64Path)).Equals($GameInstall.win64Path, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Existing runtime state targets a different Steam installation.'
        }
        Assert-ManagedFilesUnchanged -State $existingState -Win64Path $GameInstall.win64Path
    }
    elseif ((Test-Path -LiteralPath $script:StateRoot -PathType Container) -and
        @(Get-ChildItem -LiteralPath $script:StateRoot -Force).Count -gt 0) {
        throw 'Runtime backup directory exists without a valid install state. No files were changed.'
    }

    $loaderMode = Get-LoaderMode -Win64Path $GameInstall.win64Path -Manifest $Payload.manifest
    $plan = @(Get-InstallPlan -Win64Path $GameInstall.win64Path -Payload $Payload -LoaderMode $loaderMode)
    if ($existingState) {
        $plan = @(Add-ExistingManagedPlanItems -Plan $plan -ExistingState $existingState -Payload $Payload)
    }

    $snapshot = $null
    try {
        New-Item -ItemType Directory -Path $script:BaselineRoot -Force | Out-Null
        $baselineByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($existingState) {
            foreach ($record in $existingState.files) { $baselineByPath[$record.relativePath] = $record }
        }
        foreach ($item in $plan) {
            if ($baselineByPath.ContainsKey($item.relativePath)) { continue }
            $destinationPath = Get-SafeChildPath -Root $GameInstall.win64Path -RelativePath $item.relativePath
            if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                $semanticBaseline = Get-SemanticBaseline -RelativePath $item.relativePath -LiteralPath $destinationPath -Manifest $Payload.manifest
                $backupRelativePath = 'baseline/' + $item.relativePath.Replace('\', '/')
                $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath $backupRelativePath
                New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
                Copy-Item -LiteralPath $destinationPath -Destination $backupPath -Force
                $baselineByPath[$item.relativePath] = [pscustomobject]@{
                    relativePath = $item.relativePath
                    originalKind = 'file'
                    originalSha256 = Get-Sha256 -LiteralPath $backupPath
                    backupRelativePath = $backupRelativePath
                    ownership = $semanticBaseline.ownership
                    semanticEntries = @($semanticBaseline.entries)
                }
            }
            else {
                $baselineByPath[$item.relativePath] = [pscustomobject]@{
                    relativePath = $item.relativePath
                    originalKind = 'absent'
                    originalSha256 = $null
                    backupRelativePath = $null
                    ownership = 'whole-file'
                    semanticEntries = @()
                }
            }
        }

        $oldPaths = @($baselineByPath.Keys)
        $newPaths = @($plan.relativePath)
        $snapshot = New-TransactionSnapshot -Win64Path $GameInstall.win64Path -RelativePaths @($oldPaths + $newPaths)
        foreach ($oldPath in $oldPaths) {
            if ($newPaths -notcontains $oldPath) {
                Restore-BaselineRecord -Record $baselineByPath[$oldPath] -Win64Path $GameInstall.win64Path
                [void]$baselineByPath.Remove($oldPath)
            }
        }
        foreach ($item in $plan) {
            $destinationPath = Get-SafeChildPath -Root $GameInstall.win64Path -RelativePath $item.relativePath
            Copy-FileAtomically -SourcePath $item.sourcePath -DestinationPath $destinationPath -ExpectedSha256 $item.sha256
        }

        $stateRecords = @(
            foreach ($item in $plan) {
                $baseline = $baselineByPath[$item.relativePath]
                [ordered]@{
                    relativePath = $item.relativePath.Replace('\', '/')
                    installedSha256 = $item.sha256
                    originalKind = $baseline.originalKind
                    originalSha256 = $baseline.originalSha256
                    backupRelativePath = $baseline.backupRelativePath
                    ownership = if ($baseline.PSObject.Properties['ownership']) { $baseline.ownership } else { 'whole-file' }
                    semanticEntries = if ($baseline.PSObject.Properties['semanticEntries']) { @($baseline.semanticEntries) } else { @() }
                }
            }
        )
        $state = [ordered]@{
            cyberfox1337x = 'function(agefield_runtime_install_state)'
            schemaVersion = 1
            applicationVersion = $ApplicationVersion
            bridgeVersion = $Payload.manifest.bridgeVersion
            installedAtUtc = [DateTime]::UtcNow.ToString('o')
            steamAppId = $script:ExpectedAppId
            steamBuildId = $GameInstall.buildId
            manifestPath = $GameInstall.manifestPath
            installPath = $GameInstall.installPath
            win64Path = $GameInstall.win64Path
            loaderMode = if ($existingState) { $existingState.loaderMode } else { $loaderMode }
            payloadManifestSha256 = Get-Sha256 -LiteralPath (Join-Path ([IO.Path]::GetFullPath($PayloadRoot)) 'payload-manifest.json')
            files = $stateRecords
        }
        Write-InstallState -State $state
    }
    catch {
        if ($snapshot) {
            Restore-TransactionSnapshot -Snapshot $snapshot -Win64Path $GameInstall.win64Path
        }
        if ($initialInstall) {
            Remove-FailedInitialState -StateRootExistedBefore $stateRootExistedBefore
        }
        throw
    }
    finally {
        if ($snapshot -and (Test-Path -LiteralPath $snapshot.root)) {
            Remove-SafeTransaction -TransactionRoot $snapshot.root
        }
    }
    Write-Output "Agefield runtime v$($Payload.manifest.bridgeVersion) installed for official Steam build $($GameInstall.buildId)."
}

function Uninstall-Runtime {
    $state = Read-InstallState
    if (-not $state) {
        Write-Output 'No Agefield runtime install state was found; nothing to restore.'
        return
    }
    $gameInstall = Get-OfficialGameInstall
    if (-not ([IO.Path]::GetFullPath($state.win64Path)).Equals($gameInstall.win64Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime state no longer matches the manifest-derived official Steam installation.'
    }
    Assert-ManagedFilesUnchanged -State $state -Win64Path $gameInstall.win64Path
    $relativePaths = @($state.files.relativePath)
    $snapshot = New-TransactionSnapshot -Win64Path $gameInstall.win64Path -RelativePaths $relativePaths
    try {
        foreach ($record in $state.files) {
            Restore-BaselineRecord -Record $record -Win64Path $gameInstall.win64Path
        }
    }
    catch {
        Restore-TransactionSnapshot -Snapshot $snapshot -Win64Path $gameInstall.win64Path
        throw
    }
    finally {
        Remove-SafeTransaction -TransactionRoot $snapshot.root
    }

    $expectedStateRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Cyberfox1337x\AgefieldHighModMenu\Runtime'))
    if (-not $script:StateRoot.Equals($expectedStateRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected state path: $($script:StateRoot)"
    }
    Remove-Item -LiteralPath $script:StateRoot -Recurse -Force
    Write-Output 'Agefield runtime files were restored to their exact pre-install state.'
}

function Invoke-AgefieldRuntimeInstaller {
    $payload = $null
    try {
        if ($Action -eq 'VerifyPayload') {
            if ([string]::IsNullOrWhiteSpace($PayloadRoot)) { throw 'PayloadRoot is required for VerifyPayload.' }
            $payload = New-ValidatedPayloadStaging -Root $PayloadRoot
            Write-Output "Verified $($payload.manifest.payloadFiles.Count) runtime payload files."
            return
        }

        Assert-GameStopped
        if ($Action -eq 'Uninstall') {
            Uninstall-Runtime
            return
        }

        if ([string]::IsNullOrWhiteSpace($PayloadRoot)) { throw 'PayloadRoot is required for Install.' }
        $gameInstall = Get-OfficialGameInstall -RequireExactBuild
        Assert-EligibleInstall -GameInstall $gameInstall
        $payload = New-ValidatedPayloadStaging -Root $PayloadRoot
        Install-Runtime -GameInstall $gameInstall -Payload $payload
    }
    finally {
        if ($payload -and $payload.root -and (Test-Path -LiteralPath $payload.root)) {
            $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            $resolvedRoot = [IO.Path]::GetFullPath($payload.root)
            if ($resolvedRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-AgefieldRuntimeInstaller
}

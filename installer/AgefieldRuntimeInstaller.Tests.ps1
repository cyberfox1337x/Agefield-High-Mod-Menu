[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'agefield_runtime_installer_tests'

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$helperPath = Join-Path $PSScriptRoot 'AgefieldRuntimeInstaller.ps1'
$runtimeRoot = Join-Path $PSScriptRoot 'runtime'
. $helperPath -Action VerifyPayload -PayloadRoot $runtimeRoot

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Actual -ne $Expected) {
        throw "$Message Expected='$Expected' Actual='$Actual'"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )
    $threw = $false
    try { & $Action }
    catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('agefield-installer-tests-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe test root: $testRoot"
}

$originalProgramData = $env:ProgramData
$originalStateRoot = $script:StateRoot
$originalStatePath = $script:StatePath
$originalBaselineRoot = $script:BaselineRoot
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    Assert-Throws -Action { Get-SafeChildPath -Root $testRoot -RelativePath '..\escape.txt' } -Message 'Traversal was not rejected.'
    Assert-Throws -Action { Get-SafeChildPath -Root $testRoot -RelativePath 'C:\absolute.txt' } -Message 'Rooted path was not rejected.'

    $payload = New-ValidatedPayloadStaging -Root $runtimeRoot
    try {
        Assert-Equal -Actual $payload.manifest.payloadFiles.Count -Expected 25 -Message 'Unexpected payload file count.'
        Assert-Equal -Actual $payload.manifest.steamAppId -Expected '3562580' -Message 'Unexpected Steam App ID.'
    }
    finally {
        $resolvedPayloadRoot = [IO.Path]::GetFullPath($payload.root)
        Assert-True -Condition $resolvedPayloadRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -Message 'Unsafe staged payload cleanup path.'
        Remove-Item -LiteralPath $resolvedPayloadRoot -Recurse -Force
    }

    $manifest = Get-Content -LiteralPath (Join-Path $runtimeRoot 'payload-manifest.json') -Raw | ConvertFrom-Json
    $settingsExisting = Join-Path $testRoot 'existing-settings.ini'
    $settingsMerged = Join-Path $testRoot 'merged-settings.ini'
    @(
        '; preserve this comment',
        '[Hooks]',
        'HookProcessInternal = 0',
        '[ThirdParty]',
        'CustomSetting = keep-me'
    ) | Set-Content -LiteralPath $settingsExisting -Encoding utf8
    New-MergedSettingsFile -ExistingPath $settingsExisting -Manifest $manifest -OutputPath $settingsMerged
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $settingsMerged -Section 'Hooks' -Key 'HookProcessInternal').value -Expected '1' -Message 'Required process hook was not merged.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $settingsMerged -Section 'Hooks' -Key 'HookInitGameState').value -Expected '1' -Message 'Required game-state hook was not merged.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $settingsMerged -Section 'ThirdParty' -Key 'CustomSetting').value -Expected 'keep-me' -Message 'Unrelated setting was not preserved.'

    $modsExisting = Join-Path $testRoot 'existing-mods.txt'
    $modsMerged = Join-Path $testRoot 'merged-mods.txt'
    @(
        '; preserve this registry comment',
        'UnrelatedMod : 1',
        'Keybinds : 0'
    ) | Set-Content -LiteralPath $modsExisting -Encoding utf8
    New-MergedModRegistryFile -ExistingPath $modsExisting -Manifest $manifest -OutputPath $modsMerged
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $modsMerged -Name 'UnrelatedMod').value -Expected '1' -Message 'Unrelated mod entry was not preserved.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $modsMerged -Name 'Keybinds').value -Expected '1' -Message 'Keybinds was not enabled.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $modsMerged -Name 'AgefieldModBridge').value -Expected '1' -Message 'Bridge was not enabled.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $modsMerged -Name 'AgefieldReflectionDiscovery').value -Expected '0' -Message 'Discovery mod was not disabled.'

    $sandboxProgramData = Join-Path $testRoot 'ProgramData'
    $env:ProgramData = $sandboxProgramData
    $script:StateRoot = [IO.Path]::GetFullPath((Join-Path $sandboxProgramData 'Cyberfox1337x\AgefieldHighModMenu\Runtime'))
    $script:StatePath = Join-Path $script:StateRoot 'install-state.json'
    $script:BaselineRoot = Join-Path $script:StateRoot 'baseline'
    $win64Path = Join-Path $testRoot 'Win64'
    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $win64Path 'Mods') -Force | Out-Null

    $liveSettings = Join-Path $win64Path 'UE4SS-settings.ini'
    @(
        '[Hooks]',
        'HookProcessInternal = 1',
        'HookInitGameState = 1',
        '[ThirdParty]',
        'PostInstallEdit = preserve-this'
    ) | Set-Content -LiteralPath $liveSettings -Encoding utf8
    $settingsRecord = [pscustomobject]@{
        relativePath = 'UE4SS-settings.ini'
        installedSha256 = 'INTENTIONALLY-NOT-A-WHOLE-FILE-HASH'
        originalKind = 'file'
        originalSha256 = $null
        backupRelativePath = $null
        ownership = 'semantic-ini'
        semanticEntries = @(
            [pscustomobject]@{ section = 'Hooks'; key = 'HookProcessInternal'; originalPresent = $true; originalValue = '0'; installedValue = '1' },
            [pscustomobject]@{ section = 'Hooks'; key = 'HookInitGameState'; originalPresent = $false; originalValue = $null; installedValue = '1' }
        )
    }
    Assert-ManagedFilesUnchanged -State ([pscustomobject]@{ files = @($settingsRecord) }) -Win64Path $win64Path
    Restore-BaselineRecord -Record $settingsRecord -Win64Path $win64Path
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $liveSettings -Section 'Hooks' -Key 'HookProcessInternal').value -Expected '0' -Message 'Original owned setting was not restored.'
    Assert-True -Condition (-not (Get-IniValueState -LiteralPath $liveSettings -Section 'Hooks' -Key 'HookInitGameState').present) -Message 'New owned setting was not removed.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $liveSettings -Section 'ThirdParty' -Key 'PostInstallEdit').value -Expected 'preserve-this' -Message 'Post-install unrelated setting was not preserved.'

    $liveMods = Join-Path $win64Path 'Mods\mods.txt'
    @(
        'UnrelatedMod : 2',
        'Keybinds : 1',
        'AgefieldModBridge : 1',
        'AgefieldReflectionDiscovery : 0'
    ) | Set-Content -LiteralPath $liveMods -Encoding utf8
    $modsRecord = [pscustomobject]@{
        relativePath = 'Mods/mods.txt'
        installedSha256 = 'INTENTIONALLY-NOT-A-WHOLE-FILE-HASH'
        originalKind = 'file'
        originalSha256 = $null
        backupRelativePath = $null
        ownership = 'semantic-mod-registry'
        semanticEntries = @(
            [pscustomobject]@{ name = 'Keybinds'; originalPresent = $true; originalValue = '0'; installedValue = '1' },
            [pscustomobject]@{ name = 'AgefieldModBridge'; originalPresent = $false; originalValue = $null; installedValue = '1' },
            [pscustomobject]@{ name = 'AgefieldReflectionDiscovery'; originalPresent = $false; originalValue = $null; installedValue = '0' }
        )
    }
    Restore-BaselineRecord -Record $modsRecord -Win64Path $win64Path
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $liveMods -Name 'UnrelatedMod').value -Expected '2' -Message 'Post-install unrelated mod edit was not preserved.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $liveMods -Name 'Keybinds').value -Expected '0' -Message 'Original Keybinds value was not restored.'
    Assert-True -Condition (-not (Get-ModRegistryValueState -LiteralPath $liveMods -Name 'AgefieldModBridge').present) -Message 'New bridge registry entry was not removed.'
    Assert-True -Condition (-not (Get-ModRegistryValueState -LiteralPath $liveMods -Name 'AgefieldReflectionDiscovery').present) -Message 'New discovery registry entry was not removed.'

    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:StateRoot 'partial.tmp') -Value 'partial' -Encoding utf8
    Remove-FailedInitialState -StateRootExistedBefore $false
    Assert-True -Condition (-not (Test-Path -LiteralPath $script:StateRoot)) -Message 'New failed state root was not removed.'

    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:StateRoot 'partial.tmp') -Value 'partial' -Encoding utf8
    Remove-FailedInitialState -StateRootExistedBefore $true
    Assert-True -Condition (Test-Path -LiteralPath $script:StateRoot -PathType Container) -Message 'Preexisting empty state root should remain.'
    Assert-Equal -Actual @(Get-ChildItem -LiteralPath $script:StateRoot -Force).Count -Expected 0 -Message 'Failed transaction content was not removed.'

    $atomicSource = Join-Path $testRoot 'atomic-source.txt'
    $atomicDestination = Join-Path $testRoot 'atomic-target\atomic-destination.txt'
    Set-Content -LiteralPath $atomicSource -Value 'verified-copy' -Encoding utf8
    Copy-FileAtomically -SourcePath $atomicSource -DestinationPath $atomicDestination -ExpectedSha256 (Get-Sha256 -LiteralPath $atomicSource)
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $atomicDestination) -Expected (Get-Sha256 -LiteralPath $atomicSource) -Message 'Atomic copy hash mismatch.'

    foreach ($child in Get-ChildItem -LiteralPath $script:StateRoot -Force) {
        Remove-Item -LiteralPath $child.FullName -Recurse -Force
    }
    $integrationPayload = New-ValidatedPayloadStaging -Root $runtimeRoot
    try {
        $integrationWin64 = Join-Path $testRoot 'integration-game\Project_HighSchool\Binaries\Win64'
        New-Item -ItemType Directory -Path (Join-Path $integrationWin64 'Mods') -Force | Out-Null
        foreach ($loaderFile in @('UE4SS.dll', 'dwmapi.dll')) {
            Copy-Item -LiteralPath (Join-Path $integrationPayload.root $loaderFile) -Destination (Join-Path $integrationWin64 $loaderFile)
        }
        @(
            '[Hooks]',
            'HookProcessInternal = 0',
            '[ThirdParty]',
            'ExistingSetting = before-install'
        ) | Set-Content -LiteralPath (Join-Path $integrationWin64 'UE4SS-settings.ini') -Encoding utf8
        @(
            'UnrelatedMod : 1',
            'Keybinds : 0'
        ) | Set-Content -LiteralPath (Join-Path $integrationWin64 'Mods\mods.txt') -Encoding utf8

        $fakeGameInstall = [pscustomobject]@{
            buildId = '24987926'
            manifestPath = Join-Path $testRoot 'appmanifest_3562580.acf'
            installPath = Join-Path $testRoot 'integration-game'
            win64Path = $integrationWin64
        }
        Install-Runtime -GameInstall $fakeGameInstall -Payload $integrationPayload | Out-Null
        $installedState = Read-InstallState
        Assert-True -Condition ($null -ne $installedState) -Message 'Integration install did not write state.'
        $settingsState = @($installedState.files | Where-Object { $_.relativePath -eq 'UE4SS-settings.ini' })
        $modsState = @($installedState.files | Where-Object { $_.relativePath -eq 'Mods/mods.txt' })
        Assert-Equal -Actual $settingsState.Count -Expected 1 -Message 'Settings state record missing.'
        Assert-Equal -Actual $settingsState[0].ownership -Expected 'semantic-ini' -Message 'Settings were not semantically owned.'
        Assert-Equal -Actual $modsState.Count -Expected 1 -Message 'Mod registry state record missing.'
        Assert-Equal -Actual $modsState[0].ownership -Expected 'semantic-mod-registry' -Message 'Mod registry was not semantically owned.'

        Add-Content -LiteralPath (Join-Path $integrationWin64 'UE4SS-settings.ini') -Value "`n[ThirdPartyAfterInstall]`nKeep = yes" -Encoding utf8
        Add-Content -LiteralPath (Join-Path $integrationWin64 'Mods\mods.txt') -Value 'LaterMod : 1' -Encoding utf8
        Assert-ManagedFilesUnchanged -State $installedState -Win64Path $integrationWin64
        foreach ($record in $installedState.files) {
            try {
                Restore-BaselineRecord -Record $record -Win64Path $integrationWin64
            }
            catch {
                throw "Integration rollback failed for $($record.relativePath): $($_.Exception.Message)"
            }
        }
        Assert-Equal -Actual (Get-IniValueState -LiteralPath (Join-Path $integrationWin64 'UE4SS-settings.ini') -Section 'ThirdPartyAfterInstall' -Key 'Keep').value -Expected 'yes' -Message 'Integration rollback removed an unrelated later setting.'
        Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath (Join-Path $integrationWin64 'Mods\mods.txt') -Name 'LaterMod').value -Expected '1' -Message 'Integration rollback removed an unrelated later mod.'
    }
    finally {
        $resolvedIntegrationPayload = [IO.Path]::GetFullPath($integrationPayload.root)
        Assert-True -Condition $resolvedIntegrationPayload.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -Message 'Unsafe integration payload cleanup path.'
        Remove-Item -LiteralPath $resolvedIntegrationPayload -Recurse -Force
    }

    Write-Output 'Agefield runtime installer tests passed.'
}
finally {
    $env:ProgramData = $originalProgramData
    $script:StateRoot = $originalStateRoot
    $script:StatePath = $originalStatePath
    $script:BaselineRoot = $originalBaselineRoot
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        if (-not $resolvedTestRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe test cleanup path: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

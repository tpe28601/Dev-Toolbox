# The copied bootstrap may still load an older Tool-Updates.ps1.
function Get-HubLegacyStore([string]$Root, [string]$DataRoot) {
    $marker = Join-Path $Root '.dev-toolbox-id'
    if ([IO.File]::Exists($marker)) {
        try {
            $id = [IO.File]::ReadAllText($marker).Trim()
            if ($id -cmatch '^[0-9A-F]{64}$') { return (Join-Path $DataRoot "tool-updates\$id") }
        } catch { }
    }
    return (Get-ToolUpdateStore $Root $DataRoot)
}

function Get-HubUpdateStore([string]$Root, [string]$LegacyStore, [string]$RunningRoot) {
    if (Initialize-HubInstallation $Root $LegacyStore $RunningRoot) {
        $updater = Join-Path $RunningRoot 'ui-kit\Standalone-Update.ps1'
        return (Get-PortableUpdateStore $Root $LegacyStore -StandaloneUpdater $updater)
    }
    return $LegacyStore
}

function Save-HubLaunchFile([string]$Path, [byte[]]$Bytes, [switch]$Replace) {
    $pending = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $backup = "$pending.bak"
    try {
        [IO.File]::WriteAllBytes($pending, $Bytes)
        if ($Replace) { [IO.File]::Replace($pending, $Path, $backup) }
        else {
            try { [IO.File]::Move($pending, $Path) }
            catch [IO.IOException] { if (-not [IO.File]::Exists($Path)) { throw } }
        }
    } finally {
        [IO.File]::Delete($pending)
        [IO.File]::Delete($backup)
    }
}

function Initialize-HubInstallation([string]$Root, [string]$Store, [string]$RunningRoot) {
    $launcher = Join-Path $Root 'Run-Hub.bat'
    if (-not [IO.File]::Exists($launcher)) { return $false }
    try {
        $marker = Join-Path $Root '.dev-toolbox-id'
        $id = Split-Path -Leaf $Store
        if (-not [IO.File]::Exists($marker)) {
            Save-HubLaunchFile $marker ([Text.Encoding]::ASCII.GetBytes("$id`r`n"))
        }
        if ([IO.File]::ReadAllText($marker).Trim() -cne $id) { throw 'The installation ID does not match the active update store.' }

        # Leave the running batch file in place. PowerShell has already parsed its entry script.
        if ($Root -eq $RunningRoot) { return $true }
        $entry = Join-Path $Root 'hub\hub.ps1'
        $legacy = [IO.File]::ReadAllText($entry)
        if ($legacy.Contains('Get-PortableUpdateStore') -or $legacy.Contains('Get-HubLegacyStore $InstallationRoot')) { return $true }
        if (Test-Path -LiteralPath (Join-Path $Root '.git')) { return $false }
        $backup = Join-Path $Root 'hub\hub-legacy.ps1'
        if (-not [IO.File]::Exists($backup)) {
            if ($legacy -notmatch 'Get-ToolUpdateStore \$InstallationRoot') { return $false }
            Save-HubLaunchFile $backup ([IO.File]::ReadAllBytes($entry))
        }
        $bootstrap = Join-Path $RunningRoot 'hub\Hub-Installation.ps1'
        Save-HubLaunchFile $entry ([IO.File]::ReadAllBytes($bootstrap)) -Replace
        return $true
    } catch {
        Write-Verbose "Could not prepare this Hub folder for portable updates: $($_.Exception.Message)"
        return $false
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'Tool-Updates.ps1')
    $base = if ($env:DEVTOOLBOX_DATA) { $env:DEVTOOLBOX_DATA }
        elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'DevToolbox' }
        else { Join-Path $env:TEMP 'DevToolbox' }
    $data = Join-Path $base 'dev-toolbox-hub'
    $version = ([IO.File]::ReadAllText((Join-Path $root 'tool.json')) | ConvertFrom-Json).version
    $store = Join-Path $root 'updates'
    if (-not [IO.Directory]::Exists($store)) { $store = Get-HubLegacyStore $root $data }
    $active = Resolve-ToolUpdateDir $store 'dev-toolbox' $version $root
    if ($active -ne $root) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $active 'hub\hub.ps1') -InstallationRoot $root @args
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'hub\hub-legacy.ps1') @args
    }
    exit $LASTEXITCODE
}

param(
    [ValidateSet('all', 'dev-toolbox', 'agents-cfg-manager', 'build-runner', 'git-ref-manager', 'hlk-viewer', 'key-manager')]
    [string]$Package = 'all',
    [string]$Ref = 'HEAD',
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist\updates')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hub\Tool-Updates.ps1')

# Explicit paths keep local files and unrelated tools out of release assets.
$packages = [ordered]@{
    'dev-toolbox' = @{
        dir = '.'
        files = @('hub/Hub-Web.ps1', 'hub/hub.ps1', 'hub/Tool-Updates.ps1', 'hub/ui',
            'ui-kit/cli-kit.ps1', 'ui-kit/ui-kit.css', 'ui-kit/tb-theme.js', 'ui-kit/tb-icons.js')
    }
    'agents-cfg-manager' = @{
        dir = 'tools/Agents-Cfg-Manager'
        files = @('Agents-Cfg-Manager.ps1', 'Agents-Cfg-Manager-Web.ps1', 'CfgCore.ps1', 'cli-kit.ps1',
            'Run-Agents-Cfg-Manager.bat', 'Run-Agents-Cfg-Manager-Web.bat', 'ui')
    }
    'build-runner' = @{
        dir = 'tools/Build-Runner'
        files = @('Run-CLI.bat', 'Run-Web.bat', 'mcp_server.py', 'standalone_update.py', 'build_runner', 'examples', 'ui')
    }
    'git-ref-manager' = @{
        dir = 'tools/Git-Ref-Manager'
        files = @('Git-Ref-Manager.ps1', 'Git-Ref-Manager-Web.ps1', 'GitRefCore.ps1', 'cli-kit.ps1',
            'Run-Git-Ref-Manager.bat', 'Run-Git-Ref-Manager-Web.bat', 'ui')
    }
    'hlk-viewer' = @{
        dir = 'tools/HLK-Viewer'
        files = @('HLK-Web.ps1', 'Launch-HLK.ps1', 'cli-kit.ps1', 'hlk_viewer.pyw', 'hlk_core.py',
            'hlk_web.py', 'hlk_wtl.py', 'hlk_xlsx.py', 'standalone_update.py', 'ui')
    }
    'key-manager' = @{
        dir = 'tools/Key-Manager'
        files = @('run_windows.bat', 'web_server.py', 'pyproject.toml', 'THIRD_PARTY_NOTICES.md', 'src/key_manager')
    }
}

$output = [IO.Path]::GetFullPath($OutputDir)
[void][IO.Directory]::CreateDirectory($output)
$selected = if ($Package -eq 'all') { $packages.Keys } else { $Package }
foreach ($id in $selected) {
    $config = $packages[$id]
    $repo = Join-Path $PSScriptRoot $config.dir
    $commit = & git -C $repo rev-parse --verify --end-of-options "$Ref^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve $Ref in $repo" }
    $manifestJson = & git -C $repo show "${commit}:tool.json"
    if ($LASTEXITCODE -ne 0) { throw "Missing tool.json in $id at $Ref" }
    $manifest = ($manifestJson -join "`n") | ConvertFrom-Json
    $version = [string]$manifest.version
    if ($manifest.id -cne $id -or -not (ConvertTo-ToolVersion $version)) {
        throw "Invalid package ID or version in $repo at $Ref"
    }
    if ($Ref -match '^v[0-9]' -and $Ref -cne "v$version") { throw "Tag $Ref does not match tool.json ($version)" }

    $files = @('tool.json', 'LICENSE') + $config.files
    if ($id -ne 'dev-toolbox') {
        $ui = if ($manifest.uiKitTarget) { $manifest.uiKitTarget } else { 'ui' }
        $files += @('Standalone-Update.ps1', 'Tool-Updates.ps1', "$ui/tb-standalone-update.js")
        if ($id -eq 'key-manager') { $files += 'src/key_manager/web/standalone_update.py' }
    }
    $zip = Join-Path $output "$id-$version.zip"
    $staging = Join-Path $output ('.verify-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($staging)
    try {
        $candidate = Join-Path $staging 'package.zip'
        & git -C $repo archive --format=zip "--output=$candidate" $commit -- @files
        if ($LASTEXITCODE -ne 0) { throw "Could not archive $id at $Ref" }
        if ((Get-Item -LiteralPath $candidate).Length -gt $script:MaxToolZipBytes) { throw "ZIP exceeds update size limit: $id" }
        $expanded = Join-Path $staging 'contents'
        Expand-ToolRelease $candidate $expanded $id $version
        foreach ($path in $files) {
            if (-not (Test-Path -LiteralPath (Join-Path $expanded $path))) { throw "Missing package path: $id / $path" }
        }
        [IO.File]::Copy($candidate, $zip, $true)
        Write-Host "$zip  (v$version, $($commit.Substring(0, 8)))"
    } finally {
        $resolved = (Resolve-Path -LiteralPath $staging).ProviderPath
        if ($resolved -eq $staging -and (Split-Path -Parent $resolved) -eq $output) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

param(
    [ValidateSet('all', 'dev-toolbox', 'agents-cfg-manager', 'build-runner', 'git-ref-manager', 'hlk-viewer', 'key-manager', 'script-editor')]
    [string]$Package = 'all',
    [string]$Ref = 'HEAD',
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist\updates'),
    [string]$MinHub = '0.4.0',
    [string]$PythonHome,
    [string]$Wheelhouse,
    [switch]$WorkingTree
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hub\Tool-Updates.ps1')
if (-not (ConvertTo-ToolVersion $MinHub)) { throw 'MinHub must be a version in X.Y.Z format' }
if ($WorkingTree -and $Ref -ne 'HEAD') { throw 'WorkingTree cannot be combined with a tag or commit.' }

# Explicit paths keep local files and unrelated tools out of release assets.
$packages = [ordered]@{
    'dev-toolbox' = @{
        dir = '.'
        files = @('Open-Web.bat', 'Run-Hub.bat', 'hub/Hub-Web.ps1', 'hub/hub.ps1', 'hub/Tool-Updates.ps1', 'hub/Tool-Library.ps1', 'hub/ui',
            'ui-kit/cli-kit.ps1', 'ui-kit/ui-kit.css', 'ui-kit/tb-theme.js', 'ui-kit/tb-icons.js')
    }
    'agents-cfg-manager' = @{
        dir = 'tools/Agents-Cfg-Manager'
        files = @('Agents-Cfg-Manager.ps1', 'Agents-Cfg-Manager-Web.ps1', 'CfgCore.ps1', 'cli-kit.ps1',
            'Run-Agents-Cfg-Manager.bat', 'Run-Agents-Cfg-Manager-Web.bat', 'ui')
    }
    'build-runner' = @{
        dir = 'tools/Build-Runner'
        python = $true
        files = @('Run-CLI.bat', 'Run-Web.bat', 'mcp_server.py', 'standalone_update.py', 'build_runner', 'examples', 'ui')
    }
    'git-ref-manager' = @{
        dir = 'tools/Git-Ref-Manager'
        files = @('Git-Ref-Manager.ps1', 'Git-Ref-Manager-Web.ps1', 'GitRefCore.ps1', 'cli-kit.ps1',
            'Run-Git-Ref-Manager.bat', 'Run-Git-Ref-Manager-Web.bat', 'ui')
    }
    'hlk-viewer' = @{
        dir = 'tools/HLK-Viewer'
        python = $true
        files = @('Run-HLK-Viewer.bat', 'HLK-Web.ps1', 'Launch-HLK.ps1', 'cli-kit.ps1', 'hlk_viewer.pyw', 'hlk_core.py',
            'hlk_web.py', 'hlk_wtl.py', 'hlk_xlsx.py', 'standalone_update.py', 'ui')
    }
    'key-manager' = @{
        dir = 'tools/Key-Manager'
        python = $true
        files = @('run_windows.bat', 'web_server.py', 'pyproject.toml', 'THIRD_PARTY_NOTICES.md', 'src/key_manager')
    }
    'script-editor' = @{
        dir = 'tools/Script-Editor'
        python = $true
        files = @('Run-Script-Editor.bat', 'Launch-SE.ps1', 'Script-Web.ps1', 'se_web.py', 'se_core.py',
            'se_pack.py', 'standalone_update.py', 'blocks', 'examples', 'ui')
    }
}

function Add-PythonRuntime([string]$Destination, [string]$Id) {
    if (-not $PythonHome) { throw "Use -PythonHome with a complete Windows CPython 3.11+ installation for $Id." }
    $source = (Resolve-Path -LiteralPath $PythonHome).ProviderPath
    $builder = Join-Path $source 'python.exe'
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw 'PythonHome must contain python.exe.' }
    $runtime = Join-Path $Destination 'runtime\python'
    [void][IO.Directory]::CreateDirectory($runtime)
    foreach ($file in @(Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -in 'python.exe','pythonw.exe','LICENSE.txt' })) {
        Copy-Item -LiteralPath $file.FullName -Destination $runtime
    }
    foreach ($name in 'DLLs','Lib','tcl') {
        $dir = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "PythonHome is missing $name." }
        $target = Join-Path $runtime $name
        [void][IO.Directory]::CreateDirectory($target)
        foreach ($item in @(Get-ChildItem -LiteralPath $dir | Where-Object { $_.Name -notin 'site-packages','__pycache__','test','tests','idlelib','ensurepip' })) {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse
        }
    }
    $python = Join-Path $runtime 'python.exe'
    & $python -I -B -c 'import sys, ssl, tkinter; assert sys.version_info >= (3, 11); tkinter.Tcl()'
    if ($LASTEXITCODE -ne 0) { throw 'Bundled Python failed its runtime check.' }
    if ($Id -eq 'key-manager') {
        if (-not $Wheelhouse) { throw 'Use -Wheelhouse with the Windows wheels for Key Manager and its dependencies.' }
        $wheels = (Resolve-Path -LiteralPath $Wheelhouse).ProviderPath
        $site = Join-Path $runtime 'Lib\site-packages'
        $project = [IO.File]::ReadAllText((Join-Path $Destination 'pyproject.toml'))
        if ($project -notmatch '(?ms)^dependencies\s*=\s*\[(.*?)\]') { throw 'Could not read Key Manager dependencies.' }
        $dependencies = @([regex]::Matches($Matches[1], '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        if (-not $dependencies.Count) { throw 'Key Manager has no declared dependencies.' }
        & $builder -I -m pip install --no-index --only-binary=:all: --no-compile --find-links $wheels --target $site @dependencies
        if ($LASTEXITCODE -ne 0) { throw 'Could not install Key Manager dependencies from the wheelhouse.' }
        & $python -I -B -c 'import webview, bcrypt, cryptography'
        if ($LASTEXITCODE -ne 0) { throw 'Bundled Key Manager dependencies failed their import check.' }
    }
}

$output = [IO.Path]::GetFullPath($OutputDir)
[void][IO.Directory]::CreateDirectory($output)
$selected = if ($Package -eq 'all') { $packages.Keys } else { $Package }
foreach ($id in $selected) {
    $config = $packages[$id]
    $repo = Join-Path $PSScriptRoot $config.dir
    if ($WorkingTree) {
        $commit = 'working-tree'
        $manifestJson = [IO.File]::ReadAllText((Join-Path $repo 'tool.json'))
    } else {
        $commit = & git -C $repo rev-parse --verify --end-of-options "$Ref^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "Cannot resolve $Ref in $repo" }
        $manifestJson = & git -C $repo show "${commit}:tool.json"
        if ($LASTEXITCODE -ne 0) { throw "Missing tool.json in $id at $Ref" }
    }
    $manifest = ($manifestJson -join "`n") | ConvertFrom-Json
    $version = [string]$manifest.version
    if ($manifest.id -cne $id -or -not (ConvertTo-ToolVersion $version)) {
        throw "Invalid package ID or version in $repo at $Ref"
    }
    if ($Ref -match '^v[0-9]' -and $Ref -cne "v$version") { throw "Tag $Ref does not match tool.json ($version)" }

    $files = @('tool.json') + $config.files
    if ($id -ne 'script-editor') { $files += 'LICENSE' }
    if ($id -ne 'dev-toolbox') {
        $ui = if ($manifest.uiKitTarget) { $manifest.uiKitTarget } else { 'ui' }
        $files += @('Standalone-Update.ps1', 'Tool-Updates.ps1', "$ui/tb-standalone-update.js")
        if ($id -eq 'key-manager') { $files += 'src/key_manager/web/standalone_update.py' }
    }
    $zipName = "$id-$version.zip"
    $zip = Join-Path $output $zipName
    $metadataPath = Join-Path $output "$id-$version.update.json"
    $staging = Join-Path $output ('.verify-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($staging)
    try {
        $candidate = Join-Path $staging 'package.zip'
        if ($WorkingTree) {
            # Local preview only. Production packages come from exact Git refs.
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $preview = Join-Path $staging 'preview'
            [void][IO.Directory]::CreateDirectory($preview)
            foreach ($relative in ($files | Select-Object -Unique)) {
                $source = Join-Path $repo $relative
                $target = Join-Path $preview $relative
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
                if ((Get-Item -LiteralPath $source).PSIsContainer) {
                    [void][IO.Directory]::CreateDirectory($target)
                    & robocopy.exe $source $target /E /XJ /XD __pycache__ .pytest_cache .git .venv /XF '*.pyc' /NFL /NDL /NJH /NJS /NP | Out-Null
                    if ($LASTEXITCODE -ge 8) { throw "Could not copy $relative" }
                    $global:LASTEXITCODE = 0
                } else { Copy-Item -LiteralPath $source -Destination $target }
            }
            [IO.Compression.ZipFile]::CreateFromDirectory($preview, $candidate, [IO.Compression.CompressionLevel]::Optimal, $false)
        } else {
            & git -C $repo archive --format=zip "--output=$candidate" $commit -- @files
            if ($LASTEXITCODE -ne 0) { throw "Could not archive $id at $Ref" }
        }
        if ((Get-Item -LiteralPath $candidate).Length -gt $script:MaxToolZipBytes) { throw "ZIP exceeds update size limit: $id" }
        $expanded = Join-Path $staging 'contents'
        Expand-ToolRelease $candidate $expanded $id $version
        foreach ($path in $files) {
            if (-not (Test-Path -LiteralPath (Join-Path $expanded $path))) { throw "Missing package path: $id / $path" }
        }
        if ($config.python) {
            Add-PythonRuntime $expanded $id
            [IO.File]::Delete($candidate)
            [IO.Compression.ZipFile]::CreateFromDirectory($expanded, $candidate, [IO.Compression.CompressionLevel]::Optimal, $false)
            if ((Get-Item -LiteralPath $candidate).Length -gt $script:MaxToolZipBytes) { throw "ZIP exceeds update size limit: $id" }
            Expand-ToolRelease $candidate (Join-Path $staging 'verified') $id $version
        }
        $metadata = [ordered]@{ version = $version; file = $zipName }
        if ($id -ne 'dev-toolbox') { $metadata['minHub'] = $MinHub }
        if ($config.python) { $metadata['portable'] = $true }
        [IO.File]::Copy($candidate, $zip, $true)
        [IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json) + "`n")
        $sourceLabel = if ($WorkingTree) { 'working tree preview' } else { $commit.Substring(0, 8) }
        Write-Host "$zip  (v$version, $sourceLabel)"
        Write-Host $metadataPath
    } finally {
        $resolved = (Resolve-Path -LiteralPath $staging).ProviderPath
        if ($resolved -eq $staging -and (Split-Path -Parent $resolved) -eq $output) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

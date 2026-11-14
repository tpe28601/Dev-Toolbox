# hub.ps1 — Dev-Toolbox CLI（骨架版）
# 用法：
#   hub.ps1                 互動選單
#   hub.ps1 list            列出工具與版本
#   hub.ps1 doctor          檢查環境、submodule、ui-kit 版本
#   hub.ps1 web             啟動 Web 主控台（Hub-Web.ps1）並開瀏覽器
#   hub.ps1 run <id> ...    把其餘參數原封不動交給該工具的 CLI，回傳它的 exit code
#   hub.ps1 -Version

param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$ToolId,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest,
    [switch]$Version,
    [switch]$NoColor,
    [string]$InstallationRoot
)

$ErrorActionPreference = 'Stop'
$HubRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $HubRoot 'ui-kit\cli-kit.ps1')
. (Join-Path $PSScriptRoot 'Tool-Updates.ps1')
if ($NoColor) { Set-TbNoColor $true }

function Read-JsonFile([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}

function Test-VenvUsable([string]$VenvDir) {
    # .venv 可能是從別台電腦複製過來的：pyvenv.cfg 的 home 指向不存在的 Python 時不能用
    $cfg = Join-Path $VenvDir 'pyvenv.cfg'
    if (-not (Test-Path -LiteralPath (Join-Path $VenvDir 'Scripts\python.exe'))) { return $false }
    if (-not (Test-Path -LiteralPath $cfg)) { return $false }
    $hit = Select-String -LiteralPath $cfg -Pattern '^\s*home\s*=\s*(.+?)\s*$' | Select-Object -First 1
    if (-not $hit) { return $true }
    return (Test-Path -LiteralPath (Join-Path $hit.Matches[0].Groups[1].Value 'python.exe'))
}

function Get-HubDataRoot {
    $base = Join-Path $env:TEMP 'DevToolbox\dev-toolbox-hub'
    if ($env:LOCALAPPDATA) { $base = Join-Path $env:LOCALAPPDATA 'DevToolbox\dev-toolbox-hub' }
    if ($env:DEVTOOLBOX_DATA) { $base = Join-Path $env:DEVTOOLBOX_DATA 'dev-toolbox-hub' }
    return $base
}

if (-not $InstallationRoot) { $InstallationRoot = $HubRoot }
$ToolUpdateStore = Get-ToolUpdateStore $InstallationRoot (Get-HubDataRoot)
$hubVersion = (Read-JsonFile (Join-Path $HubRoot 'tool.json')).version
$activeHubDir = Resolve-ToolUpdateDir $ToolUpdateStore 'dev-toolbox' $hubVersion $HubRoot
if ($activeHubDir -ne $HubRoot) {
    $PSBoundParameters['InstallationRoot'] = $InstallationRoot
    & (Join-Path $activeHubDir 'hub\hub.ps1') @PSBoundParameters
    exit $LASTEXITCODE
}

function Get-HubSettingsPython {
    $f = Join-Path (Get-HubDataRoot) 'settings.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $p = [string](Read-JsonFile $f).pythonPath
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
    } catch { }
    return $null
}

function Resolve-HubPython([string]$ToolDir) {
    $bundled = Join-Path $ToolDir 'runtime\python\python.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    $sp = Get-HubSettingsPython
    if ($sp) { return $sp }
    if ($env:DEVTOOLBOX_PYTHON -and (Test-Path -LiteralPath $env:DEVTOOLBOX_PYTHON)) { return $env:DEVTOOLBOX_PYTHON }
    if (Test-VenvUsable (Join-Path $ToolDir '.venv')) { return (Join-Path $ToolDir '.venv\Scripts\python.exe') }
    $py = Get-Command 'py' -ErrorAction SilentlyContinue
    if ($py) { return $py.Source }
    foreach ($c in @(Get-Command 'python' -ErrorAction SilentlyContinue)) {
        if ($c.Source -notmatch 'WindowsApps') { return $c.Source }
    }
    return $null
}

function Get-UiKitVersion([string]$CssPath) {
    if (-not (Test-Path -LiteralPath $CssPath -PathType Leaf)) { return $null }
    $first = Get-Content -LiteralPath $CssPath -TotalCount 1 -Encoding UTF8
    if ($first -match 'ui-kit (\d+\.\d+\.\d+)') { return $matches[1] }
    return $null
}

. (Join-Path $PSScriptRoot 'Tool-Library.ps1')
function Get-Tools { Get-HubLibraryTools }

function Invoke-List {
    $tools = @(Get-Tools)
    if ($tools.Count -eq 0) { Write-TbWarn '尚未安裝工具。請開啟 Hub 的「管理工具」。'; return 0 }
    foreach ($t in $tools) {
        if ($t.Installed) { Write-TbOk ("{0,-24} {1,-10} {2}" -f $t.Id, $t.Version, $t.Name) }
        else { Write-TbWarn ("{0,-24} {1}" -f $t.Id, $t.Error) }
    }
    return 0
}

function Invoke-Doctor {
    $problems = 0
    Write-TbSection '環境'
    Write-TbInfo ("PowerShell {0}" -f $PSVersionTable.PSVersion)
    foreach ($exe in @('git')) {
        $c = Get-Command $exe -ErrorAction SilentlyContinue
        if ($c) { Write-TbOk "$exe：$($c.Source)" } else { Write-TbErr "找不到 $exe"; $problems++ }
    }

    Write-TbSection 'Submodule'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $st = & git -C $InstallationRoot submodule status 2>&1
        if ($LASTEXITCODE -ne 0) { Write-TbWarn '無法讀取 submodule 狀態（這個資料夾可能還不是 git repo）' }
        foreach ($line in @($st)) {
            $s = [string]$line
            if ($s -match '^-') { Write-TbWarn "未初始化：$($s.Substring(1).Trim())"; $problems++ }
            elseif ($s -match '^\+') { Write-TbWarn "指向的 commit 與 Hub 記錄不同：$($s.Substring(1).Trim())" }
            elseif ($s -match '\(([^)]+)\)\s*$' -and $matches[1] -notmatch '^v\d') { Write-TbWarn "不在 tag 上：$($s.Trim())" }
            elseif ($s.Trim()) { Write-TbOk $s.Trim() }
        }
    }

    Write-TbSection '工具'
    $hubKit = Get-UiKitVersion (Join-Path $HubRoot 'ui-kit\ui-kit.css')
    foreach ($t in @(Get-Tools)) {
        if (-not $t.Installed) { Write-TbWarn "$($t.Id)：$($t.Error)"; $problems++; continue }
        $m = $t.Manifest
        if ($m.specVersion -ne 1) { Write-TbErr "$($t.Id)：不支援的 specVersion $($m.specVersion)"; $problems++; continue }
        foreach ($req in @($m.requires)) {
            if ($req -and -not (Get-Command $req -ErrorAction SilentlyContinue)) { Write-TbErr "$($t.Id)：需要 $req，但找不到"; $problems++ }
        }
        $uiRel = if ($m.uiKitTarget) { [string]$m.uiKitTarget -replace '/', '\' } else { 'ui' }
        $kit = Get-UiKitVersion (Join-Path $t.Dir (Join-Path $uiRel 'ui-kit.css'))
        if (-not $kit) { Write-TbWarn "$($t.Id)：尚未導入 ui-kit" }
        elseif ($kit -ne $hubKit) { Write-TbWarn "$($t.Id)：ui-kit $kit，Hub 為 $hubKit，請執行 ui-kit\Sync-UiKit.ps1" }
        else { Write-TbOk "$($t.Id) $($t.Version)（ui-kit $kit）" }
    }

    if ($problems -gt 0) { Write-TbWarn "共 $problems 個問題"; return $script:TbExit.Env }
    Write-TbOk '全部正常'
    return 0
}

function Invoke-Run([string]$Id, [string[]]$ToolArgs) {
    # 注意：這個函式不可被指派（$x = Invoke-Run ...），否則工具的輸出會被攔截、互動提示也會失效。
    # 結果放在 $script:RunCode。
    $script:RunCode = 0
    $t = @(Get-Tools | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if (-not $t) { Write-TbErr "找不到工具：$Id"; $script:RunCode = $script:TbExit.BadArgs; return }
    if (-not $t.Installed) { Write-TbErr "$Id：$($t.Error)"; $script:RunCode = $script:TbExit.Env; return }
    if ($t.Source -eq 'link') { Open-ToolLink $t.Url; return }
    if (-not $t.Manifest.cli) { Write-TbErr "$Id 沒有 CLI 入口。"; $script:RunCode = $script:TbExit.BadArgs; return }
    $entry = Join-Path $t.Dir ([string]$t.Manifest.cli.entry)
    switch ([string]$t.Manifest.runtime.kind) {
        'powershell' {
            $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell.exe' }
            & $exe -NoProfile -ExecutionPolicy Bypass -File $entry @ToolArgs
        }
        'python' {
            $py = Resolve-HubPython $t.Dir
            if (-not $py) { Write-TbErr '找不到 Python（建 .venv、裝 py 啟動器或設 DEVTOOLBOX_PYTHON）'; $script:RunCode = $script:TbExit.Env; return }
            & $py $entry @ToolArgs
            $script:RunCode = $LASTEXITCODE
            return
        }
        'exe'    { & $entry @ToolArgs }
        default  { Write-TbErr "不支援的 runtime：$($t.Manifest.runtime.kind)"; $script:RunCode = $script:TbExit.BadArgs; return }
    }
    $script:RunCode = $LASTEXITCODE
}

if ($Version) {
    Write-Output (Read-JsonFile (Join-Path $HubRoot 'tool.json')).version
    exit 0
}

$code = 0
switch ($Command) {
    'list'   { $code = Invoke-List }
    'doctor' { $code = Invoke-Doctor }
    'web'    {
        # Web 主控台：直接前景執行，Ctrl+C 停止（工具服務會因 -ParentPid 跟著退）
        & (Join-Path $PSScriptRoot 'Hub-Web.ps1') -OpenBrowser -InstallationRoot $InstallationRoot
        $code = $LASTEXITCODE
    }
    'run'    {
        if (-not $ToolId) { Write-TbErr '用法：hub run <id> [參數...]'; $code = $script:TbExit.BadArgs }
        else { Invoke-Run $ToolId @($Rest); $code = $script:RunCode }
    }
    { -not $_ } {
        $hub = Read-JsonFile (Join-Path $HubRoot 'tool.json')
        Write-TbTitle 'Dev-Toolbox' ("版本 " + $hub.version)
        $tools = @(Get-Tools | Where-Object { $_.Installed })
        $items = @()
        for ($i = 0; $i -lt $tools.Count; $i++) { $items += @{ Key = [string]($i + 1); Label = "$($tools[$i].Name)（$($tools[$i].Version)）" } }
        $items += @{ Key = 'd'; Label = '環境檢查（doctor）' }
        $items += @{ Key = 'w'; Label = '開啟 Web 主控台（停止請按 Ctrl+C）' }
        $items += @{ Key = '0'; Label = '離開' }
        $choice = Show-TbMenu '選擇工具' $items
        if ($choice -eq 'd') { $code = Invoke-Doctor }
        elseif ($choice -eq 'w') { & (Join-Path $PSScriptRoot 'Hub-Web.ps1') -OpenBrowser -InstallationRoot $InstallationRoot }
        elseif ($choice -and $choice -ne '0') { Invoke-Run $tools[[int]$choice - 1].Id @(); $code = $script:RunCode }
    }
    default  { Write-TbErr "未知的指令：$Command（可用：list、doctor、web、run）"; $code = $script:TbExit.BadArgs }
}
exit $code

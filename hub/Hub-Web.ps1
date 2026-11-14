# Dev-Toolbox Hub - 本機 Web 主控台（工具切換入口）
# 純 PowerShell（HttpListener／http.sys），不需要管理者權限。只綁 127.0.0.1。
# 職責：列出 tools\ 下符合 TOOL-SPEC 的工具、啟動／停止它們的 Web 服務、
#       前端用 iframe 在同一視窗切換工具畫面。
# 用法： .\Hub-Web.ps1 [-Port 8700] [-OpenBrowser] [-Force] [-DataDir <路徑>]
# 啟動成功時 stdout 印出一行：READY http://127.0.0.1:<port>（TOOL-SPEC 第 5 節）
# 沒指定 -Port 時：8700 起往上找 20 個，都不行就請系統配一個空的 port。
# 單實例：啟動前先掃 port 範圍，發現既有 Hub 就直接開瀏覽器到舊實例並結束（exit 0）；
#         加 -Force 可跳過偵測、強制再開一個實例（除錯用）。

param(
    [int]$Port = 8700,
    [switch]$OpenBrowser,
    [switch]$Force,
    [string]$DataDir,
    [string]$InstallationRoot
)
$script:PortExplicit = $PSBoundParameters.ContainsKey('Port')

$ErrorActionPreference = 'Stop'
$script:HubRoot = Split-Path $PSScriptRoot -Parent
$script:UiDir = Join-Path $PSScriptRoot 'ui'
$script:KitDir = Join-Path $HubRoot 'ui-kit'
$script:StartedAt = Get-Date

function Read-JsonFile([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}

$script:HubManifest = Read-JsonFile (Join-Path $HubRoot 'tool.json')
. (Join-Path $PSScriptRoot 'Tool-Updates.ps1')

# ---------------- 資料夾（TOOL-SPEC 第 6 節：--data-dir > DEVTOOLBOX_DATA > LOCALAPPDATA） ----------------
function Resolve-HubDataDir([string]$Override) {
    if ($Override) { return [System.IO.Path]::GetFullPath($Override) }
    if ($env:DEVTOOLBOX_DATA) { return (Join-Path $env:DEVTOOLBOX_DATA 'dev-toolbox-hub') }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'DevToolbox\dev-toolbox-hub') }
    return (Join-Path $env:TEMP 'DevToolbox\dev-toolbox-hub')
}
$script:DataDir = Resolve-HubDataDir $DataDir
if (-not $InstallationRoot) { $InstallationRoot = $HubRoot }
$script:ToolUpdateStore = Get-ToolUpdateStore $InstallationRoot (Resolve-HubDataDir '')
$script:ToolUpdateOffers = @{}
$activeHubDir = Resolve-ToolUpdateDir $ToolUpdateStore 'dev-toolbox' $script:HubManifest.version $HubRoot
if ($activeHubDir -ne $HubRoot) {
    $launch = @{ InstallationRoot = $InstallationRoot; DataDir = $script:DataDir; OpenBrowser = $OpenBrowser; Force = $Force }
    if ($script:PortExplicit) { $launch.Port = $Port }
    & (Join-Path $activeHubDir 'hub\Hub-Web.ps1') @launch
    return
}
foreach ($d in @($script:DataDir, (Join-Path $script:DataDir 'jobs'))) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# ---------------- 工具清單（讀 tools\*\tool.json，與 hub.ps1 同邏輯） ----------------
. (Join-Path $PSScriptRoot 'Tool-Library.ps1')
function Get-Tools { Get-HubLibraryTools -IncludeCatalog }

# ---------------- 執行中的工具服務 ----------------
# $script:ToolProcs[id] = @{ Proc; Port; Url; OutFile; ErrFile; StartedAt }
$script:ToolProcs = @{}

function Test-PortFree([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(250, $false)
        if ($ok -and $c.Connected) { $c.Close(); return $false }
        $c.Close(); return $true
    } catch { return $true }
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

# ---------------- Hub 設定（DataDir\settings.json） ----------------
$script:SettingsFile = Join-Path $script:DataDir 'settings.json'

function Get-HubSettings {
    $o = [ordered]@{ pythonPath = '' }
    if (Test-Path -LiteralPath $script:SettingsFile) {
        try {
            $j = Read-JsonFile $script:SettingsFile
            if ($j.pythonPath) { $o.pythonPath = [string]$j.pythonPath }
        } catch { }
    }
    return [pscustomobject]$o
}

function Save-HubSettings($obj) {
    $json = ConvertTo-Json $obj -Depth 5
    $tmp = "$($script:SettingsFile).tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $script:SettingsFile -Force
}

function Get-PythonVersion([string]$Exe) {
    # 執行 python 取版本；3 秒逾時。回傳 @{ ok; version; message }
    if (-not $Exe) { return @{ ok = $false; version = ''; message = '沒有路徑' } }
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return @{ ok = $false; version = ''; message = '檔案不存在' } }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = '-c "import sys;print(\"%d.%d.%d\" % sys.version_info[:3])"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(3000)) { try { $p.Kill() } catch { }; return @{ ok = $false; version = ''; message = '執行逾時' } }
        $v = ([string]$outTask.Result).Trim()
        if ($p.ExitCode -ne 0 -or $v -notmatch '^(\d+)\.(\d+)\.(\d+)$') { return @{ ok = $false; version = ''; message = "無法執行（exit $($p.ExitCode)）" } }
        $major = [int]$matches[1]; $minor = [int]$matches[2]
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 11)) { return @{ ok = $false; version = $v; message = "版本 $v 太舊，需要 3.11 以上" } }
        return @{ ok = $true; version = $v; message = '' }
    } catch {
        return @{ ok = $false; version = ''; message = "無法執行：$($_.Exception.Message)" }
    }
}

function Get-PythonCandidates([string]$ToolDir) {
    # 依優先順序列出所有來源（含找不到的），給設定頁顯示與 Resolve-PythonExe 共用
    $list = @()
    if ($ToolDir) {
        $bundled = Join-Path $ToolDir 'runtime\python\python.exe'
        $list += [pscustomobject]@{ source = 'bundled'; label = '工具附帶的 Python'; path = $bundled; found = (Test-Path -LiteralPath $bundled -PathType Leaf) }
    }
    $sp = [string](Get-HubSettings).pythonPath
    $list += [pscustomobject]@{ source = 'settings'; label = 'Hub 設定指定的路徑'; path = $sp; found = [bool]($sp -and (Test-Path -LiteralPath $sp -PathType Leaf)) }
    $ev = [string]$env:DEVTOOLBOX_PYTHON
    $list += [pscustomobject]@{ source = 'env'; label = '環境變數 DEVTOOLBOX_PYTHON'; path = $ev; found = [bool]($ev -and (Test-Path -LiteralPath $ev -PathType Leaf)) }
    if ($ToolDir) {
        $vd = Join-Path $ToolDir '.venv'
        $list += [pscustomobject]@{ source = 'venv'; label = '工具的 .venv'; path = (Join-Path $vd 'Scripts\python.exe'); found = (Test-VenvUsable $vd) }
    }
    $py = Get-Command 'py' -ErrorAction SilentlyContinue
    $list += [pscustomobject]@{ source = 'py'; label = 'py 啟動器'; path = $(if ($py) { $py.Source } else { '' }); found = [bool]$py }
    $pp = ''
    foreach ($c in @(Get-Command 'python' -ErrorAction SilentlyContinue)) {
        if ($c.Source -notmatch 'WindowsApps') { $pp = $c.Source; break }
    }
    $list += [pscustomobject]@{ source = 'path'; label = 'PATH 上的 python'; path = $pp; found = [bool]$pp }
    return $list
}

function Resolve-PythonExe([string]$ToolDir) {
    foreach ($c in @(Get-PythonCandidates $ToolDir)) {
        if ($c.found) { return $c.path }
    }
    return $null
}

function Invoke-ToolHttp([string]$Url, [string]$Method, [int]$TimeoutMs) {
    # 對工具打 HTTP（health／shutdown）。失敗回 $null，不擲例外。
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = $Method
        $req.Timeout = $TimeoutMs
        $req.ReadWriteTimeout = $TimeoutMs
        if ($Method -eq 'POST') {
            $req.ContentType = 'application/json'
            $req.Headers.Add('X-Toolbox-Request', '1')
            $body = [System.Text.Encoding]::UTF8.GetBytes('{}')
            $req.ContentLength = $body.Length
            $s = $req.GetRequestStream(); $s.Write($body, 0, $body.Length); $s.Close()
        }
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $resp.Close()
        return ($text | ConvertFrom-Json)
    } catch { return $null }
}

function Get-ToolStatus($t) {
    # 執行中資訊：優先看 Hub 自己spawn 的行程，再探測預設 port 上是否有現成服務。
    if ($script:ToolProcs.ContainsKey($t.Id)) {
        $e = $script:ToolProcs[$t.Id]
        $alive = $true
        try { $e.Proc.Refresh(); $alive = -not $e.Proc.HasExited } catch { $alive = $false }
        if (-not $alive) { $script:ToolProcs.Remove($t.Id); return $null }
        return [pscustomobject]@{ port = $e.Port; url = $e.Url; pid = [int]$e.Proc.Id; managed = $true }
    }
    if ($t.Installed -and $t.Manifest.web) {
        $dp = [int]$t.Manifest.web.defaultPort
        if (-not (Test-PortFree $dp)) {
            $h = Invoke-ToolHttp "http://127.0.0.1:$dp$($t.Manifest.web.health)" 'GET' 400
            if ($h -and $h.ok -and [string]$h.id -eq $t.Id) {
                return [pscustomobject]@{ port = $dp; url = "http://127.0.0.1:$dp"; pid = [int]$h.pid; managed = $false }
            }
        }
    }
    return $null
}

function Start-ToolService([string]$Id) {
    $t = @(Get-Tools | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if (-not $t) { throw @{ code = 'TOOL_NOT_FOUND'; message = "找不到工具：$Id" } }
    if (-not $t.Installed) { throw @{ code = 'ENV_MISSING'; message = "$Id：$($t.Error)" } }
    if ($t.Source -eq 'link') { Open-ToolLink $t.Url; return @{ opened = $true } }
    if (-not $t.Manifest.web -and $t.Manifest.cli) {
        if ($t.Id -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { throw '工具 ID 不符合工具規格。' }
        $cli = Join-Path $PSScriptRoot 'hub.ps1'
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', ('"{0}"' -f $cli),
            '-InstallationRoot', ('"{0}"' -f $InstallationRoot), 'run', $t.Id)
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WorkingDirectory $t.Dir
        return @{ opened = $true }
    }
    if ($script:ToolProcs.ContainsKey($Id)) { throw @{ code = 'ALREADY_RUNNING'; message = "$Id 已在執行（port $($script:ToolProcs[$Id].Port)）" } }
    $st = Get-ToolStatus $t
    if ($st) { throw @{ code = 'ALREADY_RUNNING'; message = "$Id 已在 127.0.0.1:$($st.port) 運行（非 Hub 啟動）" } }
    if (-not $t.Manifest.web) { throw @{ code = 'BAD_ARGS'; message = "$Id 沒有 Web 模式，請用 CLI：hub run $Id" } }

    $entryRel = [string]$t.Manifest.web.entry
    $entry = Join-Path $t.Dir $entryRel
    if (-not (Test-Path -LiteralPath $entry)) { throw @{ code = 'ENV_MISSING'; message = "找不到 Web 入口：$entryRel" } }

    # port 由工具自己找（預設 port 往上 +20，再不行請系統配），實際 port 從 READY 行讀回來。
    # 不能由 Hub 先探測再指定：被 Windows 保留的 port 沒有人在聽，探測會誤判成「空的」。
    $hubOrigin = "http://127.0.0.1:$Port"

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile = Join-Path $script:DataDir "jobs\$Id-$stamp.out"
    $errFile = Join-Path $script:DataDir "jobs\$Id-$stamp.err"

    $kind = [string]$t.Manifest.runtime.kind
    switch ($kind) {
        'powershell' {
            $exe = 'powershell.exe'
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $entry), '-ParentPid', $PID, '-HubOrigin', $hubOrigin)
        }
        'python' {
            $exe = Resolve-PythonExe $t.Dir
            if (-not $exe) { throw @{ code = 'ENV_MISSING'; message = '找不到 Python（建議在工具資料夾建立 .venv）' } }
            # Start-Process joins ArgumentList into one command line.
            $argList = @(('"{0}"' -f $entry), '--parent-pid', $PID, '--hub-origin', $hubOrigin)
        }
        'exe' {
            $exe = $entry
            $argList = @('--parent-pid', $PID, '--hub-origin', $hubOrigin)
        }
        default { throw @{ code = 'ENV_MISSING'; message = "不支援的 runtime：$kind" } }
    }

    $toolProc = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $t.Dir `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $toolProc) { throw @{ code = 'START_FAILED'; message = "無法啟動 $Id" } }

    # 等 READY 行（寫入 logfile）；工具啟動通常 <5 秒，給 30 秒上限
    $readyPort = 0
    $failMsg = $null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $outFile) {
            # 子行程的 stdout 檔句柄帶 Write 存取，必須用 FileShare.ReadWrite 開，否則 ReadAllText 必然 SharingViolation
            $txt = ''
            try {
                $fs = New-Object System.IO.FileStream($outFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $txt = $sr.ReadToEnd()
                $sr.Dispose(); $fs.Dispose()
            } catch { $txt = '' }
            if ($txt -match 'READY http://127\.0\.0\.1:(\d+)') { $readyPort = [int]$matches[1]; break }
        }
        $toolProc.Refresh()
        if ($toolProc.HasExited) {
            $err = ''
            if (Test-Path -LiteralPath $errFile) { try { $err = ' ' + ((Get-Content -LiteralPath $errFile -Tail 5) -join ' / ') } catch {} }
            $failMsg = "$Id 啟動即結束（exit $($toolProc.ExitCode)）$err"
            break
        }
        Start-Sleep -Milliseconds 300
    }
    if ($failMsg) { throw @{ code = 'START_FAILED'; message = $failMsg } }
    if ($readyPort -eq 0) {
        try { & taskkill.exe /T /F /PID $toolProc.Id 2>&1 | Out-Null } catch {}
        throw @{ code = 'START_TIMEOUT'; message = "$Id 30 秒內沒有出現 READY 行" }
    }

    $url = "http://127.0.0.1:$readyPort"
    $script:ToolProcs[$Id] = @{ Proc = $toolProc; Port = $readyPort; Url = $url; OutFile = $outFile; ErrFile = $errFile; StartedAt = (Get-Date) }
    return [pscustomobject]@{ port = $readyPort; url = $url; pid = [int]$toolProc.Id; managed = $true }
}

function Stop-ToolService([string]$Id) {
    if (-not $script:ToolProcs.ContainsKey($Id)) { throw @{ code = 'NOT_RUNNING'; message = "$Id 不是由 Hub 啟動或已停止" } }
    $e = $script:ToolProcs[$Id]
    # 優先請服務自己乾淨關機（TOOL-SPEC POST /api/shutdown），5 秒後還在就殺整棵樹
    $done = $false
    $r = Invoke-ToolHttp "$($e.Url)/api/shutdown" 'POST' 1500
    if ($r -and $r.ok) { $done = $true }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        try { $e.Proc.Refresh(); if ($e.Proc.HasExited) { $done = $true; break } } catch { $done = $true; break }
        Start-Sleep -Milliseconds 300
    }
    if (-not $done) {
        & taskkill.exe /T /F /PID $e.Proc.Id 2>&1 | Out-Null
    }
    $script:ToolProcs.Remove($Id)
    return [pscustomobject]@{ stopped = $true; clean = $done }
}

# ---------------- 卡片副標與工作歷史（總覽頁用） ----------------
$script:RuntimeDetailCache = @{}

function Get-RuntimeDetail($t) {
    # 未啟動卡片的副標：「Python 3.12.7（自動偵測）」／「Windows PowerShell 5.1」。
    # /api/tools 每幾秒會被輪詢，候選掃描與直譯器版本都進快取
    # （venv 事後新增／移除要重啟 Hub 才更新，可接受）。
    $kind = [string]$t.Manifest.runtime.kind
    if ($kind -eq 'powershell') { return "Windows PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" }
    if ($kind -ne 'python') { return $kind }
    $key = "cand|$($t.Dir)|$((Get-HubSettings).pythonPath)"
    if (-not $script:RuntimeDetailCache.ContainsKey($key)) {
        $script:RuntimeDetailCache[$key] = @(Get-PythonCandidates $t.Dir | Where-Object { $_.found }) | Select-Object -First 1
    }
    $first = $script:RuntimeDetailCache[$key]
    if (-not $first) { return 'Python（未找到直譯器）' }
    $vkey = "ver|$($first.source)|$($first.path)"
    if (-not $script:RuntimeDetailCache.ContainsKey($vkey)) {
        $v = Get-PythonVersion $first.path
        $script:RuntimeDetailCache[$vkey] = if ($v.ok) { $v.version } else { '' }
    }
    $ver = [string]$script:RuntimeDetailCache[$vkey]
    $tag = switch ($first.source) {
        'settings' { 'Hub 設定' }
        'venv'     { '工具 .venv' }
        'bundled'  { '工具附帶' }
        'env'      { '環境變數' }
        default    { '自動偵測' }
    }
    if ($ver) { return "Python $ver（$tag）" }
    return "Python（$tag）"
}

function Read-JsonlTail([string]$Path, [int]$Count, [switch]$Head) {
    # 讀 jsonl 的最新 N 筆（預設檔尾＝最新；OCM 的歷史檔最新在前，用 -Head）。
    # 用 FileShare.ReadWrite 開啟，工具正在附掛寫入時也能讀；單行解析壞了略過。
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lines = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $bytes = New-Object byte[] $fs.Length
            if ($bytes.Length -gt 0) { [void]$fs.Read($bytes, 0, $bytes.Length) }
        } finally { $fs.Dispose() }
        $lines = [System.Text.Encoding]::UTF8.GetString($bytes) -split "`n"
        if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }   # 防 BOM 殘留
    } catch { return @() }
    $out = @()
    if ($Head) { $idx = 0; $dir = 1; $stop = $lines.Count }
    else { $idx = $lines.Count - 1; $dir = -1; $stop = -1 }
    while ($out.Count -lt $Count -and $idx -ne $stop) {
        $ln = (([string]$lines[$idx]) -replace "`r", '').Trim()
        if ($ln) { try { $out += ($ln | ConvertFrom-Json) } catch { } }
        $idx += $dir
    }
    return $out
}

function ConvertTo-TimeMs([string]$s) {
    # ISO8601（含／不含 offset）或 'yyyy-MM-dd HH:mm:ss' → epoch ms；失敗回 0
    if (-not $s) { return 0 }
    try { return ([System.DateTimeOffset]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)).ToUnixTimeMilliseconds() } catch { return 0 }
}

function Cut-Text([string]$s, [int]$Max) {
    $s = [string]$s
    if ($s.Length -le $Max) { return $s }
    return $s.Substring(0, $Max - 1) + [char]0x2026
}

function Get-Activity([int]$Limit) {
    # 聚合各工具真實工作歷史：直接讀 dataDir 的 history.jsonl（工具沒啟動也查得到）。
    # 只列有操作記錄概念的工具：Build Runner（建置）、Git Ref Manager（同步等 job）、
    # Agents Cfg Manager（打包／解開／複製）。歸一化成 {tool,title,detail,time,status}。
    $items = @()
    if (-not $env:LOCALAPPDATA) { return [pscustomobject]@{ ok = $true; result = @() } }
    $base = Join-Path $env:LOCALAPPDATA 'DevToolbox'

    # Build Runner：state success/failed/stopped，時間為 UTC ISO
    foreach ($h in @(Read-JsonlTail (Join-Path $base 'build-runner\history.jsonl') 30)) {
        $st = switch ($h.state) { 'success' { 'ok' } 'stopped' { 'warn' } 'failed' { 'fail' } default { 'warn' } }
        $title = Cut-Text (@(@($h.workspace, $h.recipe) | Where-Object { $_ }) -join ' · ') 90
        if (-not $title) { $title = '建置' }
        $det = @()
        if ($h.state -ne 'success') {
            if ($h.rootError -and $h.rootError.text) { $det += Cut-Text ([string]$h.rootError.text) 120 }
            elseif ($h.message) { $det += Cut-Text ([string]$h.message) 120 }
        }
        if ($null -ne $h.durationSec) {
            $m = [Math]::Round([double]$h.durationSec / 60)
            $det += $(if ($m -ge 1) { "耗時 $m 分" } else { "耗時 $([Math]::Round([double]$h.durationSec)) 秒" })
        }
        $items += [pscustomobject]@{ tool = 'build-runner'; title = $title; detail = ($det -join '，')
            time = (ConvertTo-TimeMs ([string]$h.endedAt)); status = $st }
    }

    # Git Ref Manager：job 歷史，state Done/Failed（Running 不會落盤），時間為本地 'yyyy-MM-dd HH:mm:ss'
    foreach ($h in @(Read-JsonlTail (Join-Path $base 'git-ref-manager\history.jsonl') 30)) {
        if ($h.kind -eq 'sync-preview') { continue }   # 預覽不是實際工作，不進時間軸
        $kindCn = switch ($h.kind) {
            'sync-apply'    { '本地同步' }
            'sync-preview'  { '同步預覽' }
            'fetch'         { '抓取遠端' }
            'worktree'      { '建工作樹' }
            default         { [string]$h.kind }
        }
        $title = $kindCn
        if ($h.meta) {
            $srcName = if ($h.meta.src) { Split-Path ([string]$h.meta.src) -Leaf } else { '' }
            $nDst = @(($h.meta.dsts | ForEach-Object { Split-Path ([string]$_) -Leaf }) | Where-Object { $_ })
            if ($srcName -and $nDst.Count -ge 1) {
                $t1 = $nDst[0]
                $more = if ($nDst.Count -gt 1) { " 等 $($nDst.Count) 個" } else { '' }
                $title = "$kindCn：$srcName → $t1$more"
            } elseif ($h.meta.branch) {
                $title = "$kindCn：$([string]$h.meta.branch)"
            }
        }
        $r = $h.result
        $det = @()
        if ($r.applied) { $det += "更新 $($r.applied) 個 ref" }
        if ($r.created) { $det += "建立 $($r.created) 個" }
        $sk = 0
        if ($null -ne $r.conflictSkipped) { $sk += [int]$r.conflictSkipped }
        # 落盤欄位是 skippedSubmodules 陣列（skippedCount 只是 GRM API 的顯示值）
        if ($null -ne $r.skippedSubmodules) { $sk += @($r.skippedSubmodules).Count }
        if ($sk -gt 0) { $det += "略過 $sk 個" }
        # 注意：@($null).Count 是 1，必須先判 $null（sync-preview/worktree 沒有 failed 欄位）
        $nFail = if ($null -ne $r.failed) { @($r.failed).Count } else { 0 }
        if ($nFail -gt 0) { $det += "失敗 $nFail 個" }
        if ($h.error) { $det += Cut-Text ([string]$h.error) 100 }
        $st = 'ok'
        if ($h.state -eq 'Failed' -or $nFail -gt 0) { $st = 'fail' } elseif ($sk -gt 0) { $st = 'warn' }
        $items += [pscustomobject]@{ tool = 'git-ref-manager'; title = (Cut-Text $title 90); detail = ($det -join '，')
            time = (ConvertTo-TimeMs ([string]$h.endedAt)); status = $st }
    }

    # Agents Cfg Manager：欄位自帶 status，檔案最新在前 → 讀檔頭
    foreach ($h in @(Read-JsonlTail (Join-Path $base 'agents-cfg-manager\history.jsonl') 30 -Head)) {
        $actCn = switch ($h.action) {
            'pack'   { '打包設定檔' }
            'unpack' { '解開設定檔' }
            'copy'   { '複製設定' }
            default  { [string]$h.action }
        }
        $title = if ($h.profile) { "$actCn：$([string]$h.profile)" } elseif ($h.detail) { "$actCn：$(Cut-Text ([string]$h.detail) 60)" } else { $actCn }
        $det = @()
        if ($h.source -and $h.target) { $det += "$(Split-Path ([string]$h.source) -Leaf) → $(Split-Path ([string]$h.target) -Leaf)" }
        if ($h.count) { $det += "$($h.count) 個檔案" }
        if ($h.bytes) {
            $kb = [double]$h.bytes / 1KB
            $det += $(if ($kb -ge 1024) { "$([Math]::Round($kb/1024, 1)) MB" } else { "$([Math]::Round($kb)) KB" })
        }
        $st = 'ok'
        if ($h.status -match 'fail|error') { $st = 'fail' } elseif ($h.status -match 'warn|partial') { $st = 'warn' }
        $items += [pscustomobject]@{ tool = 'agents-cfg-manager'; title = (Cut-Text $title 90); detail = ($det -join '，')
            time = (ConvertTo-TimeMs ([string]$h.time)); status = $st }
    }

    $items = @($items | Where-Object { $_.time -gt 0 } | Sort-Object { [long]$_.time } -Descending | Select-Object -First $Limit)
    return [pscustomobject]@{ ok = $true; result = $items }
}

function Get-ToolsView {
    $out = @()
    foreach ($t in @(Get-Tools)) {
        $running = $null
        $local = $t.Installed -and $t.Source -ne 'link'
        if ($local) { $running = Get-ToolStatus $t }
        $out += [pscustomobject]@{
            id        = $t.Id
            name      = $t.Name
            version   = $t.Version
            installed = $t.Installed
            canUpdate = $local -and $script:OfficialToolNames.Contains($t.Id)
            source    = $t.Source
            hidden    = $t.Hidden
            url       = $t.Url
            path      = $t.ImportPath
            icon      = [string]$t.Manifest.icon
            error     = $t.Error
            runtime   = if ($t.Installed) { [string]$t.Manifest.runtime.kind } else { '' }
            runtimeDetail = if ($local) { Get-RuntimeDetail $t } else { '' }
            web       = [bool]($t.Installed -and $t.Manifest.web)
            cli       = [bool]($t.Installed -and $t.Manifest.cli)
            desc      = if ($t.Installed) { [string]$t.Manifest.description } else { '' }
            port      = if ($t.Installed -and $t.Manifest.web) { [int]$t.Manifest.web.defaultPort } else { 0 }
            running   = $running
        }
    }
    return , $out
}

# ---------------- HTTP 基礎（HttpListener，與 Git-Ref-Manager-Web 同模式） ----------------
$script:MaxBodyChars = 1048576
$script:Shutdown = $false

function Read-ClientRequest($hctx) {
    # HttpListener（Windows 內建 http.sys）已處理好連線；這裡只轉成路由使用的格式。
    # 不自己開 socket：有些電腦的端點防護會切斷 powershell.exe 自己開的連線（ERR_CONNECTION_RESET）。
    $r = $hctx.Request
    $headers = @{}
    foreach ($k in @($r.Headers.AllKeys)) { if ($k) { $headers[$k.ToLowerInvariant()] = [string]$r.Headers[$k] } }
    $body = ''
    if ($r.HasEntityBody) {
        $sr = New-Object System.IO.StreamReader($r.InputStream, [System.Text.Encoding]::UTF8)
        $buf = New-Object char[] 65536
        $sb = New-Object System.Text.StringBuilder
        while ($true) {
            $n = $sr.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            [void]$sb.Append($buf, 0, $n)
            if ($sb.Length -gt $script:MaxBodyChars) { break }   # 超過上限：Test-RequestAllowed 會回 413
        }
        $sr.Dispose()
        $body = $sb.ToString()
    }
    [pscustomobject]@{ Method = [string]$r.HttpMethod; RawUrl = [string]$r.RawUrl; Headers = $headers; Body = $body }
}

function Send-Response($hctx, [int]$code, [string]$contentType, [byte[]]$bodyBytes) {
    if (-not $bodyBytes) { $bodyBytes = [byte[]]@() }
    # Hub 是頂層頁面：frame-ancestors 'none'；iframe 載入本機工具 port 用 frame-src 放行
    $csp = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-src http://127.0.0.1:* http://localhost:*; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    $resp = $hctx.Response
    try {
        $resp.StatusCode = $code
        $resp.ContentType = $contentType
        $resp.KeepAlive = $false
        $resp.Headers.Add('Cache-Control', 'no-store')
        $resp.Headers.Add('X-Content-Type-Options', 'nosniff')
        $resp.Headers.Add('Content-Security-Policy', $csp)
        $resp.Headers.Add('Referrer-Policy', 'no-referrer')
        $resp.ContentLength64 = $bodyBytes.Length
        if ($bodyBytes.Length -gt 0) { $resp.OutputStream.Write($bodyBytes, 0, $bodyBytes.Length) }
    } finally {
        try { $resp.OutputStream.Close() } catch { }
        try { $resp.Close() } catch { }
    }
}

function Send-Text($ctx, [int]$code, [string]$text) {
    $ctx.Code = $code
    $ctx.Type = 'text/plain; charset=utf-8'
    $ctx.Bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
}

function Send-JsonRaw($ctx, $obj, [int]$code = 200) {
    $ctx.Code = $code
    $ctx.Type = 'application/json; charset=utf-8'
    $ctx.Bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $obj -Depth 10 -Compress))
}

function Read-JsonBody($req) {
    if ([System.String]::IsNullOrWhiteSpace($req.Body)) { return [pscustomobject]@{} }
    try { return ConvertFrom-Json $req.Body } catch { throw @{ code = 'BAD_JSON'; message = "JSON 格式錯誤：$($_.Exception.Message)" } }
}

function Get-StaticFile([string]$path) {
    $map = [ordered]@{
        '/'            = @('index.html', 'text/html; charset=utf-8', $script:UiDir)
        '/index.html'  = @('index.html', 'text/html; charset=utf-8', $script:UiDir)
        '/app.js'      = @('app.js', 'application/javascript; charset=utf-8', $script:UiDir)
        '/hub.css'     = @('hub.css', 'text/css; charset=utf-8', $script:UiDir)
        '/hub-bg.js'   = @('hub-bg.js', 'application/javascript; charset=utf-8', $script:UiDir)
        '/ui-kit.css'  = @('ui-kit.css', 'text/css; charset=utf-8', $script:KitDir)
        '/tb-theme.js' = @('tb-theme.js', 'application/javascript; charset=utf-8', $script:KitDir)
        '/tb-icons.js' = @('tb-icons.js', 'application/javascript; charset=utf-8', $script:KitDir)
        '/favicon.svg' = @('favicon.svg', 'image/svg+xml', $script:UiDir)
    }
    if (-not $map.Contains($path)) { return $null }
    $entry = $map[$path]
    $file = Join-Path ([string]$entry[2]) ([string]$entry[0])
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    [pscustomobject]@{ Type = [string]$entry[1]; Bytes = [System.IO.File]::ReadAllBytes($file) }
}

# ---------------- 安全（TOOL-SPEC 第 5 節，Hub 只接受自己的 Origin） ----------------
function Test-RequestAllowed($req) {
    $selfHosts = @("127.0.0.1:$Port", "localhost:$Port")
    $hostHdr = [string]$req.Headers['host']
    if (-not ($selfHosts -contains $hostHdr.ToLowerInvariant())) {
        return @{ Status = 403; Code = 'FORBIDDEN_HOST'; Message = "不允許的 Host：$hostHdr" }
    }
    $method = ([string]$req.Method).ToUpperInvariant()
    if ($method -eq 'GET' -or $method -eq 'HEAD') { return $null }
    if ($method -ne 'POST') {
        return @{ Status = 405; Code = 'METHOD_NOT_ALLOWED'; Message = "不支援的方法：$method" }
    }
    if ([string]$req.Headers['x-toolbox-request'] -ne '1') {
        return @{ Status = 403; Code = 'MISSING_TOOLBOX_HEADER'; Message = '缺少 X-Toolbox-Request 標頭' }
    }
    $origin = [string]$req.Headers['origin']
    if ($origin) {
        $allowed = @("http://127.0.0.1:$Port", "http://localhost:$Port")
        if (-not ($allowed -contains $origin.ToLowerInvariant())) {
            return @{ Status = 403; Code = 'FORBIDDEN_ORIGIN'; Message = "不允許的來源：$origin" }
        }
    }
    $ct = [string]$req.Headers['content-type']
    if (-not $ct.ToLowerInvariant().StartsWith('application/json')) {
        return @{ Status = 415; Code = 'UNSUPPORTED_MEDIA_TYPE'; Message = 'Content-Type 必須是 application/json' }
    }
    if ($req.Body -and $req.Body.Length -gt $script:MaxBodyChars) {
        return @{ Status = 413; Code = 'PAYLOAD_TOO_LARGE'; Message = '請求內容超過 1 MB' }
    }
    return $null
}

# ---------------- API 路由 ----------------
function Get-UpdatableTool([string]$Id) {
    if ($Id -ceq 'dev-toolbox') {
        return [pscustomobject]@{ Id = $Id; Version = [string]$script:HubManifest.version; Dir = $HubRoot }
    }
    $tool = @(Get-Tools | Where-Object { $_.Id -ceq $Id -and $_.Source -in 'bundled','managed','catalog','import' })
    if ($tool.Count -ne 1 -or (-not $tool[0].Installed -and $tool[0].Source -ne 'catalog') -or -not $script:OfficialToolNames.Contains($Id)) {
        throw @{ code = 'NO_UPDATE_SOURCE'; message = '找不到可更新的工具。' }
    }
    return $tool[0]
}

function Invoke-HubUpdate($Tool, $Offer) {
    $state = @{ process = $null; url = $null }
    $result = Install-ToolRelease $ToolUpdateStore $Tool $Offer {} {
        $dir = Resolve-ToolUpdateDir $ToolUpdateStore $Tool.Id $Tool.Version $Tool.Dir
        $entry = Join-Path $dir 'hub\Hub-Web.ps1'
        $log = Join-Path $script:DataDir ('jobs\hub-update-' + [guid]::NewGuid().ToString('N'))
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $entry),
            '-Force', '-InstallationRoot', ('"{0}"' -f $InstallationRoot), '-DataDir', ('"{0}"' -f $script:DataDir))
        $state.process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $dir `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
        $deadline = (Get-Date).AddSeconds(25)
        while ((Get-Date) -lt $deadline -and -not $state.process.HasExited) {
            $line = Get-Content -LiteralPath "$log.out" -TotalCount 1 -ErrorAction SilentlyContinue
            if ($line -match '^READY (http://127\.0\.0\.1:\d+)$') {
                $url = $Matches[1]
                $health = Invoke-ToolHttp "$url/api/health" 'GET' 1000
                if ($health.ok -and $health.id -ceq $Tool.Id -and $health.version -ceq $Offer.version -and $health.pid -eq $state.process.Id) {
                    $state.url = $url
                    return
                }
            }
            Start-Sleep -Milliseconds 250
        }
        throw "新版 Hub 啟動失敗，請查看 $log.err"
    } {
        if ($state.process -and -not $state.process.HasExited) { Stop-Process -Id $state.process.Id -Force }
    }
    $script:Shutdown = $true
    return @{ version = $result.version; url = $state.url }
}

function Invoke-ToolUpdate($Tool, $Offer, [bool]$RestartConfirmed) {
    $id = $Tool.Id
    $running = Get-ToolStatus $Tool
    if ($running -and -not $running.managed) { throw '請先關閉在 Hub 外啟動的工具，再重新更新。' }
    if ($running -and -not $RestartConfirmed) { throw '工具已開始執行，請重新檢查更新並確認重新啟動。' }
    $state = @{ stopped = $false }
    $store = if ($Tool.Source -eq 'import') { Get-ImportedToolStore $Tool.ImportPath } else { $ToolUpdateStore }
    return (Install-ToolRelease $store $Tool $Offer {
        if ($running) {
            $proc = $script:ToolProcs[$id].Proc
            # Let update fail if the tool refuses to stop, without force-killing active work.
            [void](Invoke-ToolHttp "$($running.url)/api/shutdown" 'POST' 1500)
            if (-not $proc.WaitForExit(5000)) { throw '工具尚未停止，更新未套用。' }
            $script:ToolProcs.Remove($id)
            $state.stopped = $true
        }
    } {
        if ($state.stopped) {
            $started = Start-ToolService $id
            $health = Invoke-ToolHttp "$($started.url)/api/health" 'GET' 2000
            if (-not $health.ok -or $health.id -cne $id) {
                $proc = $script:ToolProcs[$id].Proc
                Stop-ToolService $id | Out-Null
                if (-not $proc.WaitForExit(2000)) {
                    & taskkill.exe /T /F /PID $proc.Id 2>&1 | Out-Null
                }
                throw '新版未通過健康檢查。'
            }
        }
    } {
        if ($state.stopped) { Start-ToolService $id | Out-Null }
    })
}

function Update-ToolLibrary($Body) {
    $library = Get-ToolLibrary
    $id = [string]$Body.id
    $tool = Get-Tools | Where-Object Id -CEQ $id | Select-Object -First 1
    switch ($Body.action) {
        'import' {
            $path = ([string]$Body.path).Trim().Trim('"')
            if ($path -notmatch '^[A-Za-z]:[\\/]') { throw '請指定本機工具資料夾的完整路徑。' }
            $path = [IO.Path]::GetFullPath($path)
            $manifest = Read-ImportedTool $path
            $existing = Get-Tools | Where-Object Id -CEQ $manifest.id | Select-Object -First 1
            if ($existing -and $existing.Source -ne 'catalog') { throw 'Hub 已有相同 ID 的工具。' }
            $library.imports = @($library.imports) + @{ id = $manifest.id; name = $manifest.name; path = $path }
        }
        'link' {
            if ($id -and $tool.Source -ne 'link') { throw '找不到這個網站連結。' }
            $name = ([string]$Body.name).Trim()
            $desc = ([string]$Body.description).Trim()
            $icon = ([string]$Body.icon).Trim()
            if (-not $name -or $name.Length -gt 60 -or $desc.Length -gt 200 -or $icon -notin '','external-link','file-code','terminal','bookmark','book','settings') {
                throw '請檢查名稱、簡介和圖示。'
            }
            if (-not $id) { $id = 'link-' + [guid]::NewGuid().ToString('N') }
            $link = @{ id = $id; name = $name; url = ConvertTo-ToolLink ([string]$Body.url); description = $desc; icon = $icon }
            $updated = $false
            $library.links = @(foreach ($record in $library.links) {
                if ($record.id -ceq $id) { $link; $updated = $true } else { $record }
            })
            if (-not $updated) { $library.links += $link }
        }
        'visibility' {
            if (-not $tool -or $tool.Source -eq 'catalog' -or $Body.hidden -isnot [bool]) { throw '找不到可設定顯示的工具。' }
            $library.hidden = @($library.hidden | Where-Object { $_ -cne $id })
            if ($Body.hidden) { $library.hidden += $id }
        }
        'remove' {
            if ($tool.Source -notin 'import','link') { throw '只能移除匯入的工具或網站連結。' }
            if ($tool.Source -eq 'import' -and $script:ToolProcs.ContainsKey($id)) { throw '請先停止工具再移除。' }
            $library.imports = @($library.imports | Where-Object id -CNE $id)
            $library.links = @($library.links | Where-Object id -CNE $id)
            $library.hidden = @($library.hidden | Where-Object { $_ -cne $id })
        }
        default { throw '不支援的工具管理操作。' }
    }
    Save-ToolLibrary $library
}

function Route-Request($req, $ctx) {
    $path = ($req.RawUrl -split '\?')[0]
    $method = ([string]$req.Method).ToUpperInvariant()

    if ($method -eq 'GET') {
        switch ($path) {
            '/api/health' {
                Send-JsonRaw $ctx ([pscustomobject]@{
                    ok = $true; id = [string]$script:HubManifest.id; version = [string]$script:HubManifest.version
                    pid = $PID; port = $Port; uptimeSec = [int]((Get-Date) - $script:StartedAt).TotalSeconds
                })
                return
            }
            '/api/info' {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; tool = $script:HubManifest; dataDir = $script:DataDir })
                return
            }
            '/api/tools' {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; tools = (Get-ToolsView) })
                return
            }
            '/api/settings' {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; settings = (Get-HubSettings) })
                return
            }
            '/api/activity' {
                # $req 只有 RawUrl（見 Read-ClientRequest），query 自己拆
                $lim = 0
                $qs = (([string]$req.RawUrl) -split '\?', 2)
                if ($qs.Count -eq 2) {
                    foreach ($pair in ($qs[1] -split '&')) {
                        $kv = $pair -split '=', 2
                        if ($kv.Count -eq 2 -and $kv[0] -eq 'limit') { [void][int]::TryParse($kv[1], [ref]$lim) }
                    }
                }
                if ($lim -lt 1 -or $lim -gt 100) { $lim = 20 }
                Send-JsonRaw $ctx (Get-Activity $lim)
                return
            }
            '/api/python' {
                # 全域來源（不含各工具 .venv）＋每個 Python 工具實際會用哪一個
                $srcList = @()
                foreach ($c in @(Get-PythonCandidates $null)) {
                    $v = if ($c.found) { Get-PythonVersion $c.path } else { @{ ok = $false; version = ''; message = '' } }
                    $srcList += [pscustomobject]@{ source = $c.source; label = $c.label; path = $c.path; found = $c.found; version = $v.version; usable = [bool]$v.ok; message = $v.message }
                }
                $perTool = @()
                foreach ($t in @(Get-Tools)) {
                    if (-not $t.Installed -or [string]$t.Manifest.runtime.kind -ne 'python') { continue }
                    $first = @(Get-PythonCandidates $t.Dir | Where-Object { $_.found }) | Select-Object -First 1
                    $perTool += [pscustomobject]@{ id = $t.Id; name = $t.Name; source = $(if ($first) { $first.source } else { '' }); path = $(if ($first) { $first.path } else { '' }) }
                }
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; sources = $srcList; tools = $perTool })
                return
            }
            default {
                $f = Get-StaticFile $path
                if ($f) { $ctx.Code = 200; $ctx.Type = $f.Type; $ctx.Bytes = $f.Bytes; return }
                Send-Text $ctx 404 "404 Not Found"
                return
            }
        }
    }

    # POST
    switch ($path) {
        '/api/tools/library' {
            try { Update-ToolLibrary (Read-JsonBody $req) }
            catch { throw @{ code = 'LIBRARY_ERROR'; message = $_.Exception.Message } }
            Send-JsonRaw $ctx @{ ok = $true }
            return
        }
        '/api/tools/folder' {
            Add-Type -AssemblyName System.Windows.Forms
            $picker = New-Object Windows.Forms.FolderBrowserDialog
            $picker.Description = '選擇包含 tool.json 的工具資料夾'
            $picker.ShowNewFolderButton = $false
            $owner = New-Object Windows.Forms.Form
            try {
                $owner.ShowInTaskbar = $false
                $owner.TopMost = $true
                $result = if ($picker.ShowDialog($owner) -eq 'OK') { $picker.SelectedPath }
                Send-JsonRaw $ctx @{ ok = $true; path = $result }
            } finally { $picker.Dispose(); $owner.Dispose() }
            return
        }
        '/api/tools/update/check' {
            $b = Read-JsonBody $req
            $t = Get-UpdatableTool ([string]$b.id)
            $script:ToolUpdateOffers.Remove($t.Id)
            $offer = Get-ToolRelease $t $script:HubManifest.version
            $update = $null
            if ($offer) {
                $script:ToolUpdateOffers[$t.Id] = @{ offer = $offer; current = $t.Version; expires = (Get-Date).AddMinutes(10) }
                $update = @{ version = $offer.version; notes = $offer.notes }
            }
            Send-JsonRaw $ctx @{ ok = $true; update = $update }
            return
        }
        '/api/tools/update/apply' {
            $b = Read-JsonBody $req
            $t = Get-UpdatableTool ([string]$b.id)
            $checked = $script:ToolUpdateOffers[$t.Id]
            if (-not $checked -or $checked.current -cne $t.Version -or
                $checked.offer.version -cne [string]$b.version -or $checked.expires -lt (Get-Date)) {
                throw @{ code = 'UPDATE_EXPIRED'; message = '請重新檢查更新後再安裝。' }
            }
            $script:ToolUpdateOffers.Remove($t.Id)
            if ($t.Id -eq 'dev-toolbox') {
                if ($b.restart -isnot [bool] -or -not $b.restart) { throw '請確認重新啟動 Hub。' }
                $result = Invoke-HubUpdate $t $checked.offer
            } elseif ($t.Source -eq 'catalog') {
                $result = Install-ToolRelease $ToolUpdateStore $t $checked.offer {} {} {}
            } else {
                $result = Invoke-ToolUpdate $t $checked.offer ($b.restart -is [bool] -and $b.restart)
            }
            Send-JsonRaw $ctx @{ ok = $true; result = $result }
            return
        }
        '/api/tools/start' {
            $b = Read-JsonBody $req
            $id = [string]$b.id
            if (-not $id) { throw @{ code = 'BAD_ARGS'; message = '缺少 id' } }
            $r = Start-ToolService $id
            Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; result = $r })
            return
        }
        '/api/tools/stop' {
            $b = Read-JsonBody $req
            $id = [string]$b.id
            if (-not $id) { throw @{ code = 'BAD_ARGS'; message = '缺少 id' } }
            $r = Stop-ToolService $id
            Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; result = $r })
            return
        }
        '/api/settings' {
            $b = Read-JsonBody $req
            $cur = Get-HubSettings
            if ($null -ne $b.pythonPath) {
                $pp = ([string]$b.pythonPath).Trim().Trim('"')
                if ($pp) {
                    $v = Get-PythonVersion $pp
                    if (-not $v.ok) { throw @{ code = 'BAD_PYTHON'; message = "這個 Python 不能用：$($v.message)" } }
                }
                $cur.pythonPath = $pp
            }
            Save-HubSettings $cur
            Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; settings = $cur })
            return
        }
        '/api/python/check' {
            $b = Read-JsonBody $req
            $pp = ([string]$b.path).Trim().Trim('"')
            if (-not $pp) { throw @{ code = 'BAD_ARGS'; message = '缺少 path' } }
            $v = Get-PythonVersion $pp
            Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; result = [pscustomobject]@{ path = $pp; usable = [bool]$v.ok; version = $v.version; message = $v.message } })
            return
        }
        '/api/shutdown' {
            $script:Shutdown = $true
            Send-JsonRaw $ctx ([pscustomobject]@{ ok = $true; result = [pscustomobject]@{ closing = $true } })
            return
        }
        default {
            Send-Text $ctx 404 "404 Not Found"
            return
        }
    }
}


function Handle-Client($hctx) {
    $ctx = $null
    try {
        $req = Read-ClientRequest $hctx
        $ctx = @{ Code = 200; Type = 'text/plain; charset=utf-8'; Bytes = $null }
        $deny = Test-RequestAllowed $req
        try {
            if ($deny) {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = $deny.Code; message = $deny.Message; detail = $null } }) ([int]$deny.Status)
            } else {
                Route-Request $req $ctx
            }
        } catch {
            $err = $_
            if ($err.TargetObject -is [hashtable] -and $err.TargetObject.ContainsKey('code')) {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $false; error = [pscustomobject]$err.TargetObject }) 400
            } else {
                Send-JsonRaw $ctx ([pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = 'INTERNAL'; message = $err.Exception.Message; detail = $null } }) 500
            }
        }
        Send-Response $hctx ([int]$ctx.Code) ([string]$ctx.Type) ([byte[]]$ctx.Bytes)
    } catch {
        # 客戶端中斷之類，忽略
        try { $hctx.Response.Abort() } catch { }
    }
}


# ---------------- 單實例偵測 ----------------
# 同機重複啟動時不默默開第二個 Hub：先看範圍內是否已有 Hub 在聽（用 /api/health 認 id，
# 不受 Windows 保留 port 影響），有就開瀏覽器連舊實例並結束。-Force 跳過（除錯用）。
if (-not $Force) {
    $scanPorts = if ($script:PortExplicit) { @($Port) } else { @($Port..($Port + 20)) }
    foreach ($sp in $scanPorts) {
        if (Test-PortFree $sp) { continue }
        $hb = Invoke-ToolHttp "http://127.0.0.1:$sp/api/health" 'GET' 400
        if ($hb -and $hb.ok -and [string]$hb.id -eq [string]$script:HubManifest.id) {
            $existUrl = "http://127.0.0.1:$sp"
            Write-Host "偵測到 Hub 已在執行：$existUrl（pid $($hb.pid)，版本 $($hb.version)）" -ForegroundColor Yellow
            if ([string]$hb.version -ne [string]$script:HubManifest.version) {
                Write-Host "  舊實例版本（$($hb.version)）與這次要啟動的（$($script:HubManifest.version)）不同；要升級請先停止舊 Hub 視窗。" -ForegroundColor Gray
            }
            Write-Host '已改為開啟既有 Hub，不重複啟動。除錯時要硬開第二實例請加 -Force。' -ForegroundColor Gray
            Start-Process $existUrl
            exit 0
        }
    }
}

# ---------------- 主迴圈 ----------------
$listener = $null
$lastErr = $null
$portDenied = 0; $portInUse = 0
# 明確指定 -Port 時只試那一個；否則從預設 port 往上找（最多 +20），都不行就請系統配一個空的 port。
# 0 代表「向系統要一個」：HttpListener 不能直接綁 0，先用 TcpListener 問到 port 再交給 HttpListener。
$tryPorts = if ($script:PortExplicit) { @($Port) } else { @($Port..($Port + 20)) + @(0, 0, 0) }
foreach ($p in $tryPorts) {
    if ($p -eq 0) {
        try {
            $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
            $probe.Start(); $p = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
        } catch { $lastErr = $_.Exception.Message; continue }
    }
    $h = New-Object System.Net.HttpListener
    $h.Prefixes.Add("http://127.0.0.1:$p/")
    $h.Prefixes.Add("http://localhost:$p/")
    try {
        $h.Start(); $listener = $h; $Port = $p
        break
    } catch {
        $lastErr = $_.Exception.Message
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.HttpListenerException])) { $ex = $ex.InnerException }
        if ($ex) { switch ([int]$ex.ErrorCode) { 5 { $portDenied++ } 32 { $portInUse++ } 183 { $portInUse++ } } }
        try { $h.Close() } catch { }
    }
}
if (-not $listener) {
    $why = if ($portDenied -gt 0 -and $portInUse -eq 0) { '存取被拒（port 被 Windows 保留，或缺少權限）。可用 netsh interface ipv4 show excludedportrange protocol=tcp 查看' } elseif ($portInUse -gt 0 -and $portDenied -eq 0) { 'port 已被其他程式佔用' } else { $lastErr }
    Write-Host "無法監聽 127.0.0.1:$($tryPorts[0])：$why" -ForegroundColor Red
    if ($script:PortExplicit) { Write-Host '不指定 -Port 時會自動找可用的 port。' -ForegroundColor Gray }
    exit 5
}
[Console]::Out.WriteLine("READY http://127.0.0.1:$Port")
[Console]::Out.Flush()

$url = "http://127.0.0.1:$Port"
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host " Dev-Toolbox Hub 已啟動： $url" -ForegroundColor Green
Write-Host ' 只綁定本機 127.0.0.1；停止請按 Ctrl+C 或關閉此視窗' -ForegroundColor Gray
Write-Host '===============================================' -ForegroundColor Cyan
if ($OpenBrowser) { Start-Process $url }

# 離開前收掉 Hub spawn 的工具服務（工具另有 -ParentPid 自主退出，這裡雙保險）
$pendingCtx = $null
try {
    while (-not $script:Shutdown) {
        if (-not $pendingCtx) { $pendingCtx = $listener.BeginGetContext($null, $null) }
        # 每 60ms 醒來一次，Ctrl+C 才能及時生效
        if ($pendingCtx.AsyncWaitHandle.WaitOne(60)) {
            $hctx = $null
            try { $hctx = $listener.EndGetContext($pendingCtx) } catch { }
            $pendingCtx = $null
            if ($hctx) { Handle-Client $hctx }
        }
    }
} finally {
    try { $listener.Stop(); $listener.Close() } catch { }
    foreach ($id in @($script:ToolProcs.Keys)) {
        try { & taskkill.exe /T /F /PID $script:ToolProcs[$id].Proc.Id 2>&1 | Out-Null } catch {}
    }
    Write-Host '已停止監聽。'
}

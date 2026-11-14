# Tool-Cleanup.ps1 — 清理 Hub 更新儲存區裡的舊版（設定 → 更新 → 清理舊版檔案）
#
# 範圍：只看 <更新儲存區>\<官方產品 id>\<版本> 這一層的版本資料夾（含 Hub 本體 dev-toolbox）。
# 每個產品保留「目前版」（active.txt）與「保留的舊版」（比目前版低、套件有效的最高版），更早的有效版本才可清理。
# 不跟隨連結（junction／符號連結）：版本資料夾本身或裡面有連結、上層路徑有連結，都略過。
# 仍有程序的執行檔或命令列指向該資料夾（Hub 管理的工具與獨立開啟的工具都算）就略過。
# 預覽只讀不寫；執行時每個產品先取得更新器用的 update.lock，重新判斷一次，只處理仍可清理的版本。
# 預設送到資源回收筒；選「永久刪除」才直接刪除。
#
# 需要先載入 Tool-Updates.ps1（ConvertTo-ToolVersion、Read-ActiveToolVersion、$script:ToolReleaseRepos）。

function Get-HubProcessText {
    # 所有程序的執行檔與命令列（小寫、反斜線），用來判斷版本資料夾是否仍在使用
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-CimInstance Win32_Process -Property ExecutablePath, CommandLine -ErrorAction Stop)) {
        foreach ($v in @($p.ExecutablePath, $p.CommandLine)) {
            if ($v) { $list.Add(([string]$v).ToLowerInvariant().Replace('/', '\')) }
        }
    }
    return , $list.ToArray()
}

function Test-HubDirInUse([string]$Dir, [string[]]$ProcessText) {
    $d = $Dir.TrimEnd('\').ToLowerInvariant()
    foreach ($t in $ProcessText) {
        $i = $t.IndexOf($d)
        while ($i -ge 0) {
            # 0.5.1 不能誤判成 0.5.10：路徑後面必須是結尾、分隔字元或引號
            $next = $i + $d.Length
            if ($next -ge $t.Length -or $t[$next] -in @([char]'\', [char]'"', [char]"'", [char]' ')) { return $true }
            $i = $t.IndexOf($d, $next)
        }
    }
    return $false
}

function Test-HubLinkedAncestor([string]$Path) {
    for ($a = [IO.Path]::GetFullPath($Path).TrimEnd('\'); $a; $a = Split-Path -Parent $a) {
        $item = Get-Item -LiteralPath $a -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $true }
    }
    return $false
}

# 版本資料夾大小；遇到連結就停（不跟隨），回傳連結位置
function Measure-HubVersionDir([string]$Dir) {
    $bytes = 0L
    $stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
    $stack.Push([IO.DirectoryInfo]::new($Dir))
    while ($stack.Count) {
        foreach ($e in $stack.Pop().GetFileSystemInfos()) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { return @{ Bytes = $bytes; Link = $e.FullName } }
            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) } else { $bytes += $e.Length }
        }
    }
    return @{ Bytes = $bytes; Link = $null }
}

function New-CleanupEntry([string]$Name, [string]$Path, [long]$Bytes, [string]$Reason) {
    [pscustomobject]@{ version = $Name; path = $Path; bytes = $Bytes; reason = $Reason }
}

# 單一產品的判斷結果：目前版、保留的舊版、可清理、略過（含原因）
function Get-ToolCleanupProduct([string]$Store, [string]$Id, [string[]]$ProcessText) {
    $toolStore = Join-Path $Store $Id
    $r = [ordered]@{ id = $Id; current = $null; retained = $null; cleanable = @(); skipped = @(); note = '' }
    $info = Get-Item -LiteralPath $toolStore -Force
    if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $r.note = '這個工具的資料夾是連結（junction），不跟隨，整個略過。'
        return [pscustomobject]$r
    }
    $activeText = $null
    try { $activeText = Read-ActiveToolVersion $toolStore } catch { }
    $active = if ($activeText) { ConvertTo-ToolVersion $activeText }

    $valid = @()
    $skipped = New-Object System.Collections.Generic.List[object]
    foreach ($e in ([IO.DirectoryInfo]::new($toolStore)).GetFileSystemInfos()) {
        if ($e -isnot [IO.DirectoryInfo]) {
            if ($e.Name -notin @('active.txt', 'update.lock')) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName $e.Length '不明檔案，保留')) }
            continue
        }
        if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName 0 '連結（junction），不跟隨')); continue }
        if ($e.Name.StartsWith('.')) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName 0 '安裝暫存資料夾，保留')); continue }
        $v = ConvertTo-ToolVersion $e.Name
        if (-not $v) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName 0 '不是版本資料夾，保留')); continue }
        $m = $null
        try { $m = [IO.File]::ReadAllText((Join-Path $e.FullName 'tool.json')) | ConvertFrom-Json } catch { }
        if (-not $m -or $m.id -cne $Id -or $m.version -cne $e.Name) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName 0 '套件內容與版本不符（tool.json），保留')); continue }
        $size = Measure-HubVersionDir $e.FullName
        if ($size.Link) { $skipped.Add((New-CleanupEntry $e.Name $e.FullName $size.Bytes '資料夾內含連結，不跟隨')); continue }
        $valid += [pscustomobject]@{ Name = $e.Name; V = $v; Path = $e.FullName; Bytes = $size.Bytes }
    }

    $current = @($valid | Where-Object { $active -and $_.V -eq $active }) | Select-Object -First 1
    if (-not $current) {
        $r.note = if (-not $activeText) { '沒有版本指標（active.txt），無法確認目前版，整個略過。' }
                  elseif (-not $active) { '版本指標（active.txt）損毀，無法確認目前版，整個略過。' }
                  else { "目前版 $activeText 的資料夾不存在或無效，整個略過。" }
        foreach ($x in $valid) { $skipped.Add((New-CleanupEntry $x.Name $x.Path $x.Bytes '無法確認目前版，保留')) }
        $r.skipped = $skipped.ToArray()
        return [pscustomobject]$r
    }
    $r.current = New-CleanupEntry $current.Name $current.Path $current.Bytes ''
    $cleanable = New-Object System.Collections.Generic.List[object]
    foreach ($x in @($valid | Sort-Object V -Descending)) {
        if ($x.V -gt $active) { $skipped.Add((New-CleanupEntry $x.Name $x.Path $x.Bytes '比目前版新（可能正在安裝），保留')); continue }
        if ($x.V -eq $active) { continue }
        if (-not $r.retained) { $r.retained = New-CleanupEntry $x.Name $x.Path $x.Bytes ''; continue }
        if (Test-HubDirInUse $x.Path $ProcessText) { $skipped.Add((New-CleanupEntry $x.Name $x.Path $x.Bytes '有程序正在使用這個版本，保留')); continue }
        $cleanable.Add((New-CleanupEntry $x.Name $x.Path $x.Bytes ''))
    }
    $r.cleanable = $cleanable.ToArray()
    $r.skipped = $skipped.ToArray()
    return [pscustomobject]$r
}

function Get-ToolCleanupIds([string]$Store) {
    return @(Get-ChildItem -LiteralPath $Store -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $script:ToolReleaseRepos.ContainsKey($_.Name) -and $_.Name -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$' } |
        Sort-Object Name | ForEach-Object Name)
}

# 預覽：只讀，不改動任何檔案。$Shared（同步 hashtable）回報進度 done／total／label。
function Get-ToolCleanupPlan([string]$Store, $Shared) {
    $plan = [ordered]@{ store = $Store; products = @(); note = '' }
    if (-not [IO.Directory]::Exists($Store)) { return [pscustomobject]$plan }
    if (Test-HubLinkedAncestor $Store) { $plan.note = '更新儲存區的路徑含有連結（junction），不自動清理，請手動處理。'; return [pscustomobject]$plan }
    $ids = Get-ToolCleanupIds $Store
    if ($Shared) { $Shared.total = $ids.Count; $Shared.label = '讀取執行中的程序…' }
    $proc = Get-HubProcessText
    $products = @()
    foreach ($id in $ids) {
        if ($Shared) { $Shared.label = $id }
        try { $products += Get-ToolCleanupProduct $Store $id $proc }
        catch { $products += [pscustomobject]@{ id = $id; current = $null; retained = $null; cleanable = @(); skipped = @(); note = "讀取失敗：$($_.Exception.Message)" } }
        if ($Shared) { $Shared.done = [int]$Shared.done + 1 }
    }
    $plan.products = $products
    return [pscustomobject]$plan
}

function Send-HubRecycleBin([string]$Path) {
    if (-not ('HubRecycleBin' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HubRecycleBin {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT {
        public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
    // FO_DELETE + FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_WANTNUKEWARNING
    // （太大放不進資源回收筒時，Windows 會先問是否永久刪除，不會靜默刪掉）
    public static int Recycle(string path, out bool aborted) {
        SHFILEOPSTRUCT op = new SHFILEOPSTRUCT();
        op.wFunc = 3; op.pFrom = path + "\0"; op.fFlags = 0x0040 | 0x0010 | 0x0004 | 0x0400 | 0x4000;
        int rc = SHFileOperation(ref op); aborted = op.fAnyOperationsAborted; return rc;
    }
}
'@
    }
    $aborted = $false
    $rc = [HubRecycleBin]::Recycle($Path, [ref]$aborted)
    if ($aborted) { throw '已取消（沒有移到資源回收筒）。' }
    if ($rc -ne 0) { throw ('移到資源回收筒失敗（代碼 0x{0:X}）。' -f $rc) }
    if ([IO.Directory]::Exists($Path)) { throw '移到資源回收筒後資料夾仍在，可能有檔案正在使用。' }
}

# 執行：$Items = @(@{ id; version })，只處理使用者在預覽確認過、而且現在仍可清理的版本。
# 回傳每一項 { id; version; status = deleted | skipped | failed; reason; bytes }。
function Invoke-ToolCleanup([string]$Store, $Items, [bool]$Permanent, $Shared) {
    $results = New-Object System.Collections.Generic.List[object]
    $add = { param($i, $status, $reason, $bytes) $results.Add([pscustomobject]@{ id = [string]$i.id; version = [string]$i.version; status = $status; reason = $reason; bytes = [long]$bytes }) }
    $items = @($Items)
    if ($Shared) { $Shared.total = $items.Count; $Shared.label = '準備中…' }
    $storeOk = [IO.Directory]::Exists($Store) -and -not (Test-HubLinkedAncestor $Store)
    $groups = $items | Group-Object { [string]$_.id }
    foreach ($g in $groups) {
        $id = $g.Name
        $toolStore = Join-Path $Store $id
        if (-not $storeOk -or -not $script:ToolReleaseRepos.ContainsKey($id) -or -not [IO.Directory]::Exists($toolStore)) {
            foreach ($i in $g.Group) { & $add $i 'skipped' '找不到這個工具的更新資料夾，請重新預覽。' 0; if ($Shared) { $Shared.done = [int]$Shared.done + 1 } }
            continue
        }
        $lock = $null
        try { $lock = [IO.File]::Open((Join-Path $toolStore 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch {
            foreach ($i in $g.Group) { & $add $i 'skipped' '這個工具正在更新，請稍後再試。' 0; if ($Shared) { $Shared.done = [int]$Shared.done + 1 } }
            continue
        }
        try {
            $plan = Get-ToolCleanupProduct $Store $id (Get-HubProcessText)
            $storeFull = [IO.Path]::GetFullPath($toolStore).TrimEnd('\')
            foreach ($i in $g.Group) {
                if ($Shared) { $Shared.label = "$id $($i.version)" }
                try {
                    $c = @($plan.cleanable | Where-Object { $_.version -ceq [string]$i.version }) | Select-Object -First 1
                    if (-not $c) {
                        $s = @($plan.skipped | Where-Object { $_.version -ceq [string]$i.version }) | Select-Object -First 1
                        $why = if ($s) { $s.reason }
                               elseif ($plan.current -and $plan.current.version -ceq [string]$i.version) { '這是目前版，保留。' }
                               elseif ($plan.retained -and $plan.retained.version -ceq [string]$i.version) { '這是保留的舊版，保留。' }
                               else { '狀態已變更（可能更新過），請重新預覽。' }
                        & $add $i 'skipped' $why 0
                        continue
                    }
                    $path = [IO.Path]::GetFullPath($c.path).TrimEnd('\')
                    if ((Split-Path -Parent $path) -ne $storeFull -or (Split-Path -Leaf $path) -cne [string]$i.version) { & $add $i 'failed' '路徑超出允許範圍。' 0; continue }
                    # 改名再改回：有檔案被開啟（例如執行中的程式、工作目錄）時會失敗，就不動它
                    $probe = "$path.~cleanup"
                    try { [IO.Directory]::Move($path, $probe) } catch { & $add $i 'skipped' '有檔案正在使用中，保留。' 0; continue }
                    try { [IO.Directory]::Move($probe, $path) } catch { & $add $i 'failed' "暫時改名後無法改回，請手動把 $probe 改回 $path。" 0; continue }
                    if ($Permanent) {
                        $trash = Join-Path $storeFull ('.removed-' + [guid]::NewGuid().ToString('N'))
                        [IO.Directory]::Move($path, $trash)
                        try { [IO.Directory]::Delete($trash, $true) }
                        catch { & $add $i 'failed' "已移出，但有檔案無法刪除：$trash" 0; continue }
                    } else {
                        Send-HubRecycleBin $path
                    }
                    & $add $i 'deleted' '' $c.bytes
                } catch {
                    & $add $i 'failed' $_.Exception.Message 0
                } finally {
                    if ($Shared) { $Shared.done = [int]$Shared.done + 1 }
                }
            }
        } finally { $lock.Dispose() }
    }
    return [pscustomobject]@{ permanent = $Permanent; items = $results.ToArray() }
}

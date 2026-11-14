$script:OfficialToolNames = [ordered]@{
    'agents-cfg-manager' = 'Agents Cfg Manager'
    'build-runner' = 'Build Runner'
    'git-ref-manager' = 'Git Ref Manager'
    'hlk-viewer' = 'HLK Viewer'
    'key-manager' = 'Key Manager'
    'script-editor' = 'Script Editor'
}

function Get-ToolLibrary {
    $path = Join-Path $ToolUpdateStore 'library.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $lib = Read-JsonFile $path
        if ($null -eq $lib.PSObject.Properties['icons']) { $lib | Add-Member -NotePropertyName icons -NotePropertyValue @() }
        return $lib
    }
    return [pscustomobject]@{ imports = @(); links = @(); hidden = @(); icons = @() }
}

# ---------------- 自訂圖示 ----------------
# library.json 的 icons：[{ id; kind = name|emoji|image; value }]；圖片存在 <ToolUpdateStore>\icons\<id>.<ext>
$script:IconMaxBytes = 262144
$script:IconTypes = [ordered]@{ png = 'image/png'; svg = 'image/svg+xml'; ico = 'image/x-icon' }

function Get-IconDir { Join-Path $ToolUpdateStore 'icons' }

function Get-ToolIconFile([string]$Id) {
    if ($Id -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { return $null }
    foreach ($ext in $script:IconTypes.Keys) {
        $p = Join-Path (Get-IconDir) "$Id.$ext"
        if ([IO.File]::Exists($p)) { return @{ Path = $p; Type = $script:IconTypes[$ext] } }
    }
    return $null
}

function Remove-ToolIconFiles([string]$Id) {
    if ($Id -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { return }
    foreach ($ext in $script:IconTypes.Keys) {
        $p = Join-Path (Get-IconDir) "$Id.$ext"
        if ([IO.File]::Exists($p)) { [IO.File]::Delete($p) }
    }
}

# 檢查並存一張圖示圖片（PNG／ICO 看檔頭；SVG 不能有腳本、事件屬性、外部實體）。回傳副檔名。
function Save-ToolIconImage([string]$Id, [byte[]]$Bytes) {
    if (-not $Bytes -or $Bytes.Length -eq 0 -or $Bytes.Length -gt $script:IconMaxBytes) { throw '圖片必須小於 256 KB。' }
    $ext = $null
    if ($Bytes.Length -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { $ext = 'png' }
    elseif ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 1 -and $Bytes[3] -eq 0) { $ext = 'ico' }
    else {
        $text = [Text.Encoding]::UTF8.GetString($Bytes)
        if ($text -match '(?is)^\s*(<\?xml[^>]*>\s*)?(<!--.*?-->\s*)*<svg[\s>]') {
            if ($text -match '(?i)<script|<foreignobject|<!entity|<!doctype|\son[a-z]+\s*=|javascript:|data:text/html|<iframe|<embed|<object') {
                throw 'SVG 含有腳本或外部內容，不能當圖示。'
            }
            $ext = 'svg'
        }
    }
    if (-not $ext) { throw '只接受 PNG、SVG 或 ICO 圖片。' }
    [void][IO.Directory]::CreateDirectory((Get-IconDir))
    Remove-ToolIconFiles $Id
    [IO.File]::WriteAllBytes((Join-Path (Get-IconDir) "$Id.$ext"), $Bytes)
    return $ext
}

function Set-ToolIcon($Library, [string]$Id, [string]$Kind, [string]$Value) {
    $Library.icons = @(@($Library.icons) | Where-Object { $_ -and $_.id -cne $Id })
    if ($Kind) { $Library.icons += [pscustomobject]@{ id = $Id; kind = $Kind; value = $Value } }
}

function Get-ToolIconView($Library, [string]$Id) {
    $rec = @($Library.icons) | Where-Object { $_ -and $_.id -ceq $Id } | Select-Object -First 1
    if (-not $rec) { return $null }
    if ($rec.kind -eq 'image') {
        $f = Get-ToolIconFile $Id
        if (-not $f) { return $null }
        $stamp = [IO.File]::GetLastWriteTimeUtc($f.Path).Ticks
        return [pscustomobject]@{ kind = 'image'; value = "/api/icon?id=$Id&v=$stamp" }
    }
    return [pscustomobject]@{ kind = [string]$rec.kind; value = [string]$rec.value }
}

function Save-ToolLibrary($Library) {
    [void][IO.Directory]::CreateDirectory($ToolUpdateStore)
    $path = Join-Path $ToolUpdateStore 'library.json'
    $temp = Join-Path $ToolUpdateStore ([guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Library -Depth 6))
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, "$temp.bak") }
        else { [IO.File]::Move($temp, $path) }
    } finally {
        [IO.File]::Delete($temp)
        [IO.File]::Delete("$temp.bak")
    }
}

function Get-OfficialToolDataPath([string]$Id) {
    if ($script:OfficialToolNames.Contains($Id)) {
        $path = Join-Path (Get-ToolDataRoot) $Id
        if ([IO.Directory]::Exists($path)) { return $path }
    }
}

function Remove-HubDirectory([string]$Root, [string]$Id) {
    if (-not $script:OfficialToolNames.Contains($Id)) { throw '無法清除未知的工具目錄。' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $path = Join-Path $rootPath $Id
    if (-not (Test-Path -LiteralPath $path)) { return }
    $resolved = (Resolve-Path -LiteralPath $path).ProviderPath
    if ($resolved -ne $path -or (Split-Path -Parent $resolved) -ne $rootPath) { throw '工具目錄超出允許範圍。' }
    for ($ancestor = $rootPath; $ancestor; $ancestor = Split-Path -Parent $ancestor) {
        if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw '工具目錄的上層含有連結，請手動處理。'
        }
    }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($path)
    while ($pending.Count) {
        $item = Get-Item -LiteralPath $pending.Pop() -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '工具目錄內含連結，請手動處理。' }
        if ($item.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) { $pending.Push($child.FullName) }
        }
    }
    $trash = Join-Path $rootPath ('.removed-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::Move($path,$trash)
    if ((Split-Path -Parent $trash) -ne $rootPath) { throw '清除路徑超出允許範圍。' }
    try { [IO.Directory]::Delete($trash,$true) }
    catch { throw "已移出工具目錄，但有檔案無法清除：$trash" }
}

function Read-ImportedTool([string]$Directory) {
    if ($Directory -notmatch '^[A-Za-z]:[\\/]') { throw '請指定本機工具資料夾的完整路徑。' }
    $m = Read-JsonFile (Join-Path $Directory 'tool.json')
    if ($m.kind -cne 'tool' -or $m.specVersion -ne 1 -or $m.id -isnot [string] -or $m.id -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or
        $m.id.Length -gt 40 -or $m.id -eq 'dev-toolbox' -or $m.id -like 'link-*' -or
        $m.name -isnot [string] -or [string]::IsNullOrWhiteSpace($m.name) -or $m.name.Length -gt 60 -or
        $m.version -isnot [string] -or $m.version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$' -or
        $m.runtime.kind -notin 'powershell','python','exe' -or -not ($m.web -or $m.cli)) {
        throw 'tool.json 不符合 Toolbox 工具規格。'
    }
    if ($m.web -and ($m.web.health -cne '/api/health' -or
        ($m.web.defaultPort -isnot [int] -and $m.web.defaultPort -isnot [long]) -or
        $m.web.defaultPort -lt 1024 -or $m.web.defaultPort -gt 65535)) {
        throw 'tool.json 的 Web 設定不符合工具規格。'
    }
    foreach ($mode in @($m.web, $m.cli)) {
        if ($mode) {
            $entry = Resolve-ToolPackagePath $Directory ([string]$mode.entry)
            if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "找不到工具入口：$($mode.entry)" }
            $extension = @{ powershell = '.ps1'; python = '.py','.pyw'; exe = '.exe' }[[string]$m.runtime.kind]
            if ([IO.Path]::GetExtension($entry) -notin $extension) { throw '工具入口的副檔名與執行環境不符。' }
        }
    }
    return $m
}

function New-LocalTool($Manifest, [string]$Directory, [string]$Source, [string]$ErrorMessage) {
    [pscustomobject]@{
        Id = [string]$Manifest.id; Name = [string]$Manifest.name; Version = [string]$Manifest.version
        Dir = $Directory; Manifest = $Manifest; Source = $Source; Installed = -not $ErrorMessage; Error = $ErrorMessage
    }
}

function Get-ImportedToolStore([string]$Path) {
    $hubDataRoot = Split-Path -Parent (Split-Path -Parent $ToolUpdateStore)
    return Get-ToolUpdateStore $Path (Join-Path (Split-Path -Parent $hubDataRoot) 'standalone')
}

function Get-HubLibraryTools([switch]$IncludeCatalog) {
    $library = Get-ToolLibrary
    $tools = [ordered]@{}
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $InstallationRoot 'tools') -Directory -ErrorAction SilentlyContinue)) {
        try {
            $m = Read-JsonFile (Join-Path $dir.FullName 'tool.json')
            $active = Resolve-ToolUpdateDir $ToolUpdateStore $m.id $m.version $dir.FullName
            if ($active -ne $dir.FullName) { $m = Read-JsonFile (Join-Path $active 'tool.json') }
            $tools[$m.id] = New-LocalTool $m $active 'bundled'
        } catch {
            if (-not ($script:OfficialToolNames.Keys | Where-Object { ($_ -replace '-', '') -eq ($dir.Name -replace '-', '') })) {
                $tools[$dir.Name] = New-LocalTool @{id=$dir.Name; name=$dir.Name} $dir.FullName 'bundled' '無法讀取 tool.json。'
            }
        }
    }
    foreach ($record in $library.imports) {
        if ($tools.Contains($record.id)) { continue }
        try {
            $m = Read-ImportedTool $record.path
            if ($m.id -cne $record.id) { throw '工具 ID 已變更，請重新匯入。' }
            $standaloneStore = Get-ImportedToolStore $record.path
            $active = Resolve-ToolUpdateDir $standaloneStore $m.id $m.version $record.path
            if ($active -ne $record.path) { $m = Read-ImportedTool $active }
            $tools[$m.id] = New-LocalTool $m $active 'import'
            $tools[$m.id] | Add-Member -NotePropertyName ImportPath -NotePropertyValue $record.path
        } catch {
            $tools[$record.id] = New-LocalTool $record $record.path 'import' "無法開啟匯入的工具：$($_.Exception.Message)"
            $tools[$record.id] | Add-Member -NotePropertyName ImportPath -NotePropertyValue $record.path
        }
    }
    foreach ($id in $script:OfficialToolNames.Keys) {
        if ($tools.Contains($id)) { continue }
        $active = Resolve-ToolUpdateDir $ToolUpdateStore $id '0.0.0' ''
        if ($active) {
            $tools[$id] = New-LocalTool (Read-JsonFile (Join-Path $active 'tool.json')) $active 'managed'
        } elseif ($IncludeCatalog) {
            $tools[$id] = New-LocalTool @{id=$id; name=$script:OfficialToolNames[$id]} '' 'catalog' '尚未安裝'
        }
    }
    foreach ($link in $library.links) {
        $tool = New-LocalTool $link '' 'link'
        $tool | Add-Member -NotePropertyName Url -NotePropertyValue $link.url
        $tools[$link.id] = $tool
    }
    foreach ($tool in $tools.Values) {
        $tool | Add-Member -NotePropertyName Hidden -NotePropertyValue ($tool.Id -in $library.hidden)
        $tool | Add-Member -NotePropertyName CustomIcon -NotePropertyValue (Get-ToolIconView $library $tool.Id)
        $tool
    }
}

function ConvertTo-ToolLink([string]$Text) {
    $url = $null
    if ($Text.Length -gt 2048 -or -not [uri]::TryCreate($Text.Trim(), [UriKind]::Absolute, [ref]$url) -or
        $url.Scheme -notin 'http','https' -or -not $url.Host -or $url.UserInfo) {
        throw '請輸入完整的 http:// 或 https:// 網址。'
    }
    return $url.AbsoluteUri
}

function Open-ToolLink([string]$Url) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = ConvertTo-ToolLink $Url
    $start.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($start)
}

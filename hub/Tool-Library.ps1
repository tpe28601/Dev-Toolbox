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
    if (Test-Path -LiteralPath $path -PathType Leaf) { return (Read-JsonFile $path) }
    return [pscustomobject]@{ imports = @(); links = @(); hidden = @() }
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

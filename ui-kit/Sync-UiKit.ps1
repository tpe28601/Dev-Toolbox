# Sync-UiKit.ps1 — 把 ui-kit 正本（ui-kit.css、tb-theme.js、tb-icons.js、tb-dirpicker.js、cli-kit.ps1）複製到 tools/ 底下每個工具。
# 只複製檔案、更新 tool.json 的 uiKit 欄位，不會自動 commit。
# 用法： powershell -NoProfile -ExecutionPolicy Bypass -File ui-kit\Sync-UiKit.ps1 [-DryRun]

param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$css = Join-Path $PSScriptRoot 'ui-kit.css'
$cli = Join-Path $PSScriptRoot 'cli-kit.ps1'
$webFiles = @('ui-kit.css', 'tb-theme.js', 'tb-icons.js', 'tb-dirpicker.js')

$first = (Get-Content -LiteralPath $css -TotalCount 1 -Encoding UTF8)
if ($first -notmatch 'ui-kit (\d+\.\d+\.\d+)') { throw 'ui-kit.css 第一行找不到版本號（格式：/* ui-kit 1.2.3 ... */）' }
$ver = $matches[1]
Write-Host "ui-kit 版本：$ver"

$toolsDir = Join-Path $root 'tools'
foreach ($dir in @(Get-ChildItem -LiteralPath $toolsDir -Directory -ErrorAction SilentlyContinue)) {
    $manifest = Join-Path $dir.FullName 'tool.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        Write-Warning "[$($dir.Name)] 沒有 tool.json（submodule 可能尚未初始化），略過"
        continue
    }
    $tool = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    # 預設複製到 ui\；ui 目錄不在前端路徑的工具（如 Python 工具）用 tool.json 的 uiKitTarget 指定
    $uiRel = if ($tool.uiKitTarget) { [string]$tool.uiKitTarget -replace '/', '\' } else { 'ui' }
    $uiDir = Join-Path $dir.FullName $uiRel
    $targets = @()
    foreach ($f in $webFiles) { $targets += @{ From = (Join-Path $PSScriptRoot $f); To = (Join-Path $uiDir $f) } }
    if ($tool.runtime.kind -eq 'powershell') { $targets += @{ From = $cli; To = (Join-Path $dir.FullName 'cli-kit.ps1') } }
    foreach ($t in $targets) {
        if ($DryRun) { Write-Host "[dry-run] $($t.From) -> $($t.To)"; continue }
        $parent = Split-Path $t.To -Parent
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        Copy-Item -LiteralPath $t.From -Destination $t.To -Force
        Write-Host "[$($dir.Name)] 已更新 $(Split-Path $t.To -Leaf)"
    }
    if (-not $DryRun) {
        # 只改 uiKit 一行，保留 tool.json 其餘排版
        $raw = [System.IO.File]::ReadAllText($manifest)
        if ($raw -match '"uiKit"\s*:\s*"[^"]*"') { $raw = $raw -replace '"uiKit"\s*:\s*"[^"]*"', ('"uiKit": "' + $ver + '"') }
        else {
            $body = $raw.TrimEnd().TrimEnd('}').TrimEnd().TrimEnd(',')
            $raw = $body + ",`n  `"uiKit`": `"$ver`"`n}" + "`n"
        }
        [System.IO.File]::WriteAllText($manifest, $raw, (New-Object System.Text.UTF8Encoding($false)))
    }
}
Write-Host '完成。請到各 submodule 內檢查差異並各自 commit。'

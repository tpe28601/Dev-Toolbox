# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本遵循 SemVer。

## [0.3.0] - 2026-11-10

### 新增
- ui-kit 3.0.0：`ui-kit.css`＋`tb-theme.js`（light／dark／system 三態、5 種強調色、postMessage 主題同步）＋`tb-icons.js`（Lucide，ISC）；示範頁 `ui-kit/demo/`
- Hub 新側欄版面；設定頁可指定 Python 路徑（存在 Hub 資料夾的 `settings.json`），並檢查版本
- `Sync-UiKit.ps1` 一併同步 `tb-theme.js`、`tb-icons.js`

### 變更
- Hub 與 Git-Ref-Manager 的 Web 伺服器改用 `HttpListener`（部分電腦的端點防護會中斷 TcpListener 連線）
- 預設 port 被 Windows 保留時改綁 port 0
- 子模組 remote 改為 GitHub（`tpe28601/*`）；三工具 pin 為 Git-Ref-Manager v1.1.1、Opencode-Cfg-Manager v1.1.1、Key-Manager v1.1.1

### 修正
- Key-Manager Web 模式：選擇 SSH 資料夾與匯出 Public Key 不再出現「視窗尚未初始化」

## [0.2.0] - 2026-11-10

### 新增
- Web Hub 主控台 `hub/Hub-Web.ps1` + `hub/ui/`（port 8700）：工具清單與狀態、啟動／停止（停止有確認框）、
  iframe 切換工具、深淺主題同步、新視窗開啟、非 Hub 啟動偵測
- `hub.ps1 web` 指令啟動 Web Hub
- Python 工具直譯器解析：`DEVTOOLBOX_PYTHON` → 工具 `.venv` → `py` → PATH（跳過 WindowsApps）
- ui-kit 2.0.0：深色為預設的 token 系統與 `.tb-*` 元件樣式；設計指南 `design-system/dev-toolbox/MASTER.md`
- 嵌入契約：Hub 以 `?theme=`／`?embedded=` 傳主題與嵌入模式，工具隱藏自身頂部列；`tool.json` 新增 `uiKitTarget`
- 三工具 pin 為 TOOL-SPEC v1 合規版：Git-Ref-Manager v3.1.1、Opencode-Cfg-Manager v1.1.1、Key-Manager v1.1.1

### 其他
- Hub UI 無障礙與 polish：頂部列標題改用 `<h1>`、`meta theme-color` 隨主題更新、
  確認框 Tab focus trap 與關閉後焦點還原、`?tool=<id>` 深連結、側欄移除誤用的 `role="toolbar"`

## [0.1.0] - 未發布

### 新增
- 工具規格 `spec/TOOL-SPEC.md` 與 `spec/tool.schema.json`（specVersion 1）。
- 共用樣式 `ui-kit/ui-kit.css` 1.0.0、`ui-kit/cli-kit.ps1` 1.0.0 與同步腳本 `Sync-UiKit.ps1`。
- `hub/hub.ps1`：`list`、`doctor` 指令。
- gitleaks 設定與 GitHub Actions。

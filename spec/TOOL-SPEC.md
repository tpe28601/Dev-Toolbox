# Dev-Toolbox 工具規格（specVersion 1）

本文件是 Dev-Toolbox 底下每個工具都要遵守的介面規格。Hub 只依賴本文件定義的東西，不依賴任何工具的內部實作。

## 1. 原則

- 每個工具是獨立 repo，單獨 clone 就能用，不依賴 Hub 或其他工具。
- 每個工具都有 Web 版與 CLI 版，兩者呼叫同一份 core。
- Web 伺服器只綁定 `127.0.0.1`。
- 使用者資料放在 `%LOCALAPPDATA%\DevToolbox\<id>\`，不放在工具資料夾。
- repo 內不得含任何公司或個人環境資訊（路徑、專案名稱、內部網址、IP、金鑰）。

## 2. 目錄

```text
<Tool>/
  tool.json          工具描述檔（必要）
  README.md
  CHANGELOG.md
  LICENSE            MIT
  .gitignore
  Run-CLI.bat        （或沿用既有檔名，於 tool.json 指定）
  Run-Web.bat
  core/  cli/  web/  ui/  tests/  examples/
```

既有工具可以先保留原本的檔名，只要 `tool.json` 的入口寫對即可。

## 3. tool.json

格式見 `tool.schema.json`。範例：

```json
{
  "specVersion": 1,
  "kind": "tool",
  "id": "git-ref-manager",
  "name": "Git Ref Manager",
  "version": "3.1.0",
  "description": "Git ref / origin / worktree 管理",
  "runtime": { "kind": "powershell", "min": "5.1" },
  "web": { "entry": "Git-Ref-Manager-Web.ps1", "defaultPort": 8756, "health": "/api/health" },
  "cli": { "entry": "Git-Ref-Manager.ps1", "menu": true, "json": false },
  "requires": ["git"],
  "dataDir": "%LOCALAPPDATA%/DevToolbox/git-ref-manager"
}
```

- `id`：小寫英數與連字號，全域唯一，也是資料夾名稱。
- `version`：SemVer，記錄目前開發版號。正式發布時，該提交的版號須與 Git tag（如 `v3.1.0`）及 CHANGELOG 一致。
- `runtime.kind`：`powershell`、`python` 或 `exe`。
- `web` 與 `cli` 至少要有一個：沒有 Web 介面（如 GUI／純批次工具 HLK Viewer）可省略 `web`，
  Hub 列表會顯示「只有 CLI」並引導 `hub run <id>`；兩者皆省則不合規格。無持久化資料的工具可省略 `dataDir`。
- `web.exe`（選填）：打包好的執行檔；Hub 優先使用，找不到才依 `runtime` 執行 `web.entry`。
- `runtime.kind = python` 時，Hub 依序尋找直譯器：環境變數 `DEVTOOLBOX_PYTHON` →
  工具資料夾的 `.venv\Scripts\python.exe` → `py` 啟動器 → PATH 上的 `python`（跳過 WindowsApps 佔位程式）。
  Web 模式入口應只用標準函式庫，必要第三方套件要有退回路徑（例如 Key-Manager 產生金鑰改用本機 `ssh-keygen`）。

### Port 分配

| 工具 | 預設 port |
| --- | --- |
| Hub | 8700 |
| Agents-Cfg-Manager | 8712 |
| Key-Manager | 8730 |
| Build Runner | 8740 |
| Git-Ref-Manager | 8756 |

沒有明確指定 port 時，從預設 port 往上找（最多 +20）；都不能用就綁 port 0，請系統配一個空的 port。
明確指定 port 而綁不上時直接失敗（exit 5），不自動換。
錯誤訊息要分清楚「port 被 Windows 保留」（WSAEACCES 10013，Hyper-V／WSL／Docker 常見）與「port 被其他程式佔用」（WSAEADDRINUSE 10048）。
Hub 啟動工具時不指定 port，由工具自己找，實際 port 從 READY 行讀回。

## 4. CLI

### 共通參數

| 參數 | PowerShell 寫法 | 作用 |
| --- | --- | --- |
| `--help` | `-Help` | 列出用法 |
| `--version` | `-Version` | 印出 tool.json 的版本後結束 |
| `--profile <名稱>` | `-Profile` | 載入設定檔 |
| `--dry-run` | `-DryRun` | 只預覽，不寫入 |
| `--yes` | `-Yes` | 略過確認；不可逆動作沒有它就一定要問 |
| `--json` | `-Json` | 結果以 JSON 輸出到 stdout，訊息改走 stderr |
| `--data-dir <路徑>` | `-DataDir` | 覆寫資料夾 |
| `--no-color` | `-NoColor` | 關閉色彩 |

工具不一定要一次實作全部參數，但已實作的必須照這個名稱與意義。

### Exit code

| 代碼 | 意義 |
| --- | --- |
| 0 | 成功 |
| 1 | 執行失敗 |
| 2 | 成功，但有略過項（衝突、跳過的項目） |
| 3 | 參數或輸入不正確 |
| 4 | 使用者取消 |
| 5 | 環境不符（缺 git、gpg，或版本太舊） |

0、1、2 與 Git-Ref-Manager 3.0 的定義相同。

### --json 輸出

```json
{ "ok": true, "tool": "git-ref-manager", "command": "sync", "dryRun": false,
  "result": {}, "warnings": [], "error": null }
```

失敗時 `error` 為 `{ "code": "DF_CONFLICT", "message": "…", "detail": {} }`。`code` 用大寫加底線，CLI 與 Web 共用。

## 5. Web

### 啟動參數

| 參數 | PowerShell 寫法 | 作用 |
| --- | --- | --- |
| `--port <n>` | `-Port` | 指定 port |
| `--open-browser` | `-OpenBrowser` | 啟動後開瀏覽器（雙擊 bat 時使用；Hub 啟動時不帶） |
| `--parent-pid <pid>` | `-ParentPid` | 父行程結束就自動關閉 |
| `--data-dir <路徑>` | `-DataDir` | 覆寫資料夾 |
| `--hub-origin <url>` | `-HubOrigin` | Hub 的實際網址（如 `http://127.0.0.1:8700`），允許它嵌入與送出請求；沒給時預設 8700 |

啟動完成後，stdout 印出一行 `READY http://127.0.0.1:<port>`，Hub 以此判定啟動成功。這一行之前不得有其他 stdout 輸出。

PowerShell 工具的 Web 伺服器請用 `System.Net.HttpListener`（http.sys），不要自己用 `TcpListener` 解析 HTTP：部分防毒或端點防護會重設這類連線，瀏覽器只收到一半的頁面（`ERR_CONNECTION_RESET`）。Python 工具用標準函式庫的 `ThreadingHTTPServer` 即可。

### 共通 API

| 方法與路徑 | 用途 |
| --- | --- |
| `GET /api/health` | `{ ok, id, version, pid, port, uptimeSec }` |
| `GET /api/info` | tool.json 內容加上 `dataDir`（實際位置） |
| `POST /api/shutdown` | 關閉伺服器（選填） |

背景工作、profile、歷史紀錄的 API 目前各工具自訂，下一版規格再統一路徑。

錯誤回應：`{ "ok": false, "error": { "code", "message", "detail" } }`。

### 安全規則（每個工具都要做）

1. 只綁定 `127.0.0.1`。
2. `Host` 標頭必須是 `127.0.0.1:<port>` 或 `localhost:<port>`（防 DNS rebinding）。
3. 非 GET／HEAD 請求：
   - 必須帶 `X-Toolbox-Request: 1`（強制瀏覽器先做 CORS preflight，其他網頁無法直接觸發）。
   - 若有 `Origin`，必須是自己或 Hub 的位址（`--hub-origin` 給的網址，沒給時為 `http://127.0.0.1:8700`、`http://localhost:8700`）。
   - 不回應 CORS preflight，也不送 `Access-Control-Allow-*` 標頭。
4. `Content-Type` 必須是 `application/json`；body 上限 1 MB。
5. 回應加上：
   - `X-Content-Type-Options: nosniff`
   - `Content-Security-Policy: frame-ancestors 'self' <Hub 位址的 127.0.0.1 與 localhost 兩種寫法>`
   - `Referrer-Policy: no-referrer`
6. 靜態檔案用寫死的白名單，不用路徑拼接。
7. 刪除、覆蓋等不可逆動作由後端確認（請求帶 `confirm`），不能只靠前端 `confirm()`。
8. 外部程式一律用參數陣列呼叫，不經 shell 字串。

違反第 2、3 條回 `403`，`error.code` 為 `FORBIDDEN_HOST`、`FORBIDDEN_ORIGIN` 或 `MISSING_TOOLBOX_HEADER`。

### 背景工作

超過約 1 秒的動作不可在 HTTP 迴圈裡同步執行，要交給子行程或執行緒，前端輪詢結果。同一時間只允許一個會寫入的工作，第二個回 `409 JOB_BUSY`。

## 6. 資料存放

```text
%LOCALAPPDATA%\DevToolbox\<id>\
  settings.json
  profiles\<名稱>.json、profiles\_last.json
  history.jsonl
  jobs\<jobId>.log
  backups\
```

優先順序：`--data-dir` > 環境變數 `DEVTOOLBOX_DATA`（加上 `\<id>`）> `%LOCALAPPDATA%\DevToolbox\<id>`。

舊版放在工具資料夾裡的資料，第一次啟動時複製到新位置（不刪除舊檔）。

寫入規則：設定檔用「暫存檔 + 改名」；文字檔 UTF-8 無 BOM；`.ps1` 本身要有 BOM。

## 7. UI 風格

- 每個工具的前端目錄（預設 `ui/`，可用 `tool.json` 的 `uiKitTarget` 指定別處）放一份 ui-kit 複本：`ui-kit.css`、`tb-theme.js`、`tb-icons.js`。正本在 Dev-Toolbox 的 `ui-kit/`，用 `Sync-UiKit.ps1` 同步（同時更新 `tool.json` 的 `uiKit` 版本）；`ui-kit.css` 連結在自己工具的 css 之前。元件外觀可參考 `ui-kit/demo/demo.html`。
- 工具專屬樣式寫在自己的 css，不改 ui-kit 複本；顏色一律用 `--tb-*` token（可定義自己的短名稱當別名），不要寫死色碼，深淺色與強調色才會一致。
- 主題：`<head>` 內、css 之後同步載入 `tb-theme.js`，由它設定 `<html data-theme="light|dark">` 與 `data-accent`。優先順序：網址參數 `?theme=light|dark|system&accent=blue|green|violet|orange|rose` > 工具自己記住的選擇 > 跟隨系統＋藍色。
- Hub 切換主題時，會對 iframe 送 `postMessage({ type: 'tb-theme', mode, accent })`；`tb-theme.js` 已處理，工具不必重新載入。工具自己的主題鈕請用 `TbTheme.set()`，並監聽 `tb-theme-change` 事件更新按鈕。
- 圖標：統一用 Lucide（`tb-icons.js`，ISC 授權），寫 `<i data-tb-icon="名稱" data-anim="spin|bounce|wiggle|pop|nudge|draw">`，或在 JS 用 `TbIcons.svg(名稱)`。不要再混用其他圖標集。
- 互動：按鈕、清單列、卡片滑過時要有邊框或光暈變化，圖標可搭配上面的小動畫；尊重 `prefers-reduced-motion`。
- 窄視窗：寬度縮到 400px 仍不能出現整頁水平捲動或內容被切掉；側欄先縮成圖標列，再改成頂部橫列（`tb-shell` 已內建）。
- 嵌入：Hub 會加網址參數 `?embedded=1`（`tb-theme.js` 會設 `<html data-embedded>`），工具必須隱藏自己的頂部列或品牌名稱與主題切換鈕（可加 `tb-hide-embedded` class），Hub 已提供外框。
- PowerShell CLI 共用 `cli-kit.ps1`（標題、選單、顏色、確認提示）。

## 8. 版本

版號格式為 `MAJOR.MINOR.PATCH`。三段都是獨立的非負整數，各段都可以超過 9，達到 10 時照常遞增。例子包括 `9.2.3 → 10.0.0`、`0.9.12 → 0.10.0`、`0.8.9 → 0.8.10`。

### 8.1 日常提交

- **日常提交可升 PATCH。** 修正錯誤、補齊基本功能、增加小型操作或調整介面時，每次提交可把受影響元件的 PATCH 加一。例如 `0.8.3 → 0.8.4 → 0.8.5`。
- 同一筆提交包含多項改動時，該元件只加一次。只改開發文件、註解或測試的提交可沿用原版號。
- 使用者可感知的變更累積在各自 `CHANGELOG.md` 的 `[Unreleased]`。ui-kit 的變更記在 Dev-Toolbox 根目錄的 `CHANGELOG.md`。開發版號可先更新，正式發布時再建立 tag。

### 8.2 重大更新

- **重大功能或工作流程改版才升 MINOR。** 中間一段加一，PATCH 歸零，例如 `0.8.12 → 0.9.0`。以功能與流程的影響判斷時機。
- **MAJOR 保留給明確的大版發布。** 例如正式定版 `1.0.0`，或穩定版的既有 CLI、API、`tool.json` 格式或資料有不相容的變更。

### 8.3 Hub、工具與 ui-kit 各自發布

- 各工具在自己的 repository 累積變更並獨立發布。Hub 的 submodule 一律指向工具 tag 對應的提交。多個工具的 pin 更新可累積到同一個 Hub 發布批次。
- Hub 的版號隨自身變更或工具 pin 更新調整。工具自行發布時，Hub 可在後續提交再納入。
- ui-kit 使用自己的版本。更新共用元件版號時，修改正本 `ui-kit.css` 第一行的版本，並用 `Sync-UiKit.ps1` 同步檔案與各工具 `tool.json` 的 `uiKit` 欄位。工具可在自己的下一次發布一併交付同步結果。

### 8.4 發布步驟

1. 例行發布可直接採用本批最後的 PATCH 開發版號。重大更新依第 8.2 節調整該 Hub 或工具的 `tool.json` 的 `version`。
2. 將 `[Unreleased]` 中本次要發布的項目移入對應版號與日期的區段。
3. 驗證後在發布提交上建立同版號的 `vX.Y.Z` tag，確認 manifest、CHANGELOG 和 tag 一致。已發布的版號與 tag 保留原樣。

- 授權：MIT。

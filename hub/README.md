# hub/

Dev-Toolbox Hub：本機工具主控台（只綁 127.0.0.1）。

- `hub.ps1`：CLI／互動選單（`list`、`doctor`、`run`、`web`）。上層 `Run-Hub.bat` 進入。
- `Hub-Web.ps1`：Web 主控台（HttpListener，port 8700 起自動找）。純 PowerShell，規格見
  `spec/TOOL-SPEC.md`。啟動時若偵測到既有 Hub 實例，會直接開瀏覽器連舊實例並結束
  （除錯要硬開第二實例加 `-Force`）。
- `ui/`：前端（ui-kit 3.1）。

## 頁面

- **總覽**（預設首頁，`?page=dash`）：工具卡片牆；每張卡可直接啟動／停止／新視窗開啟，
  頂部摘要列有執行中工具數與 Hub 運行時間。
- **工具頁**（`?tool=<id>`）：執行中以 iframe 嵌入工具畫面（keep-alive，切頁不重建），
  並經 postMessage 同步深淺色／強調色；停止中顯示工具資訊卡。
- **設定**（`?page=settings`）：深淺色、強調色、主題風格（8 色系：純色／光暈／網格／點陣／
  暮色／森林／黑白／霓虹，改整個 Hub 色調與紋理，可用 `?bg=` 預覽）與風格強度
  （明顯／內斂，`?strength=`）、Python 直譯器來源。風格只影響 Hub，嵌入工具不受影響。

## API（皆只對本機 origin 開放）

- `GET /api/health`、`GET /api/info`、`GET /api/tools`、`GET /api/settings`、`GET /api/python`
- `POST /api/tools/start`、`POST /api/tools/stop`（需 `X-Toolbox-Request: 1` + JSON）
- `POST /api/settings`、`POST /api/python/check`、`POST /api/shutdown`

資料夾：`%LOCALAPPDATA%\DevToolbox\dev-toolbox-hub`（`settings.json`、啟動工具 stdout/stderr 於 `jobs\`）。

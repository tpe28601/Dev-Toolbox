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
- `POST /api/tools/update/check`（`id`）、`POST /api/tools/update/apply`（`id`、`version`、`restart`）
- `POST /api/settings`、`POST /api/python/check`、`POST /api/shutdown`

資料夾：`%LOCALAPPDATA%\DevToolbox\dev-toolbox-hub`（`settings.json`、啟動工具 stdout/stderr 於 `jobs\`）。

## 工具更新

開啟工具頁會自動檢查該工具的公開 Releases，支援 Agents Cfg Manager、Build Runner、Git Ref Manager、Key Manager 和 HLK Viewer。有相容的正式版才會顯示「下載更新」。確認後才會下載。若工具由 Hub 啟動，Hub 會在套件驗證完成後停止工具、切換版本並重啟。新版啟動檢查失敗時會切回原本版本。在 Hub 外啟動的 Web 服務須先手動關閉。

Hub 和 `Run-Hub.bat` 共用資料目錄下的 `tool-updates\`。每份 Toolbox 安裝有自己的更新目錄，Git checkout 和工具的使用者資料保留。新版 ZIP 需要包含實際執行所需的工具檔案；Python 工具使用 Hub 設定的直譯器、環境變數或系統 Python。若依賴原本工具目錄下的 `.venv`，請在 Hub 設定中指定可用的 Python。

### 發布可更新的 ZIP

1. 在工具自己的 repo 發布正式 Release，tag 用 `vX.Y.Z`，套件根目錄的 `tool.json` 版號用 `X.Y.Z`。Release 說明會顯示在 Hub 的確認視窗。
2. 上傳自備 ZIP，檔名為 `<tool-id>-X.Y.Z.zip`，大小上限 100 MB。解壓後根目錄直接包含 `tool.json` 和 Web／CLI 入口及其執行所需檔案。GitHub 自動產生的 Source code ZIP 有外層資料夾，請另外上傳符合此格式的套件。
3. 將 ZIP asset 的 label 設成 `min-hub=X.Y.Z`，版本填最低相容的 Hub 版本。Hub 以 GitHub 回傳的 asset SHA-256 和大小驗證下載。

在 Toolbox 根目錄執行下列指令，會從各 repo 已提交的版本打包，並驗證 ZIP 可供更新器使用。輸出在 `dist/updates/`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Pack-Updates.ps1
```

只打包單一工具時，加上 `-Package build-runner`。要從指定 tag 重建時，再加上 `-Ref v0.5.1`，版號請換成該工具已建立的 tag。每個 ZIP 的收錄路徑列在 `Pack-Updates.ps1` 的 `$packages`。例如 Build Runner 的 ZIP 附件標籤可設為 `min-hub=0.4.0`。

### Hub 本身的更新

開啟 Hub 的「設定」頁會檢查 Toolbox 的公開 Releases。確認更新後，新 Hub 通過啟動檢查才會關閉舊 Hub 和它啟動的工具，瀏覽器會切到新版。原本的 `Open-Web.bat` 與 `Run-Hub.bat` 會載入已啟用的 Hub 版本。

在 Dev-Toolbox 的正式 Release 上傳 `dev-toolbox-X.Y.Z.zip`，套件根目錄包含同版號的 `tool.json`、`hub/` 和 `ui-kit/`。Hub 套件不需要 `min-hub` 標籤。新版 Hub 會沿用原安裝目錄的工具及各自已下載的版本。

### 工具獨立啟動時更新

五個工具的獨立 Web 介面會在開啟時自動檢查，有新版才顯示下載圖示。HLK Viewer 和 Key Manager 的 Windows 桌面視窗也會自動檢查。確認安裝後，關閉工具，再用原本的啟動檔開啟新版。工具在 Toolbox 的 `tools/` 內時，獨立啟動與 Hub 共用已安裝的版本。

發布前從 Toolbox 執行 `powershell -NoProfile -ExecutionPolicy Bypass -File ui-kit\Sync-UiKit.ps1 -StandaloneOnly`。工具 ZIP 要包含同步後的更新程式、介面檔案和原本的啟動檔。工具的 Release 沿用上方的 ZIP 命名與 `min-hub` 標籤。

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

- **管理工具**（`?page=manage`）：安裝官方工具、匯入本機工具資料夾、新增網站連結，以及設定項目是否顯示在總覽和側邊欄。匯入官方工具後，Hub 和工具自己的啟動檔共用其更新版本。

## API（皆只對本機 origin 開放）

- `GET /api/health`、`GET /api/info`、`GET /api/tools`、`GET /api/settings`、`GET /api/python`
- `POST /api/tools/start`、`POST /api/tools/stop`（需 `X-Toolbox-Request: 1` + JSON）
- `POST /api/tools/update/check`（`id`）、`POST /api/tools/update/apply`（`id`、`version`、`restart`）
- `POST /api/tools/library`（安裝清單的匯入、連結及顯示設定）、`POST /api/tools/folder`（選取本機資料夾）
- `POST /api/settings`、`POST /api/python/check`、`POST /api/shutdown`

資料夾：`%LOCALAPPDATA%\DevToolbox\dev-toolbox-hub`（`settings.json`、啟動工具 stdout/stderr 於 `jobs\`）。

## 工具更新

開啟工具頁會自動檢查該工具的公開 Releases，支援 Agents Cfg Manager、Build Runner、Git Ref Manager、Key Manager、HLK Viewer 和 Script Editor。有相容的正式版才會顯示「下載更新」。確認後才會下載。若工具由 Hub 啟動，Hub 會在套件驗證完成後停止工具、切換版本並重啟。新版啟動檢查失敗時會切回原本版本。在 Hub 外啟動的 Web 服務須先手動關閉。

Hub 和 `Run-Hub.bat` 共用資料目錄下的 `tool-updates\`。每份 Toolbox 安裝有自己的更新目錄，Git checkout 和工具的使用者資料保留。新版 ZIP 需要包含實際執行所需的工具檔案；Python 工具使用 Hub 設定的直譯器、環境變數或系統 Python。若依賴原本工具目錄下的 `.venv`，請在 Hub 設定中指定可用的 Python。

### 發布可更新的 ZIP

1. 在工具自己的 repo 發布正式 Release，tag 用 `vX.Y.Z`，套件根目錄的 `tool.json` 版號用 `X.Y.Z`。Release 說明會顯示在 Hub 的確認視窗。
2. 上傳自備 ZIP，檔名為 `<tool-id>-X.Y.Z.zip`，大小上限 100 MB。解壓後根目錄直接包含 `tool.json` 和 Web／CLI 入口及其執行所需檔案。GitHub 自動產生的 Source code ZIP 有外層資料夾，請另外上傳符合此格式的套件。
3. 把同版號的 `<tool-id>-X.Y.Z.update.json` 和 ZIP 一起上傳到同一個 Release 的 Assets。JSON 記錄版號、ZIP 檔名和最低相容 Hub 版本。更新器會用 GitHub 回傳的 SHA-256 和檔案大小驗證下載。

在 Toolbox 根目錄執行下列指令，會從各 repo 已提交的版本打包，並驗證 ZIP 可供更新器使用。輸出在 `dist/updates/`。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Pack-Updates.ps1 -PythonHome C:\Path\To\Python312 -Wheelhouse C:\Path\To\WindowsWheels
```

只打包單一工具時，加上 `-Package build-runner`。要從指定 tag 重建時，再加上 `-Ref v0.5.1`，版號請換成該工具已建立的 tag。工具套件預設支援 Hub 0.4.0 以上，需要更高版本時加上 `-MinHub X.Y.Z`。每個 ZIP 的收錄路徑列在 `Pack-Updates.ps1` 的 `$packages`。

`-PythonHome` 需要完整的 Windows CPython 3.11 以上（含 Tcl/Tk）。Build Runner、HLK Viewer、Key Manager 和 Script Editor 的 ZIP 會附帶 Python。Key Manager 的 `-Wheelhouse` 需放入與該 Python 版本及架構相容的 `.whl`，包含 `pyproject.toml` 宣告的依賴與間接依賴。打包從本機 Wheelhouse 安裝，執行端不用裝 Python 或執行 pip。只打包 Hub、Agents Cfg Manager 或 Git Ref Manager 時，不必提供這兩個參數。

`-WorkingTree` 可從目前工作目錄製作本機試用包。公開發版請使用已提交的版本，並以各 repo 的新版 tag 分開打包。

Hub 0.4.4 從完整版取出的 Python 存在 `%LOCALAPPDATA%\DevToolbox\shared-python`，有設定 `DEVTOOLBOX_DATA` 時則放在該目錄下。下一個工具能使用相容的共用 Python 時，Hub 會選擇輕量版。新版獨立啟動檔也會找這個目錄。Key Manager 的輕量 ZIP 在用完整打包流程產出時，會包含自己的 Python 相依套件，並記錄所需的 Python 版本和平台。

「管理工具」可以解除安裝 Hub 下載的工具，保留其資料及共用 Python。官方工具的「清除資料」會在確認視窗列出目前使用的預設資料目錄。請先關閉工具的所有視窗。設定頁的「重設 Hub 設定」會清除外觀、指定的 Python 路徑、匯入清單、連結與顯示偏好。

Python 工具預設會另外產生 `<tool-id>-X.Y.Z-lite.zip`，可與內附 Python 的 ZIP 和更新 JSON 一起發布。Hub 0.4.3 會檢查本機 Python 3.11 以上和工具所需的套件，相容時使用輕量版，否則選擇完整版。Key Manager 也會檢查 pywebview、bcrypt 和 cryptography。確認視窗會顯示選中的套件及大小。

若目前只能發布輕量版，可對單一 Python 工具使用 `-LiteOnly` 和獨立的輸出資料夾，再上傳輕量 ZIP 和對應 JSON。這類 Release 需要 Hub 0.4.3 以上及已符合需求的本機 Python。獨立工具的自動更新仍下載完整版。

支援 JSON 的更新器會優先使用它，並繼續接受只有 `min-hub=X.Y.Z` Label 的舊更新。每個工具第一次發布含新版更新器的套件時，可同時保留這個 Label，讓已安裝的舊更新器也能看到該次更新。

### Hub 本身的更新

開啟 Hub 的「設定」頁會檢查 Toolbox 的公開 Releases。確認更新後，新 Hub 通過啟動檢查才會關閉舊 Hub 和它啟動的工具，瀏覽器會切到新版。原本的 `Open-Web.bat` 與 `Run-Hub.bat` 會載入已啟用的 Hub 版本。

在 Dev-Toolbox 的正式 Release 上傳 `dev-toolbox-X.Y.Z.zip` 和 `dev-toolbox-X.Y.Z.update.json`。套件根目錄包含同版號的 `tool.json`、`hub/` 和 `ui-kit/`。Hub 的 JSON 只需記錄版號和 ZIP 檔名。新版 Hub 會沿用原安裝目錄的工具及各自已下載的版本。

### 工具獨立啟動時更新

官方工具的獨立 Web 介面會在開啟時自動檢查，有新版才顯示下載圖示。HLK Viewer 和 Key Manager 的 Windows 桌面視窗也會自動檢查。確認安裝後，關閉工具，再用原本的啟動檔開啟新版。工具在 Toolbox 的 `tools/` 內時，獨立啟動與 Hub 共用已安裝的版本。

發布前從 Toolbox 執行 `powershell -NoProfile -ExecutionPolicy Bypass -File ui-kit\Sync-UiKit.ps1 -StandaloneOnly`。工具 ZIP 要包含同步後的更新程式、介面檔案和啟動檔，並與上方的 JSON 一起上傳。

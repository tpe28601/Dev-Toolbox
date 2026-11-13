# Dev-Toolbox

把 Windows 開發工具整合成一個入口，同時保留每個工具單獨使用的能力。

| 工具 | 用途 | 語言 |
| --- | --- | --- |
| [Git-Ref-Manager](https://github.com/tpe28601/git-ref-manager) | Git ref、origin、worktree 管理 | PowerShell |
| [Agents Cfg Manager](https://github.com/tpe28601/cfg-manager) | AI agent 設定檔打包、還原、部署 | PowerShell |
| [Key-Manager](https://github.com/tpe28601/key-manager) | SSH、GPG 金鑰管理 | Python |
| [Build Runner](https://github.com/tpe28601/build-runner) | 本機建置、Recipe、Log、產出物與排程 | Python |
| [HLK Viewer](https://github.com/tpe28601/hlk-viewer) | Windows HLK 測試結果檢視與報表匯出（tkinter GUI，CLI-only 納入） | Python |

## 安裝

```bat
git clone https://github.com/tpe28601/Dev-Toolbox.git
cd Dev-Toolbox
Setup.bat
```

需要：Windows 10/11、Git for Windows、Windows PowerShell 5.1 以上。

`Setup.bat` 預設安裝公開工具，略過 private 的 HLK Viewer 和 Script Editor。已有 Dev-Toolbox clone 時，在該資料夾執行新版 `Setup.bat` 即可繼續安裝。Hub 會依各工具的 `tool.json` 自動載入。

有 private repo 的 GitHub 存取權限時，可執行 `Setup.bat --include-private` 安裝所有工具。只安裝公開工具時，最後的環境檢查會顯示 private 工具尚未初始化。

## 使用

在檔案總管雙擊 `Open-Web.bat`，即可啟動 Web Hub 並在預設瀏覽器開啟。要停止服務，請在啟動視窗按 `Ctrl+C`。

| 指令 | 作用 |
| --- | --- |
| `Run-Hub.bat` | 互動選單 |
| `Run-Hub.bat list` | 列出工具與版本 |
| `Run-Hub.bat doctor` | 檢查環境、submodule、ui-kit 版本 |
| `Run-Hub.bat web` | 啟動 Web Hub 主控台（port 8700）並開瀏覽器 |
| `Run-Hub.bat run git-ref-manager -Auto -Src <A> -Dst <B>` | 直接呼叫某個工具的 CLI，回傳它的 exit code |

Web Hub（`hub/Hub-Web.ps1`，port 8700）可在瀏覽器中啟動／停止各工具、切換頁面，深淺主題會同步傳給工具（`?theme=`、`?embedded=`）。每個工具仍可脫離 Hub 單獨使用（CLI 或各自的 Web 模式）。

## 目錄

```text
spec/        工具規格（TOOL-SPEC.md）與 tool.json 的 JSON Schema
ui-kit/      共用樣式正本：ui-kit.css、cli-kit.ps1、Sync-UiKit.ps1
hub/         Hub 本身
tools/       工具（Git submodule）
```

## 開發規則

- 新工具或改版前先讀 [spec/TOOL-SPEC.md](spec/TOOL-SPEC.md)。
- 共用樣式只改 `ui-kit/` 的正本，再執行 `ui-kit\Sync-UiKit.ps1` 發到各工具，然後到各 submodule 分別 commit。
- 使用者資料一律放 `%LOCALAPPDATA%\DevToolbox\<id>\`，不得進 repo。
- commit 前用 gitleaks 檢查：`gitleaks git`；公司專用關鍵字放在 `.gitleaks.local.toml`（不進 repo）。

## 授權

MIT，見 [LICENSE](LICENSE)。

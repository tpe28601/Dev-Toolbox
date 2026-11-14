# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本遵循 SemVer。

## [Unreleased]

## [0.5.0]

### 新增
- 主題風格大改：預設改為「石墨」（中性灰，藍色只用在強調色）；新增暖灰、冷灰藍、高對比、純黑，以及質感風格液態玻璃、磨砂、金屬、珠光；原配色保留為「經典」。強調色可與任何風格搭配，所有風格深淺色文字對比都 ≥ 4.5:1。拿掉「風格強度」設定（一律明顯）。
- 自訂圖示：工具與網站連結都能換成圖示（約 70 個可搜尋，中英文皆可）、emoji、上傳圖片（PNG／SVG／ICO，小於 256 KB，存在 Hub 資料夾），網站連結可按「抓取」下載網站圖示。上傳的 SVG 含腳本或外部內容時拒收。
- 總覽分成「工具」與「連結」兩區，連結卡與工具卡同版型（圖示、網站連結、網域），整張可點。
- 外部啟動（不是 Hub 開的）工具也能從 Hub 停止：先請工具自己關閉，沒有回應才結束「確實是這個工具」的行程（PID 與工具回報一致、命令列含工具資料夾），比對不上就拒絕。
- 工具畫面無法嵌入（工具只允許其他 Hub 嵌入）或 10 秒沒有載入時，改顯示說明卡與「在新視窗開啟」「重新載入」。
- 安裝／更新視窗：「在 GitHub 查看」開該版本的 Release 頁；版本說明支援基本 Markdown（以 DOM 建立，不會被注入）。
- 側欄可收合成圖示列（記住狀態），收合後點 logo 展開。

### 變更
- 側欄整理：上方只留總覽與工具清單，下方依序為管理工具、主題、設定、關閉 HUB；目前所在頁的指示線每一頁都看得到；工具清單不顯示捲軸、改用上下淡出提示。
- 管理工具每列固定為［開啟／安裝］［顯示在 Hub］［⋯］，編輯、移除、解除安裝、清除資料移到「⋯」選單；清除資料只在有資料時出現。三個頁面共用頁首與邊距。
- 窄螢幕上方列固定一行、可橫向捲動並有淡出提示，換頁時自動捲到目前項目。
- 工具未啟動時工具列直接有「啟動」，用不到的按鈕隱藏；外部啟動的工具標示「外部啟動」。
- 設定：Python 路徑完整顯示可複製；「重設 Hub 設定」移到「進階」卡片並說明清除範圍。
- 對話框跟著主題風格，確認框圖示依情境上色；圖示加上簡短的滑過動態（遵守「減少動態」）。
- Opencode Cfg Manager 改名為 Agents Cfg Manager（v1.2.0）：子模組資料夾改為 `tools/Agents-Cfg-Manager`，子模組名稱同步更新，GitHub repo（`tpe28601/cfg-manager`）不變；工具 id 改為 `agents-cfg-manager`，Hub 的圖示對應與「最近的工作」讀取路徑一併更新。舊資料夾 `%LOCALAPPDATA%\DevToolbox\opencode-cfg-manager` 會在工具第一次啟動時複製到 `agents-cfg-manager`（舊資料夾保留）。
- Build Runner 的工具說明改為中文。

### 修正
- Hub 不再被單一請求卡住：啟動／停止工具、選資料夾、檢查 GitHub 更新改為背景處理，等待時其他請求照常回應（離線時開工具頁不再讓整個 Hub 卡 12 秒）。
- 工具清單查詢從約 1.6 秒降到 0.05 秒（改查系統監聽表，不再對每個停止中的工具試連線），按鈕不再常常延遲。
- 匯入本機工具的「瀏覽…」：資料夾選擇視窗一定出現在最前面，等待時有提示與「取消選擇」，路徑可直接貼上。
- 「顯示在 Hub」開關按下立即切換，不再先跳回原位。
- 卡片不再各自做背景模糊，關閉對話框時不再頓一下。
- 總覽的「Hub 已運行」改為每秒更新，不再只在輪詢時跳動。
- 總覽在工具清單載入前顯示「讀取中…」，不再先閃「0 / 0 個工具」。
- 側欄工具名稱過長時最多換兩行，不再截成「…」。

## [0.4.4]

- 修正 Hub 更新後，在 Windows PowerShell 5.1 啟動時的語法錯誤。
- Hub 安裝的 Python 工具可共用執行環境。Key Manager 的相依套件獨立存放。
- 管理工具支援解除安裝和清除官方工具資料；設定頁支援重設 Hub 設定。

## [0.4.3]

- 窄版導覽只顯示圖示。確認下載後會顯示安裝中的狀態，直到操作完成。
- Python 工具可發布完整版和輕量版。Hub 驗證本機 Python 後自動選擇 ZIP。

## [0.4.2]

- 在「管理工具」列出 Script Editor，可從 Hub 安裝和更新。
- 開啟匯入工具或網站連結視窗時暫停工具清單輪詢。已取消的視窗不會被較晚回來的請求影響。
- 縮短安裝暫存路徑，並支援解壓 ZIP 裡超過 Windows 傳統路徑上限的檔案。
- Python 套件打包時排除各層的 `.pyc` 快取檔。

## [0.4.0] - 2026-11-12

### 新增
- Hub 總覽新增工具狀態卡、執行中工具數、Hub 運行時間與「最近的工作」。狀態卡支援啟動、停止與在新視窗開啟，近期工作可點進對應工具。
- Hub 新增「關閉 HUB」按鈕。確認後關閉 Hub，並停止由 Hub 啟動的工具。
- 新增深淺色快速切換、八種主題風格與兩種強度。支援網址參數預覽與單實例啟動。
- 納入 HLK Viewer v1.2.4 與 Script-Editor v0.1.0。HLK Viewer 支援 Web 瀏覽、分析與匯出 `.hlkx`、`.hlkp` 報告。Script-Editor 可視覺化編排並匯出批次腳本。
- Build Runner 新增 AI 分析範圍與提示詞預覽、log 下載及 `Clean + Build (-nou)` Recipe。
- ui-kit 更新到 3.2.0，新增共用資料夾與檔案挑選器、Git Repo 掃描及按鈕載入動畫。

### 變更
- 工具頁使用各自的 iframe，切頁時保留工具狀態。啟動入口集中在未啟動畫面，執行中可從工具列停止或重新載入。
- 統一工具分頁樣式並改善寬螢幕版面。總覽顯示工具的實際執行環境，重新整理與關閉按鈕靠右排列。
- 更新 Git Ref Manager、Opencode Cfg Manager、Key Manager 與 Build Runner 的 submodule pin。
- 更新版號規則。日常提交可升 PATCH，重大功能或流程改版升 MINOR，三段版號皆可超過 9。

### 修正
- Build Runner 改善長 log 開啟、搜尋與錯誤判讀。刪除歷史時一併移除 Job 目錄，並修正成功紀錄誤顯示錯誤的問題。
- Git Ref Manager 重新整理後保留分頁、捲動偏好與設定，並續追執行中的工作。
- Key Manager 修正圖示重複渲染。HLK Viewer 修正 WTL 時間戳與報表顯示。
- Hub 讀取工具歷史時允許工具同步寫入。「最近的工作」略過 Git Ref Manager 的同步預覽。

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

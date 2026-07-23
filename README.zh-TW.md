# ChatGPT Windows 一鍵安裝程式

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文

這是一個可重複執行的 PowerShell 安裝程式，用於在 Windows 上安裝 OpenAI 官方 ChatGPT 桌面應用程式。它會檢查本機環境、補齊缺少的套件管理支援、透過官方散佈管道安裝或更新 ChatGPT，並可選擇安裝 OpenAI Windows 文件建議的開發工具。

> [!IMPORTANT]
> 這是社群編寫的自動化指令碼，不是 OpenAI 或 Microsoft 官方發佈的安裝程式。指令碼只會從 Microsoft Store 或 OpenAI 託管的 Store 簽署 MSIX 網址下載 ChatGPT。

## 快速開始

1. 在 Windows 電腦上下載或複製本存放庫。
2. 按兩下 `Install-ChatGPT.cmd`。
3. 如果受信任元件的安裝程式顯示 Windows UAC 提示，請視需要核准。
4. 安裝完成後，在 ChatGPT 應用程式中登入帳號。

啟動程式透過 Windows PowerShell 5.1 執行，且只對目前處理程序使用執行原則略過，不會修改電腦或使用者層級的 PowerShell 執行原則。
啟動程式也會將目前安裝處理程序切換為 UTF-8，並統一 PowerShell 主控台與原生命令的輸入輸出編碼，避免本地化的 `winget` 和 Windows 中文訊息顯示為亂碼。
安裝過程中，Windows 會顯示整體動態進度列，終端也會保留帶時間戳的 `[PROGRESS xx%]` 進度行。指令碼會明確提示靜默安裝程式已啟動、處理程序傳回碼、驗證狀態，以及 ChatGPT 啟動要求是否已由 Windows 接收，即使沒有顯示獨立安裝視窗也能判斷目前狀態。

## 預設安裝內容

一鍵啟動程式預設選擇 `Complete` 完整模式，安裝或更新：

- ChatGPT 官方桌面應用程式
- Git
- Node.js LTS
- Python 3.14
- .NET SDK 10
- GitHub CLI

這些開發工具用於 ChatGPT/Codex 的 Git 檢閱、GitHub 整合和常見專案工作。一般 ChatGPT 對話不強制依賴這些工具。

## 系統需求

- Windows 10 1809（組建 17763）或更新版本；支援 Windows 11
- x64 或 Arm64 處理器
- 能夠存取 Microsoft 和 OpenAI 散佈端點
- `Complete` 完整模式約需 6 GB 可用空間
- `Core` 核心模式約需 1 GB 可用空間
- 一般的 Windows 互動式使用者工作階段

指令碼會主動拒絕 Windows Server 和 32 位元 x86 系統。

## 安裝程式執行流程

1. 檢查 Windows 版本、組建編號、處理器架構、磁碟空間和網路端點。
2. 尋找 `winget`；如果缺少或應用程式執行別名已損壞，嘗試從 `https://aka.ms/getwinget` 安裝或更新 Microsoft 官方 App Installer。
3. 透過 Microsoft Store 產品 ID `9PLM9XGG6VKS` 安裝或更新 ChatGPT。
4. 如果 Store 路徑失敗，從 OpenAI 下載最新的 x64 或 Arm64 Store 簽署 MSIX，並交由 Windows 驗證套件簽章和信任狀態。
5. 在 `Complete` 模式中，透過官方 `winget` 來源安裝或更新所有建議的開發工具。
6. 驗證所選元件、寫入文字記錄檔和 JSON 報告，然後啟動 ChatGPT。

指令碼支援重複執行。再次執行時，它會檢查已安裝元件並套用可用更新，不會刻意降級。

## 命令列用法

在存放庫目錄中開啟 Windows PowerShell：

```powershell
# 完整安裝，但安裝完成後不啟動 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -NoLaunch

# 只安裝或更新 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Core

# 優先使用 OpenAI 官方 MSIX 安裝 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -PreferMsix

# 只預覽預計執行的操作，不安裝任何內容
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -DryRun
```

### 參數說明

| 參數 | 作用 |
|---|---|
| `-Profile Complete` | 安裝 ChatGPT 和建議的開發工具；預設值 |
| `-Profile Core` | 只安裝或更新 ChatGPT |
| `-NoLaunch` | 安裝後不自動啟動 ChatGPT |
| `-PreferMsix` | 略過 ChatGPT 的 Microsoft Store 嘗試，使用官方 MSIX |
| `-SkipWingetBootstrap` | 缺少 `winget` 時不嘗試安裝 App Installer |
| `-SkipGitHubLogin` | GitHub CLI 未登入時不開啟瀏覽器授權 |
| `-DryRun` | 只顯示預計執行的操作，不安裝套件 |

## 外掛程式、Skills 與連接器

目前 ChatGPT Windows 應用程式已經包含外掛程式、Skills、內建瀏覽器和檔案預覽功能，不存在一個需要在 Windows 系統層級安裝的通用「ChatGPT 全外掛套件」。

應用程式安裝完成後，仍需使用者本人完成帳號相關操作：

- 登入 ChatGPT
- 在 ChatGPT 內安裝或啟用所需的外掛程式和 Skills
- 透過 OAuth 流程授權 GitHub、Google Drive 或 Slack 等連接器
- 如果組織原則有要求，取得工作區管理員核准
- 執行 `gh auth login` 啟用 GitHub CLI 整合

通用系統安裝程式無法安全地預先授權帳號存取、OAuth 授權、第三方權限或組織原則。
`Complete` 模式發現 GitHub CLI 未登入時，一鍵流程會執行 `gh auth login --web` 並自動開啟預設瀏覽器，使用者仍需親自確認授權。關閉或取消登入只會列為選用的「需要使用者操作」，不會誤報為安裝失敗。無人值守或企業部署可以使用 `-SkipGitHubLogin` 略過瀏覽器授權。

身分與權限確認節點：

| 節點 | 安裝程式行為 |
|---|---|
| Windows UAC | Windows 可能要求核准受信任安裝程式；這是權限確認，不是帳號登入 |
| Microsoft Store / WinGet | 正常安裝套件時通常不需要帳號登入 |
| GitHub CLI | 未登入時自動開啟瀏覽器授權；已登入或使用 `-SkipGitHubLogin` 時略過 |
| ChatGPT 帳號 | 自動啟動 ChatGPT；如應用程式提示，由使用者在應用程式內登入 |
| ChatGPT 連接器和外掛程式 | 每個選用服務都要在 ChatGPT 內單獨進行 OAuth 授權，並可能需要管理員核准 |

## 記錄檔與結束代碼

記錄檔和機器可讀的 JSON 報告會寫入：

```text
%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs
```

- 結束代碼 `0`：所選模式中的所有必要元件均成功
- 結束代碼 `1`：至少一個必要元件失敗

指令碼結束時，終端會分別列出「已安裝或更新」、「原本已就緒」、「安裝失敗」以及「已略過或需要後續操作」的元件，並顯示各類數量和明確的最終結論。當選用元件或開發工具失敗時，ChatGPT 本體仍可能已經安裝成功。JSON 報告也會儲存相同的逐項結果、數量以及失敗元件名稱。

Python 安裝完成後，指令碼會等待安裝註冊和 PATH 更新生效，並透過 WinGet 註冊資訊、Python Launcher（`py.exe`）、直譯器、Python 3.14 標準安裝路徑及 Windows 解除安裝註冊資訊進行多重驗證，全部無法確認時才會回報失敗。

## 安全行為

安裝程式：

- 只使用 OpenAI 或 Microsoft 文件中的 HTTPS 端點
- 使用精確套件 ID，不使用模糊的套件名稱搜尋
- 不允許安裝未簽署的 MSIX
- 不略過套件雜湊驗證
- 不重設或刪除使用者自訂的 `winget` 來源
- 不使用 `Invoke-Expression`
- 不關閉 Windows 安全設定
- 不儲存 ChatGPT、GitHub 或第三方帳號憑證
- 只刪除自己建立的處理程序專用暫存目錄

執行一鍵啟動程式會自動接受 `winget` 顯示的來源合約和套件合約。在受管理環境中使用前，請先檢閱指令碼及適用的軟體授權。

## 企業和受管理裝置

群組原則、MDM、Microsoft Store 限制、App Installer 限制、Proxy 規則或應用程式允許清單可能阻止部分安裝路徑。指令碼不會繞過組織管控。

如果安裝受到阻止：

1. 查看安裝結束時的摘要。
2. 開啟 `%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs` 中最新的記錄檔和 JSON 報告。
3. 將這些檔案交給裝置管理員或 IT 團隊。

OpenAI 也提供面向受管理環境的 Microsoft Intune/MDM 部署和 Store 簽署 MSIX 直接部署文件。

## 驗證

存放庫包含 `tests/static-check.js`，用於檢查必要的套件 ID、官方來源網址、安全限制、Windows PowerShell 5.1 的 ASCII 相容性，以及指令碼分隔符號是否平衡：

```powershell
node .\tests\static-check.js
```

指令碼是在 macOS 上編寫並完成靜態檢查的。UAC、Microsoft Store、`winget` 和 `Add-AppxPackage` 的端對端行為仍需在實際 Windows 裝置或 Windows CI 執行器上驗證。

每次推送和提取要求還會透過 `.github/workflows/validate.yml` 在 Windows 執行器上執行檢查。該工作流程會使用 Windows PowerShell 5.1 解析指令碼，並執行不會修改系統的 `Complete` 模式演練，其中包括 GitHub CLI 登入狀態檢查路徑。

## 官方參考資料

- [ChatGPT Windows 桌面應用程式](https://learn.chatgpt.com/docs/windows/windows-app)
- [部署 Windows 應用程式](https://learn.chatgpt.com/docs/enterprise/windows-deployment)
- [Windows Package Manager 文件](https://learn.microsoft.com/windows/package-manager/winget/)
- Microsoft Store 產品 ID：`9PLM9XGG6VKS`
- OpenAI x64 MSIX：<https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix>
- OpenAI Arm64 MSIX：<https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix>

## 檔案說明

| 檔案 | 作用 |
|---|---|
| `Install-ChatGPT.cmd` | 預設 `Complete` 模式的一鍵啟動程式 |
| `Install-ChatGPT.ps1` | 主要安裝和更新指令碼 |
| `README.md` | 英文說明文件 |
| `README.zh-CN.md` | 簡體中文說明文件 |
| `README.zh-TW.md` | 繁體中文說明文件 |
| `tests/static-check.js` | 跨平台靜態安全和結構檢查 |
| `.github/workflows/validate.yml` | Windows PowerShell 5.1 解析和演練 CI |

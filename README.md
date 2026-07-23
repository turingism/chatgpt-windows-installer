# ChatGPT Windows One-Click Installer

English | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

An idempotent PowerShell installer for the official ChatGPT desktop app on Windows. It checks the local environment, installs missing package-management support, installs or updates ChatGPT from official distribution channels, and optionally installs the developer tools recommended in OpenAI's Windows documentation.

> [!IMPORTANT]
> This is a community automation script, not an installer published by OpenAI or Microsoft. It downloads ChatGPT only from the official Microsoft Store or OpenAI-hosted, Store-signed MSIX URLs.

## Quick start

1. Download or clone this repository on a Windows computer.
2. Double-click `Install-ChatGPT.cmd`.
3. Approve any Windows UAC prompts shown by trusted component installers.
4. When installation finishes, sign in to the ChatGPT app.

The launcher uses Windows PowerShell 5.1 with a process-scoped execution-policy bypass. It does not change the machine-wide or user-wide PowerShell execution policy.
It also switches the installer process to UTF-8 and aligns PowerShell's console and native-command encodings, preventing localized `winget` and Windows messages from becoming garbled.

## Default installation

The one-click launcher selects the `Complete` profile and installs or updates:

- The official ChatGPT desktop app
- Git
- Node.js LTS
- Python 3.14
- .NET SDK 10
- GitHub CLI

The developer tools are recommended for ChatGPT/Codex development workflows such as Git review, GitHub integration, and running common project tasks. They are not required for ordinary ChatGPT conversations.

## Requirements

- Windows 10 version 1809, build 17763, or later; Windows 11 is supported
- x64 or Arm64 processor
- Internet access to Microsoft and OpenAI distribution endpoints
- Approximately 6 GB of free space for the `Complete` profile
- Approximately 1 GB of free space for the `Core` profile
- A normal interactive Windows user session

Windows Server and 32-bit x86 systems are intentionally rejected.

## What the installer does

1. Checks Windows edition, build, processor architecture, free disk space, and network endpoints.
2. Finds `winget`; if it is missing or its app alias is broken, attempts to install/update Microsoft's official App Installer from `https://aka.ms/getwinget`.
3. Installs or updates ChatGPT through Microsoft Store product ID `9PLM9XGG6VKS`.
4. If the Store path fails, downloads the latest x64 or Arm64 Store-signed MSIX from OpenAI and lets Windows validate its package signature and trust.
5. In the `Complete` profile, installs or updates all recommended developer tools through the official `winget` source.
6. Verifies each selected component, writes a text log and JSON report, and launches ChatGPT.

The script is safe to run again. Re-running it checks installed components and applies available updates instead of intentionally downgrading them.

## Command-line usage

Open Windows PowerShell in the repository directory:

```powershell
# Complete installation without launching ChatGPT afterward
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -NoLaunch

# Install or update only ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Core

# Prefer OpenAI's official MSIX path for ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -PreferMsix

# Preview planned actions without installing anything
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -DryRun
```

### Parameters

| Parameter | Description |
|---|---|
| `-Profile Complete` | Installs ChatGPT and the recommended developer tools; this is the default |
| `-Profile Core` | Installs or updates only ChatGPT |
| `-NoLaunch` | Does not launch ChatGPT after installation |
| `-PreferMsix` | Skips the Microsoft Store attempt for ChatGPT and uses the official MSIX |
| `-SkipWingetBootstrap` | Does not attempt to install App Installer when `winget` is missing |
| `-DryRun` | Shows the planned operations without installing packages |

## Plugins, Skills, and connectors

The current ChatGPT Windows app includes its plugin, Skills, built-in browser, and file-preview capabilities. There is no separate universal "ChatGPT plugin pack" that should be installed at the Windows level.

After the app is installed, the user must still complete account-dependent actions:

- Sign in to ChatGPT
- Install or enable the required plugins and Skills inside ChatGPT
- Authorize connectors such as GitHub, Google Drive, or Slack through their OAuth flows
- Obtain workspace-administrator approval where organizational policy requires it
- Run `gh auth login` to enable GitHub CLI integration

A generic system installer cannot safely pre-authorize account access, OAuth grants, third-party permissions, or organization policies.

## Logs and exit codes

Logs and machine-readable reports are written to:

```text
%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs
```

- Exit code `0`: every required component in the selected profile succeeded
- Exit code `1`: at least one required component failed

ChatGPT itself may still be installed when an optional or developer component fails. Check the JSON report for per-component status.

## Security behavior

The installer:

- Uses only HTTPS endpoints documented by OpenAI or Microsoft
- Uses exact package IDs instead of ambiguous package-name searches
- Does not allow unsigned MSIX packages
- Does not bypass package hash validation
- Does not reset or delete custom `winget` sources
- Does not use `Invoke-Expression`
- Does not disable Windows security settings
- Does not store ChatGPT, GitHub, or third-party credentials
- Deletes only its own process-specific temporary directory

Running the one-click launcher automatically accepts the source and package agreements presented through `winget`. Review the script and the applicable licenses before using it in a managed environment.

## Enterprise and managed devices

Group Policy, MDM, Microsoft Store restrictions, App Installer restrictions, proxy rules, or application allowlists may block one or more installation paths. The script does not bypass organizational controls.

If installation is blocked:

1. Review the final summary.
2. Open the newest log and JSON report under `%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs`.
3. Give those files to the device administrator or IT team.

OpenAI also documents Microsoft Intune/MDM deployment and direct Store-signed MSIX deployment for managed environments.

## Validation

The repository includes `tests/static-check.js`, which verifies required package IDs, official source URLs, safety constraints, ASCII compatibility for Windows PowerShell 5.1, and balanced script delimiters:

```powershell
node .\tests\static-check.js
```

The script was created and statically checked on macOS. A real Windows device or Windows CI runner is still required for end-to-end validation of UAC, Microsoft Store, `winget`, and `Add-AppxPackage` behavior.

Every push and pull request also runs `.github/workflows/validate.yml` on a Windows runner. The workflow parses the script with Windows PowerShell 5.1 and executes the non-mutating `Core` profile dry-run.

## Official references

- [ChatGPT desktop app for Windows](https://learn.chatgpt.com/docs/windows/windows-app)
- [Deploy the Windows app](https://learn.chatgpt.com/docs/enterprise/windows-deployment)
- [Windows Package Manager documentation](https://learn.microsoft.com/windows/package-manager/winget/)
- Microsoft Store product ID: `9PLM9XGG6VKS`
- OpenAI x64 MSIX: <https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix>
- OpenAI Arm64 MSIX: <https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix>

## Files

| File | Purpose |
|---|---|
| `Install-ChatGPT.cmd` | One-click launcher for the default `Complete` profile |
| `Install-ChatGPT.ps1` | Main installation and update script |
| `README.md` | English documentation |
| `README.zh-CN.md` | Simplified Chinese documentation |
| `README.zh-TW.md` | Traditional Chinese documentation |
| `tests/static-check.js` | Cross-platform static safety and structure checks |
| `.github/workflows/validate.yml` | Windows PowerShell 5.1 parsing and dry-run CI |

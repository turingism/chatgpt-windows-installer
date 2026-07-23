# ChatGPT Windows 一键安装器

[English](README.md) | 简体中文 | [繁體中文](README.zh-TW.md)

这是一个可重复执行的 PowerShell 安装器，用于在 Windows 上安装 OpenAI 官方 ChatGPT 桌面应用。它会检查本机环境、补齐缺失的包管理支持、通过官方分发渠道安装或更新 ChatGPT，并可选择安装 OpenAI Windows 文档推荐的开发工具。

> [!IMPORTANT]
> 这是社区编写的自动化脚本，不是 OpenAI 或 Microsoft 官方发布的安装程序。脚本只会从 Microsoft Store 或 OpenAI 托管的 Store 签名 MSIX 地址下载 ChatGPT。

## 快速开始

1. 在 Windows 电脑上下载或克隆本仓库。
2. 双击 `Install-ChatGPT.cmd`。
3. 如果受信任组件的安装程序弹出 Windows UAC 提示，请按需批准。
4. 安装完成后，在 ChatGPT 应用中登录账号。

启动器通过 Windows PowerShell 5.1 运行，并且只对当前进程使用执行策略绕过，不会修改计算机或用户级的 PowerShell 执行策略。

## 默认安装内容

一键启动器默认选择 `Complete` 完整模式，安装或更新：

- ChatGPT 官方桌面应用
- Git
- Node.js LTS
- Python 3.14
- .NET SDK 10
- GitHub CLI

这些开发工具用于 ChatGPT/Codex 的 Git 审查、GitHub 集成和常见项目任务。普通 ChatGPT 对话不强制依赖这些工具。

## 系统要求

- Windows 10 1809（内部版本 17763）或更高版本；支持 Windows 11
- x64 或 Arm64 处理器
- 能够访问 Microsoft 和 OpenAI 分发端点
- `Complete` 完整模式约需 6 GB 可用空间
- `Core` 核心模式约需 1 GB 可用空间
- 正常的 Windows 交互式用户会话

脚本会主动拒绝 Windows Server 和 32 位 x86 系统。

## 安装器执行流程

1. 检查 Windows 版本、内部版本号、处理器架构、磁盘空间和网络端点。
2. 查找 `winget`；如果缺失或应用执行别名已损坏，尝试从 `https://aka.ms/getwinget` 安装或更新 Microsoft 官方 App Installer。
3. 通过 Microsoft Store 产品 ID `9PLM9XGG6VKS` 安装或更新 ChatGPT。
4. 如果 Store 路径失败，从 OpenAI 下载最新的 x64 或 Arm64 Store 签名 MSIX，并交由 Windows 验证包签名和信任状态。
5. 在 `Complete` 模式中，通过官方 `winget` 源安装或更新所有推荐开发工具。
6. 验证所选组件，写入文本日志和 JSON 报告，然后启动 ChatGPT。

脚本支持重复运行。再次运行时，它会检查已安装组件并应用可用更新，不会故意降级。

## 命令行用法

在仓库目录中打开 Windows PowerShell：

```powershell
# 完整安装，但安装完成后不启动 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -NoLaunch

# 只安装或更新 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Core

# 优先使用 OpenAI 官方 MSIX 安装 ChatGPT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -PreferMsix

# 只预览计划执行的操作，不安装任何内容
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ChatGPT.ps1 -Profile Complete -DryRun
```

### 参数说明

| 参数 | 作用 |
|---|---|
| `-Profile Complete` | 安装 ChatGPT 和推荐开发工具；默认值 |
| `-Profile Core` | 只安装或更新 ChatGPT |
| `-NoLaunch` | 安装后不自动启动 ChatGPT |
| `-PreferMsix` | 跳过 ChatGPT 的 Microsoft Store 尝试，使用官方 MSIX |
| `-SkipWingetBootstrap` | 缺少 `winget` 时不尝试安装 App Installer |
| `-DryRun` | 只显示计划执行的操作，不安装软件包 |

## 插件、Skills 与连接器

当前 ChatGPT Windows 应用已经包含插件、Skills、内置浏览器和文件预览能力，不存在一个需要在 Windows 系统层面安装的通用“ChatGPT 全插件包”。

应用安装完成后，仍需用户本人完成账号相关操作：

- 登录 ChatGPT
- 在 ChatGPT 内安装或启用所需插件和 Skills
- 通过 OAuth 流程授权 GitHub、Google Drive 或 Slack 等连接器
- 如果组织策略有要求，获取工作区管理员批准
- 运行 `gh auth login` 启用 GitHub CLI 集成

通用系统安装器不能安全地预授权账号访问、OAuth 授权、第三方权限或组织策略。

## 日志与退出码

日志和机器可读的 JSON 报告会写入：

```text
%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs
```

- 退出码 `0`：所选模式中的所有必需组件均成功
- 退出码 `1`：至少一个必需组件失败

当可选组件或开发工具失败时，ChatGPT 本体仍可能已经安装成功。请查看 JSON 报告中的逐项状态。

## 安全行为

安装器：

- 只使用 OpenAI 或 Microsoft 文档中的 HTTPS 端点
- 使用精确软件包 ID，不使用模糊的软件包名称搜索
- 不允许安装未签名 MSIX
- 不绕过软件包哈希校验
- 不重置或删除用户自定义的 `winget` 源
- 不使用 `Invoke-Expression`
- 不关闭 Windows 安全设置
- 不保存 ChatGPT、GitHub 或第三方账号凭据
- 只删除自己创建的进程专用临时目录

运行一键启动器会自动接受 `winget` 展示的源协议和软件包协议。在托管环境中使用前，请先审阅脚本及适用的软件许可。

## 企业和托管设备

组策略、MDM、Microsoft Store 限制、App Installer 限制、代理规则或应用允许列表可能阻止部分安装路径。脚本不会绕过组织管控。

如果安装被阻止：

1. 查看安装结束时的汇总。
2. 打开 `%LOCALAPPDATA%\OpenAI\ChatGPTInstaller\logs` 中最新的日志和 JSON 报告。
3. 将这些文件交给设备管理员或 IT 团队。

OpenAI 还提供了面向托管环境的 Microsoft Intune/MDM 部署和 Store 签名 MSIX 直接部署文档。

## 验证

仓库包含 `tests/static-check.js`，用于检查必需的软件包 ID、官方来源地址、安全约束、Windows PowerShell 5.1 的 ASCII 兼容性以及脚本分隔符是否平衡：

```powershell
node .\tests\static-check.js
```

脚本是在 macOS 上编写并完成静态检查的。UAC、Microsoft Store、`winget` 和 `Add-AppxPackage` 的端到端行为仍需在真实 Windows 设备或 Windows CI 运行器上验证。

## 官方参考

- [ChatGPT Windows 桌面应用](https://learn.chatgpt.com/docs/windows/windows-app)
- [部署 Windows 应用](https://learn.chatgpt.com/docs/enterprise/windows-deployment)
- [Windows Package Manager 文档](https://learn.microsoft.com/windows/package-manager/winget/)
- Microsoft Store 产品 ID：`9PLM9XGG6VKS`
- OpenAI x64 MSIX：<https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix>
- OpenAI Arm64 MSIX：<https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix>

## 文件说明

| 文件 | 作用 |
|---|---|
| `Install-ChatGPT.cmd` | 默认 `Complete` 模式的一键启动器 |
| `Install-ChatGPT.ps1` | 主要安装和更新脚本 |
| `README.md` | 英文说明文档 |
| `README.zh-CN.md` | 简体中文说明文档 |
| `README.zh-TW.md` | 繁体中文说明文档 |
| `tests/static-check.js` | 跨平台静态安全和结构检查 |


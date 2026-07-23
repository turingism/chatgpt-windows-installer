#requires -Version 5.1

<#
.SYNOPSIS
Installs or updates the official ChatGPT desktop app on Windows.

.DESCRIPTION
The default Complete profile installs or updates ChatGPT and the developer
tools recommended by OpenAI: Git, Node.js LTS, Python, .NET SDK, and GitHub CLI.
The script prefers WinGet and falls back to OpenAI's Store-signed MSIX package.

This script is intentionally compatible with Windows PowerShell 5.1.
#>

[CmdletBinding()]
param(
    [ValidateSet('Complete', 'Core')]
    [string]$Profile = 'Complete',

    [switch]$NoLaunch,

    [switch]$PreferMsix,

    [switch]$SkipWingetBootstrap,

    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:ChatGPTStoreId = '9PLM9XGG6VKS'
$script:ChatGPTIdentityName = $null
$script:WingetPath = $null
$script:Results = @()
$script:TempDirectory = $null
$script:LogFile = $null
$script:ReportFile = $null
$script:HadRequiredFailure = $false
$script:LastProgressKey = ''

function Initialize-ConsoleEncoding {
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [Console]::InputEncoding = $utf8NoBom
        [Console]::OutputEncoding = $utf8NoBom
        $global:OutputEncoding = $utf8NoBom
    }
    catch {
        # Encoding setup is best-effort so restricted hosts can still run the installer.
    }
}

function Initialize-Logging {
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is unavailable. Run this installer from a normal Windows user session.'
    }

    $logDirectory = Join-Path $env:LOCALAPPDATA 'OpenAI\ChatGPTInstaller\logs'
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $logDirectory "install-$stamp.log"
    $script:ReportFile = Join-Path $logDirectory "install-$stamp.json"
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'CMD')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }

    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'CMD'   { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line }
    }
}

function Set-InstallerProgress {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$Percent,

        [Parameter(Mandatory = $true)]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    $progressText = '{0}% - {1}' -f $Percent, $Status
    $previousProgressPreference = $ProgressPreference
    try {
        $ProgressPreference = 'Continue'
        Write-Progress `
            -Id 1 `
            -Activity 'ChatGPT Windows One-Click Installer' `
            -Status $progressText `
            -CurrentOperation $Stage `
            -PercentComplete $Percent
    }
    finally {
        $ProgressPreference = $previousProgressPreference
    }

    $progressKey = '{0}|{1}|{2}' -f $Percent, $Stage, $Status
    if ($script:LastProgressKey -ne $progressKey) {
        $script:LastProgressKey = $progressKey
        $line = '[{0}] [PROGRESS {1,3}%] {2} - {3}' -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Percent, $Stage, $Status
        if ($script:LogFile) {
            Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
        }
        Write-Host $line -ForegroundColor Cyan
    }
}

function Complete-InstallerProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    Set-InstallerProgress -Percent 100 -Stage 'Complete' -Status $Status
    $previousProgressPreference = $ProgressPreference
    try {
        $ProgressPreference = 'Continue'
        Write-Progress -Id 1 -Activity 'ChatGPT Windows One-Click Installer' -Completed
    }
    finally {
        $ProgressPreference = $previousProgressPreference
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Version = '',

        [string]$Detail = '',

        [bool]$Required = $true
    )

    $script:Results += [pscustomobject]@{
        Component = $Component
        Status    = $Status
        Version   = $Version
        Detail    = $Detail
        Required  = $Required
    }

    if ($Required -and $Status -in @('Failed', 'Unavailable')) {
        $script:HadRequiredFailure = $true
    }
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-WindowsArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($architecture) {
        '^(AMD64|x86_64)$' { return 'x64' }
        '^(ARM64|AARCH64)$' { return 'arm64' }
        default { return $architecture }
    }
}

function Test-Endpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        Write-Log "Connectivity pre-check did not succeed for $Uri. The installer will still retry during download." 'WARN'
        return $false
    }
}

function Test-Environment {
    Set-InstallerProgress -Percent 8 -Stage 'Environment' -Status 'Checking Windows, architecture, disk space, and network.'
    Write-Log 'Step 1/5 - Checking Windows, architecture, disk, and network.'

    if ($env:OS -ne 'Windows_NT') {
        throw 'This installer only supports Windows.'
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $unsupportedServerDryRun = $false
    if ([int]$os.ProductType -ne 1) {
        if ($DryRun) {
            $unsupportedServerDryRun = $true
            Write-Log "Windows Server is not supported for installation. Continuing only because DryRun is enabled. Detected: $($os.Caption)." 'WARN'
        }
        else {
            throw "Windows Server is not supported. Detected: $($os.Caption)."
        }
    }
    if ($build -lt 17763) {
        throw "Windows build $build is too old. Windows 10 version 1809 (build 17763) or later is required."
    }

    $architecture = Get-WindowsArchitecture
    if ($architecture -notin @('x64', 'arm64')) {
        throw "Unsupported Windows architecture: $architecture. Only x64 and Arm64 packages are published."
    }

    $localAppDataRoot = [IO.Path]::GetPathRoot($env:LOCALAPPDATA)
    $driveName = $localAppDataRoot.TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName
    $requiredGb = if ($Profile -eq 'Complete') { 6 } else { 1 }
    $freeGb = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGb -lt $requiredGb) {
        throw "Insufficient free disk space. $requiredGb GB is required; $freeGb GB is available."
    }

    $isAdmin = Test-IsAdministrator
    Write-Log "Windows: $($os.Caption), build $build, architecture $architecture, free disk $freeGb GB."
    Write-Log "Administrator token: $isAdmin. Individual installers may request UAC only when needed."

    $null = Test-Endpoint -Uri "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-$architecture.msix"
    if ($Profile -eq 'Complete') {
        $null = Test-Endpoint -Uri 'https://cdn.winget.microsoft.com/cache'
    }

    $environmentStatus = if ($unsupportedServerDryRun) { 'DryRun only' } else { 'Passed' }
    $environmentDetail = if ($unsupportedServerDryRun) {
        "Unsupported Windows Server; $freeGb GB free"
    }
    else {
        "$freeGb GB free"
    }
    Add-Result -Component 'Environment' -Status $environmentStatus -Version "build $build / $architecture" -Detail $environmentDetail
    Set-InstallerProgress -Percent 15 -Stage 'Environment' -Status 'Environment checks completed.'
    return $architecture
}

function New-InstallerTempDirectory {
    $path = Join-Path $env:TEMP "ChatGPTInstaller-$PID"
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $script:TempDirectory = $path
    return $path
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [ValidateRange(-1, 100)]
        [int]$ProgressPercent = -1,

        [string]$ProgressStage = 'Download'
    )

    if ($DryRun) {
        Write-Log "[DryRun] Would download $Uri to $Destination."
        if ($ProgressPercent -ge 0) {
            Set-InstallerProgress -Percent $ProgressPercent -Stage $ProgressStage -Status 'Dry run: download planned.'
        }
        return
    }

    $lastError = $null
    foreach ($attempt in 1..3) {
        try {
            Write-Log "Downloading $Uri (attempt $attempt/3)."
            if ($ProgressPercent -ge 0) {
                Set-InstallerProgress -Percent $ProgressPercent -Stage $ProgressStage -Status ("Download started (attempt {0}/3); waiting for data." -f $attempt)
            }
            Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 300
            if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
                $downloadSizeMb = [math]::Round((Get-Item -LiteralPath $Destination).Length / 1MB, 2)
                Write-Log ("Download completed: {0} MB." -f $downloadSizeMb) 'OK'
                if ($ProgressPercent -ge 0) {
                    Set-InstallerProgress -Percent $ProgressPercent -Stage $ProgressStage -Status ("Download completed ({0} MB)." -f $downloadSizeMb)
                }
                return
            }
            throw 'The downloaded file is empty.'
        }
        catch {
            $lastError = $_
            Write-Log "Download attempt $attempt failed: $($_.Exception.Message)" 'WARN'
            if ($attempt -lt 3) {
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
    }

    throw "Download failed after three attempts: $($lastError.Exception.Message)"
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $segments = @($machinePath, $userPath) | Where-Object { $_ }
    $env:Path = $segments -join ';'
}

function Find-Winget {
    Refresh-ProcessPath
    $command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $aliasPath) {
        return $aliasPath
    }

    return $null
}

function Get-WingetVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $output = & $Path --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $output) {
            return [string]($output | Select-Object -First 1)
        }
    }
    catch {
        Write-Log "WinGet executable check failed: $($_.Exception.Message)" 'WARN'
    }

    return $null
}

function Ensure-Winget {
    Set-InstallerProgress -Percent 18 -Stage 'Package manager' -Status 'Checking Windows Package Manager (WinGet).'
    Write-Log 'Step 2/5 - Checking Windows Package Manager (WinGet).'

    $script:WingetPath = Find-Winget
    if ($script:WingetPath) {
        $version = Get-WingetVersion -Path $script:WingetPath
        if ($version) {
            Write-Log "WinGet is available: $version." 'OK'
            Add-Result -Component 'WinGet' -Status 'Ready' -Version $version -Detail 'Existing installation' -Required ($Profile -eq 'Complete')
            Set-InstallerProgress -Percent 25 -Stage 'Package manager' -Status 'WinGet is ready.'
            return $true
        }

        Write-Log 'A WinGet alias was found, but it is not functional. Attempting an App Installer repair/update.' 'WARN'
        $script:WingetPath = $null
    }

    if ($SkipWingetBootstrap) {
        Write-Log 'WinGet is missing and bootstrap was disabled.' 'WARN'
        Add-Result -Component 'WinGet' -Status 'Unavailable' -Detail 'Bootstrap disabled' -Required ($Profile -eq 'Complete')
        Set-InstallerProgress -Percent 25 -Stage 'Package manager' -Status 'WinGet is unavailable; bootstrap was skipped.'
        return $false
    }

    Write-Log 'WinGet is missing. Installing the official Microsoft App Installer package.'
    if ($DryRun) {
        Write-Log '[DryRun] Would bootstrap WinGet from https://aka.ms/getwinget.'
        $script:WingetPath = 'winget.exe'
        Add-Result -Component 'WinGet' -Status 'Planned' -Detail 'Official App Installer bootstrap' -Required ($Profile -eq 'Complete')
        Set-InstallerProgress -Percent 25 -Stage 'Package manager' -Status 'Dry run: WinGet bootstrap planned.'
        return $true
    }

    try {
        $bundle = Join-Path $script:TempDirectory 'Microsoft.DesktopAppInstaller.msixbundle'
        Invoke-Download -Uri 'https://aka.ms/getwinget' -Destination $bundle -ProgressPercent 20 -ProgressStage 'WinGet download'
        Set-InstallerProgress -Percent 22 -Stage 'Package manager' -Status 'Starting Windows App Installer package registration.'
        Write-Log 'Starting Windows App Installer package registration. A separate window may not appear.'
        Add-AppxPackage -Path $bundle -ForceApplicationShutdown
        Write-Log 'Windows App Installer registration returned; verifying WinGet.'
        Set-InstallerProgress -Percent 23 -Stage 'Package manager' -Status 'App Installer returned; verifying WinGet.'
        Start-Sleep -Seconds 2
        $script:WingetPath = Find-Winget
        if (-not $script:WingetPath) {
            throw 'App Installer completed, but winget.exe is not registered for this user.'
        }

        $version = Get-WingetVersion -Path $script:WingetPath
        if (-not $version) {
            throw 'winget.exe was registered but did not pass its version check.'
        }
        Write-Log "WinGet bootstrap completed: $version." 'OK'
        Add-Result -Component 'WinGet' -Status 'Installed' -Version $version -Detail 'Official App Installer bootstrap' -Required ($Profile -eq 'Complete')
        Set-InstallerProgress -Percent 25 -Stage 'Package manager' -Status 'WinGet installation and verification completed.'
        return $true
    }
    catch {
        Write-Log "WinGet bootstrap failed: $($_.Exception.Message)" 'WARN'
        Add-Result -Component 'WinGet' -Status 'Unavailable' -Detail $_.Exception.Message -Required ($Profile -eq 'Complete')
        Set-InstallerProgress -Percent 25 -Stage 'Package manager' -Status 'WinGet bootstrap failed; continuing where possible.'
        return $false
    }
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if ($DryRun) {
        Write-Log ("[DryRun] winget " + ($Arguments -join ' ')) 'CMD'
        return 0
    }

    if (-not $script:WingetPath) {
        return 1
    }

    try {
        Write-Log ("winget " + ($Arguments -join ' ')) 'CMD'
        Write-Log 'Starting the WinGet process now. Silent package installers may not open a separate window.'
        & $script:WingetPath @Arguments 2>&1 | ForEach-Object {
            Write-Log ([string]$_) 'CMD'
        }
        $wingetExitCode = [int]$LASTEXITCODE
        Write-Log ("WinGet process finished and returned exit code {0}." -f $wingetExitCode)
        return $wingetExitCode
    }
    catch {
        Write-Log "WinGet command failed to start: $($_.Exception.Message)" 'WARN'
        return 1
    }
}

function Update-WingetSources {
    if (-not $script:WingetPath) {
        return
    }

    Write-Log 'Refreshing the official WinGet sources without resetting custom sources.'
    $null = Invoke-Winget -Arguments @('source', 'update', '--disable-interactivity')
}

function Get-MsixIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if (-not $manifestEntry) {
            throw 'AppxManifest.xml is missing from the MSIX package.'
        }

        $stream = $manifestEntry.Open()
        $reader = New-Object IO.StreamReader($stream)
        try {
            [xml]$manifest = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }

        return [pscustomobject]@{
            Name      = [string]$manifest.Package.Identity.Name
            Version   = [string]$manifest.Package.Identity.Version
            Publisher = [string]$manifest.Package.Identity.Publisher
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-ChatGPTPackage {
    if ($script:ChatGPTIdentityName) {
        $package = Get-AppxPackage -Name $script:ChatGPTIdentityName -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($package) {
            return $package
        }
    }

    return Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '(?i)chatgpt' -or
            $_.PackageFullName -match '(?i)chatgpt'
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Test-ChatGPTInstalled {
    if (Get-ChatGPTPackage) {
        return $true
    }

    try {
        $startEntry = Get-StartApps | Where-Object { $_.Name -eq 'ChatGPT' } | Select-Object -First 1
        return ($null -ne $startEntry)
    }
    catch {
        return $false
    }
}

function Install-ChatGPTWithWinget {
    if (-not $script:WingetPath) {
        return $false
    }

    $arguments = @(
        'install',
        '--id', $script:ChatGPTStoreId,
        '--source', 'msstore',
        '--exact',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    Set-InstallerProgress -Percent 32 -Stage 'ChatGPT' -Status 'Starting the Microsoft Store installation through WinGet.'
    Write-Log 'Starting the ChatGPT Microsoft Store installer through WinGet. It runs silently and may not open a separate window.'
    $exitCode = Invoke-Winget -Arguments $arguments
    Set-InstallerProgress -Percent 42 -Stage 'ChatGPT' -Status ("WinGet returned exit code {0}; verifying ChatGPT." -f $exitCode)
    if (($exitCode -ne 0) -and (-not $DryRun)) {
        Write-Log "ChatGPT WinGet operation returned exit code $exitCode. Refreshing sources and retrying once." 'WARN'
        Set-InstallerProgress -Percent 42 -Stage 'ChatGPT' -Status 'First WinGet attempt failed; refreshing sources and retrying.'
        Update-WingetSources
        $exitCode = Invoke-Winget -Arguments $arguments
        Set-InstallerProgress -Percent 43 -Stage 'ChatGPT' -Status ("WinGet retry returned exit code {0}; verifying ChatGPT." -f $exitCode)
    }

    if ($DryRun) {
        return $true
    }

    $verified = Test-ChatGPTInstalled
    if ($verified) {
        Set-InstallerProgress -Percent 48 -Stage 'ChatGPT' -Status 'Microsoft Store installation verified.'
    }
    else {
        Set-InstallerProgress -Percent 43 -Stage 'ChatGPT' -Status 'Store installation was not verified; preparing MSIX fallback.'
    }
    return $verified
}

function Install-ChatGPTWithMsix {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture
    )

    $uri = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-$Architecture.msix"
    $msixPath = Join-Path $script:TempDirectory "ChatGPT-$Architecture.msix"

    if ($DryRun) {
        Write-Log "[DryRun] Would install OpenAI's Store-signed package from $uri."
        Set-InstallerProgress -Percent 48 -Stage 'ChatGPT' -Status 'Dry run: official MSIX installation planned.'
        return $true
    }

    try {
        Invoke-Download -Uri $uri -Destination $msixPath -ProgressPercent 44 -ProgressStage 'ChatGPT MSIX download'
        Set-InstallerProgress -Percent 45 -Stage 'ChatGPT' -Status 'Inspecting the downloaded MSIX package identity.'
        $identity = Get-MsixIdentity -Path $msixPath
        $script:ChatGPTIdentityName = $identity.Name
        Write-Log "MSIX identity: $($identity.Name), version $($identity.Version), publisher $($identity.Publisher)."
        Write-Log 'Windows will validate the Store signature and package trust during Add-AppxPackage.'
        Write-Log 'Starting ChatGPT MSIX registration now. A separate installer window may not appear.'
        Set-InstallerProgress -Percent 46 -Stage 'ChatGPT' -Status 'Starting Windows MSIX registration and signature validation.'
        Add-AppxPackage -Path $msixPath -ForceApplicationShutdown
        Write-Log 'ChatGPT MSIX registration returned; verifying the installed application.'
        Set-InstallerProgress -Percent 47 -Stage 'ChatGPT' -Status 'MSIX registration returned; verifying ChatGPT.'

        $installed = Get-ChatGPTPackage
        if (-not $installed) {
            throw 'MSIX registration finished, but the installed package could not be verified.'
        }

        Set-InstallerProgress -Percent 48 -Stage 'ChatGPT' -Status 'Official MSIX installation verified.'
        return $true
    }
    catch {
        if (Test-ChatGPTInstalled) {
            Write-Log "MSIX returned an error, but ChatGPT is already installed: $($_.Exception.Message)" 'WARN'
            return $true
        }
        Write-Log "MSIX installation failed: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Install-ChatGPT {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('x64', 'arm64')]
        [string]$Architecture
    )

    Set-InstallerProgress -Percent 28 -Stage 'ChatGPT' -Status 'Preparing to install or update the official ChatGPT app.'
    Write-Log 'Step 3/5 - Installing or updating the official ChatGPT app.'
    $installed = $false
    $method = ''

    if (-not $PreferMsix -and $script:WingetPath) {
        Write-Log 'Trying the official Microsoft Store package through WinGet.'
        $installed = Install-ChatGPTWithWinget
        $method = 'WinGet / Microsoft Store'
    }

    if (-not $installed) {
        Write-Log "Using OpenAI's latest Store-signed $Architecture MSIX package."
        $installed = Install-ChatGPTWithMsix -Architecture $Architecture
        $method = 'OpenAI Store-signed MSIX'
    }

    if (-not $installed) {
        Add-Result -Component 'ChatGPT' -Status 'Failed' -Detail 'Both WinGet and MSIX installation paths failed.'
        Set-InstallerProgress -Percent 50 -Stage 'ChatGPT' -Status 'ChatGPT installation failed; see the final failure list.'
        return $false
    }

    if ($DryRun) {
        Add-Result -Component 'ChatGPT' -Status 'Planned' -Detail $method
        Set-InstallerProgress -Percent 50 -Stage 'ChatGPT' -Status 'Dry run: ChatGPT installation plan completed.'
        return $true
    }

    $package = Get-ChatGPTPackage
    $version = if ($package) { [string]$package.Version } else { 'installed' }
    Write-Log "ChatGPT is installed and verified ($version)." 'OK'
    Add-Result -Component 'ChatGPT' -Status 'Installed/Updated' -Version $version -Detail $method
    Set-InstallerProgress -Percent 50 -Stage 'ChatGPT' -Status 'ChatGPT installation and verification completed.'
    return $true
}

function Test-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    if ($DryRun) {
        return $true
    }

    try {
        & $script:WingetPath list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        Write-Log "Package verification failed for ${Id}: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,

        [Parameter(Mandatory = $true)]
        [string[]]$VersionArguments
    )

    Refresh-ProcessPath
    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            try {
                $versionOutput = & $command.Source @VersionArguments 2>&1 | Select-Object -First 1
                if (($LASTEXITCODE -eq 0) -and $versionOutput) {
                    return [string]$versionOutput
                }
            }
            catch {
                return 'installed'
            }
        }
    }
    return ''
}

function Get-PythonInstalledVersion {
    $version = Get-CommandVersion `
        -CommandNames @('py.exe', 'py', 'python.exe', 'python') `
        -VersionArguments @('--version')
    if ($version) {
        return $version
    }

    $knownPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'),
        (Join-Path $env:ProgramFiles 'Python314\python.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $knownPaths += Join-Path ${env:ProgramFiles(x86)} 'Python314\python.exe'
    }

    foreach ($path in $knownPaths) {
        if (Test-Path -LiteralPath $path) {
            try {
                $versionOutput = & $path --version 2>&1 | Select-Object -First 1
                if (($LASTEXITCODE -eq 0) -and $versionOutput) {
                    return [string]$versionOutput
                }
            }
            catch {
                # Continue to the registry fallback.
            }
        }
    }

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($registryPath in $registryPaths) {
        $entry = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Python 3.14*' } |
            Select-Object -First 1
        if ($entry) {
            if ($entry.DisplayVersion) {
                return "Python $($entry.DisplayVersion)"
            }
            return 'Python 3.14 installed'
        }
    }

    return ''
}

function Install-DeveloperTool {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Tool,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$ProgressStart,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [int]$ProgressEnd
    )

    $arguments = @(
        'install',
        '--id', $Tool.Id,
        '--source', 'winget',
        '--exact',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    Set-InstallerProgress -Percent $ProgressStart -Stage $Tool.Name -Status 'Starting the silent package installer.'
    Write-Log "Installing or updating $($Tool.Name) ($($Tool.Id))."
    Write-Log ("Starting the {0} installer now. It may run silently without a separate window." -f $Tool.Name)
    $exitCode = Invoke-Winget -Arguments $arguments
    $returnedPercent = [math]::Min($ProgressEnd - 2, $ProgressStart + 3)
    Set-InstallerProgress -Percent $returnedPercent -Stage $Tool.Name -Status ("Installer process returned exit code {0}; preparing verification." -f $exitCode)
    if (($exitCode -ne 0) -and (-not $DryRun)) {
        Write-Log "$($Tool.Name) returned exit code $exitCode. Refreshing sources and retrying once." 'WARN'
        Set-InstallerProgress -Percent $returnedPercent -Stage $Tool.Name -Status 'First attempt failed; refreshing WinGet sources and retrying.'
        Update-WingetSources
        $exitCode = Invoke-Winget -Arguments $arguments
        Set-InstallerProgress -Percent $returnedPercent -Stage $Tool.Name -Status ("Retry returned exit code {0}; preparing verification." -f $exitCode)
    }

    if ($DryRun) {
        Add-Result -Component $Tool.Name -Status 'Planned' -Detail $Tool.Id
        Set-InstallerProgress -Percent $ProgressEnd -Stage $Tool.Name -Status 'Dry run: installation planned.'
        return
    }

    $verificationPercent = [math]::Max($ProgressStart, $ProgressEnd - 1)
    Set-InstallerProgress -Percent $verificationPercent -Stage $Tool.Name -Status 'Verifying package registration and executable version.'
    $installed = $false
    $version = ''
    foreach ($verificationAttempt in 1..3) {
        Refresh-ProcessPath
        $installed = Test-WingetPackage -Id $Tool.Id
        if ($Tool.Id -eq 'Python.Python.3.14') {
            $version = Get-PythonInstalledVersion
        }
        else {
            $version = Get-CommandVersion -CommandNames $Tool.Commands -VersionArguments $Tool.VersionArguments
        }

        if ($installed -or $version) {
            break
        }
        if ($verificationAttempt -lt 3) {
            Write-Log ("Verification for {0} is not ready yet; retrying ({1}/3)." -f $Tool.Name, $verificationAttempt) 'WARN'
            Start-Sleep -Seconds (2 * $verificationAttempt)
        }
    }

    if ($installed -or $version) {
        $versionText = ''
        if ($version) {
            $versionText = ": $version"
        }
        Write-Log "$($Tool.Name) is installed$versionText." 'OK'
        Add-Result -Component $Tool.Name -Status 'Installed/Updated' -Version $version -Detail $Tool.Id
        Set-InstallerProgress -Percent $ProgressEnd -Stage $Tool.Name -Status 'Installation verified.'
    }
    else {
        Write-Log "$($Tool.Name) could not be verified after installation." 'ERROR'
        Add-Result -Component $Tool.Name -Status 'Failed' -Detail "WinGet exit code $exitCode; package $($Tool.Id)"
        Set-InstallerProgress -Percent $ProgressEnd -Stage $Tool.Name -Status 'Verification failed; details will appear in the final summary.'
    }
}

function Install-DeveloperTools {
    Set-InstallerProgress -Percent 52 -Stage 'Developer tools' -Status 'Preparing the optional developer tool installations.'
    Write-Log 'Step 4/5 - Installing or updating OpenAI-recommended developer tools.'

    if ($Profile -eq 'Core') {
        Write-Log 'Core profile selected; optional developer tools are skipped.'
        Add-Result -Component 'Developer tools' -Status 'Skipped' -Detail 'Core profile' -Required $false
        Set-InstallerProgress -Percent 90 -Stage 'Developer tools' -Status 'Skipped because the Core profile is selected.'
        return
    }

    if (-not $script:WingetPath) {
        Write-Log 'Developer tools require WinGet, but WinGet is unavailable.' 'ERROR'
        Add-Result -Component 'Developer tools' -Status 'Failed' -Detail 'WinGet unavailable'
        Set-InstallerProgress -Percent 90 -Stage 'Developer tools' -Status 'Developer tools failed because WinGet is unavailable.'
        return
    }

    Update-WingetSources
    $tools = @(
        [pscustomobject]@{
            Name = 'Git'
            Id = 'Git.Git'
            Commands = @('git.exe', 'git')
            VersionArguments = @('--version')
        },
        [pscustomobject]@{
            Name = 'Node.js LTS'
            Id = 'OpenJS.NodeJS.LTS'
            Commands = @('node.exe', 'node')
            VersionArguments = @('--version')
        },
        [pscustomobject]@{
            Name = 'Python'
            Id = 'Python.Python.3.14'
            Commands = @('py.exe', 'py', 'python.exe', 'python')
            VersionArguments = @('--version')
        },
        [pscustomobject]@{
            Name = '.NET SDK'
            Id = 'Microsoft.DotNet.SDK.10'
            Commands = @('dotnet.exe', 'dotnet')
            VersionArguments = @('--version')
        },
        [pscustomobject]@{
            Name = 'GitHub CLI'
            Id = 'GitHub.cli'
            Commands = @('gh.exe', 'gh')
            VersionArguments = @('--version')
        }
    )

    for ($toolIndex = 0; $toolIndex -lt $tools.Count; $toolIndex++) {
        $tool = $tools[$toolIndex]
        $progressStart = 55 + ($toolIndex * 7)
        $progressEnd = $progressStart + 7
        Install-DeveloperTool -Tool $tool -ProgressStart $progressStart -ProgressEnd $progressEnd
    }
}

function Write-PostInstallGuidance {
    Set-InstallerProgress -Percent 92 -Stage 'Final checks' -Status 'Checking account-dependent follow-up actions.'
    Write-Log 'Step 5/5 - Final checks and account-dependent setup.'

    if ($Profile -eq 'Complete' -and -not $DryRun) {
        $gh = Get-Command 'gh.exe' -ErrorAction SilentlyContinue
        if ($gh) {
            & $gh.Source auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log 'GitHub CLI is installed but not signed in. Run: gh auth login' 'WARN'
                Add-Result -Component 'GitHub authentication' -Status 'User action required' -Detail 'Run gh auth login' -Required $false
            }
            else {
                Add-Result -Component 'GitHub authentication' -Status 'Ready' -Required $false
            }
        }
    }

    Write-Log 'Plugins, skills, the built-in browser, and file previews are included in the ChatGPT app; no separate Windows plug-in package is required.'
    Write-Log 'Sign in to ChatGPT to enable account or workspace features. Connectors and third-party plugins must be authorized in the app and may be controlled by an administrator.'
    Set-InstallerProgress -Percent 95 -Stage 'Final checks' -Status 'Final account and feature checks completed.'
}

function Start-ChatGPT {
    if ($NoLaunch -or $DryRun) {
        $reason = if ($DryRun) { 'dry run' } else { 'NoLaunch option' }
        Write-Log ("Automatic ChatGPT launch skipped ({0})." -f $reason)
        Set-InstallerProgress -Percent 98 -Stage 'Launch ChatGPT' -Status ("Automatic launch skipped ({0})." -f $reason)
        return
    }

    try {
        Set-InstallerProgress -Percent 96 -Stage 'Launch ChatGPT' -Status 'Looking up the ChatGPT Start menu application.'
        $entry = Get-StartApps | Where-Object { $_.Name -eq 'ChatGPT' } | Select-Object -First 1
        if ($entry) {
            Write-Log 'Sending the ChatGPT launch request to Windows.'
            Set-InstallerProgress -Percent 97 -Stage 'Launch ChatGPT' -Status 'Sending the launch request to Windows.'
            Start-Process 'explorer.exe' -ArgumentList "shell:AppsFolder\$($entry.AppID)"
            Write-Log 'The ChatGPT launch request was accepted by Windows. Complete sign-in in the app.' 'OK'
            Set-InstallerProgress -Percent 98 -Stage 'Launch ChatGPT' -Status 'Launch request accepted by Windows.'
        }
        else {
            Write-Log 'ChatGPT is installed, but its Start menu entry was not available yet. Open ChatGPT from the Start menu.' 'WARN'
            Set-InstallerProgress -Percent 98 -Stage 'Launch ChatGPT' -Status 'Start menu entry not ready; launch ChatGPT manually.'
        }
    }
    catch {
        Write-Log "ChatGPT could not be launched automatically: $($_.Exception.Message)" 'WARN'
        Set-InstallerProgress -Percent 98 -Stage 'Launch ChatGPT' -Status 'Automatic launch failed; open ChatGPT manually.'
    }
}

function Get-ResultGroups {
    $installedStatuses = @('Installed', 'Installed/Updated')
    $readyStatuses = @('Passed', 'Ready')

    $installed = @($script:Results | Where-Object {
        $installedStatuses -contains $_.Status
    })
    $ready = @($script:Results | Where-Object {
        $readyStatuses -contains $_.Status
    })
    $failed = @($script:Results | Where-Object {
        ($_.Status -eq 'Failed') -or ($_.Required -and $_.Status -eq 'Unavailable')
    })
    $other = @($script:Results | Where-Object {
        ($installedStatuses -notcontains $_.Status) -and
        ($readyStatuses -notcontains $_.Status) -and
        ($_.Status -ne 'Failed') -and
        (-not ($_.Required -and $_.Status -eq 'Unavailable'))
    })

    return [pscustomobject]@{
        InstalledOrUpdated = $installed
        Ready              = $ready
        Failed             = $failed
        Other              = $other
    }
}

function Write-ResultGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [string]$Color = 'Gray'
    )

    Write-Host ''
    Write-Host $Title -ForegroundColor $Color
    if (@($Items).Count -eq 0) {
        Write-Host '  None.'
        return
    }

    foreach ($item in @($Items)) {
        $versionText = ''
        if ($item.Version) {
            $versionText = " | Version: $($item.Version)"
        }
        Write-Host ("  - {0} | {1}{2}" -f $item.Component, $item.Status, $versionText)
        if ($item.Detail) {
            Write-Host ("    Detail: {0}" -f $item.Detail)
        }
    }
}

function Write-InstallationReport {
    $groups = Get-ResultGroups
    $requiredFailureCount = @($groups.Failed | Where-Object { $_.Required }).Count
    $report = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
        Profile = $Profile
        DryRun = [bool]$DryRun
        Success = (-not $script:HadRequiredFailure)
        Results = $script:Results
        Summary = [pscustomobject]@{
            InstalledOrUpdatedCount = @($groups.InstalledOrUpdated).Count
            ReadyCount = @($groups.Ready).Count
            FailedCount = @($groups.Failed).Count
            RequiredFailureCount = $requiredFailureCount
            OtherCount = @($groups.Other).Count
            FailedComponents = @($groups.Failed | ForEach-Object { $_.Component })
        }
        LogFile = $script:LogFile
    }

    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
}

function Show-Summary {
    $groups = Get-ResultGroups
    $installedCount = @($groups.InstalledOrUpdated).Count
    $readyCount = @($groups.Ready).Count
    $failedCount = @($groups.Failed).Count
    $otherCount = @($groups.Other).Count
    $requiredFailureCount = @($groups.Failed | Where-Object { $_.Required }).Count

    Write-Host ''
    Write-Host '================ INSTALLATION RESULTS ================' -ForegroundColor Cyan
    Write-ResultGroup -Title 'INSTALLED OR UPDATED' -Items $groups.InstalledOrUpdated -Color 'Green'
    Write-ResultGroup -Title 'ALREADY READY / CHECKS PASSED' -Items $groups.Ready -Color 'Cyan'
    Write-ResultGroup -Title 'FAILED' -Items $groups.Failed -Color 'Red'
    Write-ResultGroup -Title 'SKIPPED / PLANNED / ACTION REQUIRED' -Items $groups.Other -Color 'Yellow'
    Write-Host ''
    Write-Host ("Totals: installed/updated={0}; ready={1}; failed={2}; other={3}." -f $installedCount, $readyCount, $failedCount, $otherCount)

    if ($DryRun) {
        Write-Host 'FINAL RESULT: DRY RUN ONLY - nothing was installed.' -ForegroundColor Yellow
    }
    elseif ($requiredFailureCount -gt 0) {
        Write-Host ("FINAL RESULT: FAILED - {0} required component(s) failed." -f $requiredFailureCount) -ForegroundColor Red
    }
    elseif ($failedCount -gt 0) {
        Write-Host ("FINAL RESULT: REQUIRED COMPONENTS SUCCEEDED, but {0} optional component(s) failed." -f $failedCount) -ForegroundColor Yellow
    }
    else {
        Write-Host 'FINAL RESULT: SUCCESS - no component failed.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "Log:    $script:LogFile"
    Write-Host "Report: $script:ReportFile"
    Write-Host '=======================================================' -ForegroundColor Cyan
}

$exitCode = 0
try {
    Initialize-ConsoleEncoding
    Initialize-Logging
    Set-InstallerProgress -Percent 0 -Stage 'Initialization' -Status 'Installer started.'
    Write-Log "ChatGPT Windows one-click installer started. Profile=$Profile, DryRun=$DryRun."

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-Log 'TLS 1.2 could not be explicitly enabled; continuing with the Windows default.' 'WARN'
    }

    Set-InstallerProgress -Percent 4 -Stage 'Initialization' -Status 'Creating the temporary working directory.'
    $null = New-InstallerTempDirectory
    $architecture = Test-Environment
    $null = Ensure-Winget
    $chatGPTReady = Install-ChatGPT -Architecture $architecture
    if ($chatGPTReady) {
        Install-DeveloperTools
        Write-PostInstallGuidance
        Start-ChatGPT
    }
    else {
        Set-InstallerProgress -Percent 98 -Stage 'Installation stopped' -Status 'ChatGPT failed, so dependent steps were skipped.'
    }

    if ($script:HadRequiredFailure) {
        $exitCode = 1
        Write-Log 'Installation finished with one or more required failures. Review the report above.' 'ERROR'
    }
    else {
        Write-Log 'Installation completed successfully.' 'OK'
    }
}
catch {
    $exitCode = 1
    $script:HadRequiredFailure = $true
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
    Add-Result -Component 'Installer' -Status 'Failed' -Detail $_.Exception.Message
}
finally {
    try {
        Set-InstallerProgress -Percent 99 -Stage 'Report' -Status 'Writing the detailed JSON report.'
        Write-InstallationReport
    }
    catch {
        $exitCode = 1
        Write-Host "The final report could not be written: $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
        Show-Summary
    }
    catch {
        $exitCode = 1
        Write-Host "The installation summary could not be displayed: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($script:TempDirectory -and (Test-Path -LiteralPath $script:TempDirectory)) {
        Remove-Item -LiteralPath $script:TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($exitCode -eq 0) {
        Complete-InstallerProgress -Status 'All requested operations finished successfully.'
    }
    else {
        Complete-InstallerProgress -Status 'Finished with one or more failures; review the summary above.'
    }
}

exit $exitCode

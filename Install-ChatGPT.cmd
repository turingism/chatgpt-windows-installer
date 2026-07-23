@echo off
setlocal
cd /d "%~dp0"

title ChatGPT Windows One-Click Installer
echo.
echo ChatGPT Windows One-Click Installer
echo -----------------------------------
echo This will install or update ChatGPT and the recommended developer tools.
echo Windows may show UAC prompts for individual trusted installers.
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo This installer requires Windows PowerShell 5.1.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ChatGPT.ps1" -Profile Complete
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
if "%INSTALL_EXIT%"=="0" (
    echo Installation completed successfully.
) else (
    echo Installation did not fully complete. Review the log path shown above.
)
echo.
pause
exit /b %INSTALL_EXIT%

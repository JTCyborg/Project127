@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo Project127 - build
echo ============================================================

if not exist "tools\sjasmplus.exe" (
    echo [ERROR] SjASMPlus not found:
    echo         %CD%\tools\sjasmplus.exe
    echo.
    echo Place sjasmplus.exe in the tools directory,
    echo or run tools\build_boot.ps1 with -SjAsmPlus PATH.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_boot.ps1" -SjAsmPlus "%~dp0tools\sjasmplus.exe" -Output "%~dp0build\p127_boot.bin"
set "BUILD_EXIT=%ERRORLEVEL%"

if not "%BUILD_EXIT%"=="0" (
    echo.
    echo [BUILD] FAILED, exit code %BUILD_EXIT%
    pause
    exit /b %BUILD_EXIT%
)

echo.
echo [BUILD] SUCCESS
echo Output: %~dp0build\p127_boot.bin
pause
exit /b 0

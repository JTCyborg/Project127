@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo PROJECT127 - COMPLETE TR-DOS DISK BUILD
echo ============================================================
echo [BUILD] Source: src\boot\p127_boot.asm
echo [BUILD] Disk:   disk_A.trd
echo.

if not exist "tools\build_project127.ps1" (
    echo [ERROR] Missing tools\build_project127.ps1
    goto :failed
)
if not exist "tools\trd_image.py" (
    echo [ERROR] Missing tools\trd_image.py
    goto :failed
)
if not exist "tools\sjasmplus.exe" (
    echo [ERROR] Missing tools\sjasmplus.exe
    goto :failed
)

where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python 3 not found in PATH.
    goto :failed
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_project127.ps1" -SjAsmPlus "%~dp0tools\sjasmplus.exe" -Python "python" -Output "%~dp0disk_A.trd"
if errorlevel 1 goto :failed

if not exist "disk_A.trd" (
    echo [ERROR] disk_A.trd was not created.
    goto :failed
)
if not exist "build\p127_boot.bin" (
    echo [ERROR] build\p127_boot.bin was not created.
    goto :failed
)
if not exist "build\disk_A.trd" (
    echo [ERROR] build\disk_A.trd was not created.
    goto :failed
)

echo.
echo [BUILD] SUCCESS
for %%F in ("disk_A.trd") do echo [BUILD] IMAGE_BYTES=%%~zF
echo [BUILD] Open disk_A.trd in Unreal Speccy.
echo [BUILD] At TR-DOS prompt run: RUN "boot"
echo.
pause
exit /b 0

:failed
echo.
echo [BUILD] FAILED. See error above.
pause
exit /b 1

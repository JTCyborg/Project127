@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ============================================================
echo PROJECT127 - SJASMPLUS TR-DOS BUILD
echo ============================================================
echo [BUILD] Source: src\main.asm
echo [BUILD] Output: disk_A.trd
echo.
if not exist "tools\sjasmplus.exe" (
    echo [ERROR] tools\sjasmplus.exe was not found.
    goto :failed
)
if not exist "src\main.asm" (
    echo [ERROR] src\main.asm was not found.
    goto :failed
)
if not exist "build" mkdir "build"
del /q "disk_A.trd" 2>nul
del /q "build\disk_A.trd" 2>nul
tools\sjasmplus.exe --dirbol --lst=build\list.txt --sym=build\map.txt src/main.asm
if errorlevel 1 goto :failed
if not exist "disk_A.trd" (
    echo [ERROR] SjASMPlus did not create disk_A.trd.
    goto :failed
)
for %%F in ("disk_A.trd") do set IMAGE_SIZE=%%~zF
if not "%IMAGE_SIZE%"=="655360" (
    echo [ERROR] Wrong TR-DOS image size: %IMAGE_SIZE%
    goto :failed
)
copy /y "disk_A.trd" "build\disk_A.trd" >nul
if errorlevel 1 goto :failed
echo.
echo [BUILD] SUCCESS
echo [BUILD] IMAGE_BYTES=%IMAGE_SIZE%
echo [BUILD] BASIC=boot.B
echo [BUILD] STAGE2=P127BOOT.C LOAD=#6000
echo [BUILD] Open disk_A.trd in Unreal Speccy.
echo [BUILD] At TR-DOS prompt run: RUN "boot"
echo.
pause
exit /b 0
:failed
echo.
echo [BUILD] FAILED. Do NOT run an older disk_A.trd.
echo [BUILD] Check build\list.txt and assembler output.
echo.
pause
exit /b 1

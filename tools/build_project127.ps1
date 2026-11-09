[CmdletBinding()]
param(
    [string]$SjAsmPlus = "sjasmplus",
    [string]$Python = "python",
    [string]$Output = ".\build\Project127.trd"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Assembler = Get-Command $SjAsmPlus -ErrorAction SilentlyContinue
$Py = Get-Command $Python -ErrorAction SilentlyContinue
if (-not $Assembler) { throw "SjASMPlus not found. Add it to PATH or pass -SjAsmPlus." }
if (-not $Py) { throw "Python 3 not found. Add it to PATH or pass -Python." }
$Out = [System.IO.Path]::GetFullPath((Join-Path $Root $Output))
$Dir = Split-Path -Parent $Out
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Bin = Join-Path $Dir "p127_boot.bin"
& $Assembler.Source --cleanonerror "--raw=$Bin" ".\src\boot\p127_boot.asm"
if ($LASTEXITCODE -ne 0) { throw "SjASMPlus failed: $LASTEXITCODE" }
& $Py.Source ".\tools\trd_image.py" --code $Bin --output $Out
if ($LASTEXITCODE -ne 0) { throw "TR-DOS image build failed: $LASTEXITCODE" }
if ((Get-Item $Out).Length -ne 655360) { throw "TR-DOS image size is not 655360 bytes" }
Write-Host "[P127 BUILD] IMAGE=$Out"
Write-Host "[P127 BUILD] BUILD OK"

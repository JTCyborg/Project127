[CmdletBinding()]
param(
    [string]$SjAsmPlus = (Join-Path $PSScriptRoot "sjasmplus.exe"),
    [string]$Python = "python",
    [string]$Output = ".\disk_A.trd"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (Test-Path $SjAsmPlus) {
    $AssemblerPath = (Resolve-Path $SjAsmPlus).Path
} else {
    $AssemblerCommand = Get-Command $SjAsmPlus -ErrorAction SilentlyContinue
    if (-not $AssemblerCommand) {
        throw "SjASMPlus not found: $SjAsmPlus"
    }
    $AssemblerPath = $AssemblerCommand.Source
}

$PythonCommand = Get-Command $Python -ErrorAction SilentlyContinue
if (-not $PythonCommand) {
    throw "Python 3 not found: $Python"
}
$PythonPath = $PythonCommand.Source

$BuildDir = Join-Path $Root "build"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Bin = Join-Path $BuildDir "p127_boot.bin"
$Out = [System.IO.Path]::GetFullPath($Output)

Write-Host "[P127 BUILD] ASSEMBLER=$AssemblerPath"
Write-Host "[P127 BUILD] SOURCE=src\boot\p127_boot.asm"
& $AssemblerPath --cleanonerror "--raw=$Bin" ".\src\boot\p127_boot.asm"
if ($LASTEXITCODE -ne 0) {
    throw "SjASMPlus failed: $LASTEXITCODE"
}
if (-not (Test-Path $Bin) -or (Get-Item $Bin).Length -eq 0) {
    throw "Assembler did not create a non-empty boot binary"
}

Write-Host "[P127 BUILD] BUILDING_TRD=$Out"
& $PythonPath ".\tools\trd_image.py" --code $Bin --output $Out
if ($LASTEXITCODE -ne 0) {
    throw "TR-DOS image build failed: $LASTEXITCODE"
}
if (-not (Test-Path $Out)) {
    throw "TR-DOS image was not created: $Out"
}
$ImageSize = (Get-Item $Out).Length
if ($ImageSize -ne 655360) {
    throw "TR-DOS image size is $ImageSize; expected 655360"
}

$BuildCopy = Join-Path $BuildDir "disk_A.trd"
if ($Out -ne $BuildCopy) {
    Copy-Item -Force $Out $BuildCopy
}

Write-Host "[P127 BUILD] BOOT_BIN=$Bin ($((Get-Item $Bin).Length) bytes)"
Write-Host "[P127 BUILD] TRD_IMAGE=$Out ($ImageSize bytes)"
Write-Host "[P127 BUILD] BUILD OK"

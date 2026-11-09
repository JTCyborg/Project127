param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,8}$')]
    [string]$HostName = "p127host"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$assembler = Join-Path $root "tools/sjasmplus.exe"
if (-not (Test-Path $assembler)) {
    $command = Get-Command "sjasmplus" -ErrorAction SilentlyContinue
    if ($command) { $assembler = $command.Source }
    else { throw "SjASMPlus not found. Put tools/sjasmplus.exe in Project127 or add sjasmplus to PATH." }
}

$build = Join-Path $root "build"
$diskImage = Join-Path $root "disk_A.trd"
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $root
try {
    $loaderTemplate = Get-Content -Raw "atm_host/boot_loader.asm"
    $loader = $loaderTemplate.Replace("@@HOST_NAME@@", $HostName)
    Set-Content -Path "atm_host/boot_loader.generated.asm" -Value $loader -Encoding ASCII

    Remove-Item -Force -ErrorAction SilentlyContinue $diskImage
    Remove-Item -Force -ErrorAction SilentlyContinue "build/ATM_DISK.lst","build/ATM_DISK.map"
    Write-Host "[BUILD] PROJECT127_TRDOS_IMAGE v0.1.0"
    Write-Host "[BUILD] SjASMPlus: $assembler"
    Write-Host "[BUILD] BASIC boot file: BOOT.B"
    Write-Host "[BUILD] Host CODE file: $HostName.C"

    & $assembler --msg=all "--lst=build/ATM_DISK.lst" --lstlab=sort "--sym=build/ATM_DISK.map" "atm_host/project127_disk.asm"
    if ($LASTEXITCODE -ne 0) { throw "SjASMPlus failed with exit code $LASTEXITCODE" }

    foreach ($path in @($diskImage,"build/ATM_DISK.lst","build/ATM_DISK.map")) {
        if (-not (Test-Path $path)) { throw "Required build output missing: $path" }
    }
    $bytes = (Get-Item $diskImage).Length
    if ($bytes -ne 655360) { throw "Invalid TR-DOS image size: $bytes (expected 655360)." }

    [byte[]]$disk = [System.IO.File]::ReadAllBytes($diskImage)
    $required = @(
        @{ Name = ($HostName.PadRight(8) + "C"); Label = "$HostName.C" },
        @{ Name = "boot    B"; Label = "boot.B" }
    )
    foreach ($entry in $required) {
        [byte[]]$name = [System.Text.Encoding]::ASCII.GetBytes($entry.Name)
        $found = $false
        for ($offset=0; $offset -lt (128*16); $offset+=16) {
            $match = $true
            for ($i=0; $i -lt $name.Length; $i++) {
                if ($disk[$offset+$i] -ne $name[$i]) { $match=$false; break }
            }
            if ($match) {
                $length = [int]$disk[$offset+11] + ([int]$disk[$offset+12] -shl 8)
                $sectors = [int]$disk[$offset+13]
                if ($length -lt 1 -or $sectors -lt 1) { throw "Invalid TR-DOS metadata for $($entry.Label)." }
                Write-Host "[TRD] $($entry.Label): $length bytes, $sectors sectors"
                $found = $true
                break
            }
        }
        if (-not $found) { throw "TR-DOS directory entry missing: $($entry.Label)" }
    }

    Copy-Item -Force $diskImage (Join-Path $build "disk_A.trd")
    Write-Host "[BUILD] TR-DOS image created: disk_A.trd ($bytes bytes)"
    Write-Host "[BUILD] Copy created: build/disk_A.trd"
}
finally {
    Pop-Location
}

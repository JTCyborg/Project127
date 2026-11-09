# Project127 — TR-DOS boot and image layout

**Revision:** 0.1  
**Status:** boot/image build scaffold; execution must be validated in Unreal Speccy / ATM.

## Reused Project126 behavior

Project127 deliberately reuses the established Project126 BASIC boot sequence, not its x86 runtime or its fixed-page module packaging:

1. `OUT 239,1` establishes the boot/debug mode.
2. `CLEAR 24000` keeps the loaded host image at 24576 (6000h) outside BASIC's working area.
3. `RANDOMIZE USR 15619` calls the same TR-DOS ROM trampoline used by Project126.
4. `LOAD "p127host" CODE 24576` loads the ATM host image.
5. `OUT 239,2` selects the host-entry stage and `RANDOMIZE USR VAL "24585"` enters at 6009h.

The BASIC source is `atm_host/boot_loader.asm`. The build substitutes the host filename into the LOAD statement. The TR-DOS filename `boot.B` is intentionally lowercase to preserve automatic TR-DOS startup behavior.

## Initial disk contents

The clean Project127 image contains only:

| TR-DOS file | Purpose |
|---|---|
| `boot.B` | BASIC startup program |
| `P127HOST.C` | Initial ATM host entry image, loaded at 6000h |

No Project126 `X86CORE.C`, `X86IO.C`, `X86ALU.C`, `X86DEV.C`, `X86EXEC.C`, `X86VGA.C`, `X86VID.C` or overlay manifest is included. This prevents the old 16 KiB overlay architecture from silently becoming part of Project127.

The first host entry currently emits a versioned #EF marker and idles. It is a boot-chain test target, not the completed memory/DMA foundation. The foundation implementation must replace this entry only after its independent modules and acceptance tests are in place.

## Build

Run `build_project127.bat` or:

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_project127.ps1`

SjASMPlus must be available as `tools/sjasmplus.exe` or through `PATH`.

The build:
- generates the BASIC loader and TR-DOS assembly source from templates;
- assembles the host entry and disk image;
- requires an exact 655360-byte TR-DOS image;
- checks the directory entries for the selected host CODE file and lowercase `boot.B`;
- copies the result to both `disk_A.trd` and `build/disk_A.trd`.

A successful script run proves assembly and image-structure checks only. It does not prove that ATM boots the image in the emulator; that requires a runtime test.

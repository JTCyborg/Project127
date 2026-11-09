# Project127 boot protocol

Project127 builds its complete TR-DOS image in one SjASMPlus invocation,
following the proven Project112 pattern: EMPTYTRD plus SAVETRD.

The single assembly entry point is src/main.asm. It includes the Z80 stage-2
source from src/boot/p127_boot.asm and defines the tokenized Spectrum BASIC
loader in the same assembly source.

SjASMPlus writes two files directly into disk_A.trd:

- boot.B — BASIC autostart loader, starting at line 10.
- P127BOOT.C — Z80 stage 2, loaded at #6000.

At the TR-DOS prompt run:

~~~text
RUN "boot"
~~~

The BASIC loader initializes debug output on port #EF and executes the
Project112/126-compatible TR-DOS interception sequence:
RANDOMIZE USR 15619 : REM : LOAD "P127BOOT" CODE 24576.
It then reports the load milestone and transfers control to #6000 with
RANDOMIZE USR VAL "24576".

Build on Windows with build_project127.bat. It invokes the included
tools/sjasmplus.exe once on src/main.asm. Python and a separate TR-DOS image
generator are not part of the build.

Outputs:

- disk_A.trd — 640 KiB TR-DOS image in the repository root.
- build/disk_A.trd — identical copy.
- build/list.txt and build/map.txt — SjASMPlus listing and symbol map.

The build script checks the resulting image size. Actual ATM/TR-DOS emulator
execution still requires runtime confirmation.

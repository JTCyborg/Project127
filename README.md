# Project127

Clean implementation of the ATM Turbo 2+ host system and its NeoGS companion.
Project126 is not used as an architecture or code base. Project125/126 may be
consulted as references only.

## Fixed architecture

- ATM host RAM: 1 MiB; NeoGS RAM: 4 MiB, independent address spaces.
- Memory addresses, lengths and file offsets use unsigned 32-bit values.
- ATM owns external hardware and controller ports.
- NeoGS accesses external devices only through the agreed host DMA/transport.
- Storage target: physical Nemo IDE/SMUC, not a virtual disk image.
- RTC: DS12887 through SMUC, serviced by the host.
- Debug channel: port #EF; host entry address: #6000.

## Build boot disk

Requirements: Python 3 and SjASMPlus on PATH.

~~~powershell
.\tools\build_project127.ps1
~~~

Creates build\Project127.trd, a standard 640 KiB TR-DOS image with BOOT
(BASIC loader) and P127BOOT (Z80 host entry). At the TR-DOS prompt run:

~~~text
RUN "BOOT"
~~~

## Implementation order

1. TR-DOS boot chain.
2. UINT32 range/check API.
3. ATM RAM page allocator and memory operations.
4. TR-DOS disk service.
5. ATM native video.
6. DS12887 RTC through SMUC.
7. Keyboard/input.
8. Physical Nemo IDE/SMUC block storage.
9. Speaker/audio.
10. Timer, events and interrupt dispatch.

Each subsystem must have executable tests and a stable interface before later
drivers depend on it.

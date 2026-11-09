# Boot milestone 0 acceptance

## Build

Run:

```powershell
.\tools\build_boot.ps1
```

Expected build summary:
- `LOAD=0x6000 ENTRY=0x6000`
- non-empty binary image
- image size no greater than 16 KiB

## Runtime

Load the binary at 6000h and transfer execution to 6000h.

Expected debug bytes on port #EF:

```text
P127 START\r\n
P127 BOOT0 OK\r\n
```

The CPU then remains in the idle loop.

## Pass criteria

All bytes must arrive in order, with no missing, duplicated or extra characters. No allocator, video, RTC, input or storage test belongs to this milestone.

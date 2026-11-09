# Project127 boot stage 0.2 acceptance

## What the debug log proves

The Z80 boot stage writes progress messages to ATM debug port #EF.
These messages are emitted only after BASIC has successfully loaded the
CODE file and transferred execution to 6000h.

Expected sequence:

```text
[P127] S2 ENTRY @6000
[P127] STACK SET BFFF
[P127] DEBUG TX EF
[P127] BOOT0 PASS; IDLE
```

Interpretation:
- No first line: the BASIC/TR-DOS loader did not transfer control to 6000h,
  or the debug-port capture is not active.
- First line only: entry code started, but the next print sequence did not finish.
- First two lines: entry and stack setup were reached.
- First three lines: the debug transmit path was exercised.
- All four lines: stage 2 reached its idle loop. This is the BOOT0 pass
  condition, not proof that later Project127 subsystems work.

The CPU disables maskable interrupts, sets SP= BFFFh, emits the four lines,
then enters a HALT/JR idle loop. There are no device, allocator, video,
RTC, keyboard, or storage initializations in this milestone.

## Build

Run:

```powershell
.\tools\build_project127.ps1
```

The generated TR-DOS disk contains lowercase BASIC loader file `boot`
(type `B`) and code file `P127BOOT` (type `C`).

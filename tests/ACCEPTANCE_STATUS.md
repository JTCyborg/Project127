# Project127 acceptance status

## Runtime checkpoint — 2026-11-10

### Memory and page management — PASS

Verified by the user's ATM Turbo 2+ emulator run:

- 1 MiB / 64-page initialization.
- Fixed reservations: video P1/P3/P5/P7, boot P0/P2, IRQ table P4.
- Page-state and negative-path checks: double-free, range and reserved-page guards.
- UINT32 1 MiB bounds and top-down P8..P63 arena checks.
- Logical page-table/boundary translation and logical-span preflight.
- Map transaction commit/rollback.
- Resident stack, UI quiesce/W3 ownership, W3 rollback/recovery.
- IRQ frame/batch/table/mask/vector contract preflights; vector remains disabled.
- Full physical W3 sweep: 57/57 free pages filled and verified; P0 restored and UI resumed.
- Allocator allocate/free and guarded W3 lease API.
- Eight full-pool allocator exhaustion/recovery cycles; first-fit restored.
- Reference-counted physical PIN/UNPIN self-test; FREE correctly guarded while pinned.
- Logical span copy across page boundary and W3 restoration.

Key runtime markers:

```text
[P127] MEM PAGE TEST PASS
[P127] MEM NEGATIVE-PATH TEST PASS; DOUBLE-FREE/RANGE/RESERVE GUARDED
[P127] PHYS W3 FULL FREE-PAGE SWEEP/ALLOCATOR/RESERVES/P0 RESTORE PASS
[P127] PAGE ALLOC/FREE + GUARDED W3 LEASE API PASS; IM/EI DISABLED
[P127] ALLOCATOR 8X FULL-POOL CYCLE/EXHAUSTION PASS; FIRST-FIT RESTORED
[P127] MEM PIN/UNPIN REFCOUNT SELFTEST PASS; FREE GUARDED
[P127] LOGICAL SPAN COPY PASS; CROSS-PAGE/W3 RESTORE VERIFIED
```

Memory/page-management acceptance is closed for this checkpoint.

### ATM video — PASS

Verified by the user's 2026-11-10 ATM Turbo 2+ emulator run.

Runtime marker:

```text
[P127] ATM VIDEO RG3/RG2/RG0/RG6 CYCLE + P7/P3 FULL-PAGE CRC16 PASS; UI RESTORED
```

The run confirms:

- RG3 -> RG2 -> RG0 -> RG6 mode cycle completed.
- Full-page CRC-16/CCITT checks passed for P7 and P3 (16 KiB each), before and after the mode cycle.
- Four existing VRAM sentinel checks remained enabled.
- The temporary eight-byte trampoline at P3:#FFEC was restored before the full-page CRC comparison.
- The UI and host page mappings were restored after each transition and after the complete test.

This closes the current ATM video preservation/mode-switch acceptance scope. It does not claim CRC coverage of reserved pages P1/P5 or independent visual verification of pixel geometry in RG3/RG2/RG0.

Reference mode matrix (Project112):

| Index | Mode | Register value | Geometry |
|---:|---|---:|---|
| 0 | Sinclair / ZX | #C3 (RG=3) | 256x192 |
| 1 | ATM 640 multicolor | #C2 (RG=2) | 640x200 |
| 2 | ATM EGA | #C0 (RG=0) | 320x200x16 |
| 3 | ATM hardware text | #C6 (RG=6) | 80x25 |

### Keyboard/input — ATM XT protocol implemented; runtime pending

ATM host owns all physical keyboard reads. `src/kernel/p127_keyboard.asm` v0.2.2 now implements the Unreal Speccy ATM_KBD interface through ULA port #FE:

- Performs the documented #55/#AA handshake and command #08 mode selection.
- Enters ATM_KBD mode 2 and reads R2/R3/R4/R5; R2 is read-to-clear, while R3/R4/R5 expose key/modifier/extended-key metadata.
- Temporarily switches to mode 3 to read and clear LASTSCAN, then returns to mode 2. LASTSCAN bit 7 denotes key release.
- Logs each key event with LASTSCAN and R2/R3/R4/R5, and reports modifier/register state changes.
- Requires `[Input] ATMKBD=1` in the Unreal Speccy configuration. If the ATM_KBD handshake is absent, it explicitly falls back to the ordinary ZX 8x5 matrix diagnostic; that fallback is not full PC-keyboard support.
- All polling is ATM-side, paced in software, and independent of PIT/IRQ. No NeoGS implementation, DMA transport, IM or EI is assumed.

Expected runtime markers with ATMKBD enabled:

```text
[KBD] INIT
[KBD] ATM XT ACTIVE
[KBD] LAST=.. R2=.. R3=.. R4=.. R5=..
[KBD] DONE
```

The monitor now exits automatically after 10 seconds without a new make/break or modifier/matrix transition, prints `[KBD] DONE`, and returns to the normal boot idle loop. The timeout uses the ATM Turbo 2+ 7 MHz software-pacing estimate; it still requires runtime timing confirmation. Runtime acceptance remains pending until the user tests ordinary keys, function/navigation keys, modifiers, extended keys, make/break events, and the idle exit in the configured emulator.
### Explicitly deferred

- HDD/FAT16 functional acceptance. The latest runtime log did show a successful NEMO IDE LBA28 probe, sector 63 read, and FAT16 root-directory listing (7 files); this is recorded as an observation only, not acceptance.
- Beeper/audio acceptance. The log showed the #FE tone test beginning and ending; this stage remains deferred.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path while it is deferred.



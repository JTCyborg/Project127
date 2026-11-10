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

### Keyboard/input — IMPLEMENTED; RUNTIME PENDING

ATM host owns all physical keyboard reads. The new `src/kernel/p127_keyboard.asm` v0.1.0 implements:

- Complete eight-row / five-column active-low Spectrum matrix scan on the ATM host using row selects #FE, #FD, #FB, #F7, #EF, #DF, #BF and #7F on port #FE.
- Stable eight-byte snapshot and change detection; the initial snapshot is always published, subsequent transfers occur only when one or more row bytes change.
- Raw eight-byte matrix diagnostics on #EF and the existing console.
- Host-to-NeoGS DMA mailbox using the established Project125 contract: GSCOM command #10, NeoGS arms ZX DMA at physical #00F000, ATM writes eight bytes through the #0000 DMA aperture, then sends #FF as the end marker.
- Bounded CBIT waits (eight independent #FFFF windows). No DBIT/GSDAT payload transfer, no ATM-side DMA register programming, no keyboard IRQ, and no IM/EI enablement.
- Boot enters a live keyboard monitor after the existing startup diagnostics. The monitor reports changed matrix snapshots and DMA completion/failure.

The legacy `113/src/key_hal.asm` remains a behavioral reference only; it reads six rows and is not copied unchanged.

Expected runtime markers:

```text
[KBD v0.1.0] ATM 8X5 MATRIX MONITOR; ACTIVE-LOW; IRQ DISABLED
[KBD] MATRIX=1F 1F 1F 1F 1F 1F 1F 1F
[KBD] DMA OK
```

The matrix line is expected to change when keys are pressed/released; the corresponding row bit is cleared for a pressed key. Keyboard/DMA acceptance remains pending until a user emulator run confirms all eight rows and successful DMA handoff. The NeoGS receiver must implement the documented Project125 `CMD_HOST_INPUT` mailbox contract.

### Explicitly deferred

- HDD/FAT16 functional acceptance. The latest runtime log did show a successful NEMO IDE LBA28 probe, sector 63 read, and FAT16 root-directory listing (7 files); this is recorded as an observation only, not acceptance.
- Beeper/audio acceptance. The log showed the #FE tone test beginning and ending; this stage remains deferred.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path while it is deferred.



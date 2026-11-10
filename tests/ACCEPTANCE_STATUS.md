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

### ATM video — SMOKE TEST PASS; FULL ACCEPTANCE PENDING

Verified by the user's 2026-11-10 emulator run. The boot log contains:

```text
[P127] ATM VIDEO RG3/RG2/RG0/RG6 CYCLE + VRAM SIGNATURE PASS; UI RESTORED
```

This confirms that the boot-time test completed the RG3 -> RG2 -> RG0 -> RG6 mode cycle, compared its four VRAM sentinel bytes successfully, and returned the UI to its expected state.

Implemented in `src/ui/p127_console.asm` and invoked from `src/boot/p127_boot.asm` after TR-DOS directory diagnostics:

- Uses Project112's four complete mode bytes: #C3, #C2, #C0, #C6.
- Switches through the #FFEC trampoline and ATM shadow service #0177.
- Acquires the existing W3 UI lease before mapping video pages P7/P3.
- Restores host pages P5/P0 and releases the UI lease after each mode change.
- Holds each graphics mode briefly using a software delay; no PIT/IRQ dependency.
- Captures four representative bytes (even/odd character planes and even/odd attribute planes) before and after the cycle, then compares them.
- Returns to RG6 before the post-cycle signature check.

Reference mode matrix (Project112):

| Index | Mode | Register value | Geometry |
|---:|---|---:|---|
| 0 | Sinclair / ZX | #C3 (RG=3) | 256x192 |
| 1 | ATM 640 multicolor | #C2 (RG=2) | 640x200 |
| 2 | ATM EGA | #C0 (RG=0) | 320x200x16 |
| 3 | ATM hardware text | #C6 (RG=6) | 80x25 |

Reference sources: `Project112/112/src/video_mode_control.asm`, `mode_standard.asm`, and `mode_atm.asm`.

The smoke test checks four sentinel bytes only. It does not prove that every byte of all four reserved video pages is preserved, nor does it independently validate pixel geometry/rendering in RG2/RG0/RG3. Therefore the video stage is not yet fully accepted. Remaining work:

1. Verify visible output and geometry in RG3, RG2 and RG0.
2. Expand video-memory preservation checks beyond the four sentinels.
3. Verify page selection, UI ownership and restoration after every mode change.

### Explicitly deferred

- HDD/FAT16 functional acceptance. The latest runtime log did show a successful NEMO IDE LBA28 probe, sector 63 read, and FAT16 root-directory listing (7 files); this is recorded as an observation only, not acceptance.
- Beeper/audio acceptance. The log showed the #FE tone test beginning and ending; this stage remains deferred.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path while it is deferred.

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
- Captures four representative bytes (even/odd character planes and even/odd attribute planes) before and after the cycle.
- Calculates CRC-16/CCITT (polynomial #1021, initial value #FFFF) across every byte of the mapped 16 KiB P7 window (#4000..#7FFF) and 16 KiB P3 window (#C000..#FFFF), before and after the mode cycle. The scan is read-only and compares both page CRCs after returning to RG6.
- Returns to RG6 before the post-cycle signature and full-page CRC comparison.

Reference mode matrix (Project112):

| Index | Mode | Register value | Geometry |
|---:|---|---:|---|
| 0 | Sinclair / ZX | #C3 (RG=3) | 256x192 |
| 1 | ATM 640 multicolor | #C2 (RG=2) | 640x200 |
| 2 | ATM EGA | #C0 (RG=0) | 320x200x16 |
| 3 | ATM hardware text | #C6 (RG=6) | 80x25 |

Reference sources: `Project112/112/src/video_mode_control.asm`, `mode_standard.asm`, and `mode_atm.asm`.

The latest implementation expands preservation coverage from four sentinels to full-page CRC scans of the two pages actually mapped by the console/video path (P7 and P3). This does not claim coverage of reserved pages P1/P5, which are not mapped as the active character/attribute windows by this path. The CRC implementation and new boot marker still require a fresh emulator run; do not mark this expanded check as runtime PASS until the user supplies that log. The test does not independently validate pixel geometry/rendering in RG2/RG0/RG3. Remaining work:

1. Run the new P7/P3 full-page CRC test in the emulator and confirm the new boot marker.
2. Verify visible output and geometry in RG3, RG2 and RG0.
3. Determine and verify the role/preservation path for reserved video pages P1/P5 before claiming all four reserved pages are covered.
4. Retain the per-transition page-selection and UI-ownership restoration guards.

### Explicitly deferred

- HDD/FAT16 functional acceptance. The latest runtime log did show a successful NEMO IDE LBA28 probe, sector 63 read, and FAT16 root-directory listing (7 files); this is recorded as an observation only, not acceptance.
- Beeper/audio acceptance. The log showed the #FE tone test beginning and ending; this stage remains deferred.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path while it is deferred.


### ATM video — per-transition restoration guard

The mode-switch trampoline now checks the postconditions after every RG3/RG2/RG0/RG6 register write: the host mapping shadow must be W1=P5 and W3=P0, and the W3 state machine must be UI_ACTIVE/UI-owned/not busy. A failed postcondition returns the video test as failed instead of silently continuing to the next mode.

This is a runtime guard, not a substitute for the still-pending full video-page preservation and visible geometry tests. The existing four-byte VRAM signature remains the only preservation comparison until that next phase is implemented and exercised.


### ATM video — full-page CRC implementation checkpoint

Implemented on 2026-11-10:

- Read-only CRC-16/CCITT scan of all 16 KiB in P7 and all 16 KiB in P3 before and after the four-mode cycle.
- Existing four sentinel comparisons retained as an additional fast check.
- CRC comparison runs only after RG6 is restored.
- No pattern writes or destructive VRAM test are performed.
- Boot success marker changed to:
  `[P127] ATM VIDEO RG3/RG2/RG0/RG6 CYCLE + P7/P3 FULL-PAGE CRC16 PASS; UI RESTORED`

Runtime verification of this new code is pending. It is intentionally not recorded as PASS until a new emulator log confirms the marker.


### ATM video CRC false-positive correction — 2026-11-10

The first emulator run with full-page CRC stopped at `ATM VIDEO MODE CYCLE/VRAM RESTORE FAIL`. Source inspection identified a deterministic self-test side effect: each mode switch writes an 8-byte trampoline at P3:`#FFEC`, so the subsequent full-page P3 CRC necessarily differed from the pre-cycle CRC.

Correction committed:

- Save the original eight bytes at P3:`#FFEC` before writing the trampoline.
- Restore those exact bytes immediately after the trampoline jumps back to resident code and before P3 is unmapped.
- Keep the CRC scan over the complete 16 KiB pages; no address range is excluded.

The correction is not runtime-verified yet. A fresh emulator run must reach the new `P7/P3 FULL-PAGE CRC16 PASS` marker before the video preservation check can be marked PASS.

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

### Explicitly deferred

- HDD/FAT16 functional testing (the user's latest log showed a successful root listing, but this stage is intentionally deferred).
- Beeper/audio.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

## Next acceptance stage — ATM video

The next work item is the ATM video stage:

1. Enumerate and verify supported ATM display modes against the established Project112/ATM implementation.
2. Verify mode changes and return to the system UI.
3. Verify video-memory page selection and preservation across mode changes.
4. Verify that UI ownership and the boot memory map are restored after each test.

### Reference mode matrix (Project112)

The existing Project112 implementation defines four modes in this order:

| Index | Mode | Register value | Geometry |
|---:|---|---:|---|
| 0 | Sinclair / ZX | #C3 (RG=3) | 256x192 |
| 1 | ATM 640 multicolor | #C2 (RG=2) | 640x200 |
| 2 | ATM EGA | #C0 (RG=0) | 320x200x16 |
| 3 | ATM hardware text | #C6 (RG=6) | 80x25 |

Reference sources: `Project112/112/src/video_mode_control.asm`, `mode_standard.asm`, and `mode_atm.asm`. Project112 uses a trampoline at #FFEC for the mode-register write through #0177 and explicitly restores the Sinclair mapping when returning to index 0.

### Project127 implementation checkpoint

Implemented in `src/ui/p127_console.asm` and invoked from `src/boot/p127_boot.asm` after TR-DOS directory diagnostics:

- Uses Project112's four complete mode bytes: #C3, #C2, #C0, #C6.
- Switches through the #FFEC trampoline and ATM shadow service #0177.
- Acquires the existing W3 UI lease before mapping video pages P7/P3.
- Restores host pages P5/P0 and releases the UI lease after each mode change.
- Holds each graphics mode briefly using a software delay; no PIT/IRQ dependency.
- Captures four representative bytes (even/odd character planes and even/odd attribute planes) before and after the cycle, then compares them.
- Returns to RG6 before the post-cycle signature check.

The boot test reports:

- `[P127] ATM VIDEO RG3/RG2/RG0/RG6 CYCLE + VRAM SIGNATURE PASS; UI RESTORED`
- or `[P127] ATM VIDEO MODE CYCLE/VRAM RESTORE FAIL`

This is a smoke test, not full VRAM verification: it checks four sentinel bytes only. It does not yet prove every byte of all four reserved video pages is preserved, nor does it independently validate pixel geometry/rendering in RG2/RG0/RG3. The emulator build and runtime result are still pending.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path.

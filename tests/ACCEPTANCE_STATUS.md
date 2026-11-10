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

### Project127 baseline and gap

- `src/ui/p127_console.asm` currently initializes only RG6 80x25 and maps alternate video pages P7/P3.
- `src/kernel/p127_physmem.asm` reapplies that RG6 setup after its W3 sweep.
- No Project127 mode-cycle/test API currently exists in the inspected source.
- Project112's mode-switch code must be adapted to Project127's resident layout and W3/UI ownership rules; it must not be copied blindly.
- The four reserved video pages P1/P3/P5/P7 must remain reserved throughout all tests. Do not use them as allocator scratch pages.

The next implementation step is a bounded mode-switch test that cycles the four register modes and always restores RG6 + the original Project127 UI mapping, followed by an emulator run. VRAM preservation requires a separate non-destructive test strategy; changing display mode alone does not prove that contents were retained.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path.

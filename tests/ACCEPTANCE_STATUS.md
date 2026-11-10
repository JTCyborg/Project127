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

### Keyboard/input — ZX fallback diagnostic runtime PASS; ATM XT mode not exercised

The user's 2026-11-10 runtime log confirms:

- `[KBD] INIT` and `[KBD] ZX FALLBACK`.
- The ZX 8x5 matrix values changed in response to key presses and returned to the idle values after release.
- The inactivity timeout ended the monitor with `[KBD] DONE`.

This closes the requested keyboard diagnostic stage. The run did not activate ATM XT mode, so the #55/#AA handshake, R2/R3/R4/R5 extended-key protocol, and function/navigation keys through ATM_KBD are not claimed as tested. The timeout duration is based on the software-pacing estimate and has not been independently timed.
### Explicitly deferred

- HDD/FAT16 functional acceptance. The latest runtime log did show a successful NEMO IDE LBA28 probe, sector 63 read, and FAT16 root-directory listing (7 files); this is recorded as an observation only, not acceptance.
- Beeper/audio acceptance. The log showed the #FE tone test beginning and ending; this stage remains deferred.
- NeoGS DMA/IPC.
- IRQ activation: source remains unresolved; IM/EI and interrupt vector remain disabled.

Do not enable IM/EI as part of video work. Do not modify the HDD/NEMO-DIVIDE path while it is deferred.




### IRQ — frame source identified; live activation pending

- The upstream Unreal Speccy source audit identifies the ATM710 frame interrupt source: one pending Z80 INT per Spectrum frame, accepted during the interrupt window only when CPU IFF1 is set and ATM FF77 bit #20 is enabled.
- The emulator's IM1 handler address is fixed at #0038; IM2 reads a handler pointer from the table selected by I and the emulator-provided interrupt vector byte.
- Project127's existing IRQ tests verify only synthetic frame/context and DI-only readiness contracts. No vector bytes are installed and no live handler has run.
- The initial W3/P4 table candidate was rejected because W3 is leased and remapped. The current preflight candidate is #B000..#B100 in fixed W2/P2, beyond the resident image end and below the scratch-stack region. This is a placement candidate only; the table is not initialized.
- No live IRQ acceptance. Keep IM/EI disabled until the emulator vector byte, resident handler, stack/window ownership and acknowledgement/return behavior are implemented and tested.


### IRQ — stable IM2 table location preflight updated; live IRQ pending

- Candidate table moved from remappable W3/P4 at #C000 to fixed W2/P2 at #B000..#B100. The region is beyond the resident image end (#B000 exclusive) and below the scratch-stack/guard area.
- Preflight now checks P2 reservation and the W2->P2 mapping.
- The table remains uninitialized and IM2/IM/EI remain disabled pending confirmation of the emulator's interrupt vector byte and implementation of the resident handler.

### IRQ — interrupt-vector implementation audit blocker

- At upstream Unreal Speccy revision `a685b6f9227ec9dbb595b6cef38addbcd083d6ac`, `z80/defs.h` declares `Z80::IntVec()` as a pure virtual method, and `gsz80.h` declares `TGsZ80::IntVec()` as an override.
- The inspected `gsz80.cpp` contains the `TGsZ80` method definitions for memory, M1, IN/OUT and RETN, but no `TGsZ80::IntVec()` definition. The declaration alone does not establish the returned vector byte.
- The frame loop passes `cpu.IntVec()` to `handle_int()`; IM2 uses that byte together with I to read the little-endian handler address. Therefore the exact vector cannot be inferred from the frame source or from the IM1 fixed address `#0038`.
- Do not initialize the IM2 table with a guessed vector and do not enable IM/EI. Continue tracing the concrete runtime implementation/selected CPU class and its linked definition before writing vector bytes.

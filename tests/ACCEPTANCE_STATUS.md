# Project127 acceptance status

## Runtime checkpoint — 2026-11-10

### Memory and page management — PASS

Verified by the user's ATM Turbo 2+ emulator run:

- 1 MiB / 64-page initialization.
- Fixed reservations: video P1/P3/P5/P7; boot map P0/P2/P4. The IRQ table occupies #B000..#B100 inside already-reserved W2/P2; it is not a separate physical-page reservation.
- Page-state and negative-path checks: double-free, range and reserved-page guards.
- UINT32 1 MiB bounds and top-down P8..P63 arena checks.
- Logical page-table/boundary translation and logical-span preflight.
- Map transaction commit/rollback.
- Resident stack, UI quiesce/W3 ownership, W3 rollback/recovery.
- IRQ frame/batch/table/mask/vector contract preflights; vector remains disabled.
- Full physical W3 sweep: 57/57 free pages filled and verified; P0 restored and UI resumed. Confirmed by the user's 2026-11-10 runtime after adding the missing P4 boot reservation.
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

Memory/page-management acceptance is closed for this checkpoint. Latest runtime confirms the full W3 sweep and allocator/pin/span-copy self-tests.

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

- HDD/FAT16 functional acceptance remains deferred. Latest runtime confirms NEMO IDE LBA28 master-ready, LBA 63 sector read (512 bytes, BPB, 55AA), and FAT16 root-directory listing of 7 files (IO.SYS, MSDOS.SYS, DOS, COMMAND.COM, WINA20.386, CONFIG.SYS, AUTOEXEC.BAT). This is a successful probe/directory-read observation, not full FAT16 write/cluster-chain acceptance.
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


### IRQ table reservation correction — 2026-11-10

- Runtime log stopped at `IRQ TABLE PAGE RESERVE FAIL` because the table candidate had been moved to physical P2/W2, while `p127_mem_reserve_boot` already reserves P2 for the resident UI/stack.
- `p127_mem_reserve_irq_table` incorrectly attempted a second exclusive reservation of P2. The page manager correctly rejected that overlap.
- Corrected the routine to validate that P2 is already in `P127_MEM_RESERVED` state instead of reserving it again. The IRQ table remains an address range inside the existing boot reservation; no new page is consumed and no table bytes/IM/EI are installed.
- Updated the boot diagnostic to identify the shared P2/W2 reservation. Runtime confirmation is pending the next user emulator run.


### Physical W3 sweep count correction — 2026-11-10

- Latest user runtime reaches `PHYS W3 PAGE SWITCH/MEMORY TEST FAIL` with `PHYSMEM ERROR=08`. Error 08 is the allocator-count assertion.
- The physical-memory test's fixed-map contract explicitly includes P0/P1/P2/P3/P4/P5/P7 as seven RESERVED pages, leaving 57 allocatable pages. The arena separately uses the contiguous P8..P63 run; P6 remains isolated and allocatable.
- The boot reservation routine reserved P0 and P2 but omitted fixed system page P4. Consequently the allocator found 58 pages, while the physical sweep correctly expected 57 and its reservation checks correctly required P4.
- Fixed the source by reserving P4 during boot-map initialization, retaining the 57-page physical sweep and P4 reservation checks, and updating the boot diagnostic to report P0/P2/P4. P4 is not mapped or accessed by this change.
- The temporary six-reservation/58-page adjustment in commit `f8cfdf0` was superseded; the intended seven-page reservation invariant is restored.
- Runtime confirmation is pending a fresh build and emulator run.

### Latest integrated runtime — 2026-11-10 15:37

The user's latest complete boot log confirms:

- Boot memory map reports P0/P2/P4 and P5 active; kernel image bounds pass.
- Physical W3 full free-page sweep passes: pages P6 and P8..P63 were filled and verified in descending order; 57/57 free pages verified; P0 restored and UI active.
- Page allocator/free, guarded W3 lease, 8x full-pool exhaustion/recovery, PIN/UNPIN reference-count and cross-page logical span-copy tests all pass.
- ATM video mode cycle and P7/P3 full-page CRC16 pass; UI restored.
- NEMO-DIVIDE LBA28 probe and FAT16 root directory scan pass at probe level: 7 root entries listed.
- Speaker smoke-test begin/end markers observed; no audio acceptance inferred.
- Keyboard monitor used ZX fallback and ended normally. No ATM XT extended-key protocol claim is added.
- IRQ source/vector remains unresolved; IM/EI stay disabled.

The earlier PHYSMEM ERROR=08 is resolved in this runtime by the P4 reservation correction. The corrected W3 sweep has now been confirmed by the user.

### IRQ source audit — concrete ATM CPU path clarified

- In Unreal Speccy, the ATM/Spectrum frame loop in `z80_main.inl` calls `handle_int(&cpu, cpu.IntVec())`. The active object is declared as `extern TMainZ80 cpu` in `vars.h`; `TMainZ80` derives from `Z80` and declares its own `IntVec()` override.
- The ATM frame source is a pending INT once per Spectrum frame. For ATM710/ATM3, the hardware gate is `comp.pFF77 & 0x20`; `set_atm_FF77()` mirrors that bit to `cpu.int_gate`. The interrupt is accepted only when the Z80 IFF1/EI-delay conditions and the ATM gate allow it.
- `handle_int()` uses fixed address `#0038` for IM0/IM1. In IM2 it forms the table address from `I * 256 + vector`, reads the little-endian handler address, pushes the return PC, and clears IFF1/IFF2.
- The earlier `TGsZ80::IntVec()` lead is a separate GS Z80 core path, not the ATM host CPU path. `gsz80.h` declares that override; the ATM frame loop instead calls `cpu.IntVec()` on `TMainZ80`.
- The current upstream source inspection confirms the `TMainZ80::IntVec()` declaration but has not located its concrete definition or established its returned byte. Do not infer the vector from the frame cadence, FF77 gate, IM1 address, or the GS core.
- Project127 remains DI-only: no IM selection, no EI, no IM2 table contents, and no live IRQ handler. Next source-audit step is to locate the linked `TMainZ80::IntVec()` implementation and trace its return value in the exact Unreal Speccy build used for runtime testing.

### IRQ vector value — concrete implementation found

- The concrete ATM CPU implementation is in Unreal Speccy `vars.cpp`, `TMainZ80::IntVec()`: it returns `0xFF` when `CF_Z80FBUS` is clear; when that flag is set it returns the low byte of `rdtsc()`, so the vector is variable.
- `memory.cpp::set_banks()` clears and recalculates `CF_Z80FBUS`. It sets the flag when `conf.floatbus` is enabled (normal bus) or `conf.floatdos` is enabled while TR-DOS ports are active. The config parser's default for `FloatBus` is 0, but the user's active emulator configuration has not been inspected.
- Therefore the exact IM2 vector is **#FF only under the non-floating-bus configuration**. With floating bus enabled, a single #FF slot is not safe. Before live activation, the runtime configuration must be confirmed (or the Project127 IRQ mode must deliberately avoid dependence on a fixed IM2 vector).
- With `I=#B0` and vector `#FF`, the IM2 pointer bytes are at `#B0FF/#B100`; the existing 257-byte reserved W2/P2 table region `#B000..#B100` includes both bytes. No bytes are written yet.
- Keep IM/EI disabled until the active emulator configuration, handler location, stack mapping, and return path have all been verified.

### Active Unreal Speccy configuration — verified from repository unreal.ini

- `[ULA]`: `FloatBus=0`, `FloatDOS=0`.
- Active model/preset: `HIMEM=ATM710`, `Preset=ATM1_2_3.5MHz`; the selected preset also specifies `floatBus=0,floatDOS=0`.
- Thus, for the committed Project127 emulator configuration, `CF_Z80FBUS` remains clear in normal and TR-DOS operation, and `TMainZ80::IntVec()` returns the deterministic IM2 vector `0xFF`.
- With the existing candidate `I=0xB0`, the only vector slot required by this configuration is `#B0FF/#B100`. The table remains uninitialized until the handler address and executable mapping are verified.
- This confirms the vector condition from the repository's `unreal.ini`; it does not by itself prove the user's local INI has no uncommitted overrides or that the live IRQ path is safe.


### Latest integrated runtime — 2026-11-10 15:48

The user's new ATM Turbo 2+ runtime log reconfirms the previously accepted memory, video and ZX keyboard diagnostic results and adds the following observations:

- TR-DOS directory initialization completed before the system UI; the later directory read returned 8 sectors / 2048 bytes and listed `boot.B` and `P127BOOT.C`.
- DS12887 RTC probe through GLUK/SMUC succeeded: time read returned `15:48:04`.
- Memory initialization and fixed page map remained correct: P0/P2/P4 boot reservations, P1/P3/P5/P7 video reservations, P5 active; kernel image size `0x33AB`, bounds pass.
- Full physical W3 sweep again verified all 57/57 free pages, restored P0 and UI, and passed allocator exhaustion/recovery, PIN/UNPIN and cross-page span-copy tests.
- ATM video RG3/RG2/RG0/RG6 cycle and full-page P7/P3 CRC16 checks passed; UI restored.
- Speaker #FE D4 tone smoke test began and ended; no audio acceptance inferred.
- NEMO-DIVIDE LBA28 probe again found the master ready, read LBA 63 (512-byte sector with BPB and 55AA signature), and listed seven FAT16 root entries. Full FAT16 acceptance remains deferred.
- Keyboard again used ZX fallback, showed a matrix change on key press and returned to idle; monitor ended with `[KBD] DONE`. This does not test ATM XT extended-key protocol.
- IRQ preflights pass, but the log explicitly keeps vector/IM/EI disabled. No live IRQ acceptance is claimed.

No new failure is reported in this run. The IRQ stage remains the next active development item; do not enable IM/EI based on these preflight markers alone.


### Latest integrated runtime — 2026-11-10 15:52

The user's 15:52 ATM Turbo 2+ runtime log shows no new failure and reconfirms the integrated diagnostics:

- DS12887 RTC probe via GLUK/SMUC returned a time and reported `READ OK`.
- TR-DOS directory read completed: 8 sectors / 2048 bytes, with `boot.B` and `P127BOOT.C`.
- Memory map and kernel bounds remained correct; the full W3 sweep again verified 57/57 free pages and restored P0/UI.
- Allocator full-pool exhaustion/recovery, PIN/UNPIN and cross-page span-copy tests passed.
- ATM video RG3/RG2/RG0/RG6 cycle and P7/P3 full-page CRC16 passed.
- Speaker tone test began and ended; this remains a smoke test only.
- NEMO-DIVIDE LBA28 master probe, LBA 63 sector read and seven-entry FAT16 root scan succeeded. Full FAT16 acceptance remains deferred.
- Keyboard monitor selected ZX fallback and ended with `[KBD] DONE`. This particular run contains no matrix-change sample, so it confirms monitor completion but does not independently demonstrate a key press. ATM XT extended-key mode remains untested.
- IRQ frame/batch/table/mask/trampoline/window preflights passed, but the runtime still reports vector disabled and IM/EI/OUT disabled. No live IRQ was delivered or accepted.

The diagnostic text `SOURCE UNRESOLVED` in the IRQ batch marker is stale relative to the repository source audit, which has already identified the ATM host `TMainZ80::IntVec()` implementation and the configured #FF vector condition. It must not be interpreted as evidence that the upstream source audit is still unresolved. The live IRQ handler/activation path remains unverified; keep IM/EI disabled.


### IRQ — masked IM2 vector installation staged — 2026-11-10

- The boot path now installs the configured ATM710 IM2 vector while DI is asserted: vector byte #FF, I register #B0, pointer slot #B0FF/#B100.
- The slot receives the linked `p127_irq_entry` address and is read back for verification. The installer checks the reserved P2/W2 mapping and verifies that the handler address lies in fixed W2/P2 (#8000..#9FFF).
- The handler and stack use the fixed W2/P2 mapping; no W3 remap or hardware page OUT is involved.
- The installer selects IM 2 but never executes EI. IFF2 is checked after DI using the P/V flag from `LD A,I`; the check branches before any flag-changing instruction.
- The batch diagnostic message now reflects the source audit rather than claiming the source is unresolved.
- This is a source change only. Build and emulator runtime confirmation are pending. Do not claim live IRQ delivery, handler dispatch, or RETI under a real interrupt. Keep EI disabled until the next runtime log confirms the masked install marker and a separate controlled live-IRQ test is designed.


### Latest integrated runtime — 2026-11-10 16:33

The user's latest ATM Turbo 2+ runtime log confirms the masked IM2 installation stage and reconfirms the previously accepted subsystems:

- DS12887 RTC probe through GLUK/SMUC succeeded; time read returned `16:33:20`.
- TR-DOS directory read completed: 8 sectors / 2048 bytes; entries `boot.B` and `P127BOOT.C`.
- Kernel image size is now `0x3494`; P5/P2 bounds pass.
- Memory/page-management tests pass, including the complete W3 sweep (57/57 free pages), P0/UI restoration, allocator full-pool exhaustion/recovery, PIN/UNPIN and cross-page span copy.
- ATM video RG3/RG2/RG0/RG6 cycle and P7/P3 full-page CRC16 pass; UI restored.
- Keyboard ZX fallback matrix changed from `1F` to `1E` and returned to `1F`, demonstrating a key press and release in this run. ATM XT extended-key mode remains untested.
- NEMO-DIVIDE LBA28 master probe, LBA 63 sector read and seven-entry FAT16 root scan succeeded. Full FAT16 acceptance remains deferred.
- Speaker #FE D4 tone begin/end observed; audio acceptance remains deferred.

IRQ update:

- The runtime explicitly reports `IM2 VECTOR #FF INSTALLED AT B0FF; I=B0; DI; EI DISABLED`. This confirms the masked installer executed and its internal vector-slot readback checks passed.
- Subsequent IRQ table slot, mask/vector contract, resident trampoline and resident window preflights all pass.
- This supersedes the earlier runtime entries that said the vector was not installed. The initial boot diagnostic `IRQ TABLE USES RESERVED BOOT PAGE P2/W2; IM2 DISABLED` is emitted before the installer and is not the final IRQ state.
- Interrupts remain disabled: no `EI` was executed, no live frame interrupt was delivered to the handler, and no real interrupt/RETI roundtrip has been accepted. Keep live IRQ activation as the next IRQ test stage.
- This is user-confirmed emulator runtime evidence; it does not establish a separate clean rebuild in CI or live IRQ delivery.


### Latest integrated runtime — 2026-11-10 16:38

The user's latest ATM Turbo 2+ runtime log reports no new failures and reconfirms the integrated diagnostics:

- DS12887 RTC probe through GLUK/SMUC succeeded; time read returned `16:38:16`.
- TR-DOS directory read completed: 8 sectors / 2048 bytes, with `boot.B` and `P127BOOT.C`.
- Kernel image size remains `0x3494`; P5/P2 bounds pass.
- Memory/page-management checks pass, including the complete W3 sweep (57/57 free pages), P0/UI restoration, allocator exhaustion/recovery, PIN/UNPIN and cross-page span copy.
- ATM video RG3/RG2/RG0/RG6 cycle and P7/P3 full-page CRC16 pass; UI restored.
- NEMO-DIVIDE LBA28 master probe, LBA 63 sector read and seven-entry FAT16 root scan succeed. Full FAT16 functional acceptance remains deferred.
- Speaker #FE D4 tone begin/end markers are present; audio acceptance remains deferred.
- Keyboard monitor starts in ZX fallback and ends with `[KBD] DONE`. This log contains no matrix-change sample, so no key-press detection is newly claimed. ATM XT extended-key mode remains untested.

IRQ update:

- The synthetic `IRQ FRAME ROUNDTRIP PASS; VECTOR DISABLED` marker is an earlier software-only test and does not contradict the subsequent installer marker.
- The runtime again reports `IM2 VECTOR #FF INSTALLED AT B0FF; I=B0; DI; EI DISABLED`, followed by successful table-slot, mask/vector, resident-trampoline and resident-window preflights.
- The masked IM2 installation is therefore reconfirmed by this run. No `EI` was executed and no live frame interrupt, hardware handler entry or real interrupt/RETI roundtrip was observed. Live IRQ acceptance remains open; keep interrupts disabled.

This entry records user-supplied runtime evidence only; it is not an independent CI/build result.


### IRQ — controlled live-delivery test plan — 2026-11-10

The next IRQ stage is a deliberately bounded, opt-in runtime test. It is not part of normal boot and must not change the currently accepted DI-only startup behavior.

Test prerequisites:

- The active emulator preset must remain ATM710 with `FloatBus=0` and `FloatDOS=0`; the host ATM CPU must therefore supply vector `#FF`.
- The masked IM2 installer must report success: `I=#B0`, vector pointer at `#B0FF/#B100`, handler in fixed W2/P2, and P2 still reserved/mapped in W2.
- The existing ATM frame-interrupt gate (`FF77 bit #20`) must already be in the expected enabled state. The test must first inspect the current gate/configuration and must not blindly overwrite unrelated FF77 bits.
- The resident stack and handler window must remain fixed. No W3 lease/remap, memory allocator operation, video transition, or UI operation may run during the live window.
- Normal boot continues to execute `DI`; the live test is entered only by an explicit diagnostic action.

Bounded test sequence to implement:

1. With `DI` asserted, clear a dedicated IRQ-entry counter and arm a one-shot test state.
2. Confirm the IM2 vector/table and fixed W2/P2 mapping again immediately before activation.
3. Execute the controlled `EI` window and poll the counter using a finite instruction-count timeout; do not use an unbounded `HALT`.
4. On the first observed handler entry, execute `DI` immediately in the foreground before any other subsystem work. The handler increments only the dedicated counter and follows the existing full-register save/restore path to `RETI`.
5. Verify exactly one entry, intact foreground sentinel state, unchanged page mapping, and successful return to the instruction following the polling loop. A zero count is a timeout/failure; more than one entry is a failure, not a pass.
6. Restore the normal masked state and emit explicit PASS/FAIL/TIMEOUT markers. Any failure path must end in `DI`.

Important distinction: the emulator's frame INT is a CPU interrupt event, not an independently identified PIC/PIT device request. Do not add a speculative port-acknowledge sequence. The current evidence establishes the ATM frame source and IM2 vector behavior, but not a separate peripheral acknowledge protocol. If later source inspection establishes an acknowledge requirement, document and test it separately before adding it.

Acceptance requires a user-supplied emulator log showing a real handler-entry counter change during the bounded live window, exactly one entry, successful `RETI` return, and interrupts masked afterward. The existing synthetic CALL-based context test and masked installer markers do not satisfy this criterion.

**Current implementation status:** design recorded only. No live-test routine has been added or invoked; no `EI` is executed by normal boot. Keep live IRQ acceptance open until the above sequence is implemented, built, and observed in the emulator.


### Latest integrated runtime — 2026-11-10 16:58

The user's 16:58 ATM Turbo 2+ runtime log reports no new failures and confirms:

- DS12887 RTC probe through GLUK/SMUC succeeded; the read returned `16:58:01`.
- TR-DOS directory read completed: 8 sectors / 2048 bytes; entries `boot.B` and `P127BOOT.C`.
- Kernel image size remains `0x3494`; P5/P2 bounds pass.
- Memory/page-management tests pass, including the complete W3 physical sweep (57/57 free pages), P0/UI restoration, allocator exhaustion/recovery, PIN/UNPIN and cross-page logical span copy.
- ATM video RG3/RG2/RG0/RG6 cycle and P7/P3 full-page CRC16 pass; UI restored.
- NEMO-DIVIDE LBA28 master probe and LBA 63 sector read pass; FAT16 root scan lists seven entries: IO.SYS, MSDOS.SYS, DOS, COMMAND.COM, WINA20.386, CONFIG.SYS and AUTOEXEC.BAT. This remains probe/root-directory evidence only; full FAT16 write/cluster-chain acceptance is deferred.
- Speaker #FE D4 tone begin/end markers are present; audio remains a smoke test, not accepted functionality.
- Keyboard monitor starts in ZX fallback, prints the idle matrix and ends with `[KBD] DONE`. No matrix transition is shown in this log, so no key press/release detection is newly claimed. ATM XT extended-key mode remains untested.

IRQ update:

- The synthetic `IRQ FRAME ROUNDTRIP PASS; VECTOR DISABLED` marker remains a software-only test and is not evidence of a live interrupt.
- The subsequent `IM2 VECTOR #FF INSTALLED AT B0FF; I=B0; DI; EI DISABLED` marker reconfirms masked IM2 installation. Table-slot, mask/vector, resident-trampoline and resident-window preflights also pass.
- No `EI` was executed; no live frame interrupt, handler entry or hardware `RETI` roundtrip is shown. The controlled live-delivery test remains unimplemented/unaccepted. Keep normal boot masked.

This entry records only the user's supplied emulator runtime evidence; it is not an independent build or CI result.


### IRQ — bounded live frame-interrupt probe added — 2026-11-10

- Added a bounded live-delivery probe immediately after the masked IM2 install. It does not write ATM FF77 or any other I/O port; the existing host frame-interrupt gate is left untouched.
- The resident handler executes DI as its first instruction. While the probe is armed, its dispatcher consumes one event, clears the armed flag and increments a dedicated counter. RETI therefore returns with IFF1/IFF2 clear; repeated frame interrupts cannot re-enter during the foreground check.
- The foreground opens a finite EI window, polls a 16-bit instruction-count timeout, then verifies exactly one entry, a preserved DE sentinel, and IFF2 still clear. Timeout and all failure paths execute DI and disarm the probe.
- Boot reports either `IRQ LIVE ONE-SHOT PASS; RETI RETURNED; DI RESTORED` or `IRQ LIVE TEST TIMEOUT/STATE FAIL; DI RESTORED`. A timeout is diagnostic, not a boot halt, and does not claim IRQ acceptance.
- Source change only; clean build and emulator runtime confirmation are still required. PASS marker is live-delivery evidence; TIMEOUT means no interrupt was delivered within the bounded window. The test exits masked.



### Latest integrated runtime — 2026-11-10 17:05

The user's 17:05:39 ATM Turbo 2+ runtime confirms the prior memory, video, RTC, TR-DOS, HDD root-scan and keyboard-monitor results. The IRQ-specific observations are:

- Masked IM2 vector installation at #B0FF succeeds; table, mask/vector, trampoline and resident-window preflights pass.
- The newly added live probe reports `IRQ LIVE TEST TIMEOUT/STATE FAIL; DI RESTORED`. No live handler entry or real RETI return occurred. This run does not pass IRQ acceptance.
- Source audit of the matching Unreal Speccy ATM710 path explains a likely missing prerequisite: `set_atm_FF77()` assigns `cpu.int_gate = (comp.pFF77 & 0x20) != 0`. The ordinary/default reset path calls `set_atm_FF77(0,0)`, which closes the gate; the DOS reset path writes `0xE3`, which opens it. The emulator frame loop only calls `handle_int()` when `cpu.int_pend`, `cpu.iff1`, the EI-delay condition, and `cpu.int_gate` all permit delivery. The supplied runtime log does not identify which reset path/state established FF77, so the closed gate is a strong candidate, not yet proven for this exact run.
- The prior implementation violated the documented prerequisite by executing EI automatically without first establishing the ATM FF77 gate. Corrected boot behavior: the live probe is no longer invoked automatically; normal startup remains DI-only and prints `IRQ LIVE TEST SKIPPED; ATM FF77 GATE NOT CONTROLLED; DI`. The bounded probe routine remains available for a later explicitly controlled test.
- Do not write a guessed FF77 byte: the emulator's read path exposes only the low video-mode nibble, not the full FF77 value, so a read/modify/write cannot safely preserve all unrelated bits. Before re-enabling the probe, establish the exact startup FF77 state and a safe way to enable bit 5 without clobbering other state (or provide an explicit test setup that owns the whole register).
- This is based on user-supplied runtime evidence and source inspection; no independent build or emulator run is claimed.



### IRQ — legacy host frame-handler chaining integrated — 2026-11-10

- Adapted the archived `0/src.r2731/x86/x86.asm` interrupt ordering: save the complete Z80 register frame, chain the pre-existing host frame handler, then run the local dispatcher and restore the frame.
- In the current IM2 implementation the old handler is reached by `CALL #0038`; the existing #0038 bytes are not patched or replaced. This preserves the host ROM's frame service while retaining the already verified ATM710 IM2 #FF vector at #B0FF/#B100.
- Added a re-entry guard around the host chain. The archived host handler may execute EI before RET; the Project127 entry executes DI immediately after it returns. If a frame arrives in that EI/RET window, the nested entry skips a second host-chain call and still follows the resident save/restore + RETI path.
- The host chain is armed only after the masked IM2 installer has passed its table/handler checks. `p127_irq_init` clears both chain flags, so the synthetic CALL-based register test does not call the host ROM handler.
- Normal boot still does not execute EI and the live probe remains skipped. No FF77 writes, guessed gate values, peripheral acknowledge sequence, PIC/PIT model, or live-IRQ PASS claim were added.
- Source-level change only. A clean assembler build and emulator run are still required to verify the #0038 chain and its re-entry behavior. IRQ acceptance remains open.


### IRQ — committed Unreal Speccy reset configuration audit — 2026-11-10

- Inspected the repository's committed `unreal.ini` rather than inferring the active reset mode from TR-DOS activity. It explicitly contains `RESET=MENU`, not `RESET=DOS`; the ATM710 preset is `ATM1_2_3.5MHz`, with `FloatBus=0` and `FloatDOS=0`. The committed input configuration also has `ATMKBD=0`.
- Cross-checking the previously audited Unreal Speccy reset code: the ordinary/default reset path initializes FF77 to zero (interrupt gate bit #20 closed), whereas the DOS reset path initializes FF77 to #E3 (gate bit #20 open). Therefore the repository's configured MENU reset path points to the closed-gate explanation for the live IRQ timeout. This is a source/configuration conclusion; the exact FF77 value in the user's running emulator has not been read back.
- The fixed #FF IM2 vector remains correct for the committed `FloatBus=0` / `FloatDOS=0` configuration. That does not open the FF77 gate.
- No Project127 source code is changed to write FF77. The register's full value is not readable through the audited I/O read path, so a safe read/modify/write is unavailable. Do not substitute a guessed #20 or #E3 value: that would overwrite unrelated ATM state.
- The next safe route is an explicit emulator-side test setup that owns the complete FF77 value (or a dedicated emulator debug/control hook), followed by the already bounded one-shot live IRQ test. Normal Project127 boot remains DI-only and the live probe remains skipped.
- Source/configuration audit only; no assembler build or emulator run was performed for this note. IRQ remains unaccepted.


### Latest integrated runtime — 2026-11-10 19:02

The user's supplied ATM Turbo 2+ runtime log confirms:

- DS12887 RTC probe/read through GLUK/SMUC succeeds; observed time `19:02:11`.
- Memory/page-management path passes: 1 MiB/64 pages, bounds and negative-path checks, 57/57 free physical pages, W3/P0/UI restoration, allocator exhaustion/recovery, PIN/UNPIN and cross-page logical span copy.
- TR-DOS directory acquisition completes: 8 sectors / 2048 bytes; two entries (`boot .B`, `P127BOOT.C`) are listed.
- ATM video RG3/RG2/RG0/RG6 cycle and P7/P3 full-page CRC16 pass; UI restored.
- Speaker #FE D4 tone begins and ends; this remains a smoke test only.
- HDD transport now reports `DRIVER=NEMO-DIVIDE LBA28 0.1.2`, status `50`, Master Ready, and successful LBA 63 read with BPB/55AA validation. FAT16 root scan completes and lists seven entries (IO.SYS, MSDOS.SYS, DOS, COMMAND.COM, WINA20.386, CONFIG.SYS, AUTOEXEC.BAT). This accepts the current read-only root-directory scan only; cluster-chain/file loading and writes remain unaccepted.
- Keyboard diagnostic enters ZX fallback, prints the idle matrix and exits. No key transition is present, so key press/release detection is not newly accepted; ATM XT mode remains untested.

IRQ remains unchanged and unaccepted:

- IM2 #FF vector is installed at #B0FF with I=#B0 while DI is active; table/vector/trampoline/window preflights pass.
- Live IRQ is explicitly skipped because the FF77 gate is not controlled. No live handler entry, host #0038 chain execution, or RETI roundtrip is evidenced. Normal boot remains DI-only.
- This run is consistent with the prior FF77 gate diagnosis but does not independently prove the runtime FF77 value. Do not write a guessed FF77 byte. Next IRQ step remains a controlled emulator-side gate setup (or a debug/control hook that owns the complete FF77 value), then the bounded one-shot live test.

This entry records user-supplied runtime evidence only. No independent build or emulator run is claimed.

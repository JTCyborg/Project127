# Project127 ATM Core — implementation scenario

Scenario revision: **0.8.44**  
Status: **BOOT0, console, page-state self-test, bootstrap reservations, resident stack probe v0.1.0, software mapper model, handoff guard v0.2.2 and resident-window contract v0.1.0 and W3 rollback/recovery v0.3.0 accepted by user runtime test; resident trampoline address preflight v0.1.0 accepted by user runtime test; DI-only interrupt ownership preflight v0.1.0 runtime accepted; interrupt-enable readiness gate v0.2.0 runtime accepted; IRQ frame save/restore v0.4.1 runtime accepted by user #EF log; future IM2 table page P4 reserved in software v0.3.0 and slot preflight runtime accepted; software-only map transaction commit/rollback v0.3.0 runtime accepted; bounded console video-page switching active; general-purpose W3 RAM remapping v0.2.0 accepted by user runtime test**  
Repository baseline before this step: `8afc61d9c6bd1820c0c3cc8d0d42ff28828974d9`

## Fixed architecture requirements

1. ATM physical RAM is exactly 1 MiB (1,048,576 bytes).
2. ATM Turbo 2+ RAM consists of 64 physical pages × 16 KiB. The page dispatcher uses inverse page IDs on ports #3FF7/#7FF7/#BFF7/#FFF7; RAM selection sets D6=1 and D7=0. Hardware mapping remains disabled in Project127 until the mapper stage.
3. Kernel size is measured from the linked image/runtime layout; no guessed fixed kernel reservation.
4. Video memory reservations must cover every supported ATM/Spectrum video mode. Exact physical ranges are to be derived from Project112/Project126 source and validated before they are marked unavailable.
5. Free program memory is computed from the actual page map after kernel, video, firmware, stack, and device reservations.
6. The kernel API uses 32-bit unsigned lengths/offsets and checks overflow and physical bounds.
7. Context switching must preserve the complete Z80-visible execution context and the active page map. Interrupt mode/IFF restoration must be implemented through a safe interrupt-entry/return protocol, not guessed from an ordinary routine.
8. Programs may use a logical address space larger than 64 KiB only through a defined managed ABI/runtime. Unmodified Z80 binaries using arbitrary direct 16-bit memory references cannot be promised transparent access to >64 KiB: Z80 has no hardware page-fault mechanism.
9. ATM host owns physical peripherals. NeoGS is not treated as an independent external-device host; requests to host-owned devices use the defined host/DMA transport.
10. The kernel is placed in the lowest suitable RAM region directly adjacent to the system ROM boundary, subject to verified ATM mapping and exclusion of ROM/device/video windows. Its linked/runtime size determines its actual end; it is not relocated while applications run.\n11. The program arena is allocated top-down: its initial upper boundary is the highest eligible physical RAM address, and allocations extend toward lower addresses. The current lower boundary is calculated from the measured kernel end and all reserved regions. Allocation fails before crossing any reservation. Freeing memory contracts the arena upward where possible.\n12. Kernel and program placement are expressed in the physical memory map; the managed program ABI presents a continuous logical address space and hides physical page boundaries. This does not imply transparent direct addressing for arbitrary legacy Z80 binaries.\n13. The known-good BASIC loader and BOOT0 entry protocol remain intact. Extensions are added after the existing BOOT0 diagnostics.

## Implementation stages and module versions

| Stage | Status | Deliverable / acceptance |
|---|---|---|
| 0 — Bootstrap baseline | **PASS (baseline)** | BASIC `boot.B` loads `P127BOOT.C` at #6000; original four BOOT0 diagnostic lines retained. |
| 1 — Physical page-state manager | **PASS (runtime accepted)** | 64-entry page-state table; video and active boot-map reservations; allocate/free/reallocate smoke test. |
| 2 — Physical memory map | **PARTIALLY VERIFIED (software reservations runtime accepted)** | Project112/ATM2+ docs confirm page dispatcher encoding and video pages. Current bootstrap map: window 0=TR-DOS ROM; window 1=RAM page 5 (P127BOOT.C); window 2=RAM page 2 (resident UI/stack); window 3=RAM page 0 (host/staging). Reserve live RAM pages 0 and 2; page 5 is already reserved with video union. Low-kernel relocation and top-down arena still pending. |
| 3 — UINT32 memory/range API | PLANNED — UPDATED | Overflow-safe range validation, top-down arena allocation/free, copy/fill/compare across page boundaries, collision checks against kernel/video/device reservations. |
| 4 — Page mapper | **SOFTWARE MODEL + HANDOFF GUARD v0.2.2 RUNTIME ACCEPTED** | Page encoding, four shadow-port addresses, bootstrap shadow map and validation self-test. Hardware OUT writes remain disabled. |
| 5 — Process/context manager | **SOFTWARE PREFLIGHT + MAP TRANSACTION RUNTIME ACCEPTED** — stack probe v0.1.0, resident-window contract v0.1.0, W3 ownership v0.2.0, rollback/recovery v0.3.0, resident layout preflight v0.1.0, P4 table-slot preflight v0.3.0, map transaction v0.3.0 | Implement resident interrupt-entry/return and controlled physical W3 mapping. Physical remap remains blocked; independent physical stack backing and IFF/IM/vector handling are not proven. |
| 6 — Managed program address space | PLANNED | Loader, logical address space, cross-page memory API, relocation/ABI; document legacy-binary compatibility. |
| 7 — TR-DOS and filesystem services | PLANNED | Reuse Project126 routines after dependency and device-map audit. |
| 8 — Video service | PLANNED | All ATM/Spectrum modes, framebuffer ownership and DMA/display handoff. |
| 9 — RTC and input | PLANNED | DS12887/SMUC and keyboard/input host services. |
| 10 — Physical storage | PLANNED | Nemo IDE/SMUC IDENTIFY, READ, WRITE, FLUSH with LBA and RAM bounds checks. |
| 11 — Audio and timer/events | PLANNED | Speaker/audio, timer, interrupt dispatch and event queues. |
| 12 — Integration/acceptance | PLANNED | Multi-page program, context-switch, video coexistence, storage and peripheral regression suite. |

## Versioned module register

| Module | Version | State |
|---|---:|---|
| `src/boot/p127_boot.asm` | 0.7.1 | BOOT0 preserved; reserves P4 for future IM2 table and runs its software preflight |
| `src/kernel/p127_mem.asm` | 0.4.1 | Software page-state manager; Stage 2.19 validates full allocator exhaustion/reuse and reserved-page invariants through physical-memory batch |
| `src/kernel/p127_map.asm` | 0.3.0 | Software mapper plus full-map transaction snapshot, commit, accept, post-commit fault injection and rollback; no OUT |
| `src/ui/p127_console.asm` | 0.1.2 | ATM RG6 80x25 console; screen/log output mirrored to #EF |
| `src/kernel/p127_handoff.asm` | 0.1.0 | Resident stack-switch integrity probe; no physical remap |
| `src/kernel/p127_irq.asm` | 0.5.0 | DI-only contract; 16-check exhaustive readiness-mask/prerequisite batch runtime accepted; P4 IM2 table reservation and address preflight; no EI/IM or physical mapping |
| `src/kernel/p127_physmem.asm` | 0.3.4 | Full free-page allocation/uniqueness sweep; per-page address-pattern fill/reverse verification; allocator state/reservation/reuse checks; W3/P0 recovery |
| `src/kernel/p127_resident.asm` | 0.4.0 | Fixed W1/P5 resident code/data + W2/P2 live-stack address preflight; W3 ownership and software rollback; no page OUT |
| `src/main.asm` | existing | Build entry; assembles boot and included kernel modules |
## Stage 1 — physical page-state manager 0.2.0

- Page IDs: 0..63; page size: 16 KiB.
- Per-page states: FREE=0, RESERVED=1, ALLOCATED=2.
- `p127_mem_reserve`: A=first page, B=count; validates full range and overlap before changing state.
- `p127_mem_alloc`: first-fit allocation.
- `p127_mem_free`: only releases ALLOCATED pages; RESERVED pages cannot be freed.
- `p127_mem_reserve_video`: reserves the union of ATM video pages 1, 3, 5, 7.
- `p127_mem_reserve_boot`: additionally reserves page 0 (window 3 host/staging) and page 2 (window 2 resident UI/stack); page 5 (window 1 boot image) is already reserved by the video union.
- `p127_mem_selftest`: verifies video and bootstrap pages cannot be freed, then allocate -> free -> allocate same first-fit page -> free.
- Boot emits `MEM INIT` and `MEM PAGE TEST PASS/FAIL` on #EF after the original BOOT0 messages.

**Acceptance boundary:** the smoke test validates software state transitions only. It does not validate ATM physical page IDs, hardware mapping, video reservations, DMA, or availability of pages for applications. The allocator must not be exposed to application loading until Stage 2 supplies the verified physical map.

## Project126 reuse policy

Project126 `docs/src.r2731` is the source base for reusable kernel services and drivers. Reuse is conditional on auditing each module's assumptions about ATM model, memory windows, page IDs, interrupt model, and hardware ports. Project126's existing 16 KiB window API is not itself the Project127 large-address-space implementation. Drivers are ported in stages and retain source provenance/version notes.

## Stage log

### 2026-11-09 — Stage 1 code added

- Added `src/kernel/p127_mem.asm` v0.1.0; corrected zero-length reservation handling in v0.1.1 and first-page argument preservation in v0.1.2.
- Updated `src/boot/p127_boot.asm` v0.3.0 to initialize the table and run the allocator smoke test after the four original BOOT0 diagnostics.
- Added `tests/ATM_CORE_STAGE1.md`.
- Source/build verification: **not run in this environment**. User must build with `tools/build_project127.ps1` and run the TR-DOS image in the target emulator.
- Expected additional #EF lines: `[P127] MEM INIT 1MB/64P`, then `[P127] MEM PAGE TEST PASS`.
- Next: confirm the exact Stage 1 log; then derive the real physical map and all video reservations from Project112/Project126 before enabling application allocations.


## Architecture decision record — kernel and program arena placement (2026-11-09)

**Decision:** Keep the kernel as close as the verified ATM memory map permits to the system ROM boundary. The kernel occupies a stable low-address RAM region adjacent to ROM, without assuming a fixed kernel size. The kernel's actual end is obtained from linker symbols/runtime layout.

**Program arena:** Program memory grows from the high end of eligible RAM toward lower addresses. The allocator maintains a descending high-water boundary. A request of N bytes/pages is validated against the current lower limit, kernel end, video reservations, firmware, stacks, and device windows before the boundary is changed. Release returns space to the arena; coalescing and per-process ownership are part of the later allocator implementation.

**Why:** The kernel remains in a stable location for system calls, interrupt dispatch, drivers, and compatibility services. Top-down program allocation makes the available program region adapt to the actual kernel footprint and fixed reservations without hardcoding a maximum kernel reservation.

**Implementation constraint:** This is a placement policy, not yet a physical-address assertion. Stage 2 must inspect the actual ATM ROM/RAM banking and Project112 video layouts before assigning page IDs or emitting hardware mapping writes. The existing Stage 1 page-state module remains accounting-only until then.

**Next acceptance:** Stage 2 must report the verified ROM boundary, kernel load/start/end, all reserved physical ranges, highest eligible RAM address, and computed initial program-arena size in the #EF boot log and scenario table.


### 2026-11-09 — Stage 2.1: video-page map confirmed and reserved

- Inspected Project112 `112/src/mode_atm.asm`, `112/src/video_mode_control.asm`, and ATM Turbo 2+ architecture documentation.
- Confirmed physical ATM RAM page IDs: ZX video uses page 5 or 7; ATM640, EGA and 80x25 text use pairs 5+1 or 7+3 depending on the selected video bank.
- Reserved the union `{1,3,5,7}` (64 KiB) in `p127_mem_reserve_video`; these pages are not available to program allocations in any supported mode.
- `src/kernel/p127_mem.asm` advanced to v0.2.0. Boot logs the reservation result and tests that reserved pages cannot be freed.
- Still not implemented: actual low-memory kernel relocation, ROM-window mapping, kernel-end discovery, top-down program arena, and hardware page switching. These require the Stage 2 memory-map transition and must not be inferred from the video page IDs.
- Build/emulator verification remains pending; expected log includes `[P127] VIDEO RAM RESERVED P1,P3,P5,P7` before the allocator self-test.


### 2026-11-09 — Stage 2.2: Project126 ATM console port v0.1.0

- Ported the required console renderer from `Project126/atm_host/p126_screen_console.asm` into `src/ui/p127_console.asm`.
- Retained ATM Turbo 2+ RG6 text mode, 80×25 layout, upper 12-row status panel, lower 13-row scrolling log, video-page map/restore and host-page preservation.
- UI module is placed at `#A000`; the existing BOOT0 code remains at `#6000` with its existing `#A000` upper bound. `P127BOOT.C` now contains the image from `#6000` through the end of the console, with an assembler bound at `#B000` to leave stack headroom below `#BFFF`.
- Console startup occurs after the original BOOT0 diagnostics. The `p127_puts` sink routes subsequent diagnostic characters through `BIOS_DebugConsole_PrintChar`.
- `BIOS_DebugConsole_PrintChar` emits each character to `#EF`; `BIOS_DebugConsole_PrintAt` mirrors static status-panel characters and appends CR/LF. The visible status panel and scrolling log are therefore also represented in the port log.
- Module versions: `src/boot/p127_boot.asm` 0.4.0; `src/ui/p127_console.asm` 0.1.0; scenario 0.5.0.
- Build and Unreal Speccy runtime acceptance have not yet been run; ATM shadow-port setup and page mapping require target verification.


### 2026-11-09 — Stage 2.2 build correction: console v0.1.1

- Removed the accidentally duplicated `BIOS_DebugConsole_PrintChar` body that caused duplicate global and local labels.
- Replaced relative `JR` branches in the console module with absolute `JP` branches. This removes the ±128-byte displacement limit encountered after integrating the larger renderer.
- No changes to BOOT0 entry, BASIC loader, memory allocator, or UI address placement.
- Module version: `src/ui/p127_console.asm` 0.1.1; scenario revision 0.5.1.
- Build and emulator verification remain pending.


### 2026-11-09 — Stage 2.3: ATM Turbo 2+ bootstrap map and safe reservations

- Audited Project112 `112/src/main.asm`, `112/src/video_mode_control.asm`, `112/src/mode_atm.asm`, the Project127 Project126-derived console, and the ATM Turbo 2+ architecture document, section 4.1.
- Confirmed the four 16 KiB CPU windows are independently selected through shadow ports #3FF7 (window 0), #7FF7 (window 1), #BFF7 (window 2), and #FFF7 (window 3).
- For RAM pages, D0-D5 carry the inverted physical page number, D6=1 selects RAM, and D7=0 disables #7FFD page-bit substitution. Thus page 5 is encoded as #7A, page 1 as #7E, page 7 as #78, page 3 as #7C, and page 0 as #7F. The mapper is documented but not yet activated by Project127.
- Confirmed the active bootstrap layout: window 0 remains TR-DOS ROM; window 1 uses RAM page 5 (loaded code at #6000); window 2 uses RAM page 2 (resident console at #A000 and stack at #BFFF); window 3 is restored as RAM page 0 by the Project126-derived console host-page routine.
- Added `p127_mem_reserve_boot` in memory module v0.3.0 to reserve live bootstrap pages 0 and 2. Page 5 is already reserved by the video union. The self-test now verifies pages 0,1,2,3,5,7 cannot be freed.
- Boot now reports `[P127] BOOT MAP RESERVED P0,P2; P5 ACTIVE` before the allocator test.
- This is conservative accounting of the current boot map, not kernel relocation or a runtime physical-bank probe. The first allocator page should now be page 4; verify this in the next emulator run.
- Next: implement a controlled page-mapper API using the verified inverse encoding, preserving the active map and refusing to remap windows containing the currently executing kernel/stack.

### 2026-11-09 — Runtime acceptance: BOOT0, console and Stage 1 memory smoke test

- User-reported emulator output confirms the BASIC loader and second-stage entry at `#6000`; stack initialization at `#BFFF`; debug transmission through port `#EF`; and `BOOT0 PASS; IDLE`.
- Project127 ATM RG6 console starts and reports `UI READY; ALL DEBUG OUTPUT MIRRORED TO EF`.
- Physical page-state manager initializes its 64-page / 1 MiB accounting table; video pages P1, P3, P5 and P7 are reserved; allocator smoke test reports `MEM PAGE TEST PASS`.
- Acceptance applies to the software page-state manager and visible console/log path only. It does not yet prove physical bank-register mapping, true physical page IDs on hardware, kernel relocation, DMA, or application memory availability.
- RTC diagnostic remains `NOT INITIALIZED`; RTC/SMUC integration remains open under Stage 9.
- Runtime acceptance source: user-provided emulator log in the Project127 development conversation.
- Next implementation step: audit the real ATM Turbo 2+ memory map and ROM/RAM banking against Project112 before implementing low-memory kernel placement, runtime kernel-end discovery, and the top-down program arena. Do not expose the current page allocator to application loading until that map is verified.


### 2026-11-09 — Stage 2.3 build correction: memory manager v0.3.1

- User build with SjASMPlus v1.24.0 reported two relative-branch range errors in `p127_mem.asm` (source lines 38 and 41): both branches targeted the shared `p127_mem_error` handler beyond the signed 8-bit JR displacement.
- Replaced only those two conditional relative branches with absolute conditional `JP` instructions. Reservation validation and error handling are unchanged.
- Advanced `src/kernel/p127_mem.asm` from v0.3.0 to v0.3.1; scenario revision 0.6.1.
- The reported assembler failure is addressed at source level. A fresh SjASMPlus build and emulator run are still required; no successful build is claimed.


### 2026-11-09 — Runtime acceptance: bootstrap reservations v0.3.1

- User rebuilt and ran the Project127 TR-DOS image after commit `a126a26`.
- The supplied #EF log confirms `MEM INIT 1MB/64P`, `VIDEO RAM RESERVED P1,P3,P5,P7`, `BOOT MAP RESERVED P0,P2; P5 ACTIVE`, and `MEM PAGE TEST PASS`.
- Stage 1 page-state manager and the Stage 2.3 bootstrap reservation calls are accepted in the emulator.
- The acceptance covers software bookkeeping and reservation guards only. It does not prove physical page-register writes, actual physical bank identity, remapping, or program arena availability.
- No module code changed in this acceptance update. Scenario revision advanced to 0.6.2.
- Next: implement a pure ATM page-register encoding/state model and self-tests first. Keep hardware OUT writes disabled until the safe remap protocol can preserve the executing code, UI, and stack windows.


### 2026-11-09 — Stage 2.4: pure ATM page-mapper model v0.1.0

- Added `src/kernel/p127_map.asm` v0.1.0. The module encodes physical page IDs 0..63 as `#7F-page`, rejects page 64+, returns the four documented shadow-port addresses, and stores the current bootstrap map (W0=TR-DOS ROM, W1=P5, W2=P2, W3=P0) in a software shadow table.
- Added a self-test for page encodings P0/P1/P3/P5/P7/P63, rejection of P64, window-port values #3FF7/#7FF7/#BFF7/#FFF7, invalid window 4, and all four bootstrap shadow entries.
- Boot calls the mapper self-test after the accepted memory-page test and reports `[P127] MAP MODEL TEST PASS; OUT DISABLED` or `MAP MODEL TEST FAIL` through the existing console/#EF diagnostic path.
- No hardware `OUT` instruction is present in the mapper module. No active window is changed. The allocator remains unavailable to application loading.
- Module versions: `p127_map.asm` 0.1.0; `p127_boot.asm` advanced to 0.5.0; scenario revision 0.7.0.
- Build and emulator runtime verification are **pending**. The test validates software constants/state only, not physical ATM bank-register behavior.
- Next: user builds/runs and supplies the #EF log. After acceptance, implement a safe remap handoff that executes from a stable, non-remapped window and preserves the stack/UI before any physical page-register write is enabled.


### 2026-11-09 — Build correction: mapper include and diagnostics v0.5.1

- User build exposed unresolved labels `p127_map_init`, `p127_map_selftest`, `p127_msg_map_pass`, `p127_msg_map_fail`.
- Root cause: the two mapper/memory INCLUDE directives had been written on one line with literal backslash-n characters, so SjASMPlus did not process them as separate directives. The two mapper diagnostic string labels were also missing.
- Corrected `src/boot/p127_boot.asm` to contain separate physical INCLUDE lines and added both diagnostic strings.
- Boot module version: 0.5.1. Scenario revision: 0.7.1.
- Rebuild/runtime verification pending user confirmation.


### 2026-11-09 — Build correction: mapper shadow lookup v0.1.1

- User build with SjASMPlus v1.24.0 reported `p127_map.asm(75): error: [JR] Target out of range (+225)`.
- Root cause: `p127_map_get_shadow` used a relative conditional branch to the shared `p127_map_invalid` handler, which is 225 bytes away and outside the signed 8-bit JR range.
- Replaced `JR NC,p127_map_invalid` with absolute `JP NC,p127_map_invalid`. Validation semantics are unchanged.
- Advanced `src/kernel/p127_map.asm` from v0.1.0 to v0.1.1; scenario revision 0.7.2.
- This addresses the reported assembler error at source level. Fresh SjASMPlus build and emulator runtime test remain pending; no successful build is claimed.


### 2026-11-09 — Runtime acceptance: software page-mapper model v0.1.1

- User rebuilt Project127 and supplied the emulator #EF log ending with `[P127] MAP MODEL TEST PASS; OUT DISABLED`.
- The complete reported boot sequence also confirms BASIC LOAD, Stage 2 entry at #6000, stack setup at #BFFF, debug output through #EF, UI startup, 1 MiB/64-page memory-state initialization, video reservations P1/P3/P5/P7, bootstrap reservations P0/P2 with P5 active, and the memory-page self-test.
- Stage 2.4 software mapper model v0.1.1 is accepted at runtime: the model's encoding, window-port lookup, bootstrap shadow map, and self-test pass.
- Acceptance is strictly software-only. Hardware page switching remains disabled; no physical OUT writes, safe remap handoff, or application-memory allocation have been validated.
- RTC remains `NOT INITIALIZED`; this is unchanged and outside this stage.
- Next stage: design and implement the remap handoff with explicit execution-window, stack, UI, interrupt and rollback protections. Keep hardware OUT disabled until the handoff can be tested without risking the active boot environment.


### 2026-11-09 — Stage 2.5: software-only safe-remap handoff gate v0.2.0

- Added `p127_map_handoff_prepare`: caller supplies the target window, destination physical page, and a four-bit protected-window mask. The routine rejects invalid windows/pages and any target marked protected; otherwise it stages a pending request in RAM.
- Added `p127_map_handoff_abort` to clear a staged request.
- Added self-tests for all four bootstrap windows being protected, rejection of invalid window/page values, a synthetic case with W0 explicitly declared stable, pending-request contents, and abort.
- The bootstrap protection mask is currently `#0F`: W0=TR-DOS ROM, W1=executing Stage 2 code, W2=UI/stack, W3=host/staging. Therefore no real bootstrap window is eligible for remapping. The synthetic W0 case tests the guard logic only; it does not assert that W0 is safe in the real system.
- Boot module advanced to v0.5.2 and now emits `[P127] HANDOFF GUARD TEST PASS; OUT DISABLED` when the new self-test passes.
- **No OUT instructions, physical remap, page-table commit, or automatic protection-mask discovery are implemented.** Caller correctness in declaring every live window protected remains a requirement. The guard is a software preflight model, not yet the final executable handoff trampoline.
- Build/runtime verification of this new stage is pending. Existing accepted tests remain accepted; do not interpret the new pass message until the user rebuilds and runs this revision.
- Next: after user acceptance, design a resident trampoline and stack transition located in a verified stable mapping, then validate interrupt/IFF handling and rollback before considering any physical page-port write.


### 2026-11-09 — Build correction: handoff reject target v0.2.1

- User's SjASMPlus v1.24.0 build reported three unresolved references to `p127_map_handoff_reject` in `p127_map_handoff_prepare`.
- Root cause: the preflight routine branched to a shared rejection target that had not been defined.
- Added `p127_map_handoff_reject` as a local failure exit that sets carry and returns, matching the documented API. Invalid page, invalid window, and protected-window paths now share this target.
- Mapper module advanced to v0.2.1; scenario revision 0.8.1.
- This is a source-level correction only. Rebuild and runtime test of the handoff guard remain pending; do not use an older disk image.


### 2026-11-09 — Runtime correction: handoff guard v0.2.2

- User emulator log reached `MEM PAGE TEST PASS` and then reported `HANDOFF GUARD TEST FAIL`; therefore the failure is inside the new software-only handoff self-test, before any hardware page-port write.
- Root cause: `p127_map_handoff_prepare` retained the target window in D, then used DE as a table offset without clearing D. The mask lookup therefore addressed memory outside the four-entry `p127_map_window_mask` table for windows 1–3. The test also did not invalidate an older staged request when a subsequent request was rejected.
- Corrected the index to DE=0:E, preserved the target window in E, and clear `p127_map_pending_valid` at the start of every preparation attempt. A rejected request can no longer leave a stale pending request.
- Extended the self-test: after a successful synthetic staging, a protected-window rejection must clear pending_valid; invalid window and invalid page rejections must also leave it clear.
- Mapper module advanced to v0.2.2; scenario revision 0.8.2. No physical OUT or bank switching was added.
- Build and emulator verification of this correction remain pending user confirmation.


### 2026-11-09 — Runtime acceptance: handoff guard v0.2.2

- User rebuilt and ran the current Project127 image after mapper correction commit `ce4bb5c`.
- The supplied #EF log reached all three final diagnostics: `HANDOFF GUARD TEST PASS; OUT DISABLED` and `MAP MODEL TEST PASS; OUT DISABLED`, following `MEM PAGE TEST PASS`.
- Stage 2.5 software-only handoff guard v0.2.2 is accepted in the emulator. This confirms protected-window rejection, synthetic safe-window staging, pending-state validation, abort, and rejection cleanup as exercised by the current self-test.
- This acceptance does not validate a real stable execution window, stack migration, interrupt-vector ownership, IFF/IM state restoration, rollback after a physical bank write, or any actual hardware bank switch. No physical `OUT` has been enabled.
- Scenario revision advanced to 0.8.3. No source module changed in this acceptance update.
- Next implementation stage is a separately tested resident handoff/trampoline model. First map the exact live code/data/stack/interrupt/vector dependencies and prove a scratch stack transition without touching a bank port. Only after that test passes may the design specify a hardware commit sequence and rollback. The current bootstrap has no unprotected window (`C=#0F`), so it is not eligible for physical remapping.


### 2026-11-09 — Stage 2.6: resident stack handoff probe v0.1.0

- Added `src/kernel/p127_handoff.asm` v0.1.0, resident in the Stage2 image/W1/P5 alongside the kernel code.
- Audited the current linked layout: Stage2 and mapper code execute from W1/P5; the console image is placed at `#A000` and bounded by `#B000`; the active bootstrap stack is in W2/P2 with initial SP `#BFFF`. The interval `#B000..#BFFF` is therefore available for explicit stack budgeting, subject to the runtime low-water guard.
- The probe saves the caller's register frame and exact SP in resident W1 data, refuses to run if the saved live SP is below `#B900`, places guard bytes at `#B7FE/#B7FF`, switches SP to `#B880`, exercises nested CALL/PUSH/POP and sentinel integrity, checks the guard bytes, and restores the exact original SP/register frame.
- The scratch stack occupies the bounded interval `#B800..#B87F`; a 128-byte gap separates it from the declared live-stack low-water boundary. This is an isolated software stack test, not a mapping transition: W2/P2 remains mapped for the entire routine.
- Interrupts are disabled defensively and remain disabled on return. IM and interrupt vectors are not modified. The routine does not claim to save/restore an enabled IFF state; callers must enter from the boot's DI-protected phase.
- Boot module advanced to v0.5.3 and now reports `RESIDENT STACK PROBE PASS; OUT DISABLED` or `RESIDENT STACK PROBE FAIL`.
- No physical `OUT`, remap, or stack-in-another-physical-page operation is introduced. A future remap trampoline still requires a separately reserved resident code page and a stack page that is independent of whichever window is targeted; the current all-protected bootstrap map is not eligible for remapping.
- Build and emulator runtime verification are pending user confirmation.


### 2026-11-09 — Runtime acceptance: resident stack handoff probe v0.1.0

- User rebuilt and ran the Project127 image containing commit `5160e3b`.
- The supplied #EF runtime log reached `[P127] RESIDENT STACK PROBE PASS; OUT DISABLED`, followed by `HANDOFF GUARD TEST PASS; OUT DISABLED` and `MAP MODEL TEST PASS; OUT DISABLED`.
- Stage 2.6 resident stack probe v0.1.0 is accepted in the emulator. The reported pass confirms the probe's bounded scratch-stack exercise, nested CALL/PUSH/POP checks, sentinel/canary checks and return to the saved stack frame as implemented by the self-test.
- This is a same-window stack-pointer transition: W2/P2 remains mapped. It does not prove a stack backed by an independent physical page, safe remapping of any window, physical page-port writes, interrupt-mode/IFF restoration, or rollback after a bank change.
- The boot test is entered with interrupts disabled; the probe leaves them disabled and does not modify IM or interrupt vectors.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.5.
- Next: define and reserve a genuinely independent resident execution/data/stack region, then validate interrupt-entry and return conventions. Keep physical page switching disabled until the trampoline, stack and rollback path are independent of the target window and have explicit runtime coverage.

### 2026-11-09 — Stage 2.7: resident-window contract v0.1.0

- Added `src/kernel/p127_resident.asm` v0.1.0 and boot integration v0.5.4.
- Fixed the first remap contract explicitly: W1/P5 contains resident execution and resident data; W2/P2 contains the resident stack/control state; W3 is the sole candidate target window; W0 remains ROM.
- The validator rejects any target other than W3, any code window other than W1, any stack window other than W2, and any request whose UI-quiesced flag is not set. It also explicitly checks target/resident-window separation.
- The self-test exercises the valid synthetic W3 case and rejects attempts to target W1/W2, a non-quiesced UI state, and a displaced resident-code window.
- Important: the self-test passes a synthetic quiesced-UI flag. It does not actually stop the console or its page-restore routines. The existing UI uses W3 as a temporary video/staging window and restores P0, so physical W3 remapping must remain disabled until the UI is explicitly suspended and cannot execute again before restoration/reinitialization.
- This stage formalizes a safe candidate topology; it does not reserve or map a new physical page, execute from an independent physical page, change the active map, or issue `OUT`.
- Boot reports `RESIDENT WINDOW CONTRACT PASS; OUT DISABLED` when the software contract tests pass.
- Build and emulator runtime verification are pending user confirmation. Scenario revision 0.8.6.
- Next: implement an explicit UI quiesce/resume state machine and host-staging ownership transfer for W3. Only after that is runtime-verified may W3 become a physical remap candidate. Keep all physical bank writes disabled.


### 2026-11-09 — Runtime acceptance: resident-window contract v0.1.0

- User rebuilt and ran the Project127 image and supplied the complete #EF log.
- The log confirms the existing bootstrap path: BASIC load, Stage 2 entry at #6000, stack at #BFFF, BOOT0, console/debug mirror, 1 MiB / 64-page software memory initialization, video/bootstrap reservations, and page-state self-test.
- The new line `RESIDENT WINDOW CONTRACT PASS; OUT DISABLED` confirms that resident-window contract self-test v0.1.0 executes successfully in the user's emulator.
- The same run also reports `RESIDENT STACK PROBE PASS; OUT DISABLED`, `HANDOFF GUARD TEST PASS; OUT DISABLED`, and `MAP MODEL TEST PASS; OUT DISABLED`.
- Acceptance is limited to software validation and the synthetic quiesced-UI test input. It does not prove that the console is actually quiesced, that W3 ownership is transferred, or that any physical page mapping is changed.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.7.
- Next implementation stage: inspect the actual console's W3 access/restore paths and implement a real software UI quiesce/resume plus W3 ownership state machine. Physical `OUT` remains disabled.


### 2026-11-09 — Stage 2.8: UI quiesce and W3 software ownership v0.2.0

- Added the W3 lifecycle state machine to resident module v0.2.0: UI_ACTIVE/UI owner, QUIESCED/no owner, and QUIESCED/HANDOFF owner. Transitions reject a busy UI, repeated quiesce/resume, incorrect owner, and UI writes while quiesced or handed off.
- Added short UI writer leases around the console's public character and positioned-text output routines. A lease is released on normal completion; a denied entry returns without touching the screen or debug port.
- Boot initializes the ownership manager before UI startup and runs a self-test covering busy quiesce rejection, successful quiesce, blocked UI entry, exclusive handoff acquire/release, resume, duplicate-resume rejection, and post-resume writer admission.
- Boot module v0.5.5; console module v0.1.1. Diagnostic: `UI QUIESCE/W3 OWNERSHIP PASS; OUT DISABLED`.
- This is a software lease/state machine only. It does not remap W3 or issue page-port OUT, and does not prove asynchronous interrupt exclusion. Existing video initialization/clear executes before the handoff self-test. Low-level page-map/restore helpers remain hardware operations and must only be reached through guarded public writers after initialization.
- Build and emulator runtime verification are pending user confirmation. Scenario revision 0.8.8.
- Next: run the new diagnostic in the user's emulator and add explicit rollback/recovery validation before any physical W3 remap is considered.


### 2026-11-09 — Build correction: UI quiesce/W3 ownership v0.2.1

- User's SjASMPlus v1.24.0 build of commit `19e37ad` failed on two out-of-range conditional relative branches in boot, one out-of-range conditional relative branch in the console, and missing W3 ownership diagnostic labels.
- Replaced the boot memory-reservation failure branches and console writer-denial branch with absolute conditional `JP` instructions.
- Added the missing `p127_msg_w3_pass` and `p127_msg_w3_fail` strings at the actual diagnostic-string section. The previous patch attempted to insert them using a label form that does not exist in this source file.
- Corrected a related parameter-preservation issue in `BIOS_DebugConsole_PrintAt`: the W3 lease routine changes A, so the caller's AF/BC/DE/HL frame is restored and re-stacked after successful lease acquisition before row/column parameters are consumed.
- Boot module remains v0.5.5; resident module remains v0.2.0; console module advanced to v0.1.2. Scenario revision 0.8.9.
- This addresses the exact reported assembler errors and the adjacent PrintAt parameter-clobber defect. A fresh SjASMPlus build and emulator run are still required; no successful build is claimed. Physical page-port `OUT` remains disabled.


### 2026-11-09 — Build correction: W3 diagnostic labels restored v0.5.6

- The user's fresh SjASMPlus v1.24.0 build still reported unresolved `p127_msg_w3_pass` and `p127_msg_w3_fail` in `p127_boot.asm`.
- Re-inspection of the actual merged `main` HEAD showed that the previous correction's documentation claimed the two strings had been added, but the committed boot source did not contain either definition. The calls were present after `p127_w3_selftest`, and the failure path referenced the missing fail label.
- Added both exact global labels and their diagnostic strings immediately after the existing handoff diagnostics, before the kernel INCLUDE directives. This matches the source's actual label-based layout and ensures both definitions are in the same assembly unit.
- Advanced boot module to 0.5.6; scenario revision 0.8.10. No resident ownership logic or physical mapping behavior changed.
- Fresh SjASMPlus build and emulator runtime verification remain pending. No successful build is claimed; physical page-port OUT remains disabled.


### 2026-11-09 — Runtime acceptance: UI quiesce/W3 ownership v0.2.0

- User rebuilt and ran the Project127 TR-DOS image after boot diagnostic-label correction v0.5.6. The supplied runtime log reaches `UI QUIESCE/W3 OWNERSHIP PASS; OUT DISABLED` and continues through `RESIDENT WINDOW CONTRACT PASS; OUT DISABLED`, `HANDOFF GUARD TEST PASS; OUT DISABLED`, and `MAP MODEL TEST PASS; OUT DISABLED`.
- Stage 2.8 software W3 lifecycle and UI writer-lease self-test v0.2.0 is accepted in the emulator. The log also reconfirms memory-page accounting, video/bootstrap reservations, and the resident stack probe.
- Acceptance is limited to software state/lease behavior. It does not prove asynchronous interrupt exclusion, actual UI shutdown during a physical remap, independent physical stack backing, page-register writes, or rollback after a hardware bank change. Physical page-port `OUT` remains disabled.
- No functional module code changed in this acceptance update. Scenario revision advanced to 0.8.11.
- Next: implement and test explicit rollback/recovery using the software model only, including failed acquisition, failed transition, and restoration of the prior owner/state. Keep physical page-port writes disabled until rollback, interrupt/IFF handling, and all resident dependencies are validated.


### 2026-11-09 — Stage 2.9: W3 software rollback/recovery model v0.3.0

- Added a complete software ownership snapshot tuple (state, owner, busy) and a rollback routine that restores that tuple without touching hardware.
- Added a recovery self-test covering failed HANDOFF acquisition from UI_ACTIVE/UI, rejection of quiesce while a UI lease is busy, exact restoration of the active/busy UI tuple, successful quiesce followed by HANDOFF acquisition and a rejected transition while HANDOFF owns W3, rollback to QUIESCED/NONE, UI resume, and a fresh successful UI lease.
- Boot runs this test after the accepted W3 ownership self-test and reports W3 ROLLBACK/RECOVERY PASS; OUT DISABLED or W3 ROLLBACK/RECOVERY FAIL.
- Resident module advanced to 0.3.0; boot module to 0.5.7; scenario revision 0.8.12.
- This validates RAM-backed software state restoration and post-recovery UI admission only. It does not model or validate rollback after a physical page-register write, asynchronous interrupt exclusion, actual UI quiescence during remap, or hardware page switching. Physical page-port OUT remains disabled.
- Build and emulator runtime verification are pending. Do not treat the new recovery test as accepted until the user supplies a fresh SjASMPlus build and runtime log.


### 2026-11-09 — Build correction: memory self-test branch range v0.5.8

- User's SjASMPlus v1.24.0 build reported `src/boot/p127_boot.asm(59): error: [JR] Target out of range (+147)`.
- The failing instruction was the conditional branch after `p127_mem_selftest`: `JR C,p127_mem_failed`. The failure handler is now 147 bytes forward, outside the signed 8-bit relative displacement range.
- Replaced that instruction with `JP C,p127_mem_failed`. The condition and failure-path behavior are unchanged; only the branch encoding is now absolute.
- Boot module advanced to v0.5.8; scenario revision advanced to 0.8.13.
- No memory-manager logic, test semantics, page mapping, or physical `OUT` behavior changed. Hardware page-port writes remain disabled.
- This is a source correction for the exact reported assembler error. A fresh full SjASMPlus build and emulator runtime test are still required; no successful build is claimed.


### 2026-11-09 — Runtime acceptance: W3 rollback/recovery v0.3.0 and boot branch correction

- User supplied the fresh emulator #EF log after the v0.5.8 boot correction. The run reaches the complete diagnostic sequence through `MAP MODEL TEST PASS; OUT DISABLED`.
- The log explicitly confirms `W3 ROLLBACK/RECOVERY PASS; OUT DISABLED`, following the existing resident stack probe and UI quiesce/W3 ownership pass. Stage 2.9 software rollback/recovery model v0.3.0 is therefore accepted at runtime.
- The same run confirms the boot module's absolute-branch correction did not prevent the memory-page self-test or later boot diagnostics from executing.
- Acceptance remains limited to software state/lease and RAM-backed snapshot/rollback tests. It does not prove actual UI shutdown across a physical remap, independent physical stack backing, asynchronous interrupt exclusion, IFF/IM preservation, rollback after a physical page-register write, or hardware page switching.
- Physical page-port `OUT` remains disabled. No source module changed in this acceptance update; scenario revision advanced to 0.8.14.
- Next: before enabling any physical remap, implement and test a fully resident remap trampoline with independently mapped code/data/stack, interrupt-entry/return discipline, and a rollback path that can execute after the target window changes. Keep physical `OUT` disabled until those prerequisites are demonstrated.


### 2026-11-09 — Stage 2.10: resident trampoline address preflight v0.1.0

- Moved `src/kernel/p127_resident.asm` to the first kernel include position immediately after the Stage2 boot body. This gives remap-critical code and its mutable state first claim on the W1/P5 portion of the Stage2 image rather than assuming that source order already guarantees placement.
- Added `p127_resident_trampoline_preflight`: at runtime it checks the actual linked resident-module start/end against the W1 address window, verifies the resident W3 state byte lies inside that module, and checks the live stack pointer (after CALL entry) lies in W2.
- The preflight asserts DI and returns with interrupts disabled. It does not change IM or vectors and does not attempt to restore an unknown prior IFF state; the current boot path already enters this phase with DI.
- Boot now emits `RESIDENT TRAMPOLINE PREFLIGHT PASS; OUT DISABLED` or a distinct failure line. Boot module v0.5.9; resident module v0.4.0; scenario revision 0.8.15.
- This is an address/layout preflight, not a bank-switch trampoline. No page-port OUT, physical remap, interrupt scheduling, or hardware rollback is implemented. The runtime pass is still required to establish that the linked image really fits W1 and the live stack is in W2.
- Build and emulator verification have not been run in this environment. Do not treat the new preflight as accepted until the user rebuilds with SjASMPlus and supplies the #EF result.

**Remaining acceptance groups before physical remap (5):**
1. Interrupt-entry/return protocol and explicit DI/IFF/IM/vector ownership.
2. Resident trampoline execution with register/context preservation across the software transition.
3. Software-model target-map commit, failure injection, and rollback from the post-transition path.
4. Controlled physical W3 page switch with UI quiesced and resident W1/W2 untouched.
5. Full boot/UI/memory/application regression after physical remap and rollback.


### 2026-11-09 — Runtime acceptance: resident trampoline address preflight v0.1.0

- User supplied the fresh #EF runtime log for boot v0.5.9 and resident module v0.4.0. It reaches `RESIDENT TRAMPOLINE PREFLIGHT PASS; OUT DISABLED` and continues through the resident-window, handoff-guard and mapper diagnostics.
- Stage 2.10 address preflight v0.1.0 is accepted in the user's emulator. The runtime test confirms the linked resident module's bounds satisfy the W1 address checks, the selected resident state byte lies inside that module, and the live SP at the preflight call site satisfies the W2 range checks.
- The same run reconfirms memory accounting, the resident stack probe, W3 ownership and software rollback/recovery.
- Acceptance is strictly an address/layout and software-contract result. It does not prove the stack is backed by an independent physical page, that W3 has been remapped, or that interrupt entry/return and IFF/IM/vector restoration are safe. No page-port OUT is enabled.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.17.
- The complete diagnostic chain is accepted for this software-only stage; all reported tests retain the `OUT DISABLED` boundary.
- Remaining acceptance groups before the first controlled physical W3 remap: (1) interrupt-entry/return and DI/IFF/IM/vector ownership; (2) resident transition with complete register/context preservation; (3) software target-map commit plus post-transition failure injection/rollback; (4) controlled physical W3 switch with UI quiesced and W1/W2 resident; (5) full boot/UI/memory/application regression after switch and rollback.


### 2026-11-09 — Stage 2.11: DI-only interrupt ownership preflight v0.1.0

- Added `src/kernel/p127_irq.asm` v0.1.0 and integrated its software contract self-test into boot v0.6.0.
- The current boot phase is explicitly DI-protected. The module asserts DI, records the only permitted bootstrap tuple (interrupts masked, no vector owner, IM policy unset), and rejects inconsistent software claims through fault-injection tests.
- Deliberately does not execute EI or IM, install/write an interrupt vector, or claim to preserve an unknown prior IFF/IM state. A stock Z80 cannot directly read its IM mode; `LD A,I` exposes IFF2 through P/V but is not a general IFF1/IFF2 restoration mechanism. No interrupt dispatcher is claimed.
- New #EF diagnostic: `IRQ MASK/VECTOR CONTRACT PASS; EI DISABLED`. Runtime acceptance is pending the user's build and emulator log.
- This is only the safe bootstrap interrupt-ownership preflight. Real interrupt entry/return, handler/vector installation, IM selection, and context preservation remain unimplemented. Physical page-port OUT remains disabled.
- Build was not run in this environment.


### 2026-11-09 — Runtime acceptance: DI-only interrupt ownership preflight v0.1.0

- User supplied the #EF log for boot v0.6.0. The run reports `IRQ MASK/VECTOR CONTRACT PASS; EI DISABLED` and continues through `RESIDENT TRAMPOLINE PREFLIGHT PASS; OUT DISABLED`, `RESIDENT WINDOW CONTRACT PASS; OUT DISABLED`, `HANDOFF GUARD TEST PASS; OUT DISABLED`, and `MAP MODEL TEST PASS; OUT DISABLED`.
- The Stage 2.11 DI-only interrupt ownership preflight v0.1.0 is accepted in the user's emulator. The acceptance covers the software fault-injection checks for the declared masked/no-vector/IM-unset bootstrap contract.
- This does not validate asynchronous interrupt entry/return, an installed interrupt handler/vector, IM selection, IFF1/IFF2 preservation/restoration, or complete register/context preservation. It is not permission to execute EI or IM. Physical page-port OUT remains disabled.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.19.
- The first remaining acceptance group is still open: implement a real controlled interrupt-entry/return protocol with explicit vector ownership and a defined interrupt-mode policy. The current bootstrap remains DI-only. Then test resident transition/context preservation, software target-map commit/rollback, controlled physical W3 remap, and full regression.


### 2026-11-09 — Stage 2.12: interrupt-enable readiness gate v0.2.0

- Advanced `src/kernel/p127_irq.asm` to v0.2.0 and boot to v0.6.1.
- Added a closed-by-default readiness gate. It rejects interrupt enablement unless all three future prerequisites are explicitly committed: vector ownership, verified vector-table mapping, and installed resident handler. A synthetic self-test proves the default-closed state, rejects an incomplete tuple, accepts only the complete tuple, and restores the safe boot state.
- The gate is a preflight only and never executes EI or IM. The boot still runs DI-only with no owned vector and no installed handler. No interrupt entry/return routine is claimed.
- Architectural blocker remains explicit: IM1's fixed vector #0038 resides in the current W0 ROM mapping and cannot be claimed writable by this stage. IM2 requires a verified, writable 257-byte table and known I-register mapping that do not overlap resident code/data; neither reservation has yet been established. Therefore no mode is selected and no vector is installed.
- New boot calls run the gate self-test; the existing #EF pass line remains `IRQ MASK/VECTOR CONTRACT PASS; EI DISABLED`. Runtime acceptance pending.
- Physical page-port OUT remains disabled. Build not run in this environment.


### 2026-11-09 — Runtime acceptance: interrupt-enable readiness gate v0.2.0

- User supplied the rebuilt Project127 #EF runtime log for boot v0.6.1 / IRQ module v0.2.0.
- The log reaches `IRQ MASK/VECTOR CONTRACT PASS; EI DISABLED` and continues through resident trampoline, resident-window, handoff-guard and map-model diagnostics. In boot source v0.6.1, the new `p127_irq_gate_selftest` is called before this marker and branches to the IRQ failure path on any failed assertion. Reaching the later diagnostics therefore confirms that the closed-by-default readiness-gate self-test returned successfully.
- Acceptance is limited to the software gate test: incomplete readiness tuples are rejected, the complete synthetic tuple is accepted, and the routine restores the safe DI/no-vector/IM-unset boot tuple.
- The log does not independently identify the gate test with its own marker, and does not demonstrate real asynchronous interrupt entry/return, an installed vector/handler, a selected IM, IFF preservation, or execution of EI. The system remains DI-only; physical page-port OUT remains disabled.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.21.
- Next: reserve and verify a writable interrupt vector/table strategy compatible with the actual ATM memory map, then implement controlled handler entry/return and context preservation. Do not enable interrupts until those prerequisites have dedicated runtime diagnostics.

### 2026-11-09 — Stage 2.13: reserve future IM2 table page v0.3.0

- Audited the live Project127 bootstrap map and page reservations. W0 is TR-DOS ROM, W1 is resident image on P5, W2 is UI/stack on P2, and W3 remains host/staging P0. Video pages {1,3,5,7} are reserved; pages 0 and 2 are also reserved.
- Reserved physical page P4 exclusively for a future IM2 vector table. P4 is not part of the active bootstrap map or the video-page union; this stage changes only the 64-entry software page-state table.
- Defined the future table geometry: W3 base #C000, I=#C0, 257 bytes (#C000-#C100 inclusive), leaving the rest of the 16 KiB physical page available. The 257-byte extent covers the maximum vector offset #FF and the second byte of the fetched address.
- Added a runtime preflight that verifies P4 is RESERVED and the live W3 shadow mapping remains P0. Added assembly-time assertions for the address, I value, window, extent and 64 KiB boundary.
- Boot v0.6.2 emits IRQ TABLE PAGE RESERVED P4; IM2 DISABLED and IRQ TABLE SLOT PREFLIGHT PASS; OUT DISABLED. Memory manager v0.4.0; IRQ module v0.3.0; scenario revision 0.8.22.
- This does NOT populate the table, map P4 into W3, load I, execute IM 2, install a handler, or execute EI. It does not prove P4 physical identity in the emulator. The next stage must implement a controlled W3 map transaction with rollback and runtime verification before any IM2 instruction is considered. Physical page-port OUT remains disabled.
- Build and emulator verification pending user run; no successful build is claimed.

### 2026-11-09 — Scenario register correction v0.8.23

- Normalized the versioned module register after the Stage 2.13 update. The previous table contained literal escaped newline text and stale duplicate IRQ descriptions; the table now records the actual boot, memory-manager and IRQ module versions and their current acceptance boundaries.
- No source behavior changed. Scenario revision advanced to 0.8.23.


### 2026-11-09 — Runtime acceptance: IM2 table-page reservation and slot preflight v0.3.0

- User supplied the fresh #EF runtime log. It reports `IRQ TABLE PAGE RESERVED P4; IM2 DISABLED` and `IRQ TABLE SLOT PREFLIGHT PASS; OUT DISABLED`, then continues through the IRQ contract, resident trampoline, resident-window, handoff-guard and mapper diagnostics.
- Stage 2.13 is now runtime accepted for software reservation and preflight: P4 is recorded RESERVED, W3's software shadow remains on bootstrap page P0, and the table geometry checks pass.
- This does not prove that the emulator's physical P4 is mapped or writable. No bytes are populated at #C000, I is not loaded, IM 2 and EI are not executed, and no interrupt handler/vector is installed. Physical page-port OUT remains disabled.
- No functional source module changed in this acceptance update. Scenario revision advanced to 0.8.25.
- Next: implement a software-only W3 target-map transaction with explicit old/new map snapshots, commit validation, injected post-transition failures and exact rollback. Keep hardware OUT, IM and EI disabled.

### 2026-11-09 — Stage 2.14: software-only target-map transaction v0.3.0

- Advanced src/kernel/p127_map.asm to v0.3.0 and boot to v0.6.3.
- Added transaction begin: validate window/page/protection mask and snapshot all four shadow-map entries before any update.
- Added software commit, explicit accept and rollback. Rollback restores the complete four-entry snapshot and clears pending/transaction state.
- Added post-commit failure injection: change W0 from ROM to synthetic page 10, inject failure, roll back, and verify all four original entries (ROM/P5/P2/P0). A second path commits synthetic page 11 and accepts it, then restores the bootstrap map.
- Boot emits MAP TXN COMMIT/ROLLBACK PASS; OUT DISABLED or a distinct failure line.
- No physical page-port OUT, physical page identity check, UI ownership transition, vector installation, IM 2 or EI. Physical remapping remains blocked.
- Scenario revision 0.8.26. Build and emulator verification are pending; no successful assembly is claimed.

### 2026-11-09 — Memory manager branch-range correction

- Fixed the SjASMPlus build failure reported at `p127_mem.asm(43)`: conditional branches to the shared `p127_mem_error` handler now use absolute `JP` rather than relative `JR`, avoiding the Z80 relative-branch displacement limit. All remaining conditional `JR` branches targeting `p127_mem_error` were converted as well.
- Memory manager version advanced to 0.4.1; scenario revision 0.8.24. No allocator or reservation semantics changed.
- Awaiting a fresh user build; assembler/emulator verification has not yet been run here.


### 2026-11-09 — Runtime acceptance: software-only target-map transaction v0.3.0

- User supplied the fresh #EF runtime log. It reports `MAP TXN COMMIT/ROLLBACK PASS; OUT DISABLED` and continues through the resident stack, UI/W3 ownership, W3 recovery, IRQ table-slot, IRQ mask/vector, resident trampoline, resident-window, handoff-guard and map-model diagnostics.
- Stage 2.14 software-only target-map transaction v0.3.0 is accepted in the user's emulator. The reported pass confirms that the transaction self-test completed its software commit/rollback paths, including post-commit failure injection and restoration of the prior shadow map, as implemented by the module.
- Acceptance is limited to the software shadow-map model. It does not validate physical page identity, actual W3 remapping, rollback after a hardware page-port write, or a writable IM2 table. Physical page-port OUT remains disabled; IM 2 and EI remain disabled.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.27.
- Next: implement a real interrupt entry/return protocol and prove resident execution/context preservation before attempting a controlled physical W3 remap. Keep physical OUT, IM 2 and EI disabled until their prerequisites have dedicated runtime verification.


### 2026-11-09 — Stage 2.15: resident IRQ frame save/restore protocol v0.4.0

- Added the resident IRQ entry/exit frame in `src/kernel/p127_irq.asm`: saves primary AF/BC/DE/HL/IX/IY and alternate AF'/BC'/DE'/HL', calls a dispatcher hook, restores the complete general-register set, and exits through RETI. RETI is relied upon to copy IFF2 back to IFF1; the routine itself never executes EI or IM.
- Added an inert dispatcher by default. A test-only clobber mode deliberately overwrites both register banks and index registers so the frame round-trip can be checked without any hardware interrupt source.
- Added a CALL-based synthetic context self-test with sentinel values for both register banks and an IFF2-disabled check via LD A,I. Boot v0.6.4 invokes it and reports `IRQ FRAME ROUNDTRIP PASS; VECTOR DISABLED`.
- The test runs under DI and uses RETI only as a return instruction in the synthetic CALL path. It does not install a vector, select IM 1/2, populate/map the P4 table, acknowledge an interrupt controller, or execute EI. No asynchronous IRQ is enabled; physical page-port OUT remains disabled.
- Module versions: `src/kernel/p127_irq.asm` 0.4.0; `src/boot/p127_boot.asm` 0.6.4; scenario revision 0.8.28.
- Build and emulator runtime verification are pending. This is source implementation only; do not treat the frame test as accepted until the user rebuilds and supplies the #EF diagnostic.


### 2026-11-09 — Stage 2.15 test-vector correction

- Corrected the expected flag-register bytes in the synthetic context test. Z80 `OR A` sets P/V from even parity and copies undocumented flag bits 5/3 from A; the exact expected AF snapshots are now `#5A0C` and `#A5A4`.
- IRQ module advanced to v0.4.1; boot source label advanced to v0.6.5; scenario revision 0.8.29.
- No interrupt/vector policy changed. Runtime and assembly verification remain pending.


### 2026-11-09 — Stage 2.15 runtime acceptance

- User-provided ATM runtime log reports `[P127] IRQ FRAME ROUNDTRIP PASS; VECTOR DISABLED` and all preceding diagnostics through `MAP MODEL TEST PASS; OUT DISABLED`.
- Stage 2.15 synthetic IRQ frame save/restore v0.4.1 is accepted at runtime: primary/alternate register-bank round-trip test and IFF2-disabled guard passed in the user's emulator run.
- Acceptance is limited to the synchronous CALL-based frame test. It does not validate asynchronous interrupt entry, interrupt-source acknowledgement, vector-bus behavior, IM1/IM2, P4 physical mapping, or EI. Hardware IRQ remains disabled and physical mapper OUT remains disabled.
- Scenario revision 0.8.30. No source module version change.


### 2026-11-09 — Stage 2.16: consolidated IRQ contract batch v0.5.0

- Advanced `src/kernel/p127_irq.asm` to v0.5.0 and `src/boot/p127_boot.asm` to v0.6.6. Boot now runs one consolidated IRQ batch after the existing register-frame round-trip test.
- The batch performs 16 checks in one startup: initial safe-state validation; all eight combinations of the three readiness bits; rejection when vector ownership is absent; rejection when the mode policy is absent; rejection of an unmasked state, guessed vector ownership and guessed mode policy; then restoration and validation of the real DI/no-owner/no-mode boot tuple. It emits `IRQ BATCH 16-CHECK PASS; SOURCE UNRESOLVED; IM/EI/OUT DISABLED`.
- Project112 `112/src/main.asm` was inspected: it explicitly enters DI during initialization and implements ATM video/keyboard handling, but provides no ATM Z80 IRQ source, vector-bus, acknowledge or EOI contract. It is not valid evidence for an IRQ vector or acknowledgement policy.
- Therefore this batch deliberately tests only the software readiness/ownership contract. It does not synthesize an asynchronous interrupt, invent a vector byte, emulate an interrupt source, or claim acknowledgement/EOI behavior. No IM 1/IM 2, EI, I-register write, P4 physical mapping or page-port OUT is introduced.
- Scenario revision 0.8.31. Build and emulator runtime verification are pending the user's single batch run; no successful assembly or runtime acceptance is claimed.
- Next research gate: inspect the exact Unreal Speccy source/revision used by the user and trace its ATM INT assertion, vector-bus response and source-clear behavior. Only then can a real source/vector test be added.


### 2026-11-09 — Stage 2.16 runtime acceptance: consolidated IRQ contract batch

- User supplied the complete #EF startup log from the v0.5.0 IRQ batch. It reports `IRQ BATCH 16-CHECK PASS; SOURCE UNRESOLVED; IM/EI/OUT DISABLED`.
- Stage 2.16 software-only batch is runtime accepted. The run also reports PASS for IRQ frame round-trip, IRQ table-slot preflight, IRQ mask/vector contract, resident trampoline/window, handoff guard and mapper model.
- The batch validates the software readiness gate and rejection/restoration paths only. It does not establish an ATM interrupt source, vector-bus byte, acknowledge/EOI sequence, interrupt timing, asynchronous entry, or actual IM1/IM2 behavior.
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.32.
- Next: trace the exact Unreal Speccy revision used for Project127 and the ATM Turbo 2+ interrupt implementation in its source. Record the source assertion, vector response and clear/acknowledge behavior before adding any asynchronous IRQ test. Keep IM, EI and physical page-port OUT disabled.
- Build is not independently verified in this environment; the user's runtime log confirms that the tested image executed the batch successfully.


### 2026-11-09 — Stage 2.17: first physical W3 RAM switching test v0.1.0

- Corrected the architecture record after auditing `src/ui/p127_console.asm`: Project127 already opens ATM shadow ports through the documented TR-DOS ROM trampoline and performs bounded physical video mapping (W1=page 7, W3=page 3), then restores W1=page 5 and W3=page 0. The earlier blanket statement that Project127 performed no physical page OUT was too broad. The pure software mapper and resident preflight modules still do not issue OUT.
- Added `src/kernel/p127_physmem.asm` v0.1.0 in W2, after the console image at #A000. The test code and live stack therefore remain outside the remapped W3 window; UI ownership is quiesced and acquired before the test.
- The test allocates two currently free physical pages from the page-state manager. It first performs a non-destructive one-byte probe against the existing P0 contents: it saves the byte at #C000, writes its complement into the candidate page, switches back to P0 and verifies P0 was unchanged, then switches to the candidate page and verifies persistence. If the dispatcher does not switch, cleanup restores the one touched P0 byte; full-page writes are not attempted.
- After the probe succeeds, the test writes distinct patterns (#A5 and #5A) across all 16,384 bytes of each allocated page, switches between them, verifies every byte on both pages, and rechecks page A after page B to detect aliasing. It then restores W3 to P0, restores the saved P0 byte, releases the UI lease, and frees both test pages.
- Boot advanced to v0.6.7 and runs the complete physical test as one batch after the existing software diagnostics. Success marker: `PHYS W3 SWITCH/2X16K ISOLATION/VERIFY/P0 RESTORE PASS`. Failure has a dedicated boot diagnostic.
- The test writes only the W3 page port #FFF7. It does not remap W0/W1/W2, enable interrupts, alter IM/IFF policy, use P4, or enable general application mapping. The existing console's bounded video mapping remains unchanged.
- Scenario revision 0.8.33. Build and emulator runtime verification are pending the user's next single run; no successful assembly or physical test is claimed.
- Next: if this batch passes, add multi-pattern/address-sensitive sweeps and test repeated map/restore cycles, then expose a guarded page-map API. If it fails, use the returned diagnostic and preserve the P0 recovery path before expanding scope.


### 2026-11-09 — Stage 2.17 runtime acceptance: physical W3 page switching

- User supplied the complete #EF startup log from the Stage 2.17 physical-memory batch. It reaches `PHYS W3 SWITCH/2X16K ISOLATION/VERIFY/P0 RESTORE PASS` after all prior boot, memory, software-map, resident-window and IRQ-preflight diagnostics.
- Stage 2.17 / `src/kernel/p127_physmem.asm` v0.1.0 is accepted in the user's Unreal Speccy runtime. The diagnostic is emitted only after the routine completes its physical W3 mapping probe, two-page 16 KiB write/readback isolation checks, return to P0, restoration of the saved P0 byte, UI handoff release and page frees.
- This is runtime evidence for the tested two allocated pages and the W3 dispatcher path. It does not establish exhaustive correctness across all 64 physical pages, arbitrary concurrent remapping, W0/W1/W2 remapping, application mapping, or interrupt operation. The system remains DI-only; IM/EI and the IRQ source/vector contract remain unresolved.
- No functional source module changed in this acceptance update. Scenario revision advanced to 0.8.34.
- Next: extend the single-run physical-memory batch with address-sensitive patterns, repeated A/B switching cycles and broader page-pair coverage while preserving the P0 recovery path. Do not expose unrestricted application mapping until those checks pass.


### 2026-11-09 — Stage 2.17 runtime acceptance: physical W3 page switching

- User supplied the complete #EF startup log. It reaches `PHYS W3 SWITCH/2X16K ISOLATION/VERIFY/P0 RESTORE PASS` after all earlier diagnostics.
- Stage 2.17 / `src/kernel/p127_physmem.asm` v0.1.0 is accepted in the user's Unreal Speccy runtime. The marker is emitted only after the physical W3 probe, two-page 16 KiB isolation/readback, return to P0, restoration of the saved P0 byte, UI handoff release and freeing both allocated pages.
- Acceptance covers the two allocated pages and W3 dispatcher path exercised by this batch. It does not establish exhaustive correctness across all 64 physical pages, arbitrary concurrent remapping, W0/W1/W2 remapping, application mapping, or interrupt operation. DI-only policy remains; IM/EI and the IRQ source/vector contract remain unresolved.
- No source behavior changed as part of this acceptance record. Scenario revision advanced to 0.8.35.

### 2026-11-09 — Stage 2.18: address-sensitive W3 memory batch v0.2.0

- Advanced `src/kernel/p127_physmem.asm` to v0.2.0 and boot source to v0.6.8.
- Extended the existing single startup batch after the non-destructive physical-page probe and two-page isolation stage. Each of the two allocator-owned pages is filled and checked using an address-derived byte pattern (`ROL(address_low) XOR address_high XOR seed`), rather than a single constant byte.
- Four pattern rounds use distinct seeds on both pages. Each round repeatedly switches W3 between A and B and re-verifies the previously written page after returning from the other page. This combines address-sensitive data checks, page isolation, repeated mapping, and data retention in one boot run.
- The original safety contract is retained: code and stack remain in W2; W1/W2 are not remapped; UI is quiesced and W3 ownership is acquired; the probe byte on P0 is saved/restored; cleanup returns W3 to P0, releases ownership, resumes UI, and frees allocated pages.
- Success marker: `PHYS W3 ADDR PATTERN/4ROUND/20MAP/2PAGE VERIFY/P0 RESTORE PASS`.
- The batch still covers two allocator-selected physical pages, not all 64 pages. It does not authorize unrestricted application mapping or IM/EI.
- Scenario revision 0.8.35. Build and emulator runtime verification for Stage 2.18 are pending the user's next single run; no successful build is claimed.


### 2026-11-09 — Stage 2.18 runtime acceptance: address-sensitive W3 memory batch

- User supplied the complete #EF startup log from the Stage 2.18 image. All preceding diagnostics pass and the log reaches `PHYS W3 ADDR PATTERN/4ROUND/20MAP/2PAGE VERIFY/P0 RESTORE PASS`.
- Stage 2.18 / `src/kernel/p127_physmem.asm` v0.2.0 is accepted in the user's Unreal Speccy runtime. The marker confirms that the combined startup batch completed its address-derived pattern rounds, repeated A/B W3 mapping and full-page verification, then restored W3 to P0 and completed cleanup.
- Runtime acceptance is limited to the two allocator-selected physical pages and the W3 path covered by the batch. It is not an exhaustive test of all 64 pages, W0/W1/W2 mapping, concurrent mapping, application allocation policy under load, or interrupt operation. IM/EI remain disabled and IRQ source/vector/acknowledgement remain unresolved.
- No functional source module changed in this acceptance update. Scenario revision advanced to 0.8.36.
- Next stage: expand the same single-run batch to allocator/page-state integrity and broader physical-page pair coverage, retaining guarded W3 ownership, P0 restoration, UI recovery and full cleanup. Do not enable unrestricted remapping or interrupts based solely on this test.


### 2026-11-09 — Stage 2.19: full free-page W3 sweep and allocator integrity batch v0.3.0

- Advanced `src/kernel/p127_physmem.asm` to v0.3.0 and boot source to v0.6.9.
- The existing Stage 2.18 two-page test remains first. Under the same UI quiesce/W3 ownership lease, the batch then allocates every remaining free page, stores each physical page ID in a private 64-byte list, and rejects duplicate IDs. The current reservation map expects exactly 57 allocatable pages and seven protected pages: P0/P1/P2/P3/P4/P5/P7.
- Every allocated page is mapped through W3 and filled with an address-derived pattern seeded by its physical page ID. A reverse-order second sweep verifies all 16 KiB of every page after all other pages have been written, detecting aliases and data loss across page switches.
- The batch validates that every listed page remains ALLOCATED during the sweep and that all seven protected page-state entries remain RESERVED. Cleanup restores W3=P0 and the saved P0 byte, releases UI ownership, resumes the UI, frees every page in reverse order, checks reservation invariants again, and verifies allocator reuse returns the original first-fit page.
- This exercises all 57 currently allocatable physical pages, not the seven intentionally reserved pages. It does not prove arbitrary concurrent remapping, W0/W1/W2 mapping, DMA, or interrupt operation. IM/EI remain disabled.
- Success marker: `PHYS W3 FULL FREE-PAGE SWEEP/ALLOCATOR/RESERVES/P0 RESTORE PASS`.
- Scenario revision 0.8.37. Build and emulator verification are pending; no successful assembly or runtime acceptance is claimed.


### 2026-11-09 — Stage 2.19 cleanup audit correction v0.3.1

- Audited the newly added full-page sweep before user execution. Preserved the page-list cursor across `p127_mem_free`, whose implementation uses HL internally; without this preservation the reverse cleanup loop would not reliably traverse the list.
- Added a post-release audit of all 64 page-state entries: the seven fixed pages must remain RESERVED and every other page must be FREE. The first-fit allocation/release check remains in place.
- Physical-memory module advanced to v0.3.1. Scenario revision 0.8.38. Test coverage and boot marker are unchanged.
- Build and emulator verification remain pending; no successful assembly is claimed.


### 2026-11-09 — Stage 2.19 runtime failure correction v0.3.2

- User runtime log passed all diagnostics through the mapper model, then failed in the full physical-memory batch.
- Source audit found a deterministic pointer-clobber bug: the full-page fill/verify routines use HL as the W3 data cursor and leave it at the end of the 16 KiB window. The outer page-list traversal also used HL, so the next iteration read from the wrong address. The list cursor is now preserved on the stack around both pattern routines.
- Boot source advanced to v0.7.0 and now prints the physical-memory error byte in hexadecimal after the failure line, enabling precise diagnosis if another check fails.
- Physical-memory module advanced to v0.3.2; scenario revision 0.8.39.
- This corrects the identified control-flow defect but is not yet runtime accepted. Rebuild and rerun; expected success marker remains `PHYS W3 FULL FREE-PAGE SWEEP/ALLOCATOR/RESERVES/P0 RESTORE PASS`. On failure, the new `PHYSMEM ERROR=XX` line identifies the failure class.


### 2026-11-09 — Stage 2.19 build correction: boot idle-branch range v0.7.1

- User's SjASMPlus v1.24.0 build reported `src/boot/p127_boot.asm(142): [JR] Target out of range (+132)`. The new physical-memory failure-reporting path had lengthened the distance from its failure branch to the common idle loop beyond the signed 8-bit JR range.
- Replaced every boot error-handler branch to `p127_idle` with absolute `JP`. This avoids future range regressions as diagnostics grow and does not alter the failure destinations or runtime test sequence.
- Boot module advanced from v0.7.0 to v0.7.1; scenario revision advanced to 0.8.40. No memory-test or allocator behavior changed.
- This is a source-level correction only. SjASMPlus build and emulator runtime verification remain pending the user's rebuild.


### 2026-11-09 — Stage 2.19 execution trace markers v0.3.3

- User runtime log passes all boot diagnostics through `MAP MODEL TEST PASS` but does not return from `p127_physmem_batch_selftest`. The last visible line alone cannot distinguish a slow full-page sweep from a loop/control-flow fault.
- Added single-character phase markers sent directly to the established debug port `#EF`, which remains available while the UI is quiesced and W3 is leased: `S`=physical batch entered, `2`=two-page Stage 2.18 tests completed, `A`=allocator exhaustion/list completed, `F`=57-page fill sweep completed, `V`=reverse verification completed, `C`=cleanup entered.
- Physical-memory module advanced to v0.3.3; scenario revision 0.8.41. No test pattern, page mapping, allocator, or cleanup semantics changed. These markers are diagnostic only and intentionally avoid calling UI routines while W3 ownership is held.
- Build/runtime verification pending. The next #EF log's last marker will localize the stalled phase.


### 2026-11-09 — Stage 2.19 per-page progress output v0.3.4

- Added a readable #EF progress line immediately before each page operation in the exhaustive physical W3 sweep: `FILL PAGE ID=xx` for the fill pass and `VERIFY PAGE ID=xx` for the reverse verification pass. The page ID is printed as two hexadecimal digits.
- The progress routine preserves AF/BC/DE/HL so it cannot corrupt the page-list traversal or pattern seed. Output is sent directly to the already established debug port while UI ownership is quiesced; it does not invoke UI/BIOS console code.
- Physical-memory module advanced to v0.3.4; scenario revision 0.8.42. Existing phase markers remain. No mapping, test-pattern, allocation or cleanup behavior changed.
- Expected output is 57 FILL lines followed by 57 VERIFY lines, followed by the existing completion marker. Build and emulator verification are pending.


### 2026-11-09 — Stage 2.19 runtime acceptance: exhaustive free-page sweep v0.3.4

- User supplied the #EF log from the v0.3.4 image. The diagnostic shows all 57 allocatable pages being filled (IDs #06 and #08–#3F) and then verified in reverse order (#3F–#08 and #06).
- The final marker `PHYS W3 FULL FREE-PAGE SWEEP/ALLOCATOR/RESERVES/P0 RESTORE PASS` confirms that the batch returned successfully after the full-page data checks, allocator-state validation, reserved-page checks, W3=P0 restoration, UI handoff release/resume, freeing all allocated pages, free-state audit and first-fit allocator reuse check.
- Stage 2.19 / `src/kernel/p127_physmem.asm` v0.3.4 is accepted by the user's runtime result. The page-by-page progress output also confirms that the apparent stall was execution time rather than an infinite loop in this run.
- The seven protected pages remain outside the sweep: P0–P5 and P7. The test validates the 57 allocatable pages through W3; it does not establish arbitrary concurrent remapping, W0/W1/W2 remapping, DMA, or interrupt operation. IM/EI remain disabled.
- The concatenated phase letters (`S2A`, `F`, `V`, `C`) are legacy compact markers; the readable per-page lines and final PASS are authoritative. No source change is required for this acceptance.
- Scenario revision advanced to 0.8.43. No assembler build was independently run here; runtime acceptance is based on the user's supplied log.


### 2026-11-09 — Stage 2.20: allocator wrappers and guarded W3 lease API v0.4.0

- Added public `p127_physmem_alloc_page` / `p127_physmem_free_page` entry points over the page-state allocator. Free is rejected while a W3 lease is active, preventing release of a page that may be mapped or in use by the caller.
- Added `p127_physmem_w3_begin`, `p127_physmem_w3_map`, and `p127_physmem_w3_end`. Begin requires the bootstrap W3=P0 map, quiesces the UI and acquires the existing W3 handoff owner, then saves the P0 byte. Map accepts only a page whose allocator state is ALLOCATED and changes W3 only. End restores W3=P0 and the saved byte before releasing ownership and resuming UI. Failure flags are retained across release/resume errors so end can be retried.
- Added a runtime API self-test after the exhaustive Stage 2.19 sweep: reject freeing a reserved page; reject mapping a reserved page; reject freeing the currently mapped allocated page; map/write a test page; restore P0 data; free and first-fit reallocate the same page; verify W3 shadow and UI owner/state restoration.
- Boot module advanced to v0.7.2; physical-memory module advanced to v0.4.0; scenario revision 0.8.44. This is deliberately a W3-only lease API. It does not permit W0/W1/W2 mapping, arbitrary simultaneous mappings, DMA, or interrupt enablement. DI remains asserted; IM/EI and IRQ vector ownership remain unchanged.
- Build and emulator runtime verification are pending. The new boot marker is `PAGE ALLOC/FREE + GUARDED W3 LEASE API PASS; IM/EI DISABLED`.

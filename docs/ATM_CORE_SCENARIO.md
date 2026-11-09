# Project127 ATM Core — implementation scenario

Scenario revision: **0.8.16**  
Status: **BOOT0, console, page-state self-test, bootstrap reservations, resident stack probe v0.1.0, software mapper model, handoff guard v0.2.2 and resident-window contract v0.1.0 and W3 rollback/recovery v0.3.0 accepted by user runtime test; resident trampoline address preflight v0.1.0 accepted by user runtime test; physical bank switching not yet enabled**  
Repository baseline before this step: `188a72d68cf3a6c0e10434d2d5d9cee016159684`

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
| 5 — Process/context manager | **SOFTWARE PREREQUISITES + TRAMPOLINE ADDRESS PREFLIGHT ACCEPTED** — stack probe v0.1.0, resident-window contract v0.1.0, W3 ownership v0.2.0, rollback/recovery v0.3.0, resident layout preflight v0.1.0 | Implement interrupt-entry/return and transactional physical remap; address preflight is runtime accepted but does not prove independent physical stack backing. |
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
| `src/boot/p127_boot.asm` | 0.5.9 | Original BOOT0 sequence retained; runs Stage 1 smoke test |
| `src/kernel/p127_mem.asm` | 0.3.1 | Software page-state manager; reserves video pages 1,3,5,7 plus active bootstrap pages 0,2; no hardware mapping yet |\n| `src/kernel/p127_map.asm` | 0.2.2 | Pure mapper model: inverse page encoding, window-port lookup, bootstrap shadow map and self-test; no OUT instructions |
| `src/ui/p127_console.asm` | 0.1.1 | Project126 ATM RG6 80×25 interface; screen/log output mirrored to #EF; duplicate routine and JR range errors fixed |
| `src/kernel/p127_handoff.asm` | 0.1.0 | Resident stack-switch integrity probe; no physical remap |
| `src/kernel/p127_resident.asm` | 0.4.0 | Fixed W1/P5 resident code/data + W2/P2 live-stack address preflight; W3 ownership, UI leases and software snapshot/rollback; no page OUT |
| `src/main.asm` | existing | Build entry; assembles boot and included kernel module |

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

**Remaining acceptance groups before physical remap (6):**
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
- No source module changed in this acceptance update. Scenario revision advanced to 0.8.16.
- Remaining acceptance groups before the first controlled physical W3 remap: (1) interrupt-entry/return and DI/IFF/IM/vector ownership; (2) resident transition with complete register/context preservation; (3) software target-map commit plus post-transition failure injection/rollback; (4) controlled physical W3 switch with UI quiesced and W1/W2 resident; (5) full boot/UI/memory/application regression after switch and rollback.

# Project127 ATM Core — implementation scenario

Scenario revision: **0.5.2**  
Status: **BOOT0, console, and Stage 1 memory smoke test accepted in user-reported emulator run**  
Repository baseline before this step: `188a72d68cf3a6c0e10434d2d5d9cee016159684`

## Fixed architecture requirements

1. ATM physical RAM is exactly 1 MiB (1,048,576 bytes).
2. The page-accounting model uses 64 pages × 16 KiB. This is a software accounting unit; physical page-register encoding must be verified against the target ATM model before any hardware mapping is enabled.
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
| 1 — Physical page-state manager | **PASS (runtime smoke test)** | 64-entry page-state table; video reservations; allocate/free/reallocate smoke test passed in user-reported emulator log. |
| 2 — Physical memory map | IN PROGRESS | Project112 confirms video page IDs 1, 3, 5, 7; these are now reserved. Verify ROM boundary and ATM bank mapping; place kernel immediately beside ROM; derive kernel end; reserve stacks, firmware and remaining device regions; identify highest eligible RAM boundary for top-down program arena. No guessed ranges. |
| 3 — UINT32 memory/range API | PLANNED — UPDATED | Overflow-safe range validation, top-down arena allocation/free, copy/fill/compare across page boundaries, collision checks against kernel/video/device reservations. |
| 4 — Page mapper | PLANNED | Verified ATM hardware page-register backend; map/unmap API; no direct hardware writes from applications. |
| 5 — Process/context manager | PLANNED | Full register/context frame, page-map snapshot, safe interrupt scheduling and restore tests. |
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
| `src/boot/p127_boot.asm` | 0.3.0 | Original BOOT0 sequence retained; runs Stage 1 smoke test |
| `src/kernel/p127_mem.asm` | 0.2.0 | Software page-state manager; reserves verified video pages 1,3,5,7; no hardware mapping yet |
| `src/ui/p127_console.asm` | 0.1.1 | Project126 ATM RG6 80×25 interface; screen/log output mirrored to #EF; duplicate routine and JR range errors fixed |
| `src/main.asm` | existing | Build entry; assembles boot and included kernel module |

## Stage 1 — physical page-state manager 0.2.0

- Page IDs: 0..63; page size: 16 KiB.
- Per-page states: FREE=0, RESERVED=1, ALLOCATED=2.
- `p127_mem_reserve`: A=first page, B=count; validates full range and overlap before changing state.
- `p127_mem_alloc`: first-fit allocation.
- `p127_mem_free`: only releases ALLOCATED pages; RESERVED pages cannot be freed.
- `p127_mem_reserve_video`: reserves the union of ATM video pages 1, 3, 5, 7.
- `p127_mem_selftest`: verifies video pages cannot be freed, then allocate -> free -> allocate same first-fit page -> free.
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


### 2026-11-09 — Runtime acceptance: BOOT0, console and Stage 1 memory smoke test

- User-reported emulator output confirms the BASIC loader and second-stage entry at `#6000`; stack initialization at `#BFFF`; debug transmission through port `#EF`; and `BOOT0 PASS; IDLE`.
- Project127 ATM RG6 console starts and reports `UI READY; ALL DEBUG OUTPUT MIRRORED TO EF`.
- Physical page-state manager initializes its 64-page / 1 MiB accounting table; video pages P1, P3, P5 and P7 are reserved; allocator smoke test reports `MEM PAGE TEST PASS`.
- Acceptance applies to the software page-state manager and visible console/log path only. It does not yet prove physical bank-register mapping, true physical page IDs on hardware, kernel relocation, DMA, or application memory availability.
- RTC diagnostic remains `NOT INITIALIZED`; RTC/SMUC integration remains open under Stage 9.
- Runtime acceptance source: user-provided emulator log in the Project127 development conversation.
- Next implementation step: audit the real ATM Turbo 2+ memory map and ROM/RAM banking against Project112 before implementing low-memory kernel placement, runtime kernel-end discovery, and the top-down program arena. Do not expose the current page allocator to application loading until that map is verified.

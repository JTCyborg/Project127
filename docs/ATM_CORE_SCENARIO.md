# Project127 ATM Core — implementation scenario

Scenario revision: **0.2.0**  
Status: **Stage 1 implementation committed; emulator acceptance pending**  
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
10. The known-good BASIC loader and BOOT0 entry protocol remain intact. Extensions are added after the existing BOOT0 diagnostics.

## Implementation stages and module versions

| Stage | Status | Deliverable / acceptance |
|---|---|---|
| 0 — Bootstrap baseline | **PASS (baseline)** | BASIC `boot.B` loads `P127BOOT.C` at #6000; original four BOOT0 diagnostic lines retained. |
| 1 — Physical page-state manager | **IMPLEMENTED; runtime pending** | 64-entry page-state table; reserve/allocate/free; allocator smoke test wired into Stage 2 boot. |
| 2 — Physical memory map | PLANNED | Derive hardware page IDs and reserve kernel, stacks, firmware, and all video-mode regions. No guessed ranges. |
| 3 — UINT32 memory/range API | PLANNED | Overflow-safe range validation, copy/fill/compare across page boundaries, boundary tests. |
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
| `src/kernel/p127_mem.asm` | 0.1.0 | Software page-state manager; no physical mapping |
| `src/main.asm` | existing | Build entry; assembles boot and included kernel module |

## Stage 1 — physical page-state manager 0.1.0

- Page IDs: 0..63; page size: 16 KiB.
- Per-page states: FREE=0, RESERVED=1, ALLOCATED=2.
- `p127_mem_reserve`: A=first page, B=count; validates full range and overlap before changing state.
- `p127_mem_alloc`: first-fit allocation.
- `p127_mem_free`: only releases ALLOCATED pages; RESERVED pages cannot be freed.
- `p127_mem_selftest`: allocate -> free -> allocate same first-fit page -> free.
- Boot emits `MEM INIT` and `MEM PAGE TEST PASS/FAIL` on #EF after the original BOOT0 messages.

**Acceptance boundary:** the smoke test validates software state transitions only. It does not validate ATM physical page IDs, hardware mapping, video reservations, DMA, or availability of pages for applications. The allocator must not be exposed to application loading until Stage 2 supplies the verified physical map.

## Project126 reuse policy

Project126 `docs/src.r2731` is the source base for reusable kernel services and drivers. Reuse is conditional on auditing each module's assumptions about ATM model, memory windows, page IDs, interrupt model, and hardware ports. Project126's existing 16 KiB window API is not itself the Project127 large-address-space implementation. Drivers are ported in stages and retain source provenance/version notes.

## Stage log

### 2026-11-09 — Stage 1 code added

- Added `src/kernel/p127_mem.asm` v0.1.0.
- Updated `src/boot/p127_boot.asm` v0.3.0 to initialize the table and run the allocator smoke test after the four original BOOT0 diagnostics.
- Added `tests/ATM_CORE_STAGE1.md`.
- Source/build verification: **not run in this environment**. User must build with `tools/build_project127.ps1` and run the TR-DOS image in the target emulator.
- Expected additional #EF lines: `[P127] MEM INIT 1MB/64P`, then `[P127] MEM PAGE TEST PASS`.
- Next: confirm the exact Stage 1 log; then derive the real physical map and all video reservations from Project112/Project126 before enabling application allocations.

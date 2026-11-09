# Project127 — low-level foundation

**Revision:** 0.1  
**Status:** architecture baseline; implementation is the next milestone.  
**Scope:** ATM Turbo 2+ Z80 firmware, NeoGS Z80 firmware, their shared memory/transport ABI, and the later 8086 emulator.

## 1. Non-negotiable design rule

A 16 KiB page/window/aperture is never a program-size limit, module-size limit, buffer-size limit, API-size limit, or logical-address-space limit.

The hardware may expose memory through fixed-size windows and DMA may have a fixed-size aperture. Those are backend constraints only. The low-level system must split, map, stream and reassemble data internally. Callers always work with a logical address and a full length.

No source module may need to be artificially shortened to fit one 16 KiB overlay. No linker assertion may enforce that condition.

## 2. Separate logical memory from physical memory

Each processor has its own logical address space and backend:

- ATM backend: ATM RAM/page hardware and ATM-side Z80 execution windows.
- NeoGS backend: NeoGS RAM and its local page/window mapping.
- Shared transport: DMA transactions between the two systems.
- Guest backend (added later): the 8086 20-bit physical address space, exactly 1 MiB.

The memory API uses 32-bit unsigned offsets and lengths. This is an API width, not a promise that either device physically contains 4 GiB. The backend reports its actual capacity and rejects out-of-range requests.

A logical allocation is represented by a handle plus a 32-bit length. It may occupy multiple physical extents. Physical extents are private to the backend and must not leak into application/module interfaces.

### Required memory operations

Every backend must provide equivalents of:

- query capacity and free space;
- allocate/release an arbitrary-length byte range;
- read/write at an arbitrary byte offset;
- fill and copy arbitrary-length ranges;
- stream sequential data in either direction;
- pin/unpin ranges while DMA or execution is in progress.

All operations must correctly cross any number of physical page/window boundaries. Length zero is a valid no-op. Arithmetic must be checked for overflow before range validation.

## 3. Executable modules larger than one window

Data storage and code execution are separate problems. A Z80 has a 16-bit native program counter; therefore a flat 32-bit storage address alone cannot make arbitrary fragmented code directly executable.

Project127 uses a module format with:
- one module header containing total image length and ABI version;
- independently placeable code sections and data sections;
- relocation records;
- exported/imported symbols;
- explicit far-call/far-jump references between code sections;
- stack and memory requirements;
- optional initialization/finalization entry points.

The loader accepts an arbitrary total module size, allocates storage as multiple extents, validates all offsets/relocations, and loads it as a stream. The linker/runtime, not the programmer, handles code-window placement and far transfers. A module may contain many sections and its total size is limited only by available memory and format limits—not 16 KiB.

A single native Z80 instruction stream cannot transparently fetch from a fragmented 32-bit address space without a mapping/fetch mechanism. The first implementation must therefore provide compiler/linker-managed sections and far-call thunks rather than pretending the Z80 has a 32-bit PC. This is an execution ABI detail, not a limit on total program size.

## 4. DMA is a stream transport, not a 16 KiB message API

The existing NeoGS DMA hardware exposes a 16 KiB aperture. That physical aperture is retained as a low-level hardware fact; it is not exposed as the maximum transfer size.

The shared transport API accepts:
- source logical address;
- destination logical address;
- total 32-bit byte length;
- direction and service/operation;
- completion/error result.

The DMA engine internally:
1. chooses the next safe chunk fitting the current hardware aperture;
2. maps the relevant source/destination physical extent;
3. arms the hardware DMA transaction;
4. transfers and validates the chunk;
5. advances offsets and repeats;
6. reports completion only after the entire requested length is committed.

The receiver must never expose partially received data as a completed object. Cancellation, timeout, reset and CRC failure must release the DMA engine and all pinned extents. Chunks may not be interleaved across directions within one hardware transaction.

The maximum chunk size is obtained from the backend capability at runtime; it is not hard-coded into service callers. The protocol must support lengths larger than 64 KiB and must use checked 32-bit counters.

## 5. Ownership and device access

- ATM Z80 owns physical ATM hardware and host-side services.
- NeoGS Z80 owns NeoGS-local memory and software device models.
- NeoGS must not perform direct IN/OUT to real external devices or ATM peripherals.
- Any operation requiring the outside world is represented as a service request and carried to ATM through DMA.
- Guest x86 I/O ports are software models. They do not become physical NeoGS ports.

This preserves the host/guest separation while allowing the later emulator to use the same memory and transport services.

## 6. Guest 8086 memory

The emulator will use Intel 8086 Real Mode with a 20-bit physical address bus and a 1 MiB guest physical address space. Segment:offset translation and 20-bit wrap are guest CPU semantics.

The guest's 1 MiB address space is independent of the ATM and NeoGS physical-memory layouts. It is backed by guest allocations in the memory backend; VGA/ROM/device overlays are implemented by the guest memory decoder, not by exposing ATM/NeoGS page numbers to the CPU core.

The guest memory decoder must offer byte/word read/write operations that correctly handle:
- segment offset wrap;
- 20-bit physical wrap;
- accesses crossing backend extent boundaries;
- ROM write policy;
- VGA/device address routing.

No 16 KiB guest-memory window is visible to the 8086 core.

## 7. Startup and capability discovery

Boot code must not assume a fixed number of free pages or a fixed DMA chunk size. ATM and NeoGS each publish a capability record containing:
- ABI major/minor;
- backend memory capacity;
- allocatable capacity;
- physical mapping granularity (diagnostic/backend field only);
- maximum single DMA aperture chunk;
- supported module format and relocation types;
- firmware build ID.

The two sides negotiate compatible ABI versions before loading modules or sending service traffic. Incompatible versions fail explicitly; they do not silently fall back to a 16 KiB-only mode.

## 8. Required acceptance tests before the emulator

The foundation is not considered complete until the following pass independently on ATM and NeoGS, then across the DMA link:

1. Allocate, write, read and free sizes: 1 byte, 16 KiB−1, 16 KiB, 16 KiB+1, 32 KiB, 48 KiB+1, 64 KiB+1, and a size larger than 256 KiB where capacity permits.
2. Verify patterns at every boundary: page−1, page, page+1, first byte, last byte.
3. Copy overlapping and non-overlapping ranges across multiple extents.
4. Load and validate one module whose total image is larger than 16 KiB; verify relocations and exported symbols.
5. Execute code sections on both sides of a code-window boundary using generated far-call/far-return stubs.
6. Transfer a payload larger than 64 KiB ATM→NeoGS and NeoGS→ATM; compare full payload CRC and byte count.
7. Inject timeout, malformed length, CRC mismatch and cancellation; prove no DMA remains armed and no partial object is published.
8. Reset either side mid-transfer; renegotiate and successfully transfer a fresh object.
9. Run the tests with different physical page layouts to prove callers do not depend on physical contiguity.

Test output must include project name, firmware build ID, ABI version, test size, source/destination offsets, CRC, and PASS/FAIL.

## 9. Implementation order

1. Freeze this memory/module/DMA ABI.
2. Implement ATM memory backend and its allocator/stream primitives.
3. Implement NeoGS memory backend and its allocator/stream primitives.
4. Implement shared DMA streaming and capability negotiation.
5. Implement module packer/loader/linker relocation and far-call runtime.
6. Run the acceptance tests without the x86 emulator.
7. Only then add the 8086 CPU and guest memory/device models.

Project126's fixed 16 KiB overlay/module layout is a historical reference only. It is not the Project127 implementation template.

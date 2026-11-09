# Project127 — low-level foundation

**Revision:** 0.7  
**Status:** ATM memory, video, and RTC services runtime-confirmed. Nemo IDE LBA28 backend added in host v0.15.0; physical-device IDENTIFY remains to be confirmed on hardware/emulator.  
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

Capability flags are defined as bit 0 = range validation, bit 1 = ATM
fixed-window page mapping, bit 2 = ATM contiguous ALLOC/FREE, and bit 3 =
ATM byte READ/WRITE/FILL/COPY. The ATM capability record reports 58
allocatable pages (0x000E8000 bytes). DMA is not implied by these flags.

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

## 9. ATM Turbo 2+ physical page map (verified source baseline)

ATM2+ exposes 64 physical 16 KiB RAM pages. The memory dispatcher at the
shadow port family #3FF7/#7FF7/#BFF7/#FFF7 selects which page is visible in
CPU windows 0..3. D0-D5 are the inverted page number, D6 selects RAM, and
D7=0 selects the fixed dispatcher page number. The page number is therefore
an internal backend detail; public requests remain 32-bit byte offsets and
lengths.

The current ATM runtime reserves physical pages:
- 0: active system/BASIC memory map;
- 1 and 5: Project112 ATM video planes;
- 3 and 7: alternate ZX video pages selected through the ZX-128 screen bit;
- 2: Project127 host stack and stable transfer/runtime window.

The current host image is loaded in the page-5 window, so page 5 is reserved
for both host code and video use. The reserved bitmap is #AF followed by
seven zero bytes. The remaining 58 pages (0x000E8000 bytes) are eligible for
allocation. The first allocator implementation returns contiguous runs of
physical pages and returns a 32-bit byte offset; it does not expose page
numbers to callers. A 16 KiB+1 allocation is covered by the runtime allocator
self-test. The scatter-handle allocator and handle-relative READ/WRITE/FILL/COPY are implemented and runtime-confirmed. Handle PIN/UNPIN is implemented in v0.10.0; its new runtime test must pass before it is considered verified.

## 10. ATM memory-operation ABI decision

The ATM backend uses a **host-buffer descriptor**, not a raw Z80 pointer, as
the data endpoint of bulk memory operations. A raw 16-bit Z80 pointer is not
a valid general-purpose buffer descriptor: its address space is shared with
the four ATM mapping windows, can cross a window boundary, and may refer to
the code or stack that must remain resident while the backend remaps RAM.

The public request therefore carries 32-bit byte offsets for both endpoints
and a 32-bit byte length. The endpoints identify physical ATM RAM ranges;
the caller never supplies a page number or a CPU-window address. The backend
validates both complete ranges before modifying memory and performs internal
mapping/chunking. The host firmware, code, stack, and video reservations are
never allocatable endpoints.

The operation semantics are:

- READ: copy bytes from the specified managed range to a caller-owned ATM RAM
  transfer range.
- WRITE: copy bytes from a caller-owned ATM RAM transfer range into the
  specified managed range.
- FILL: fill the specified managed range with the requested byte value.
- COPY: memmove semantics between two managed ranges, including overlapping
  ranges; direction is selected from the validated physical offsets.
- All offsets and lengths are UINT32 little-endian byte quantities.
- Zero length succeeds without touching memory, provided each offset is a
  valid position at or below capacity.
- A nonzero operation validates every source and destination range before
  the first write. Any unsupported mapping or ownership condition fails
  explicitly; it must never report partial completion as success.
- Page/window size is strictly private. A request may span any number of
  physical pages and is completed internally.

The transfer range is a separately allocated/pinned ATM range, not an
arbitrary 16-bit CPU pointer. This keeps the ABI independent of whichever
window currently exposes a physical page and permits later DMA streaming to
use the same descriptors. READ/WRITE are synchronous memory-to-memory
operations in this milestone; host-mediated NeoGS DMA streaming is a later
transport layer and is not implied by these names.

This decision deliberately avoids a 16-bit caller-buffer ceiling and avoids
mapping over the active host code or stack. It also means READ/WRITE must not
be implemented by blindly copying through the currently mapped CPU window.
The initial ATM backend provides a safe single-aperture bytewise engine: it
remaps only CPU window 3 ($C000-$FFFF), while the host image remains in window
1 and the host stack remains in window 2. The Project112 runtime maps window 3
to physical page 1; the engine restores that mapping after each complete
operation. Each byte is read into host-resident scratch before the destination
page is mapped. Calls are synchronous and non-reentrant; callers must serialize
window-3 users while an operation is active. This is deliberately simple
and slow; it avoids remapping the active code or stack and has no 16 KiB
request limit. READ/WRITE/COPY validate both complete ranges before the first
write; FILL validates its complete destination first. COPY uses backward
traversal whenever destination > source, which is safe for both overlapping
and non-overlapping ranges. The request descriptors remain unchanged; private
32-bit cursors are used during execution. The current implementation is a
bytewise physical-range primitive. The scatter-handle backend adds opaque handles backed by private one-page
extents and transactional allocation rollback. Its allocator smoke test
allocates and frees a 0x4001-byte object. The handle data-operation layer now
provides handle-relative READ/WRITE/FILL/COPY using UINT32 offsets and lengths.
A host runtime self-test exercises a 0x4001-byte fill and read across the
logical extent boundary, checks offsets 0, 0x3FFF and 0x4000, verifies
same-handle overlapping COPY, and rejects an out-of-range request. This test
is an acceptance gate; implementation correctness is not considered proven
until its PASS line is observed on the ATM runtime.

## 11. Physical storage service — Nemo IDE / SMUC

Project127 uses a **physical storage device attached through Nemo IDE / SMUC**.
The disk is not required to be represented by a virtual image. The physical
controller and drive are owned exclusively by the ATM Z80 host firmware.
NeoGS and the emulated 8086 never issue physical controller IN/OUT operations.
They submit block requests to the ATM storage service through the existing
host-mediated DMA/IPC path.

### Ownership and request path

1. Guest/NeoGS submits operation, drive number, 28-bit LBA, sector count,
   transfer direction, and a DMA-backed buffer/stream descriptor.
2. ATM validates the complete request, buffer bounds, sector count and LBA
   range before touching the device.
3. ATM executes the physical controller transaction and transfers data in
   bounded sector/DMA chunks. A partial transfer is never reported as success.
4. ATM returns a completion record containing status, sectors completed,
   device error/status and (for IDENTIFY) the device identity/capacity data.

The service must support IDENTIFY, READ SECTORS, WRITE SECTORS and FLUSH CACHE
at minimum. Use 512-byte logical sectors initially; obtain capacity and device
capabilities from IDENTIFY rather than hard-coding disk geometry. The first
implementation may use LBA28 only if IDENTIFY confirms the device supports it;
otherwise fail explicitly. LBA48 can be added as a separately negotiated
capability. Writes and flushes must preserve device error status.

### Hardware backend separation

The Project126/Project125 ATM-side Nemo IDE bridge is the reference for the
Nemo register interface and bounded ATA status polling. Its observed register
map is data low/high at #10/#11, sector count at #50, LBA bytes at #70/#90/#B0,
drive/head at #D0, and command/status at #F0. The reference implements
IDENTIFY, one-sector READ/WRITE and FLUSH. Project127 must extend this into
multi-sector/block streaming behind the storage service API; do not expose the
one-sector packet size as a public limit.

SMUC must be treated as a distinct hardware backend until its exact register
map, device-select protocol and status semantics are verified against the
Project126/Project112 source or hardware documentation. Do not assume that
SMUC is electrically or register-compatible with Nemo IDE. Probe available
backends at startup, report the detected controller and capabilities, and
select only a backend whose probe succeeds. No destructive write test is
allowed during detection.

All physical controller port access is confined to ATM storage backend source.
No NeoGS module, guest x86 BIOS/device model, or shared memory API may access
these ports directly. The guest-facing IDE controller, if later emulated,
translates its register operations into the same ATM block-service requests.

## 12. Implementation order and frozen milestone

The ATM backend milestone v0.9.1 is runtime-confirmed: range core, page allocator,
physical byte operations, scatter allocation, and handle READ/WRITE/FILL/COPY
all report PASS. The next v0.10.0 gate adds reference-counted PIN/UNPIN and
requires its dedicated runtime self-test to pass.

After that gate, the next integration phase is the host platform layer requested
for Project127: TR-DOS service integration, ATM video service, RTC service,
HDD/block-device service, and speaker/audio output driver. These are host-side
services; NeoGS external I/O continues to be mediated only by ATM/DMA.

The broader foundation work remains: NeoGS 4 MiB memory backend, shared DMA
streaming/capability negotiation, module packer/loader/linker relocation and
far-call runtime, and the cross-device acceptance tests. The 8086 emulator
starts only after the required platform and memory/transport foundations are
validated.

Project126's fixed 16 KiB overlay/module layout is a historical reference only. It is not the Project127 implementation template.

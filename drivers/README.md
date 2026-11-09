# Project127 low-level drivers

The driver tree is split by physical backend. The shared ABI uses byte offsets
and 32-bit lengths; ATM and NeoGS capacities are independent.

## Current executable milestone

- drivers/atm/atm_memory_backend.asm: ATM 1 MiB capability record, checked range validation, physical page mapper, reserved-page map, contiguous page allocator, FREE, and executable self-tests.
- drivers/atm/atm_memory_manager.asm: 32-bit byte-length allocation/free API; physical 16 KiB page granularity remains private to the backend.
- drivers/neogs/neogs_memory_backend.asm: NeoGS 4 MiB capability record and checked range validation.
- drivers/shared/p127_memory_core.inc: common overflow-safe UINT32 range primitive.

The ATM page allocator is executable and reports 58 allocatable physical
pages (0x000E8000 bytes). It currently supports contiguous extents and exact
ALLOC/FREE matching. The 16 KiB physical page size is hidden behind 32-bit byte
lengths. READ/WRITE/FILL/COPY and multi-extent logical handles are not yet
implemented. NeoGS still advertises range validation only.

## Next implementation gates

1. Extend ATM's contiguous page allocator to multi-extent handles and add
   READ/WRITE/FILL/COPY with internal page-window chunking.
2. Complete NeoGS physical-page mapping and reserve resident firmware, stack,
   interrupt and DMA areas.
3. Add host-mediated DMA streaming with full-length commit semantics.
4. Add boundary, fragmentation, reset and bidirectional transport tests.

No guest emulator code should depend on either backend's private mapping.

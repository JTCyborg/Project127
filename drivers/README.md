# Project127 low-level drivers

The driver tree is split by physical backend. The shared ABI uses byte offsets
and 32-bit lengths; ATM and NeoGS capacities are independent.

## Current executable milestone

- drivers/atm/atm_memory_backend.asm: ATM 1 MiB capability record and checked range validation.
- drivers/neogs/neogs_memory_backend.asm: NeoGS 4 MiB capability record and checked range validation.
- drivers/shared/p127_memory_core.inc: common overflow-safe UINT32 range primitive.

This is an executable foundation stage, not a claim that allocation or DMA is
already operational. Capability flags currently advertise only discovery and
range validation. Allocatable capacity is zero until system/video/firmware/
stack/transport reservations and physical mapping are implemented and verified.

## Next implementation gates

1. Complete ATM physical-page selection and active-video reservation using
   Project112's verified mode mappings.
2. Complete NeoGS physical-page mapping and reserve resident firmware, stack,
   interrupt and DMA areas.
3. Add multi-extent allocator and full READ/WRITE/FILL/COPY/STREAM operations.
4. Add host-mediated DMA streaming with full-length commit semantics.
5. Add boundary, fragmentation, reset and bidirectional transport tests.

No guest emulator code should depend on either backend's private mapping.

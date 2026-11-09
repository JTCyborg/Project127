# Project127 ATM page allocator tests

The ATM backend uses 64 physical 16 KiB RAM pages. Reserved page bitmap:
`#AF,00,00,00,00,00,00,00`, corresponding to pages 0, 1, 2, 3, 5 and 7.
The remaining 58 pages are allocator-owned.

## Runtime self-test

1. Allocate 0x4001 bytes. It must occupy two contiguous pages. Pages 4 and 6
   are isolated by reserved pages, so first-fit must select page 8 and return
   byte offset 0x00020000.
2. Free using the exact returned offset and original byte length.
3. Allocate one byte. First-fit must select page 4 and return 0x00010000.
4. Free using the exact returned offset and original byte length.

The self-test is linked into the ATM host entry and prints
`ATM PAGE ALLOCATOR SELFTEST PASS` only after both allocations and frees
complete successfully.

## Mapping rule

To map physical page `p` into CPU window 3 ($C000-$FFFF), write
`#40 | ((~p) & #3F)` to shadow port `#FFF7`. The other window ports are
`#3FF7`, `#7FF7`, and `#BFF7`. Shadow ports are opened through the
Project112-proven TR-DOS ROM trampoline before the mapper is used.

## Current allocator contract

- Requests use a 32-bit byte length; zero and lengths above 1 MiB fail.
- Returned physical byte offsets are page-aligned 32-bit values.
- ALLOC uses first-fit contiguous pages and records the exact requested length.
- FREE requires the exact base offset and exact original byte length; partial
  frees, double frees, and freeing reserved pages are rejected.
- Up to 64 concurrent allocations are tracked.
- Total allocatable capacity is 0x000E8000 bytes. Because this first allocator
  is contiguous, its largest single run is 56 pages (0x000E0000 bytes).
- READ/WRITE/FILL/COPY, multi-extent handles and DMA are not implemented yet.

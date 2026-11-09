# ATM Core Stage 1/2 — page-state manager 0.2.0

## Scope

Software accounting for 64 × 16 KiB ATM RAM pages (1 MiB total). No physical page-register writes and no application allocation.

## Verified video reservations

Based on Project112 ATM710 video implementation and the ATM Turbo 2+ architecture reference:

- ZX video bank D3=0: page 5.
- ZX video bank D3=1: page 7.
- ATM640/EGA/80x25 bank D3=0: pages 5 and 1.
- ATM640/EGA/80x25 bank D3=1: pages 7 and 3.

The allocator therefore reserves pages 1, 3, 5 and 7 (64 KiB union) before any program page can be allocated.

## Runtime checks

After the original BOOT0 diagnostics, expect:

```text
[P127] MEM INIT 1MB/64P
[P127] VIDEO RAM RESERVED P1,P3,P5,P7
[P127] MEM PAGE TEST PASS
```

The self-test verifies that freeing each reserved video page fails, then verifies allocate/free/reallocate/free on an ordinary free page.

## Not covered

This test does not validate physical page-register writes, ROM mapping, kernel relocation, dynamic kernel-end discovery, top-down program arena, DMA, or video output. Those remain separate acceptance stages.

## Verification status

Source changes committed; SjASMPlus build and target-emulator run have not been performed in this environment.

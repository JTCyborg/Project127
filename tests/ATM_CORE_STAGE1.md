# ATM Core Stage 1 — page-state manager 0.1.0

## Scope

Software accounting for 64 × 16 KiB pages (1 MiB total). No physical page-register writes and no application allocation are enabled in this stage.

## API

- `p127_mem_init`: clear the 64-entry state table.
- `p127_mem_reserve`: A=first page, B=count; carry set for invalid range or overlap.
- `p127_mem_alloc`: returns first-fit page in A; carry set if exhausted.
- `p127_mem_free`: A=page; carry set unless that page is currently ALLOCATED.
- `p127_mem_selftest`: allocate/free/reallocate same first-fit page/free.

## Boot integration

The original four BOOT0 diagnostics are retained. The Stage 1 test then emits:

```text
[P127] MEM INIT 1MB/64P
[P127] MEM PAGE TEST PASS
```

A failure prints:

```text
[P127] MEM PAGE TEST FAIL
```

## Acceptance boundary

Passing this test validates the allocator's basic software state transitions only. It does not validate ATM physical page IDs, memory mapping, video reservations, DMA, or application memory availability.

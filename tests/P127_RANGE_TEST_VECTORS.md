# Project127 UINT32 range test vectors

The range primitive validates offset + length using unsigned 32-bit arithmetic,
rejects arithmetic overflow, and accepts a range only when its exclusive end
does not exceed backend capacity.

| Capacity | Offset | Length | Expected |
|---:|---:|---:|---|
| 1 MiB | 0 | 0 | PASS |
| 1 MiB | 0 | 1 | PASS |
| 1 MiB | 1 MiB - 1 | 1 | PASS |
| 1 MiB | 1 MiB | 0 | PASS |
| 1 MiB | 1 MiB | 1 | FAIL |
| 1 MiB | 1 MiB - 1 | 2 | FAIL |
| 1 MiB | 0xFFFFFFFF | 1 | FAIL (UINT32 overflow) |
| 4 MiB | 0 | 4 MiB | PASS |
| 4 MiB | 4 MiB - 1 | 1 | PASS |
| 4 MiB | 4 MiB | 1 | FAIL |
| 4 MiB | 0xFFFFFFF0 | 0x40 | FAIL (UINT32 overflow) |

These are expected vectors, not reported as executed until an assembler/runtime
self-test is linked and run on each target.

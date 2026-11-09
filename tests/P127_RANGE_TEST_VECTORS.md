# Project127 UINT32 range test vectors

The range primitive validates offset + length using unsigned 32-bit arithmetic,
rejects arithmetic overflow, and accepts a range only when its exclusive end
does not exceed backend capacity. Zero-length ranges are valid at offsets from
zero through capacity inclusive, and invalid beyond capacity.

## ATM runtime self-test (1 MiB)

The ATM boot-linked self-test executes all of these cases:

| Offset | Length | Expected |
|---:|---:|---|
| 0x000FFFFF | 1 | PASS — final RAM byte |
| 0x00100000 | 1 | FAIL — first byte beyond RAM |
| 0 | 0x00100000 | PASS — exact full capacity |
| 0x00100000 | 0 | PASS — empty range at capacity |
| 0x00100001 | 0 | FAIL — empty range beyond capacity |
| 0x000FFFFF | 2 | FAIL — crosses RAM end |
| 0xFFFFFFFF | 1 | FAIL — UINT32 addition overflow |

The boot log reports the aggregate result as UINT32 RANGE SELFTEST PASS/FAIL.

## Shared expected vectors

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
| 4 MiB | 4 MiB | 0 | PASS |
| 4 MiB | 4 MiB | 1 | FAIL |
| 4 MiB | 0xFFFFFFF0 | 0x40 | FAIL (UINT32 overflow) |

NeoGS vectors remain expected-only until its backend self-test is linked into
the NeoGS firmware and run on target.

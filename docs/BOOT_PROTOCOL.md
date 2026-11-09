# Boot protocol — milestone 0

## Host image

- Load address: `0x6000`.
- Entry address: `0x6000`.
- CPU: ATM Z80 host.
- Debug output: 8-bit writes to port `0x00EF`.

## Milestone 0 expected output

```text
P127 START
P127 BOOT0 OK
```

Each line ends with CR LF. No other subsystem is allowed to print before these markers.

## Failure isolation

- No first marker: loader, file name, load address or entry transfer is wrong.
- First marker only: entry was reached; inspect execution after the first marker.
- Both markers: boot entry and debug output are working; only then proceed to memory tests.

## Stack

The first implementation uses stack top `0xBFFF`. This is a temporary boot-stage placement, not a final ATM memory map. It must be replaced by the agreed memory map before allocator work begins.

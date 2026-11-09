# Project127

ATM Turbo 2+ / NeoGS low-level platform and x86 emulator.

Project127 starts with a new memory and transport foundation. The Project126 16 KiB overlay/module layout is not carried forward as an application-level constraint.

## Architecture baseline

- [Foundation architecture](docs/P127_FOUNDATION.md)
- Guest CPU target: Intel 8086 Real Mode, 1 MiB address space.
- ATM and NeoGS firmware use memory APIs that accept arbitrary lengths.
- Hardware DMA aperture/page sizes are implementation details; transfers are transparently split and reassembled.
- NeoGS has no direct access to external devices or host ports. All host interaction is requested from ATM through DMA.

The emulator is built only after the low-level memory, module-loading and DMA layers have independent tests.

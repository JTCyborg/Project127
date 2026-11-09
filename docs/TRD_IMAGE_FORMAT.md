# TR-DOS image format

Project127 emits a raw 80-cylinder, double-sided TR-DOS image: 160 interleaved
logical tracks, 16 sectors per track, 256 bytes per sector (655,360 bytes).

Logical track 0 stores 128 directory entries in sectors 1–8 and the disk
descriptor in sector 9. File data starts at logical track 1, sector index 0.
For double-sided images, logical tracks interleave sides (0 = side 0/track 0,
1 = side 1/track 0, 2 = side 0/track 1).

A directory entry is 16 bytes: 8-byte name, file type, two little-endian
parameters, sector count, zero-based starting sector and logical track.
For BASIC, the parameters are BASIC area length (excluding the three-byte
TR-DOS run-line marker) and variables-area offset. For CODE, they are load
address and byte length.

The image contains BOOT (BASIC) and P127BOOT (CODE at #6000). The builder
writes a disk descriptor and contiguous file extents, then verifies the image.

Reference: https://sinclair.wiki.zxnet.co.uk/wiki/TR-DOS_filesystem

; Project127 shared 32-bit memory range core
; UINT32 values are little-endian. Carry set means overflow or end > capacity.
; Zero-length ranges are valid when offset <= capacity.
; Non-reentrant: each processor serializes memory API calls.

P127_ABI_MAJOR EQU 1
P127_ABI_MINOR EQU 0
P127_MEM_CAPS_SIZE EQU 18

p127_range_check::
        ld      hl,p127_range_offset
        ld      de,p127_range_length
        ld      a,(hl)
        ld      b,a
        ld      a,(de)
        add     a,b
        ld      (p127_range_end),a
        inc     hl
        inc     de
        ld      a,(hl)
        ld      b,a
        ld      a,(de)
        adc     a,b
        ld      (p127_range_end+1),a
        inc     hl
        inc     de
        ld      a,(hl)
        ld      b,a
        ld      a,(de)
        adc     a,b
        ld      (p127_range_end+2),a
        inc     hl
        inc     de
        ld      a,(hl)
        ld      b,a
        ld      a,(de)
        adc     a,b
        ld      (p127_range_end+3),a
        jr      c,p127_range_invalid

        ; Unsigned end <= capacity, most-significant byte first.
        ld      a,(p127_range_end+3)
        ld      hl,p127_range_capacity+3
        cp      (hl)
        jr      c,p127_range_valid
        jr      nz,p127_range_invalid
        ld      a,(p127_range_end+2)
        dec     hl
        cp      (hl)
        jr      c,p127_range_valid
        jr      nz,p127_range_invalid
        ld      a,(p127_range_end+1)
        dec     hl
        cp      (hl)
        jr      c,p127_range_valid
        jr      nz,p127_range_invalid
        ld      a,(p127_range_end)
        dec     hl
        cp      (hl)
        jr      c,p127_range_valid
        jr      nz,p127_range_invalid
p127_range_valid:
        or      a
        ret
p127_range_invalid:
        scf
        ret

p127_range_offset:   defs 4,0
p127_range_length:   defs 4,0
p127_range_capacity: defs 4,0
p127_range_end:      defs 4,0

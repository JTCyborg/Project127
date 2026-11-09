; Project127 NeoGS memory backend — capability and range core.
; Physical capacity: 4 MiB on the target board.
; NeoGS local memory is accessed only by NeoGS firmware. External/ATM device
; operations must be requested from ATM over the host DMA transport.
;
; neogs_mem_query_caps: HL -> 18-byte capability record
; neogs_mem_validate_range: carry clear iff offset+length is in 4 MiB
; neogs_mem_range_selftest: carry clear iff all arithmetic boundary tests pass
;
; Local page registers and physical mapping are private backend details.
; READ/WRITE/ALLOC/FREE are not advertised until firmware, stack, transport,
; DMA and other reserved regions have a verified physical map.

        INCLUDE "drivers/shared/p127_memory_core.inc"

NEOGS_RAM_CAPACITY_LO  EQU #00
NEOGS_RAM_CAPACITY_MID EQU #00
NEOGS_RAM_CAPACITY_HI  EQU #40
NEOGS_RAM_CAPACITY_TOP EQU #00

neogs_mem_query_caps::
        ld      hl,neogs_mem_capabilities
        ret

neogs_mem_validate_range::
        ld      hl,NEOGS_RAM_CAPACITY_LO
        ld      (p127_range_capacity),hl
        ld      a,NEOGS_RAM_CAPACITY_HI
        ld      (p127_range_capacity+2),a
        xor     a
        ld      (p127_range_capacity+3),a
        jp      p127_range_check

neogs_mem_range_selftest::
        ; Last byte of installed RAM is valid.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      hl,#003F
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    neogs_mem_validate_range
        jr      c,neogs_mem_selftest_fail

        ; First byte beyond installed RAM is invalid.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      hl,#0040
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    neogs_mem_validate_range
        jr      nc,neogs_mem_selftest_fail

        ; UINT32 addition overflow must be rejected.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    neogs_mem_validate_range
        jr      nc,neogs_mem_selftest_fail
        or      a
        ret
neogs_mem_selftest_fail:
        scf
        ret

neogs_mem_capabilities:
        db      "P127"
        db      P127_ABI_MAJOR,P127_ABI_MINOR
        db      1
        db      0
        db      #00,#00,#40,#00
        db      #00,#00,#00,#00
        db      P127_MEM_CAPS_SIZE,0

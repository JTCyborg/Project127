; Project127 ATM Turbo 2+ memory backend — capability and range core.
; Physical capacity is the agreed 1 MiB ATM RAM configuration.
; Active video backing and system reservations are NOT allocatable.
; Project112 proves video mappings (physical page 5/page 1), but does not
; define a complete general-purpose physical-page selector for all ATM RAM.
;
; atm_mem_query_caps: HL -> 18-byte capability record
; atm_mem_validate_range: carry clear iff offset+length is in 1 MiB
; atm_mem_range_selftest: carry clear iff all arithmetic boundary tests pass
;
; READ/WRITE/ALLOC/FREE are not advertised until page selection and the
; reservation map are implemented and tested on target.

        INCLUDE "drivers/shared/p127_memory_core.inc"

ATM_RAM_CAPACITY_LO  EQU #00
ATM_RAM_CAPACITY_MID EQU #00
ATM_RAM_CAPACITY_HI  EQU #10
ATM_RAM_CAPACITY_TOP EQU #00

atm_mem_query_caps::
        ld      hl,atm_mem_capabilities
        ret

atm_mem_validate_range::
        ld      hl,ATM_RAM_CAPACITY_LO
        ld      (p127_range_capacity),hl
        ld      a,ATM_RAM_CAPACITY_HI
        ld      (p127_range_capacity+2),a
        xor     a
        ld      (p127_range_capacity+3),a
        jp      p127_range_check

atm_mem_range_selftest::
        ; Last byte of installed RAM is valid: 0x000FFFFF + 1.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      hl,#000F
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail

        ; First byte beyond installed RAM is invalid: 0x00100000 + 1.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail

        ; Exact full-capacity range: 0 + 0x00100000.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      (p127_range_offset+2),hl
        ld      (p127_range_length),hl
        ld      hl,#0010
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail

        ; Zero length exactly at capacity is a valid empty range.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ld      (p127_range_length),hl
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail

        ; Zero length beyond capacity is invalid.
        ld      hl,1
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ld      hl,0
        ld      (p127_range_length),hl
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail

        ; A two-byte range starting at the last byte crosses the end.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      hl,#000F
        ld      (p127_range_offset+2),hl
        ld      hl,2
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail

        ; UINT32 addition overflow must be rejected.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail
        or      a
        ret
atm_mem_selftest_fail:
        scf
        ret

atm_mem_capabilities:
        db      "P127"
        db      P127_ABI_MAJOR,P127_ABI_MINOR
        db      0
        db      0
        db      #00,#00,#10,#00
        db      #00,#00,#00,#00
        db      P127_MEM_CAPS_SIZE,0

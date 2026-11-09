; Project127 ATM Turbo 2+ memory backend.
; Physical capacity: 1 MiB (64 x 16 KiB pages).
; ATM page selection is private to atm_memory_manager.asm.
; Reserved pages: 0,1,2,3,5,7; allocator owns the remaining 58 pages.
;
; atm_mem_query_caps: HL -> 18-byte capability record
; atm_mem_validate_range: carry clear iff offset+length is in 1 MiB
; atm_mem_range_selftest: carry clear iff all arithmetic boundary tests pass
;
; ALLOC/FREE and UINT32 byte READ/WRITE/FILL/COPY are implemented.
; Operations use a bytewise single-aperture engine; multi-extent handles remain future work.

        INCLUDE "drivers/shared/p127_memory_core.inc"

ATM_RAM_CAPACITY_LO  EQU #00
ATM_RAM_CAPACITY_MID EQU #00
ATM_RAM_CAPACITY_HI  EQU #10
ATM_RAM_CAPACITY_TOP EQU #00

atm_mem_test4_length_snapshot:
        defs    4,0

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
        ; Test 1: final installed byte is valid.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      hl,#000F
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail_1

        ; Test 2: first byte beyond installed RAM is invalid.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail_2

        ; Test 3: exact full-capacity range is valid.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      (p127_range_offset+2),hl
        ld      (p127_range_length),hl
        ld      hl,#0010
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail_3

        ; Test 4: zero length at capacity is valid.
        ld      hl,0
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ; Zero-length test: HL must be cleared after setting offset high word.
        ld      hl,0
        ld      (p127_range_length),hl
        ld      (p127_range_length+2),hl
        ; Preserve the exact test input before the validator runs.
        ld      hl,p127_range_length
        ld      de,atm_mem_test4_length_snapshot
        ld      bc,4
        ldir
        call    atm_mem_validate_range
        jp      c,atm_mem_selftest_fail_4

        ; Test 5: zero length beyond capacity is invalid.
        ld      hl,1
        ld      (p127_range_offset),hl
        ld      hl,#0010
        ld      (p127_range_offset+2),hl
        ld      hl,0
        ld      (p127_range_length),hl
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail_5

        ; Test 6: two bytes from the final byte cross the end.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      hl,#000F
        ld      (p127_range_offset+2),hl
        ld      hl,2
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail_6

        ; Test 7: UINT32 addition overflow is rejected.
        ld      hl,#FFFF
        ld      (p127_range_offset),hl
        ld      (p127_range_offset+2),hl
        ld      hl,1
        ld      (p127_range_length),hl
        ld      hl,0
        ld      (p127_range_length+2),hl
        call    atm_mem_validate_range
        jp      nc,atm_mem_selftest_fail_7
        xor     a
        ret

atm_mem_selftest_fail_1:
        ld      a,1
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_2:
        ld      a,2
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_3:
        ld      a,3
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_4:
        ld      a,4
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_5:
        ld      a,5
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_6:
        ld      a,6
        jr      atm_mem_selftest_fail
atm_mem_selftest_fail_7:
        ld      a,7
atm_mem_selftest_fail:
        scf
        ret

atm_mem_capabilities:
        db      "P127"
        db      P127_ABI_MAJOR,P127_ABI_MINOR
        db      #0F                 ; range + page-map + alloc/free + byte operations
        db      0
        db      #00,#00,#10,#00
        db      #00,#80,#0E,#00     ; 58 pages = 0x000E8000 bytes allocatable
        db      P127_MEM_CAPS_SIZE,0

        INCLUDE "drivers/atm/atm_memory_manager.asm"
        INCLUDE "drivers/atm/atm_memory_ops.asm"
        INCLUDE "drivers/atm/atm_memory_handles.asm"

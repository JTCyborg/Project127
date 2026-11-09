; =========================================================================
; Project127 ATM physical-page manager
; ATM RAM: 64 x 16 KiB pages, mapped through four 16 KiB CPU windows.
;
; Public request ABI:
;   atm_mem_request_length[4]  UINT32 byte length
;   atm_mem_request_offset[4]  UINT32 physical byte offset (FREE)
;   atm_mem_result_offset[4]   UINT32 physical byte offset (ALLOC result)
;
; ALLOC returns a page-aligned contiguous physical extent. The caller sees
; a 32-bit byte offset; page numbers and the 16 KiB mapping window are private.
; READ/WRITE/STREAM operations will use the same mapper and split internally.
;
; Reserved pages are based on the Project112 ATM2+ memory map and the P127
; boot runtime: page 0 system/BASIC map, page 2 host stack, page 5 host image,
; pages 1/5 ATM video pair, and pages 3/7 alternate ZX video pages.
; =========================================================================

ATM_PAGE_COUNT          EQU 64
ATM_PAGE_SHIFT          EQU 14
ATM_PAGE_SIZE           EQU #4000
ATM_PAGE_PORT_WINDOW3   EQU #FFF7
ATM_ALLOCATION_SLOTS     EQU 64

atm_mem_init::
        ; Clear allocations from a previous initialization.
        xor     a
        ld      hl,atm_mem_allocated_bitmap
        ld      (hl),a
        ld      de,atm_mem_allocated_bitmap+1
        ld      bc,7
        ldir
        ld      hl,atm_mem_alloc_table
        ld      (hl),a
        ld      de,atm_mem_alloc_table+1
        ld      bc,383
        ldir
        ; Open the ATM shadow-port decoder using the proven Project112 ROM
        ; trampoline. This is required before writes to #FFF7.
        call    atm_mem_open_shadow_ports
        or      a
        ret

atm_mem_open_shadow_ports:
        ld      bc,atm_mem_shadow_ports_opened
        push    bc
        ld      bc,#2A53
        push    bc
        ld      bc,#0177
        ld      a,#C3
        jp      #3D2F
atm_mem_shadow_ports_opened:
        ret

; A = physical RAM page 0..63. Maps it into CPU window 3 ($C000-$FFFF).
; The ATM dispatcher uses inverted D0-D5, D6=1 (RAM), D7=0 (fixed page).
atm_mem_map_page::
        cp      ATM_PAGE_COUNT
        jp      nc,atm_mem_map_page_invalid
        cpl
        and     #3F
        or      #40
        ld      bc,ATM_PAGE_PORT_WINDOW3
        out     (c),a
        or      a
        ret
atm_mem_map_page_invalid:
        scf
        ret

; Validate request_offset + request_length against physical capacity.
atm_mem_validate_request:
        ld      hl,(atm_mem_request_offset)
        ld      (p127_range_offset),hl
        ld      hl,(atm_mem_request_offset+2)
        ld      (p127_range_offset+2),hl
        ld      hl,(atm_mem_request_length)
        ld      (p127_range_length),hl
        ld      hl,(atm_mem_request_length+2)
        ld      (p127_range_length+2),hl
        jp      atm_mem_validate_range

; A = ceil(request_length / 16384), 1..64. Request must already be validated.
atm_mem_pages_for_length:
        ld      a,(atm_mem_request_length+1)
        and     #C0
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        ld      b,a
        ld      a,(atm_mem_request_length+2)
        add     a,a
        add     a,a
        add     a,b
        ld      b,a
        ld      a,(atm_mem_request_length)
        ld      c,a
        ld      a,(atm_mem_request_length+1)
        and     #3F
        or      c
        jp      z,atm_mem_pages_exact
        inc     b
atm_mem_pages_exact:
        ld      a,b
        ret

; ALLOC: request_length -> result_offset. First-fit contiguous page extent.
; Carry clear = complete allocation; carry set = invalid size or no run.
atm_mem_alloc::
        ld      hl,0
        ld      (atm_mem_request_offset),hl
        ld      (atm_mem_request_offset+2),hl
        ld      a,(atm_mem_request_length)
        ld      b,a
        ld      a,(atm_mem_request_length+1)
        or      b
        ld      b,a
        ld      a,(atm_mem_request_length+2)
        or      b
        ld      b,a
        ld      a,(atm_mem_request_length+3)
        or      b
        jp      z,atm_mem_alloc_fail
        call    atm_mem_validate_request
        jp      c,atm_mem_alloc_fail
        call    atm_mem_pages_for_length
        or      a
        jp      z,atm_mem_alloc_fail
        ld      (atm_mem_pages_needed),a

        ; Reserve a bookkeeping slot before searching for physical pages.
        ld      hl,atm_mem_alloc_table
        ld      b,ATM_ALLOCATION_SLOTS
atm_mem_alloc_find_slot:
        ld      a,(hl)
        or      a
        jp      z,atm_mem_alloc_slot_found
        push    bc
        ld      de,6
        add     hl,de
        pop     bc
        djnz    atm_mem_alloc_find_slot
        jp      atm_mem_alloc_fail
atm_mem_alloc_slot_found:
        ld      (atm_mem_record_ptr),hl

        xor     a
        ld      (atm_mem_candidate),a

atm_mem_alloc_candidate:
        ld      a,(atm_mem_candidate)
        cp      ATM_PAGE_COUNT
        jp      nc,atm_mem_alloc_fail
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_alloc_scan:
        ld      a,b
        cp      ATM_PAGE_COUNT
        jp      nc,atm_mem_alloc_next_candidate
        call    atm_mem_page_is_free
        jp      nz,atm_mem_alloc_next_candidate
        inc     b
        dec     c
        jp      nz,atm_mem_alloc_scan

        ; Entire run is free. Mark all pages allocated.
        ld      a,(atm_mem_candidate)
        ld      (atm_mem_alloc_start),a
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_alloc_mark:
        ld      a,b
        call    atm_mem_page_set_allocated
        inc     b
        dec     c
        jp      nz,atm_mem_alloc_mark

        ; Record exact allocation identity: start page, page count, byte length.
        ld      hl,(atm_mem_record_ptr)
        ld      a,(atm_mem_alloc_start)
        ld      (hl),a
        inc     hl
        ld      a,(atm_mem_pages_needed)
        ld      (hl),a
        inc     hl
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir

        ; Convert page index to a 32-bit byte offset (page << 14).
        ld      a,(atm_mem_alloc_start)
        and     3
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (atm_mem_result_offset+1),a
        ld      a,(atm_mem_alloc_start)
        srl     a
        srl     a
        ld      (atm_mem_result_offset+2),a
        xor     a
        ld      (atm_mem_result_offset),a
        ld      (atm_mem_result_offset+3),a
        or      a
        ret

atm_mem_alloc_next_candidate:
        ld      a,(atm_mem_candidate)
        inc     a
        ld      (atm_mem_candidate),a
        jp      atm_mem_alloc_candidate

atm_mem_alloc_fail:
        scf
        ret

; FREE: request_offset + request_length identify the original allocation.
; Both the base and the rounded page extent must match allocated pages.
atm_mem_free::
        ld      a,(atm_mem_request_offset)
        or      a
        jp      nz,atm_mem_free_fail_01
        ld      a,(atm_mem_request_offset+3)
        or      a
        jp      nz,atm_mem_free_fail_02
        ld      a,(atm_mem_request_offset+1)
        and     #3F
        jp      nz,atm_mem_free_fail_03
        ld      a,(atm_mem_request_length)
        ld      b,a
        ld      a,(atm_mem_request_length+1)
        or      b
        ld      b,a
        ld      a,(atm_mem_request_length+2)
        or      b
        ld      b,a
        ld      a,(atm_mem_request_length+3)
        or      b
        jp      z,atm_mem_free_fail_04
        call    atm_mem_validate_request
        jp      c,atm_mem_free_fail_05

        ; Page index = (offset >> 14).
        ld      a,(atm_mem_request_offset+2)
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(atm_mem_request_offset+1)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     3
        or      b
        ld      (atm_mem_alloc_start),a

        ; Require an exact base+length match in the allocation table.
        ld      hl,atm_mem_alloc_table
        ld      b,ATM_ALLOCATION_SLOTS
atm_mem_free_find_record:
        ld      a,(hl)
        or      a
        jp      z,atm_mem_free_next_record
        ld      d,a
        ld      a,(atm_mem_alloc_start)
        cp      d
        jp      nz,atm_mem_free_next_record
        push    hl
        inc     hl
        inc     hl
        ld      de,atm_mem_request_length
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_free_record_mismatch
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_free_record_mismatch
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_free_record_mismatch
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_free_record_mismatch
        pop     hl
        ld      (atm_mem_record_ptr),hl
        inc     hl
        ld      a,(hl)
        ld      (atm_mem_pages_needed),a
        jp      atm_mem_free_record_found
atm_mem_free_record_mismatch:
        pop     hl
atm_mem_free_next_record:
        push    bc
        ld      de,6
        add     hl,de
        pop     bc
        djnz    atm_mem_free_find_record
        jp      atm_mem_free_fail
atm_mem_free_record_found:

        ; Validate every page before changing any bitmap bit.
        ld      a,(atm_mem_alloc_start)
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_free_check:
        ld      a,b
        cp      ATM_PAGE_COUNT
        jp      nc,atm_mem_free_fail_06
        call    atm_mem_page_is_allocated
        jp      z,atm_mem_free_fail_07
        inc     b
        dec     c
        jp      nz,atm_mem_free_check

        ld      a,(atm_mem_alloc_start)
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_free_clear:
        ld      a,b
        call    atm_mem_page_clear_allocated
        inc     b
        dec     c
        jp      nz,atm_mem_free_clear
        ; Release the exact allocation record only after all page bits clear.
        ld      hl,(atm_mem_record_ptr)
        xor     a
        ld      (hl),a
        or      a
        ret
atm_mem_free_fail_01:
        ld      a,1
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_02:
        ld      a,2
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_03:
        ld      a,3
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_04:
        ld      a,4
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_05:
        ld      a,5
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_06:
        ld      a,6
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail_07:
        ld      a,7
        ld      (atm_mem_free_error),a
        scf
        ret
atm_mem_free_fail:
        ld      a,255
        ld      (atm_mem_free_error),a
        scf
        ret
        scf
        ret

; A=page. Z if neither reserved nor allocated.
atm_mem_page_is_free:
        push    bc
        ld      c,a
        and     7
        ld      b,a
        ld      a,c
        srl     a
        srl     a
        srl     a
        ld      c,a
        ld      e,1
        ld      a,b
        or      a
        jp      z,atm_mem_page_free_mask_ready
atm_mem_page_free_mask_loop:
        sla     e
        djnz    atm_mem_page_free_mask_loop
atm_mem_page_free_mask_ready:
        ld      a,c
        ld      c,a
        ld      b,0
        ld      hl,atm_mem_reserved_bitmap
        add     hl,bc
        ld      a,(hl)
        and     e
        jp      nz,atm_mem_page_used
        ld      hl,atm_mem_allocated_bitmap
        add     hl,bc
        ld      a,(hl)
        and     e
        pop     bc
        ret
atm_mem_page_used:
        ld      a,1
        or      a
        pop     bc
        ret

; A=page. Sets its bit in the allocation bitmap.
atm_mem_page_set_allocated:
        push    bc
        ld      c,a
        and     7
        ld      b,a
        ld      a,c
        srl     a
        srl     a
        srl     a
        ld      c,a
        ld      e,1
        ld      a,b
        or      a
        jp      z,atm_mem_page_set_mask_ready
atm_mem_page_set_mask_loop:
        sla     e
        djnz    atm_mem_page_set_mask_loop
atm_mem_page_set_mask_ready:
        ld      a,e
        push    af
        ld      a,c
        ld      c,a
        ld      b,0
        ld      hl,atm_mem_allocated_bitmap
        add     hl,bc
        pop     af
        or      (hl)
        ld      (hl),a
        pop     bc
        ret

; A=page. Returns NZ if its allocation bit is set.
atm_mem_page_is_allocated:
        push    bc
        ld      c,a
        and     7
        ld      b,a
        ld      a,c
        srl     a
        srl     a
        srl     a
        ld      c,a
        ld      e,1
        ld      a,b
        or      a
        jp      z,atm_mem_page_alloc_test_ready
atm_mem_page_alloc_test_loop:
        sla     e
        djnz    atm_mem_page_alloc_test_loop
atm_mem_page_alloc_test_ready:
        ld      a,c
        ld      c,a
        ld      b,0
        ld      hl,atm_mem_allocated_bitmap
        add     hl,bc
        ld      a,(hl)
        and     e
        pop     bc
        ret

; A=page. Clears its allocation bit.
atm_mem_page_clear_allocated:
        push    bc
        ld      c,a
        and     7
        ld      b,a
        ld      a,c
        srl     a
        srl     a
        srl     a
        ld      c,a
        ld      e,1
        ld      a,b
        or      a
        jp      z,atm_mem_page_clear_mask_ready
atm_mem_page_clear_mask_loop:
        sla     e
        djnz    atm_mem_page_clear_mask_loop
atm_mem_page_clear_mask_ready:
        ld      a,e
        cpl
        push    af
        ld      a,c
        ld      c,a
        ld      b,0
        ld      hl,atm_mem_allocated_bitmap
        add     hl,bc
        pop     af
        and     (hl)
        ld      (hl),a
        pop     bc
        ret

; Runtime allocator smoke test. Verifies a 16 KiB + 1 byte allocation crosses
; the physical page boundary, then verifies a one-byte allocation and FREE.
atm_mem_allocator_selftest::
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jp      c,atm_mem_allocator_fail_01
        ld      a,(atm_mem_result_offset)
        or      a
        jp      nz,atm_mem_allocator_fail_02
        ld      a,(atm_mem_result_offset+1)
        or      a
        jp      nz,atm_mem_allocator_fail_03
        ld      a,(atm_mem_result_offset+2)
        cp      2
        jp      nz,atm_mem_allocator_fail_04
        ld      a,(atm_mem_result_offset+3)
        or      a
        jp      nz,atm_mem_allocator_fail_05
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_request_offset+2),hl
        call    atm_mem_free
        jp      c,atm_mem_allocator_free_fail_06

        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jp      c,atm_mem_allocator_fail_07
        ld      a,(atm_mem_result_offset)
        or      a
        jp      nz,atm_mem_allocator_fail_08
        ld      a,(atm_mem_result_offset+1)
        or      a
        jp      nz,atm_mem_allocator_fail_09
        ld      a,(atm_mem_result_offset+2)
        cp      1
        jp      nz,atm_mem_allocator_fail_10
        ld      a,(atm_mem_result_offset+3)
        or      a
        jp      nz,atm_mem_allocator_selftest_fail
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_request_offset+2),hl
        call    atm_mem_free
        ret

atm_mem_allocator_fail_01:
        ld      a,1
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_02:
        ld      a,2
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_03:
        ld      a,3
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_04:
        ld      a,4
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_05:
        ld      a,5
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_free_fail_06:
        ld      a,(atm_mem_free_error)
        or      #80
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_07:
        ld      a,7
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_08:
        ld      a,8
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_09:
        ld      a,9
        jr      atm_mem_allocator_selftest_fail
atm_mem_allocator_fail_10:
        ld      a,10
atm_mem_allocator_selftest_fail:
        scf
        ret

atm_mem_request_offset:     defs 4,0
atm_mem_request_length:     defs 4,0
atm_mem_result_offset:      defs 4,0
atm_mem_pages_needed:       db 0
atm_mem_candidate:          db 0
atm_mem_alloc_start:        db 0
atm_mem_record_ptr:         dw 0
atm_mem_free_error:         db 0
; 64 records * 6 bytes: start page, page count, exact UINT32 byte length.
atm_mem_alloc_table:        defs 384,0

; Page 0,1,2,3,5,7 are reserved: $AF in bitmap byte zero.
atm_mem_reserved_bitmap:
        db #AF,0,0,0,0,0,0,0
atm_mem_allocated_bitmap:
        defs 8,0

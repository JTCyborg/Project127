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

atm_mem_init::
        ; Clear allocations from a previous initialization.
        xor     a
        ld      hl,atm_mem_allocated_bitmap
        ld      (hl),a
        ld      de,atm_mem_allocated_bitmap+1
        ld      bc,7
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
        jr      nc,atm_mem_map_page_invalid
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
        jr      z,atm_mem_pages_exact
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
        jr      z,atm_mem_alloc_fail
        call    atm_mem_validate_request
        jr      c,atm_mem_alloc_fail
        call    atm_mem_pages_for_length
        or      a
        jr      z,atm_mem_alloc_fail
        ld      (atm_mem_pages_needed),a
        xor     a
        ld      (atm_mem_candidate),a

atm_mem_alloc_candidate:
        ld      a,(atm_mem_candidate)
        cp      ATM_PAGE_COUNT
        jr      nc,atm_mem_alloc_fail
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_alloc_scan:
        ld      a,b
        cp      ATM_PAGE_COUNT
        jr      nc,atm_mem_alloc_next_candidate
        call    atm_mem_page_is_free
        jr      nz,atm_mem_alloc_next_candidate
        inc     b
        dec     c
        jr      nz,atm_mem_alloc_scan

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
        jr      nz,atm_mem_alloc_mark

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
        jr      atm_mem_alloc_candidate

atm_mem_alloc_fail:
        scf
        ret

; FREE: request_offset + request_length identify the original allocation.
; Both the base and the rounded page extent must match allocated pages.
atm_mem_free::
        ld      a,(atm_mem_request_offset)
        or      a
        jr      nz,atm_mem_free_fail
        ld      a,(atm_mem_request_offset+3)
        or      a
        jr      nz,atm_mem_free_fail
        ld      a,(atm_mem_request_offset+1)
        and     #3F
        jr      nz,atm_mem_free_fail
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
        jr      z,atm_mem_free_fail
        call    atm_mem_validate_request
        jr      c,atm_mem_free_fail
        call    atm_mem_pages_for_length
        ld      (atm_mem_pages_needed),a

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

        ; Validate every page before changing any bitmap bit.
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_free_check:
        ld      a,b
        cp      ATM_PAGE_COUNT
        jr      nc,atm_mem_free_fail
        call    atm_mem_page_is_allocated
        jr      z,atm_mem_free_fail
        inc     b
        dec     c
        jr      nz,atm_mem_free_check

        ld      a,(atm_mem_alloc_start)
        ld      b,a
        ld      a,(atm_mem_pages_needed)
        ld      c,a
atm_mem_free_clear:
        ld      a,b
        call    atm_mem_page_clear_allocated
        inc     b
        dec     c
        jr      nz,atm_mem_free_clear
        or      a
        ret

atm_mem_free_fail:
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
        jr      z,atm_mem_page_free_mask_ready
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
        jr      nz,atm_mem_page_used
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
        jr      z,atm_mem_page_set_mask_ready
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
        jr      z,atm_mem_page_alloc_test_ready
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
        jr      z,atm_mem_page_clear_mask_ready
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
        jr      c,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+1)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+2)
        cp      2
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+3)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_request_offset+2),hl
        call    atm_mem_free
        jr      c,atm_mem_allocator_selftest_fail

        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jr      c,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+1)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+2)
        cp      1
        jr      nz,atm_mem_allocator_selftest_fail
        ld      a,(atm_mem_result_offset+3)
        or      a
        jr      nz,atm_mem_allocator_selftest_fail
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_request_offset+2),hl
        call    atm_mem_free
        ret

atm_mem_allocator_selftest_fail:
        scf
        ret

atm_mem_request_offset:     defs 4,0
atm_mem_request_length:     defs 4,0
atm_mem_result_offset:      defs 4,0
atm_mem_pages_needed:       db 0
atm_mem_candidate:          db 0
atm_mem_alloc_start:        db 0

; Page 0,1,2,3,5,7 are reserved: $AF in bitmap byte zero.
atm_mem_reserved_bitmap:
        db #AF,0,0,0,0,0,0,0
atm_mem_allocated_bitmap:
        defs 8,0

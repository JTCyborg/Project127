; ============================================================================
; Project127 physical ATM RAM page test — Stage 2.19
; Module version: 0.3.3
; Runs from W2 (#A000..), with stack in W2. W1 resident/kernel remains fixed.
; W3 is exclusively leased from the UI and restored to physical page 0.
; This is the first general-purpose physical W3 remap test.
; ============================================================================
P127_PHYSMEM_VERSION_MAJOR EQU 0
P127_PHYSMEM_VERSION_MINOR EQU 3
P127_PHYSMEM_VERSION_PATCH EQU 3
P127_PHYSMEM_PAGE_SIZE     EQU 04000h
P127_PHYSMEM_WINDOW_BASE   EQU 0C000h
P127_PHYSMEM_PAGE_PORT     EQU 0FFF7h

; OUT: carry=1 on any failure. Starts with two pages, then allocates and
; scans every remaining free physical page under one W3 ownership lease.
; The probe byte is complemented so it can never equal the saved P0 byte.
; If the dispatcher is not actually switching, only that one P0 byte is
; touched and it is restored before returning. Full-page writes start only
; after the physical switch has been proven.
p127_physmem_batch_selftest:
        ld      a,'S'
        call    p127_physmem_trace
        xor     a
        ld      (p127_physmem_error),a
        ld      (p127_physmem_alloc_count),a
        ld      (p127_physmem_quiesced),a
        ld      (p127_physmem_acquired),a
        ld      (p127_physmem_mapped),a
        ld      (p127_physmem_saved_valid),a

        ; The host/staging page must be the documented W3 page before entry.
        ld      a,(p127_map_shadow+3)
        or      a
        jp      nz,p127_physmem_fail_map_state

        call    p127_mem_alloc
        jp      c,p127_physmem_fail_alloc
        ld      (p127_physmem_page_a),a
        ld      (p127_physmem_page_list),a
        ld      a,1
        ld      (p127_physmem_alloc_count),a

        call    p127_mem_alloc
        jp      c,p127_physmem_fail_alloc
        ld      (p127_physmem_page_b),a
        ld      (p127_physmem_page_list+1),a
        ld      a,2
        ld      (p127_physmem_alloc_count),a

        ld      a,(p127_physmem_page_a)
        ld      b,a
        ld      a,(p127_physmem_page_b)
        cp      b
        jp      z,p127_physmem_fail_alloc

        ; No UI routine may run while W3 is reassigned.
        call    p127_w3_quiesce
        jp      c,p127_physmem_fail_lease
        ld      a,1
        ld      (p127_physmem_quiesced),a
        call    p127_w3_handoff_acquire
        jp      c,p127_physmem_fail_lease
        ld      a,1
        ld      (p127_physmem_acquired),a

        ; Preserve one byte from P0 for a non-destructive port-open probe.
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      (p127_physmem_saved_p0),a
        cpl
        ld      (p127_physmem_probe),a
        ld      a,1
        ld      (p127_physmem_saved_valid),a

        ; Select allocated page A and write one complemented probe byte.
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      a,1
        ld      (p127_physmem_mapped),a
        ld      a,(p127_physmem_probe)
        ld      (P127_PHYSMEM_WINDOW_BASE),a

        ; Return to P0. Its saved byte must be unchanged if the OUT worked.
        xor     a
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      b,a
        ld      a,(p127_physmem_saved_p0)
        cp      b
        jp      nz,p127_physmem_fail_probe
        ; Re-select page A and verify that its probe byte persisted.
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      b,a
        ld      a,(p127_physmem_probe)
        cp      b
        jp      nz,p127_physmem_fail_probe

        ; Stage 2.18: four address-sensitive pattern rounds. Every round
        ; fills both pages, then alternates W3 and verifies retention.
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,011h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0A2h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,011h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0A2h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,011h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data

        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,037h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0C8h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0C8h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,037h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0C8h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data

        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,05Dh
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0E4h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,05Dh
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,0E4h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,05Dh
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data

        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,083h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,016h
        call    p127_physmem_fill_pattern
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,016h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_a)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,083h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_page_b)
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      d,016h
        call    p127_physmem_verify_pattern
        jp      c,p127_physmem_fail_data

        ld      a,'2'
        call    p127_physmem_trace

        ; Stage 2.19: exhaust the allocator into a private page-ID list.
        ; The first two pages are already listed. Each new allocation is
        ; checked against all prior IDs before it is appended.
p127_physmem_alloc_more:
        ld      a,(p127_physmem_alloc_count)
        cp      P127_PHYSMEM_MAX_PAGES
        jr      nc,p127_physmem_alloc_complete
        call    p127_mem_alloc
        jr      c,p127_physmem_alloc_complete
        ld      (p127_physmem_candidate),a
        ld      d,a
        ld      a,(p127_physmem_alloc_count)
        ld      b,a
        ld      hl,p127_physmem_page_list
p127_physmem_duplicate_scan:
        ld      a,(hl)
        cp      d
        jp      z,p127_physmem_fail_duplicate
        inc     hl
        djnz    p127_physmem_duplicate_scan
        ld      a,(p127_physmem_alloc_count)
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_page_list
        add     hl,de
        ld      a,(p127_physmem_candidate)
        ld      (hl),a
        ld      hl,p127_physmem_alloc_count
        inc     (hl)
        jr      p127_physmem_alloc_more

p127_physmem_alloc_complete:
        ld      a,'A'
        call    p127_physmem_trace
        ; Current map has exactly seven protected pages and 57 allocatable.
        ld      a,(p127_physmem_alloc_count)
        cp      57
        jp      nz,p127_physmem_fail_count
        call    p127_physmem_check_reserved
        jp      c,p127_physmem_fail_reserve

        ; First sweep: fill every allocated physical page with a unique
        ; address-derived pattern whose seed includes its physical page ID.
        ld      a,(p127_physmem_alloc_count)
        ld      (p127_physmem_scan_remaining),a
        ld      hl,p127_physmem_page_list
p127_physmem_full_fill_loop:
        ld      a,(hl)
        inc     hl
        ld      (p127_physmem_current_page),a
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      a,(p127_physmem_current_page)
        xor     05Ah
        ld      d,a
        push    hl
        call    p127_physmem_fill_pattern
        pop     hl
        ld      a,(p127_physmem_scan_remaining)
        dec     a
        ld      (p127_physmem_scan_remaining),a
        jr      nz,p127_physmem_full_fill_loop

        ld      a,'F'
        call    p127_physmem_trace

        ; Reverse sweep verifies every page after all other pages have
        ; already been written. This catches aliases and lost page contents.
        ld      a,(p127_physmem_alloc_count)
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_page_list
        add     hl,de
p127_physmem_full_verify_loop:
        dec     hl
        ld      a,(hl)
        ld      (p127_physmem_current_page),a
        call    p127_physmem_set_w3
        jp      c,p127_physmem_fail_map
        ld      a,(p127_physmem_current_page)
        xor     05Ah
        ld      d,a
        push    hl
        call    p127_physmem_verify_pattern
        pop     hl
        jp      c,p127_physmem_fail_data
        ld      a,(p127_physmem_scan_remaining)
        ; Reinitialize the reverse counter on first entry.
        or      a
        jr      nz,p127_physmem_reverse_count_ready
        ld      a,(p127_physmem_alloc_count)
p127_physmem_reverse_count_ready:
        dec     a
        ld      (p127_physmem_scan_remaining),a
        jr      nz,p127_physmem_full_verify_loop

        ld      a,'V'
        call    p127_physmem_trace

        ; Verify the allocator still marks every listed page ALLOCATED.
        call    p127_physmem_check_allocated
        jp      c,p127_physmem_fail_state
        xor     a
        ld      (p127_physmem_error),a
        jp      p127_physmem_cleanup

p127_physmem_fail_map_state:
        ld      a,1
        jp      p127_physmem_set_error
p127_physmem_fail_alloc:
        ld      a,2
        jp      p127_physmem_set_error
p127_physmem_fail_lease:
        ld      a,3
        jp      p127_physmem_set_error
p127_physmem_fail_map:
        ld      a,4
        jp      p127_physmem_set_error
p127_physmem_fail_probe:
        ld      a,5
        jp      p127_physmem_set_error
p127_physmem_fail_data:
        ld      a,6
        jp      p127_physmem_set_error
p127_physmem_fail_duplicate:
        ld      a,7
        jp      p127_physmem_set_error
p127_physmem_fail_count:
        ld      a,8
        jp      p127_physmem_set_error
p127_physmem_fail_reserve:
        ld      a,9
        jp      p127_physmem_set_error
p127_physmem_fail_state:
        ld      a,10
p127_physmem_set_error:
        ld      (p127_physmem_error),a

p127_physmem_cleanup:
        ld      a,'C'
        call    p127_physmem_trace
        ; Always return W3 to P0 before releasing UI ownership.
        ld      a,(p127_physmem_mapped)
        or      a
        jr      z,p127_physmem_cleanup_saved
        xor     a
        call    p127_physmem_set_w3
        jp      c,p127_physmem_cleanup_error
p127_physmem_cleanup_saved:
        ld      a,(p127_physmem_saved_valid)
        or      a
        jr      z,p127_physmem_cleanup_release
        ld      a,(p127_physmem_saved_p0)
        ld      (P127_PHYSMEM_WINDOW_BASE),a

p127_physmem_cleanup_release:
        ld      a,(p127_physmem_acquired)
        or      a
        jr      z,p127_physmem_cleanup_resume
        call    p127_w3_handoff_release
        jp      c,p127_physmem_cleanup_error
p127_physmem_cleanup_resume:
        ld      a,(p127_physmem_quiesced)
        or      a
        jr      z,p127_physmem_cleanup_free
        call    p127_w3_resume
        jp      c,p127_physmem_cleanup_error

p127_physmem_cleanup_free:
        ld      a,(p127_physmem_alloc_count)
        ld      (p127_physmem_scan_remaining),a
        ld      a,(p127_physmem_alloc_count)
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_page_list
        add     hl,de
p127_physmem_cleanup_free_loop:
        ld      a,(p127_physmem_scan_remaining)
        or      a
        jr      z,p127_physmem_cleanup_done
        dec     hl
        ld      a,(hl)
        push    hl
        call    p127_mem_free
        pop     hl
        jp      c,p127_physmem_cleanup_error
        ld      a,(p127_physmem_scan_remaining)
        dec     a
        ld      (p127_physmem_scan_remaining),a
        jr      p127_physmem_cleanup_free_loop
p127_physmem_cleanup_done:
        ; Reallocation must return the same lowest free page and release it.
        ld      a,(p127_physmem_error)
        or      a
        jr      nz,p127_physmem_cleanup_return
        call    p127_mem_alloc
        jp      c,p127_physmem_cleanup_error
        ld      b,a
        ld      a,(p127_physmem_page_a)
        cp      b
        jp      nz,p127_physmem_cleanup_error
        ld      a,b
        call    p127_mem_free
        jp      c,p127_physmem_cleanup_error
        call    p127_physmem_check_reserved
        jp      c,p127_physmem_cleanup_error
        call    p127_physmem_check_free_state
        jp      c,p127_physmem_cleanup_error
p127_physmem_cleanup_return:
        ld      a,(p127_physmem_error)
        or      a
        ret     z
        scf
        ret

p127_physmem_cleanup_error:
        ld      a,0FFh
        ld      (p127_physmem_error),a
        scf
        ret

; Check the seven fixed reservation states: P0/P1/P2/P3/P4/P5/P7.
; OUT carry=1 if any protected page is not RESERVED.
p127_physmem_check_reserved:
        ld      hl,p127_mem_page_state
        ld      b,8
        ld      c,0
p127_physmem_reserved_loop:
        ld      a,c
        cp      6
        jr      z,p127_physmem_reserved_skip
        cp      7
        jr      z,p127_physmem_reserved_check
        cp      0
        jr      z,p127_physmem_reserved_check
        cp      1
        jr      z,p127_physmem_reserved_check
        cp      2
        jr      z,p127_physmem_reserved_check
        cp      3
        jr      z,p127_physmem_reserved_check
        cp      4
        jr      z,p127_physmem_reserved_check
        cp      5
        jr      z,p127_physmem_reserved_check
        jr      p127_physmem_reserved_skip
p127_physmem_reserved_check:
        push    bc
        push    hl
        ld      e,c
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_RESERVED
        pop     hl
        pop     bc
        jr      nz,p127_physmem_reserved_fail
p127_physmem_reserved_skip:
        inc     c
        djnz    p127_physmem_reserved_loop
        or      a
        ret
p127_physmem_reserved_fail:
        scf
        ret

; Every page in the private list must remain ALLOCATED during the sweep.
p127_physmem_check_allocated:
        ld      a,(p127_physmem_alloc_count)
        ld      b,a
        ld      hl,p127_physmem_page_list
p127_physmem_alloc_state_loop:
        ld      a,(hl)
        ld      e,a
        ld      d,0
        push    bc
        push    hl
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        pop     hl
        pop     bc
        jr      nz,p127_physmem_alloc_state_fail
        inc     hl
        djnz    p127_physmem_alloc_state_loop
        or      a
        ret
p127_physmem_alloc_state_fail:
        scf
        ret

; After release, every non-reserved page must be FREE; reserved pages
; are checked separately by p127_physmem_check_reserved.
p127_physmem_check_free_state:
        ld      hl,p127_mem_page_state
        ld      b,64
        ld      c,0
p127_physmem_free_state_loop:
        ld      a,c
        cp      0
        jr      z,p127_physmem_free_state_reserved
        cp      1
        jr      z,p127_physmem_free_state_reserved
        cp      2
        jr      z,p127_physmem_free_state_reserved
        cp      3
        jr      z,p127_physmem_free_state_reserved
        cp      4
        jr      z,p127_physmem_free_state_reserved
        cp      5
        jr      z,p127_physmem_free_state_reserved
        cp      7
        jr      z,p127_physmem_free_state_reserved
        ld      a,(hl)
        or      a
        jr      nz,p127_physmem_free_state_fail
        jr      p127_physmem_free_state_next
p127_physmem_free_state_reserved:
        ld      a,(hl)
        cp      P127_MEM_RESERVED
        jr      nz,p127_physmem_free_state_fail
p127_physmem_free_state_next:
        inc     hl
        inc     c
        djnz    p127_physmem_free_state_loop
        or      a
        ret
p127_physmem_free_state_fail:
        scf
        ret

; Emit one printable phase marker directly on the established #EF debug port.
; This remains available while the UI is quiesced and W3 is leased.
p127_physmem_trace:
        ld      bc,00EFh
        out     (c),a
        ret

; IN A=physical RAM page ID. Program only W3 (#FFF7), never W0/W1/W2.
; D6=1 selects RAM, D7=0 selects the inverse D0-D5 page ID.
p127_physmem_set_w3:
        ld      (p127_physmem_page_arg),a
        call    p127_map_encode_page
        ret     c
        ld      bc,P127_PHYSMEM_PAGE_PORT
        out     (c),a
        ld      a,(p127_physmem_page_arg)
        ld      (p127_map_shadow+3),a
        or      a
        ret

; IN D=pattern seed. Byte(address)=ROL(address_low) XOR address_high XOR D.
; The same address produces a different expected value at each seed.
p127_physmem_fill_pattern:
        ld      hl,P127_PHYSMEM_WINDOW_BASE
        ld      bc,P127_PHYSMEM_PAGE_SIZE
.p127_physmem_fill_pattern_loop:
        ld      a,l
        rlca
        xor     h
        xor     d
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p127_physmem_fill_pattern_loop
        ret

; IN D=pattern seed. Verify all 16 KiB against the address-derived pattern.
p127_physmem_verify_pattern:
        ld      hl,P127_PHYSMEM_WINDOW_BASE
        ld      bc,P127_PHYSMEM_PAGE_SIZE
.p127_physmem_verify_pattern_loop:
        ld      a,l
        rlca
        xor     h
        xor     d
        cp      (hl)
        jr      nz,.p127_physmem_verify_pattern_fail
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p127_physmem_verify_pattern_loop
        or      a
        ret
.p127_physmem_verify_pattern_fail:
        scf
        ret

P127_PHYSMEM_MAX_PAGES EQU 64
p127_physmem_error: db 0
p127_physmem_alloc_count: db 0
p127_physmem_quiesced: db 0
p127_physmem_acquired: db 0
p127_physmem_mapped: db 0
p127_physmem_saved_valid: db 0
p127_physmem_page_a: db 0
p127_physmem_page_b: db 0
p127_physmem_page_arg: db 0
p127_physmem_saved_p0: db 0
p127_physmem_probe: db 0
p127_physmem_candidate: db 0
p127_physmem_current_page: db 0
p127_physmem_scan_remaining: db 0
p127_physmem_page_list: ds P127_PHYSMEM_MAX_PAGES,0


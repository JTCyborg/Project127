; ============================================================================
; Project127 physical ATM RAM page test — Stage 2.18
; Module version: 0.2.0
; Runs from W2 (#A000..), with stack in W2. W1 resident/kernel remains fixed.
; W3 is exclusively leased from the UI and restored to physical page 0.
; This is the first general-purpose physical W3 remap test.
; ============================================================================
P127_PHYSMEM_VERSION_MAJOR EQU 0
P127_PHYSMEM_VERSION_MINOR EQU 2
P127_PHYSMEM_VERSION_PATCH EQU 0
P127_PHYSMEM_PAGE_SIZE     EQU 04000h
P127_PHYSMEM_WINDOW_BASE   EQU 0C000h
P127_PHYSMEM_PAGE_PORT     EQU 0FFF7h

; OUT: carry=1 on any failure. Uses two pages obtained from the page allocator.
; The probe byte is complemented so it can never equal the saved P0 byte.
; If the dispatcher is not actually switching, only that one P0 byte is
; touched and it is restored before returning. Full-page writes start only
; after the physical switch has been proven.
p127_physmem_batch_selftest:
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
        ld      a,1
        ld      (p127_physmem_alloc_count),a

        call    p127_mem_alloc
        jp      c,p127_physmem_fail_alloc
        ld      (p127_physmem_page_b),a
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
p127_physmem_set_error:
        ld      (p127_physmem_error),a

p127_physmem_cleanup:
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
        cp      2
        jr      c,p127_physmem_cleanup_free_a
        ld      a,(p127_physmem_page_b)
        call    p127_mem_free
        jp      c,p127_physmem_cleanup_error
p127_physmem_cleanup_free_a:
        ld      a,(p127_physmem_alloc_count)
        or      a
        jr      z,p127_physmem_cleanup_done
        ld      a,(p127_physmem_page_a)
        call    p127_mem_free
        jp      c,p127_physmem_cleanup_error
p127_physmem_cleanup_done:
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


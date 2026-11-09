; ============================================================================
; Project127 physical ATM RAM page test — Stage 2.23
; Module version: 0.4.3
; Runs from W2 (#A000..), with stack in W2. W1 resident/kernel remains fixed.
; W3 is exclusively leased from the UI and restored to physical page 0.
; This is the first general-purpose physical W3 remap test.
; ============================================================================
P127_PHYSMEM_VERSION_MAJOR EQU 0
P127_PHYSMEM_VERSION_MINOR EQU 4
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
        ld      a,'F'
        call    p127_physmem_trace_page
        ld      a,(p127_physmem_current_page)
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
        ld      a,'V'
        call    p127_physmem_trace_page
        ld      a,(p127_physmem_current_page)
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
        jr      nz,p127_physmem_cleanup_return_error
        ; The live page sweep ran with W3 exclusively leased, so progress was
        ; mirrored to #EF only. Replay the compact page list now that W3=P0
        ; and the UI owner has been restored.
        call    p127_physmem_replay_page_log
        or      a
        ret
p127_physmem_cleanup_return_error:
        scf
        ret

; Replay all successful physical-page selections on the visible ATM console.
; The 57 IDs are compacted into two wrapped lines rather than 114 long lines.
p127_physmem_replay_page_log:
        ld      hl,p127_physmem_screen_fill_label
        call    p127_physmem_screen_puts
        ld      a,(p127_physmem_alloc_count)
        ld      (p127_physmem_scan_remaining),a
        ld      hl,p127_physmem_page_list
p127_physmem_replay_fill_loop:
        ld      a,(hl)
        inc     hl
        call    p127_physmem_screen_hex8
        ld      a,' '
        call    BIOS_DebugConsole_PrintChar
        ld      a,(p127_physmem_scan_remaining)
        dec     a
        ld      (p127_physmem_scan_remaining),a
        jr      nz,p127_physmem_replay_fill_loop
        ld      a,13
        call    BIOS_DebugConsole_PrintChar
        ld      a,10
        call    BIOS_DebugConsole_PrintChar

        ld      hl,p127_physmem_screen_verify_label
        call    p127_physmem_screen_puts
        ld      a,(p127_physmem_alloc_count)
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_page_list
        add     hl,de
        ld      a,(p127_physmem_alloc_count)
        ld      (p127_physmem_scan_remaining),a
p127_physmem_replay_verify_loop:
        dec     hl
        ld      a,(hl)
        call    p127_physmem_screen_hex8
        ld      a,' '
        call    BIOS_DebugConsole_PrintChar
        ld      a,(p127_physmem_scan_remaining)
        dec     a
        ld      (p127_physmem_scan_remaining),a
        jr      nz,p127_physmem_replay_verify_loop
        ld      a,13
        call    BIOS_DebugConsole_PrintChar
        ld      a,10
        call    BIOS_DebugConsole_PrintChar

        ; Put the decisive result in the fixed status panel as well as the
        ; scrolling log. PrintAt addresses rows directly, so this does not
        ; depend on the current scrolling cursor after the long page replay.
        ld      hl,p127_physmem_screen_status_line0
        ld      a,2
        ld      c,1
        call    BIOS_DebugConsole_PrintAt
        ld      hl,p127_physmem_screen_status_line1
        ld      a,3
        ld      c,1
        call    BIOS_DebugConsole_PrintAt
        ret

; HL=zero-terminated string. The console routine preserves HL.
p127_physmem_screen_puts:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        push    hl
        call    BIOS_DebugConsole_PrintChar
        pop     hl
        jr      p127_physmem_screen_puts

; A=page ID. Emit two hexadecimal digits through the visible UI console.
p127_physmem_screen_hex8:
        push    hl
        push    af
        and     0F0h
        rrca
        rrca
        rrca
        rrca
        call    p127_physmem_screen_nibble
        pop     af
        and     00Fh
        call    p127_physmem_screen_nibble
        pop     hl
        ret
p127_physmem_screen_nibble:
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_trace_hex_table
        add     hl,de
        ld      a,(hl)
        jp      BIOS_DebugConsole_PrintChar

p127_physmem_screen_status_line0:
        db      "PHYSICAL RAM: 57/57 FREE PAGES VERIFIED",0
p127_physmem_screen_status_line1:
        db      "W3: P0 RESTORED | UI ACTIVE | IM/EI DISABLED",0
p127_physmem_screen_fill_label:
        db      "W3 FILL: ",0
p127_physmem_screen_verify_label:
        db      "W3 VERIFY: ",0

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

; ============================================================================
; Stage 2.20 — guarded physical-page API.
; All code and stack remain in W2. The only hardware mapping operation is W3.
; Public ABI:
;   alloc_page: OUT A=allocated page, carry=1 if exhausted.
;   free_page:  IN A=allocated page, carry=1 if invalid or lease active.
;   w3_begin:  quiesce UI, acquire W3, save P0 byte; DI remains in force.
;   w3_map:    IN A=allocated page; valid only inside an active W3 lease.
;   w3_end:    restore W3=P0 and saved byte, release lease, resume UI.
; No API maps W0/W1/W2, frees a currently mapped page, or enables IRQs.
; ============================================================================
p127_physmem_alloc_page:
        jp      p127_mem_alloc

p127_physmem_free_page:
        ld      (p127_physmem_api_page_arg),a
        ld      a,(p127_physmem_api_active)
        or      a
        jp      nz,p127_physmem_api_reject
        ld      a,(p127_physmem_api_page_arg)
        ld      b,a
        ld      a,(p127_map_shadow+3)
        cp      b
        jp      z,p127_physmem_api_reject
        ld      a,(p127_physmem_api_page_arg)
        jp      p127_mem_free

; Begin a bounded W3 lease. Bootstrap mapping must be W3=P0.
p127_physmem_w3_begin:
        di
        ld      a,(p127_physmem_api_active)
        or      a
        jp      nz,p127_physmem_api_reject
        ld      a,(p127_map_shadow+3)
        or      a
        jp      nz,p127_physmem_api_reject
        call    p127_w3_quiesce
        ret     c
        ld      a,1
        ld      (p127_physmem_api_quiesced),a
        call    p127_w3_handoff_acquire
        jr      c,p127_physmem_w3_begin_rollback
        ld      a,1
        ld      (p127_physmem_api_acquired),a
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      (p127_physmem_api_saved_p0),a
        ld      a,1
        ld      (p127_physmem_api_saved_valid),a
        ld      (p127_physmem_api_active),a
        or      a
        ret
p127_physmem_w3_begin_rollback:
        call    p127_w3_resume
        xor     a
        ld      (p127_physmem_api_quiesced),a
        scf
        ret

; Map only an allocator-owned page into W3.
p127_physmem_w3_map:
        ld      (p127_physmem_api_page_arg),a
        ld      a,(p127_physmem_api_active)
        cp      1
        jp      nz,p127_physmem_api_reject
        ld      a,(p127_physmem_api_page_arg)
        cp      P127_PHYSMEM_MAX_PAGES
        jp      nc,p127_physmem_api_reject
        ld      e,a
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_physmem_api_reject
        ld      a,(p127_physmem_api_page_arg)
        jp      p127_physmem_set_w3

; End the lease in recovery order. If release/resume fails, state flags are
; retained so the caller can retry this routine without losing ownership.
p127_physmem_w3_end:
        ld      a,(p127_physmem_api_active)
        cp      1
        jp      nz,p127_physmem_api_reject
        xor     a
        call    p127_physmem_set_w3
        ret     c
        ld      a,(p127_physmem_api_saved_valid)
        or      a
        jr      z,p127_physmem_w3_end_release
        ld      a,(p127_physmem_api_saved_p0)
        ld      (P127_PHYSMEM_WINDOW_BASE),a
p127_physmem_w3_end_release:
        ld      a,(p127_physmem_api_acquired)
        or      a
        jr      z,p127_physmem_w3_end_resume
        call    p127_w3_handoff_release
        ret     c
        xor     a
        ld      (p127_physmem_api_acquired),a
p127_physmem_w3_end_resume:
        ld      a,(p127_physmem_api_quiesced)
        or      a
        jr      z,p127_physmem_w3_end_done
        call    p127_w3_resume
        ret     c
        xor     a
        ld      (p127_physmem_api_quiesced),a
p127_physmem_w3_end_done:
        xor     a
        ld      (p127_physmem_api_saved_valid),a
        ld      (p127_physmem_api_active),a
        or      a
        ret

p127_physmem_api_reject:
        scf
        ret

; Runtime API contract test. It proves rejection paths, allocated-page-only
; mapping, mapped-page free protection, P0 byte restoration and UI recovery.
p127_physmem_api_selftest:
        xor     a
        ld      (p127_physmem_api_active),a
        ld      (p127_physmem_api_quiesced),a
        ld      (p127_physmem_api_acquired),a
        ld      (p127_physmem_api_saved_valid),a
        ld      a,1
        call    p127_physmem_free_page
        jp      nc,p127_physmem_api_test_fail
        call    p127_physmem_alloc_page
        jp      c,p127_physmem_api_test_fail
        ld      (p127_physmem_api_test_page),a
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      (p127_physmem_api_test_p0),a
        call    p127_physmem_w3_begin
        jp      c,p127_physmem_api_test_free
        ; A reserved page must never be accepted by the map API.
        ld      a,1
        call    p127_physmem_w3_map
        jp      nc,p127_physmem_api_test_end
        ld      a,(p127_physmem_api_test_page)
        call    p127_physmem_w3_map
        jp      c,p127_physmem_api_test_end
        ; The currently mapped page cannot be freed while the lease is held.
        ld      a,(p127_physmem_api_test_page)
        call    p127_physmem_free_page
        jp      nc,p127_physmem_api_test_end
        ld      a,0A5h
        ld      (P127_PHYSMEM_WINDOW_BASE),a
        call    p127_physmem_w3_end
        jp      c,p127_physmem_api_test_fail
        ld      a,(P127_PHYSMEM_WINDOW_BASE)
        ld      b,a
        ld      a,(p127_physmem_api_test_p0)
        cp      b
        jp      nz,p127_physmem_api_test_fail
        ld      a,(p127_physmem_api_test_page)
        call    p127_physmem_free_page
        jp      c,p127_physmem_api_test_fail
        ; First-fit must return the same page after release.
        call    p127_physmem_alloc_page
        jp      c,p127_physmem_api_test_fail
        ld      b,a
        ld      a,(p127_physmem_api_test_page)
        cp      b
        jp      nz,p127_physmem_api_test_fail
        ld      a,b
        call    p127_physmem_free_page
        jp      c,p127_physmem_api_test_fail
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_UI_ACTIVE
        jp      nz,p127_physmem_api_test_fail
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_UI
        jp      nz,p127_physmem_api_test_fail
        ld      a,(p127_map_shadow+3)
        or      a
        jp      nz,p127_physmem_api_test_fail
        or      a
        ret

p127_physmem_api_test_end:
        call    p127_physmem_w3_end
p127_physmem_api_test_free:
        ld      a,(p127_physmem_api_test_page)
        call    p127_physmem_free_page
p127_physmem_api_test_fail:
        scf
        ret

p127_physmem_api_active: db 0
p127_physmem_api_quiesced: db 0
p127_physmem_api_acquired: db 0
p127_physmem_api_saved_valid: db 0
p127_physmem_api_saved_p0: db 0
p127_physmem_api_page_arg: db 0
p127_physmem_api_test_page: db 0
p127_physmem_api_test_p0: db 0

p127_physmem_trace:
        ld      bc,00EFh
        out     (c),a
        ret

; Emit progress for each physical page while the UI is quiesced.
; A='F' prints FILL PAGE ID=xx; A='V' prints VERIFY PAGE ID=xx.
; Preserve every register because the caller owns the page-list cursor.
p127_physmem_trace_page:
        push    af
        push    bc
        push    de
        push    hl
        ; W3 is leased by the sweep, so live screen progress uses only W1.
        ; The renderer maps reserved character page P7 in W1, writes one
        ; status row, then restores resident page P5 before returning.
        call    p127_physmem_live_trace_page
        cp      'F'
        jr      nz,p127_physmem_trace_page_verify
        ld      hl,p127_physmem_trace_fill_text
        jr      p127_physmem_trace_page_text
p127_physmem_trace_page_verify:
        ld      hl,p127_physmem_trace_verify_text
p127_physmem_trace_page_text:
        ld      a,(hl)
        or      a
        jr      z,p127_physmem_trace_page_value
        inc     hl
        push    hl
        call    p127_physmem_trace_char
        pop     hl
        jr      p127_physmem_trace_page_text
p127_physmem_trace_page_value:
        ld      a,(p127_physmem_current_page)
        call    p127_physmem_trace_hex8
        ld      a,13
        call    p127_physmem_trace_char
        ld      a,10
        call    p127_physmem_trace_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret


; Live progress renderer for the physical W3 sweep.
; W3 is deliberately untouched: it remains mapped to the page under test.
; Only W1 is temporarily mapped to reserved video character page P7.
; Character attributes were initialized before the test on reserved P3.
; Code and stack execute in W2, so the bounded W1 switch is safe here.
p127_physmem_live_trace_page:
        push    af
        push    bc
        push    de
        push    hl
        ld      (p127_physmem_live_phase),a
        ; Do not guess the resident map. If W1 is not the expected P5,
        ; skip the optional screen mirror and retain the authoritative #EF log.
        ld      a,(p127_map_shadow+1)
        cp      5
        jp      nz,.p127_live_done
        ld      a,7
        call    p127_map_encode_page
        jp      c,.p127_live_done
        ld      bc,07FF7h
        out     (c),a
        ld      a,7
        ld      (p127_map_shadow+1),a

        ld      a,(p127_physmem_live_phase)
        cp      'F'
        jr      nz,.p127_live_verify
        ld      a,2
        ld      (p127_physmem_live_row),a
        ld      hl,p127_physmem_live_fill_text
        jr      .p127_live_prefix
.p127_live_verify:
        ld      a,3
        ld      (p127_physmem_live_row),a
        ld      hl,p127_physmem_live_verify_text
.p127_live_prefix:
        xor     a
        ld      (p127_physmem_live_col),a
.p127_live_text_loop:
        ld      a,(hl)
        or      a
        jr      z,.p127_live_page_id
        inc     hl
        push    hl
        call    p127_physmem_live_putc
        pop     hl
        jr      .p127_live_text_loop

.p127_live_page_id:
        ld      a,(p127_physmem_current_page)
        push    af
        and     0F0h
        rrca
        rrca
        rrca
        rrca
        call    p127_physmem_live_nibble
        pop     af
        and     00Fh
        call    p127_physmem_live_nibble

        ; Restore the resident W1 mapping before returning to the sweep.
        ld      a,5
        call    p127_map_encode_page
        ld      bc,07FF7h
        out     (c),a
        ld      a,5
        ld      (p127_map_shadow+1),a
.p127_live_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; A=ASCII character. Write only the P7 character plane through W1.
; ATM 80-column text uses two interleaved character planes at #4000/#6000.
p127_physmem_live_putc:
        push    af
        push    bc
        push    de
        push    hl
        ld      (p127_physmem_live_char),a
        ld      a,(p127_physmem_live_row)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,001C0h
        add     hl,de
        ld      a,(p127_physmem_live_col)
        ld      c,a
        and     1
        ld      (p127_physmem_live_parity),a
        ld      a,c
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(p127_physmem_live_parity)
        or      a
        jr      nz,.p127_live_odd
        ld      de,04000h
        jr      .p127_live_base
.p127_live_odd:
        ld      de,06000h
.p127_live_base:
        add     hl,de
        ld      a,(p127_physmem_live_char)
        ld      (hl),a
        ld      a,(p127_physmem_live_col)
        inc     a
        ld      (p127_physmem_live_col),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; A=hex nibble.
p127_physmem_live_nibble:
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_trace_hex_table
        add     hl,de
        ld      a,(hl)
        jp      p127_physmem_live_putc

p127_physmem_live_fill_text:
        db      "FILL PAGE ID=",0
p127_physmem_live_verify_text:
        db      "VERIFY PAGE ID=",0

p127_physmem_trace_hex8:
        push    af
        and     0F0h
        rrca
        rrca
        rrca
        rrca
        call    p127_physmem_trace_nibble
        pop     af
        and     00Fh
        jp      p127_physmem_trace_nibble

p127_physmem_trace_nibble:
        ld      e,a
        ld      d,0
        ld      hl,p127_physmem_trace_hex_table
        add     hl,de
        ld      a,(hl)
        jp      p127_physmem_trace_char

p127_physmem_trace_char:
        ld      bc,00EFh
        out     (c),a
        ret

p127_physmem_trace_fill_text:
        db      "FILL PAGE ID=",0
p127_physmem_trace_verify_text:
        db      "VERIFY PAGE ID=",0
p127_physmem_trace_hex_table:
        db      "0123456789ABCDEF"

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
p127_physmem_live_phase: db 0
p127_physmem_live_row: db 0
p127_physmem_live_col: db 0
p127_physmem_live_char: db 0
p127_physmem_live_parity: db 0
p127_physmem_page_list: ds P127_PHYSMEM_MAX_PAGES,0


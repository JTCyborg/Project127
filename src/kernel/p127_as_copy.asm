; ============================================================================
; Project127 — managed logical-span copy
; Module version: 0.1.0
;
; Copies between non-overlapping mapped logical spans using the guarded W3
; lease and a resident 64-byte bounce buffer. W1/P5 holds this code/buffer;
; W2/P2 holds the live stack. No UI call occurs while W3 is leased.
;
; API inputs:
;   p127_as_copy_source      uint32 little-endian
;   p127_as_copy_destination uint32 little-endian
;   p127_as_copy_length      uint32 little-endian
; Outputs:
;   carry clear = success; carry set = failure
;   p127_as_copy_completed   exact bytes written before return
;   p127_as_copy_error       0 success, 1 span, 2 overlap, 3 lease,
;                            4 source map, 5 destination map, 6 lease restore
; Overlap is rejected; this is not memmove. Unexpected runtime failures after
; writes begin may leave a destination prefix modified.
; ============================================================================
P127_AS_COPY_VERSION_MAJOR EQU 0
P127_AS_COPY_VERSION_MINOR EQU 1
P127_AS_COPY_VERSION_PATCH EQU 2
P127_AS_COPY_BUFFER_SIZE EQU 64
P127_AS_COPY_WINDOW_BASE EQU 0C000h

p127_as_copy:
        xor     a
        ld      (p127_as_copy_error),a
        ld      (p127_as_copy_completed),a
        ld      (p127_as_copy_completed+1),a
        ld      (p127_as_copy_completed+2),a
        ld      (p127_as_copy_completed+3),a

        ; Validate source and destination completely before taking W3.
        ld      hl,p127_as_copy_source
        ld      de,p127_as_span_start
        ld      bc,4
        ldir
        ld      hl,p127_as_copy_length
        ld      de,p127_as_span_length
        ld      bc,4
        ldir
        call    p127_as_span_check
        jp      c,p127_as_copy_span_reject

        ld      hl,p127_as_copy_destination
        ld      de,p127_as_span_start
        ld      bc,4
        ldir
        call    p127_as_span_check
        jp      c,p127_as_copy_span_reject

        ; Empty spans are valid no-ops, including an address exactly 4 MiB.
        ld      a,(p127_as_copy_length)
        ld      b,a
        ld      a,(p127_as_copy_length+1)
        or      b
        ld      b,a
        ld      a,(p127_as_copy_length+2)
        or      b
        ld      b,a
        ld      a,(p127_as_copy_length+3)
        or      b
        jp      z,p127_as_copy_success

        ; Calculate both end-exclusive addresses (preflight proved no overflow).
        ld      hl,(p127_as_copy_source)
        ld      a,(p127_as_copy_length)
        ld      c,a
        ld      a,(p127_as_copy_length+1)
        ld      b,a
        add     hl,bc
        ld      (p127_as_copy_source_end),hl
        ld      hl,(p127_as_copy_source+2)
        ld      a,(p127_as_copy_length+2)
        ld      c,a
        ld      a,(p127_as_copy_length+3)
        ld      b,a
        adc     hl,bc
        ld      (p127_as_copy_source_end+2),hl

        ld      hl,(p127_as_copy_destination)
        ld      a,(p127_as_copy_length)
        ld      c,a
        ld      a,(p127_as_copy_length+1)
        ld      b,a
        add     hl,bc
        ld      (p127_as_copy_destination_end),hl
        ld      hl,(p127_as_copy_destination+2)
        ld      a,(p127_as_copy_length+2)
        ld      c,a
        ld      a,(p127_as_copy_length+3)
        ld      b,a
        adc     hl,bc
        ld      (p127_as_copy_destination_end+2),hl

        ; Disjoint iff source_end <= destination OR destination_end <= source.
        ld      hl,p127_as_copy_source_end
        ld      de,p127_as_copy_destination
        call    p127_as_copy_compare_u32
        jr      c,p127_as_copy_ranges_disjoint
        jr      z,p127_as_copy_ranges_disjoint
        ld      hl,p127_as_copy_destination_end
        ld      de,p127_as_copy_source
        call    p127_as_copy_compare_u32
        jr      c,p127_as_copy_ranges_disjoint
        jr      z,p127_as_copy_ranges_disjoint
        ld      a,2
        ld      (p127_as_copy_error),a
        scf
        ret

p127_as_copy_ranges_disjoint:
        ; W3 begin is the only transition into physical access.
        call    p127_physmem_w3_begin
        jp      c,p127_as_copy_lease_reject

        ld      hl,p127_as_copy_source
        ld      de,p127_as_copy_remaining
        ld      bc,4
        ldir
        ld      hl,p127_as_copy_source
        ld      de,p127_as_copy_work_source
        ld      bc,4
        ldir
        ld      hl,p127_as_copy_destination
        ld      de,p127_as_copy_work_destination
        ld      bc,4
        ldir

p127_as_copy_loop:
        ; Remaining==0 completes the transfer.
        ld      a,(p127_as_copy_remaining)
        ld      b,a
        ld      a,(p127_as_copy_remaining+1)
        or      b
        ld      b,a
        ld      a,(p127_as_copy_remaining+2)
        or      b
        ld      b,a
        ld      a,(p127_as_copy_remaining+3)
        or      b
        jp      z,p127_as_copy_finish

        ; Translate the current source byte address.
        ld      hl,p127_as_copy_work_source
        ld      de,p127_as_address
        ld      bc,4
        ldir
        call    p127_as_translate
        jp      c,p127_as_copy_source_map_fail
        ld      (p127_as_copy_source_page),a
        ld      (p127_as_copy_source_offset),hl

        ; Translate the current destination byte address.
        ld      hl,p127_as_copy_work_destination
        ld      de,p127_as_address
        ld      bc,4
        ldir
        call    p127_as_translate
        jp      c,p127_as_copy_destination_map_fail
        ld      (p127_as_copy_destination_page),a
        ld      (p127_as_copy_destination_offset),hl

        ; Chunk <= 64, remaining length, source page tail and destination tail.
        ld      a,P127_AS_COPY_BUFFER_SIZE
        ld      (p127_as_copy_chunk),a
        ld      hl,(p127_as_copy_source_offset)
        call    p127_as_copy_limit_page_tail
        ld      hl,(p127_as_copy_destination_offset)
        call    p127_as_copy_limit_page_tail
        ld      a,(p127_as_copy_remaining+1)
        ld      b,a
        ld      a,(p127_as_copy_remaining+2)
        or      b
        ld      b,a
        ld      a,(p127_as_copy_remaining+3)
        or      b
        jr      nz,p127_as_copy_chunk_ready
        ld      a,(p127_as_copy_remaining)
        cp      P127_AS_COPY_BUFFER_SIZE
        jr      nc,p127_as_copy_chunk_ready
        ld      (p127_as_copy_chunk),a
p127_as_copy_chunk_ready:
        ld      a,(p127_as_copy_source_page)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_source_map_fail

        ; Read source bytes into the resident bounce buffer.
        ld      hl,(p127_as_copy_source_offset)
        ld      de,P127_AS_COPY_WINDOW_BASE
        add     hl,de
        ld      de,p127_as_copy_buffer
        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        ldir

        ; Map destination only after the source chunk is safely resident.
        ld      a,(p127_as_copy_destination_page)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_destination_map_fail
        ld      hl,(p127_as_copy_destination_offset)
        ld      de,P127_AS_COPY_WINDOW_BASE
        add     hl,de
        ex      de,hl
        ld      hl,p127_as_copy_buffer
        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        ldir

        ; Advance both 32-bit cursors by this chunk.
        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        ld      hl,(p127_as_copy_work_source)
        add     hl,bc
        ld      (p127_as_copy_work_source),hl
        ld      hl,(p127_as_copy_work_source+2)
        ld      de,0
        adc     hl,de
        ld      (p127_as_copy_work_source+2),hl

        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        ld      hl,(p127_as_copy_work_destination)
        add     hl,bc
        ld      (p127_as_copy_work_destination),hl
        ld      hl,(p127_as_copy_work_destination+2)
        ld      de,0
        adc     hl,de
        ld      (p127_as_copy_work_destination+2),hl

        ; remaining -= chunk; completed += chunk.
        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        or      a
        ld      hl,(p127_as_copy_remaining)
        sbc     hl,bc
        ld      (p127_as_copy_remaining),hl
        ld      hl,(p127_as_copy_remaining+2)
        ld      bc,0
        sbc     hl,bc
        ld      (p127_as_copy_remaining+2),hl

        ld      a,(p127_as_copy_chunk)
        ld      c,a
        ld      b,0
        ld      hl,(p127_as_copy_completed)
        add     hl,bc
        ld      (p127_as_copy_completed),hl
        ld      hl,(p127_as_copy_completed+2)
        ld      bc,0
        adc     hl,bc
        ld      (p127_as_copy_completed+2),hl
        jp      p127_as_copy_loop

p127_as_copy_finish:
        call    p127_physmem_w3_end
        jp      c,p127_as_copy_restore_fail
        xor     a
        ld      (p127_as_copy_error),a
        or      a
        ret

p127_as_copy_source_map_fail:
        ld      a,4
        ld      (p127_as_copy_error),a
        jp      p127_as_copy_abort
p127_as_copy_destination_map_fail:
        ld      a,5
        ld      (p127_as_copy_error),a
        jp      p127_as_copy_abort
p127_as_copy_abort:
        call    p127_physmem_w3_end
        jp      c,p127_as_copy_restore_fail
        scf
        ret
p127_as_copy_restore_fail:
        ld      a,6
        ld      (p127_as_copy_error),a
        scf
        ret
p127_as_copy_span_reject:
        ld      a,1
        ld      (p127_as_copy_error),a
        scf
        ret
p127_as_copy_lease_reject:
        ld      a,3
        ld      (p127_as_copy_error),a
        scf
        ret
p127_as_copy_success:
        xor     a
        ld      (p127_as_copy_error),a
        or      a
        ret

; IN HL=left uint32 pointer, DE=right uint32 pointer.
; OUT carry if left<right; Z if equal. Preserves BC.
p127_as_copy_compare_u32:
        push    bc
        ld      bc,3
        add     hl,bc
        ex      de,hl
        add     hl,bc
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_as_copy_compare_done
        dec     de
        dec     hl
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_as_copy_compare_done
        dec     de
        dec     hl
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_as_copy_compare_done
        dec     de
        dec     hl
        ld      a,(de)
        cp      (hl)
p127_as_copy_compare_done:
        pop     bc
        ret

; IN HL=14-bit page offset. Reduce current chunk if fewer than 64 bytes
; remain before the end of this 16 KiB logical page.
p127_as_copy_limit_page_tail:
        ld      a,h
        cp      03Fh
        ret     nz
        ld      a,l
        cp      0C1h
        ret     c
        xor     a
        sub     l
        ld      b,a
        ld      a,(p127_as_copy_chunk)
        cp      b
        ret     c
        ld      a,b
        ld      (p127_as_copy_chunk),a
        ret

; Runtime regression: seed two source pages, copy 32 bytes across both source
; and destination page boundaries, then verify destination byte-for-byte.
p127_as_copy_selftest:
        ld      a,1
        ld      (p127_as_copy_test_phase),a
        xor     a
        ld      (p127_as_copy_test_alloc_count),a
        ld      (p127_as_copy_test_bind_count),a
        ld      (p127_as_copy_test_lease),a
        call    p127_as_init

        call    p127_physmem_alloc_page
        jp      c,p127_as_copy_test_fail
        ld      (p127_as_copy_test_page_a),a
        ld      a,1
        ld      (p127_as_copy_test_alloc_count),a
        call    p127_physmem_alloc_page
        jp      c,p127_as_copy_test_cleanup
        ld      (p127_as_copy_test_page_b),a
        ld      a,2
        ld      (p127_as_copy_test_alloc_count),a
        call    p127_physmem_alloc_page
        jp      c,p127_as_copy_test_cleanup
        ld      (p127_as_copy_test_page_c),a
        ld      a,3
        ld      (p127_as_copy_test_alloc_count),a

        ld      a,(p127_as_copy_test_page_a)
        ld      b,a
        xor     a
        call    p127_as_bind
        jp      c,p127_as_copy_test_cleanup
        ld      a,1
        ld      (p127_as_copy_test_bind_count),a
        ld      a,(p127_as_copy_test_page_b)
        ld      b,a
        ld      a,1
        call    p127_as_bind
        jp      c,p127_as_copy_test_cleanup
        ld      a,2
        ld      (p127_as_copy_test_bind_count),a
        ld      a,(p127_as_copy_test_page_c)
        ld      b,a
        ld      a,2
        call    p127_as_bind
        jp      c,p127_as_copy_test_cleanup
        ld      a,3
        ld      (p127_as_copy_test_bind_count),a

        ld      a,2
        ld      (p127_as_copy_test_phase),a
        ; Zero-length at the exact 4 MiB boundary must not acquire W3.
        ld      a,040h
        ld      (p127_as_copy_source+2),a
        ld      (p127_as_copy_destination+2),a
        xor     a
        ld      (p127_as_copy_source),a
        ld      (p127_as_copy_source+1),a
        ld      (p127_as_copy_source+3),a
        ld      (p127_as_copy_destination),a
        ld      (p127_as_copy_destination+1),a
        ld      (p127_as_copy_destination+3),a
        ld      (p127_as_copy_length),a
        ld      (p127_as_copy_length+1),a
        ld      (p127_as_copy_length+2),a
        ld      (p127_as_copy_length+3),a
        call    p127_as_copy
        jp      c,p127_as_copy_test_cleanup
        ld      a,(p127_physmem_api_active)
        or      a
        jp      nz,p127_as_copy_test_cleanup

        ld      a,3
        ld      (p127_as_copy_test_phase),a
        ; Overlapping spans must be rejected before lease acquisition.
        xor     a
        ld      (p127_as_copy_source+2),a
        ld      (p127_as_copy_destination+2),a
        ld      (p127_as_copy_source+3),a
        ld      (p127_as_copy_destination+3),a
        ld      a,010h
        ld      (p127_as_copy_source),a
        ld      (p127_as_copy_destination),a
        xor     a
        ld      (p127_as_copy_source+1),a
        ld      a,011h
        ld      (p127_as_copy_destination),a
        ld      a,020h
        ld      (p127_as_copy_length),a
        xor     a
        ld      (p127_as_copy_length+1),a
        ld      (p127_as_copy_length+2),a
        ld      (p127_as_copy_length+3),a
        call    p127_as_copy
        jp      nc,p127_as_copy_test_cleanup
        ld      a,(p127_physmem_api_active)
        or      a
        jp      nz,p127_as_copy_test_cleanup

        ld      a,4
        ld      (p127_as_copy_test_phase),a
        ; Invalid destination page 3 is rejected before any W3 lease.
        ld      a,0F0h
        ld      (p127_as_copy_source),a
        ld      a,03Fh
        ld      (p127_as_copy_source+1),a
        xor     a
        ld      (p127_as_copy_source+2),a
        ld      (p127_as_copy_source+3),a
        ld      a,0
        ld      (p127_as_copy_destination),a
        ld      a,0C0h
        ld      (p127_as_copy_destination+1),a
        ld      a,1
        ld      (p127_as_copy_length),a
        xor     a
        ld      (p127_as_copy_length+1),a
        ld      (p127_as_copy_length+2),a
        ld      (p127_as_copy_length+3),a
        call    p127_as_copy
        jp      nc,p127_as_copy_test_cleanup
        ld      a,(p127_physmem_api_active)
        or      a
        jp      nz,p127_as_copy_test_cleanup

        ld      a,5
        ld      (p127_as_copy_test_phase),a
        ; Seed 16 bytes at the end of page 0 and 16 at the start of page 1.
        call    p127_physmem_w3_begin
        jp      c,p127_as_copy_test_cleanup
        ld      a,1
        ld      (p127_as_copy_test_lease),a
        ld      a,(p127_as_copy_test_page_a)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_test_cleanup
        ld      hl,0FFF0h
        ld      de,p127_as_copy_test_pattern
        ld      bc,16
        ldir
        ld      a,(p127_as_copy_test_page_b)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_test_cleanup
        ld      hl,0C000h
        ld      de,p127_as_copy_test_pattern+16
        ld      bc,16
        ldir
        call    p127_physmem_w3_end
        jp      c,p127_as_copy_test_cleanup
        xor     a
        ld      (p127_as_copy_test_lease),a

        ld      a,6
        ld      (p127_as_copy_test_phase),a
        ; Source [3FF0h,4010h), destination [7FF0h,8010h).
        ld      a,0F0h
        ld      (p127_as_copy_source),a
        ld      (p127_as_copy_destination),a
        ld      a,03Fh
        ld      (p127_as_copy_source+1),a
        ld      a,07Fh
        ld      (p127_as_copy_destination+1),a
        xor     a
        ld      (p127_as_copy_source+2),a
        ld      (p127_as_copy_source+3),a
        ld      (p127_as_copy_destination+2),a
        ld      (p127_as_copy_destination+3),a
        ld      a,32
        ld      (p127_as_copy_length),a
        xor     a
        ld      (p127_as_copy_length+1),a
        ld      (p127_as_copy_length+2),a
        ld      (p127_as_copy_length+3),a
        call    p127_as_copy
        jp      c,p127_as_copy_test_cleanup
        ld      a,(p127_as_copy_completed)
        cp      32
        jp      nz,p127_as_copy_test_cleanup
        ld      a,(p127_as_copy_completed+1)
        or      a
        jp      nz,p127_as_copy_test_cleanup

        ld      a,7
        ld      (p127_as_copy_test_phase),a
        ; Verify the two destination fragments byte-for-byte.
        call    p127_physmem_w3_begin
        jp      c,p127_as_copy_test_cleanup
        ld      a,1
        ld      (p127_as_copy_test_lease),a
        ld      a,(p127_as_copy_test_page_b)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_test_cleanup
        ld      hl,0FFF0h
        ld      de,p127_as_copy_test_pattern
        ld      bc,16
        call    p127_as_copy_test_compare
        jp      c,p127_as_copy_test_cleanup
        ld      a,(p127_as_copy_test_page_c)
        call    p127_physmem_w3_map
        jp      c,p127_as_copy_test_cleanup
        ld      hl,0C000h
        ld      de,p127_as_copy_test_pattern+16
        ld      bc,16
        call    p127_as_copy_test_compare
        jp      c,p127_as_copy_test_cleanup
        call    p127_physmem_w3_end
        jp      c,p127_as_copy_test_cleanup
        xor     a
        ld      (p127_as_copy_test_lease),a

        jp      p127_as_copy_test_cleanup_success

p127_as_copy_test_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_as_copy_test_compare_fail
        inc     de
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,p127_as_copy_test_compare
        or      a
        ret
p127_as_copy_test_compare_fail:
        scf
        ret

p127_as_copy_test_cleanup:
        ld      a,(p127_physmem_api_active)
        or      a
        jr      z,p127_as_copy_test_cleanup_lease_flag
        call    p127_physmem_w3_end
p127_as_copy_test_cleanup_lease_flag:
        xor     a
        ld      (p127_as_copy_test_lease),a
        ld      a,(p127_as_copy_test_bind_count)
        cp      3
        jr      c,p127_as_copy_test_unbind_b
        ld      a,2
        call    p127_as_unbind
p127_as_copy_test_unbind_b:
        ld      a,(p127_as_copy_test_bind_count)
        cp      2
        jr      c,p127_as_copy_test_unbind_a
        ld      a,1
        call    p127_as_unbind
p127_as_copy_test_unbind_a:
        ld      a,(p127_as_copy_test_bind_count)
        or      a
        jr      z,p127_as_copy_test_free_pages
        xor     a
        call    p127_as_unbind
p127_as_copy_test_free_pages:
        ld      a,(p127_as_copy_test_alloc_count)
        cp      3
        jr      c,p127_as_copy_test_free_b
        ld      a,(p127_as_copy_test_page_c)
        call    p127_physmem_free_page
p127_as_copy_test_free_b:
        ld      a,(p127_as_copy_test_alloc_count)
        cp      2
        jr      c,p127_as_copy_test_free_a
        ld      a,(p127_as_copy_test_page_b)
        call    p127_physmem_free_page
p127_as_copy_test_free_a:
        ld      a,(p127_as_copy_test_alloc_count)
        or      a
        jr      z,p127_as_copy_test_fail
        ld      a,(p127_as_copy_test_page_a)
        call    p127_physmem_free_page
p127_as_copy_test_fail:
        scf
        ret
p127_as_copy_test_cleanup_success:
        ; The same cleanup path releases all temporary logical and physical pages.
        ld      a,3
        ld      (p127_as_copy_test_bind_count),a
        ld      a,3
        ld      (p127_as_copy_test_alloc_count),a
        jp      p127_as_copy_test_cleanup_success_body
p127_as_copy_test_cleanup_success_body:
        ld      a,2
        call    p127_as_unbind
        ld      a,1
        call    p127_as_unbind
        xor     a
        call    p127_as_unbind
        ld      a,(p127_as_copy_test_page_c)
        call    p127_physmem_free_page
        jp      c,p127_as_copy_test_fail
        ld      a,(p127_as_copy_test_page_b)
        call    p127_physmem_free_page
        jp      c,p127_as_copy_test_fail
        ld      a,(p127_as_copy_test_page_a)
        call    p127_physmem_free_page
        jp      c,p127_as_copy_test_fail
        or      a
        ret

p127_as_copy_source: ds 4,0
p127_as_copy_destination: ds 4,0
p127_as_copy_length: ds 4,0
p127_as_copy_completed: ds 4,0
p127_as_copy_error: db 0
p127_as_copy_source_end: ds 4,0
p127_as_copy_destination_end: ds 4,0
p127_as_copy_remaining: ds 4,0
p127_as_copy_work_source: ds 4,0
p127_as_copy_work_destination: ds 4,0
p127_as_copy_source_page: db 0
p127_as_copy_destination_page: db 0
p127_as_copy_source_offset: dw 0
p127_as_copy_destination_offset: dw 0
p127_as_copy_chunk: db 0
p127_as_copy_buffer: ds P127_AS_COPY_BUFFER_SIZE,0

p127_as_copy_test_phase: db 0
p127_as_copy_test_page_a: db 0
p127_as_copy_test_page_b: db 0
p127_as_copy_test_page_c: db 0
p127_as_copy_test_alloc_count: db 0
p127_as_copy_test_bind_count: db 0
p127_as_copy_test_lease: db 0
p127_as_copy_test_pattern:
        db 010h,011h,012h,013h,014h,015h,016h,017h
        db 018h,019h,01Ah,01Bh,01Ch,01Dh,01Eh,01Fh
        db 020h,021h,022h,023h,024h,025h,026h,027h
        db 028h,029h,02Ah,02Bh,02Ch,02Dh,02Eh,02Fh

; Project127 ATM scatter-handle allocator.
; Public handle is an opaque byte (1..8); physical extent vectors are private.
; Each extent reserves one physical 16 KiB page using the existing allocator.
; Allocation is transactional: partial acquisitions are rolled back on failure.
ATM_SCATTER_HANDLE_COUNT EQU 8
ATM_SCATTER_MAX_EXTENTS  EQU 58
ATM_SCATTER_EXTENT_BYTES EQU 232

atm_mem_scatter_alloc::
        ; Validate logical size from offset zero, independent of stale callers.
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
        jp      z,atm_mem_scatter_fail
        call    atm_mem_validate_request
        jp      c,atm_mem_scatter_fail
        call    atm_mem_pages_for_length
        or      a
        jp      z,atm_mem_scatter_fail
        cp      ATM_SCATTER_MAX_EXTENTS+1
        jp      nc,atm_mem_scatter_fail
        ld      (atm_mem_scatter_needed),a
        ld      hl,atm_mem_request_length
        ld      de,atm_mem_scatter_length
        ld      bc,4
        ldir

        ld      hl,atm_mem_scatter_handles
        ld      b,ATM_SCATTER_HANDLE_COUNT
        ld      c,1
atm_mem_scatter_find_handle:
        ld      a,(hl)
        or      a
        jp      z,atm_mem_scatter_handle_found
        push    bc
        ld      de,6
        add     hl,de
        pop     bc
        inc     c
        djnz    atm_mem_scatter_find_handle
        jp      atm_mem_scatter_fail
atm_mem_scatter_handle_found:
        ld      (atm_mem_scatter_record),hl
        ld      a,c
        ld      (atm_mem_scatter_handle),a
        dec     c
        ld      hl,atm_mem_scatter_extents
        ld      de,ATM_SCATTER_EXTENT_BYTES
        ld      a,c
        or      a
        jp      z,atm_mem_scatter_vector_ready
atm_mem_scatter_vector_offset:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_vector_offset
atm_mem_scatter_vector_ready:
        ld      (atm_mem_scatter_vector),hl
        xor     a
        ld      (atm_mem_scatter_done),a

atm_mem_scatter_alloc_loop:
        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jp      c,atm_mem_scatter_rollback
        ; Store the allocator's physical byte offset in this extent slot.
        ; LDIR copies HL -> DE; do not reverse these endpoints.
        ld      hl,atm_mem_result_offset
        ld      de,(atm_mem_scatter_vector)
        ld      bc,4
        ldir
        ld      hl,(atm_mem_scatter_vector)
        ld      de,4
        add     hl,de
        ld      (atm_mem_scatter_vector),hl
        ld      a,(atm_mem_scatter_done)
        inc     a
        ld      (atm_mem_scatter_done),a
        ld      b,a
        ld      a,(atm_mem_scatter_needed)
        cp      b
        jp      nz,atm_mem_scatter_alloc_loop

        ; A newly published handle always starts unpinned.
        ld      a,(atm_mem_scatter_handle)
        dec     a
        ld      hl,atm_mem_scatter_pin_counts
        ld      e,a
        ld      d,0
        add     hl,de
        xor     a
        ld      (hl),a
        ld      hl,(atm_mem_scatter_record)
        ld      a,(atm_mem_scatter_handle)
        ld      (hl),a
        inc     hl
        ld      a,(atm_mem_scatter_done)
        ld      (hl),a
        inc     hl
        ; Copy the exact UINT32 logical length INTO the handle record.
        ; LDIR source is HL and destination is DE.
        ex      de,hl
        ld      hl,atm_mem_scatter_length
        ld      bc,4
        ldir
        ld      hl,atm_mem_scatter_length
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir
        ld      a,(atm_mem_scatter_handle)
        or      a
        ret

atm_mem_scatter_rollback:
        ld      a,(atm_mem_scatter_done)
        or      a
        jp      z,atm_mem_scatter_restore_fail
        ld      (atm_mem_scatter_rollback_count),a
        ld      a,(atm_mem_scatter_handle)
        dec     a
        ld      hl,atm_mem_scatter_extents
        ld      de,ATM_SCATTER_EXTENT_BYTES
        or      a
        jp      z,atm_mem_scatter_rollback_vector_ready
atm_mem_scatter_rollback_vector:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_rollback_vector
atm_mem_scatter_rollback_vector_ready:
        ld      (atm_mem_scatter_vector),hl
atm_mem_scatter_rollback_loop:
        ld      hl,(atm_mem_scatter_vector)
        ld      de,atm_mem_request_offset
        ld      bc,4
        ldir
        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_free
        ld      hl,(atm_mem_scatter_vector)
        ld      de,4
        add     hl,de
        ld      (atm_mem_scatter_vector),hl
        ld      a,(atm_mem_scatter_rollback_count)
        dec     a
        ld      (atm_mem_scatter_rollback_count),a
        jp      nz,atm_mem_scatter_rollback_loop
atm_mem_scatter_restore_fail:
        ld      hl,atm_mem_scatter_length
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir
atm_mem_scatter_fail:
        scf
        ret

atm_mem_scatter_free::
        or      a
        jp      z,atm_mem_scatter_fail
        cp      ATM_SCATTER_HANDLE_COUNT+1
        jp      nc,atm_mem_scatter_fail
        ld      (atm_mem_scatter_handle),a
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        or      a
        jp      z,atm_mem_scatter_free_record_ready
atm_mem_scatter_free_record:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_free_record
atm_mem_scatter_free_record_ready:
        ld      a,(hl)
        or      a
        jp      z,atm_mem_scatter_fail
        ; A pinned object cannot be freed: reject before releasing any extent.
        ld      a,(atm_mem_scatter_handle)
        call    atm_mem_scatter_pin_count
        jp      c,atm_mem_scatter_fail
        or      a
        jp      nz,atm_mem_scatter_fail
        ld      a,(atm_mem_scatter_handle)
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        or      a
        jp      z,atm_mem_scatter_free_record_reseek_ready
atm_mem_scatter_free_record_reseek:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_free_record_reseek
atm_mem_scatter_free_record_reseek_ready:
        inc     hl
        ld      a,(hl)
        ld      (atm_mem_scatter_rollback_count),a
        ld      a,(atm_mem_scatter_handle)
        dec     a
        ld      hl,atm_mem_scatter_extents
        ld      de,ATM_SCATTER_EXTENT_BYTES
        or      a
        jp      z,atm_mem_scatter_free_vector_ready
atm_mem_scatter_free_vector:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_free_vector
atm_mem_scatter_free_vector_ready:
        ld      (atm_mem_scatter_vector),hl
atm_mem_scatter_free_loop:
        ld      hl,(atm_mem_scatter_vector)
        ld      de,atm_mem_request_offset
        ld      bc,4
        ldir
        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_free
        jp      c,atm_mem_scatter_fail
        ld      hl,(atm_mem_scatter_vector)
        ld      de,4
        add     hl,de
        ld      (atm_mem_scatter_vector),hl
        ld      a,(atm_mem_scatter_rollback_count)
        dec     a
        ld      (atm_mem_scatter_rollback_count),a
        jp      nz,atm_mem_scatter_free_loop

        ld      a,(atm_mem_scatter_handle)
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        or      a
        jp      z,atm_mem_scatter_clear_ready
atm_mem_scatter_clear_record:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_clear_record
atm_mem_scatter_clear_ready:
        xor     a
        ld      (hl),a
        or      a
        ret

; PIN/UNPIN reference-count a live logical handle (A=handle id).
; PIN fails on invalid handles or counter overflow; UNPIN fails at zero.
; FREE checks this count before touching any physical extent.
atm_mem_scatter_pin::
        call    atm_mem_scatter_pin_count
        ret     c
        cp      #FF
        jp      z,atm_mem_scatter_pin_fail
        ld      hl,(atm_mem_scatter_pin_ptr)
        inc     (hl)
        or      a
        ret

atm_mem_scatter_unpin::
        call    atm_mem_scatter_pin_count
        ret     c
        or      a
        jp      z,atm_mem_scatter_pin_fail
        ld      hl,(atm_mem_scatter_pin_ptr)
        dec     (hl)
        or      a
        ret

; A=handle id. Returns A=pin count, HL=counter address; carry on invalid id.
atm_mem_scatter_pin_count:
        or      a
        jp      z,atm_mem_scatter_pin_fail
        cp      ATM_SCATTER_HANDLE_COUNT+1
        jp      nc,atm_mem_scatter_pin_fail
        ld      (atm_mem_scatter_pin_id),a
        dec     a
        ld      hl,atm_mem_scatter_pin_counts
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (atm_mem_scatter_pin_ptr),hl
        ld      a,(atm_mem_scatter_pin_id)
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        or      a
        jp      z,atm_mem_scatter_pin_record_ready
atm_mem_scatter_pin_record_step:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_pin_record_step
atm_mem_scatter_pin_record_ready:
        ld      a,(hl)
        ld      b,a
        ld      a,(atm_mem_scatter_pin_id)
        cp      b
        jp      nz,atm_mem_scatter_pin_fail
        ld      hl,(atm_mem_scatter_pin_ptr)
        ld      a,(hl)
        or      a
        ret
atm_mem_scatter_pin_fail:
        scf
        ret

; Runtime test: nested pins prevent FREE until every reference is released.
atm_mem_scatter_pin_selftest::
        ld      a,1
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      hl,1
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_scatter_alloc
        jp      c,atm_mem_scatter_pin_test_fail
        ld      (atm_mem_scatter_pin_test_handle),a

        ld      a,2
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_pin
        jp      c,atm_mem_scatter_pin_test_fail
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_pin
        jp      c,atm_mem_scatter_pin_test_fail

        ; First FREE must be rejected and leave the complete handle intact.
        ld      a,3
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_free
        jp      nc,atm_mem_scatter_pin_test_fail
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_pin_count
        jp      c,atm_mem_scatter_pin_test_fail
        cp      2
        jp      nz,atm_mem_scatter_pin_test_fail

        ld      a,4
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_unpin
        jp      c,atm_mem_scatter_pin_test_fail
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_free
        jp      nc,atm_mem_scatter_pin_test_fail

        ld      a,5
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_unpin
        jp      c,atm_mem_scatter_pin_test_fail
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_unpin
        jp      nc,atm_mem_scatter_pin_test_fail

        ld      a,6
        ld      (atm_mem_scatter_pin_test_stage),a
        ld      a,(atm_mem_scatter_pin_test_handle)
        call    atm_mem_scatter_free
        jp      c,atm_mem_scatter_pin_test_fail
        ld      a,0
        call    atm_mem_scatter_pin
        jp      nc,atm_mem_scatter_pin_test_fail
        xor     a
        ret
atm_mem_scatter_pin_test_fail:
        ld      a,(atm_mem_scatter_pin_test_stage)
        scf
        ret

; Smoke test verifies an object spanning two private extent records.
atm_mem_scatter_selftest::
        ld      a,1
        ld      (atm_mem_scatter_test_stage),a
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_scatter_alloc
        jp      c,atm_mem_scatter_test_fail
        ld      (atm_mem_scatter_test_handle),a

        ld      a,2
        ld      (atm_mem_scatter_test_stage),a
        ld      a,(atm_mem_scatter_done)
        cp      2
        jp      nz,atm_mem_scatter_test_fail
        ld      a,7
        ld      (atm_mem_scatter_test_stage),a
        ; The public logical length must be stored in record bytes 2..5.
        ld      a,(atm_mem_scatter_test_handle)
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        or      a
        jp      z,atm_mem_scatter_test_length_record_ready
atm_mem_scatter_test_length_record_step:
        add     hl,de
        dec     a
        jp      nz,atm_mem_scatter_test_length_record_step
atm_mem_scatter_test_length_record_ready:
        inc     hl
        inc     hl
        ld      de,atm_mem_scatter_length
        ld      b,4
atm_mem_scatter_test_length_record_compare:
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_scatter_test_fail
        inc     de
        inc     hl
        djnz    atm_mem_scatter_test_length_record_compare

        ld      hl,(atm_mem_scatter_vector)
        ld      de,8
        or      a
        sbc     hl,de
        ld      (atm_mem_scatter_test_vector),hl

        ld      a,3
        ld      (atm_mem_scatter_test_stage),a
        ld      hl,(atm_mem_scatter_test_vector)
        ld      a,(hl)
        inc     hl
        or      (hl)
        inc     hl
        or      (hl)
        inc     hl
        or      (hl)
        jp      z,atm_mem_scatter_test_fail
        ld      hl,(atm_mem_scatter_test_vector)
        ld      de,atm_mem_scatter_test_first
        ld      bc,4
        ldir

        ld      a,4
        ld      (atm_mem_scatter_test_stage),a
        ld      hl,(atm_mem_scatter_test_vector)
        ld      de,4
        add     hl,de
        ld      a,(hl)
        ld      b,a
        inc     hl
        ld      a,(hl)
        or      b
        ld      b,a
        inc     hl
        ld      a,(hl)
        or      b
        ld      b,a
        inc     hl
        ld      a,(hl)
        or      b
        jp      z,atm_mem_scatter_test_fail

        ld      a,5
        ld      (atm_mem_scatter_test_stage),a
        ld      hl,atm_mem_scatter_test_first
        ld      de,(atm_mem_scatter_test_vector)
        inc     de
        inc     de
        inc     de
        inc     de
        ld      b,4
atm_mem_scatter_test_compare_offsets:
        ld      a,(de)
        cp      (hl)
        jp      nz,atm_mem_scatter_test_offsets_distinct
        inc     hl
        inc     de
        djnz    atm_mem_scatter_test_compare_offsets
        jp      atm_mem_scatter_test_fail
atm_mem_scatter_test_offsets_distinct:
        ld      a,6
        ld      (atm_mem_scatter_test_stage),a
        ld      a,(atm_mem_scatter_test_handle)
        call    atm_mem_scatter_free
        jp      c,atm_mem_scatter_test_fail
        xor     a
        ret
atm_mem_scatter_test_fail:
        ld      a,(atm_mem_scatter_test_stage)
        scf
        ret

atm_mem_scatter_needed:          db 0
atm_mem_scatter_done:            db 0
atm_mem_scatter_handle:          db 0
atm_mem_scatter_rollback_count:  db 0
atm_mem_scatter_test_handle:     db 0
atm_mem_scatter_test_stage:      db 0
atm_mem_scatter_test_vector:     dw 0
atm_mem_scatter_test_first:      defs 4,0
atm_mem_scatter_record:          dw 0
atm_mem_scatter_vector:          dw 0
atm_mem_scatter_length:          defs 4,0
atm_mem_scatter_pin_id:           db 0
atm_mem_scatter_pin_ptr:          dw 0
atm_mem_scatter_pin_test_handle:  db 0
atm_mem_scatter_pin_test_stage:   db 0
atm_mem_scatter_pin_counts:       defs ATM_SCATTER_HANDLE_COUNT,0
atm_mem_scatter_handles:         defs ATM_SCATTER_HANDLE_COUNT*6,0
atm_mem_scatter_extents:         defs ATM_SCATTER_HANDLE_COUNT*ATM_SCATTER_MAX_EXTENTS*4,0

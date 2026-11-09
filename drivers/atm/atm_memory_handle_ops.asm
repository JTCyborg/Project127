; Project127 ATM logical scatter-handle operations.
; All offsets and lengths are UINT32 byte quantities relative to an opaque
; handle. Physical extent vectors are resolved privately for each byte.
;
; Descriptors:
;   atm_mem_handle_source       db handle id
;   atm_mem_handle_destination  db handle id
;   atm_mem_handle_source_offset      defs 4
;   atm_mem_handle_destination_offset defs 4
;   atm_mem_handle_op_length          defs 4
;   atm_mem_handle_fill_value   db value
;
; READ and WRITE use the same validated handle-to-handle copy primitive:
; READ convention: source=object, destination=transfer handle.
; WRITE convention: source=transfer handle, destination=object.
; FILL and COPY are handle-relative. Carry clear means complete operation.
;
; Bytewise implementation intentionally favors correctness first. It maps
; only window 3 and restores page 1 on successful completion.

atm_mem_handle_read::
        jp      atm_mem_handle_copy

atm_mem_handle_write::
        jp      atm_mem_handle_copy

atm_mem_handle_copy::
        ld      a,(atm_mem_handle_source)
        ld      hl,atm_mem_handle_source_offset
        call    atm_mem_handle_validate_range
        ret     c
        ld      a,(atm_mem_handle_destination)
        ld      hl,atm_mem_handle_destination_offset
        call    atm_mem_handle_validate_range
        ret     c
        ld      hl,atm_mem_handle_source_offset
        ld      de,atm_mem_source_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_handle_destination_offset
        ld      de,atm_mem_destination_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_handle_op_length
        ld      de,atm_mem_remaining
        ld      bc,4
        ldir
        call    atm_mem_remaining_is_zero
        ret     z
        ; Backward traversal for same-handle overlapping ranges where dst>src.
        ld      a,(atm_mem_handle_source)
        ld      b,a
        ld      a,(atm_mem_handle_destination)
        cp      b
        jp      nz,atm_mem_handle_copy_forward
        call    atm_mem_destination_after_source
        jp      nc,atm_mem_handle_copy_forward
        ld      hl,(atm_mem_source_cursor)
        ld      de,(atm_mem_remaining)
        add     hl,de
        ld      (atm_mem_source_cursor),hl
        ld      hl,(atm_mem_source_cursor+2)
        ld      de,(atm_mem_remaining+2)
        adc     hl,de
        ld      (atm_mem_source_cursor+2),hl
        call    atm_mem_source_dec
        ld      hl,(atm_mem_destination_cursor)
        ld      de,(atm_mem_remaining)
        add     hl,de
        ld      (atm_mem_destination_cursor),hl
        ld      hl,(atm_mem_destination_cursor+2)
        ld      de,(atm_mem_remaining+2)
        adc     hl,de
        ld      (atm_mem_destination_cursor+2),hl
        call    atm_mem_destination_dec
atm_mem_handle_copy_backward_loop:
        call    atm_mem_handle_copy_one
        ret     c
        call    atm_mem_source_dec
        call    atm_mem_destination_dec
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jp      nz,atm_mem_handle_copy_backward_loop
        jp      atm_mem_restore_window3
atm_mem_handle_copy_forward:
atm_mem_handle_copy_forward_loop:
        call    atm_mem_handle_copy_one
        ret     c
        call    atm_mem_source_inc
        call    atm_mem_destination_inc
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jp      nz,atm_mem_handle_copy_forward_loop
        jp      atm_mem_restore_window3

atm_mem_handle_fill::
        ld      a,(atm_mem_handle_destination)
        ld      hl,atm_mem_handle_destination_offset
        call    atm_mem_handle_validate_range
        ret     c
        ld      hl,atm_mem_handle_destination_offset
        ld      de,atm_mem_destination_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_handle_op_length
        ld      de,atm_mem_remaining
        ld      bc,4
        ldir
        call    atm_mem_remaining_is_zero
        ret     z
atm_mem_handle_fill_loop:
        ld      a,(atm_mem_handle_destination)
        ld      hl,atm_mem_destination_cursor
        call    atm_mem_handle_resolve
        ret     c
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(atm_mem_handle_fill_value)
        ld      (hl),a
        call    atm_mem_destination_inc
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jp      nz,atm_mem_handle_fill_loop
        jp      atm_mem_restore_window3

; Validate [offset, offset+op_length) against the exact logical handle length.
; A=handle id, HL=pointer to UINT32 logical offset.
atm_mem_handle_validate_range:
        ld      (atm_mem_handle_temp_id),a
        ld      (atm_mem_handle_temp_offset_ptr),hl
        call    atm_mem_handle_find_record
        ret     c
        ld      (atm_mem_handle_temp_record),hl
        ; Compute end = offset + operation length with full carry checking.
        ld      hl,(atm_mem_handle_temp_offset_ptr)
        ld      de,atm_mem_handle_temp_end
        ld      bc,4
        ldir
        ld      hl,(atm_mem_handle_temp_end)
        ld      de,(atm_mem_handle_op_length)
        add     hl,de
        ld      (atm_mem_handle_temp_end),hl
        ld      hl,(atm_mem_handle_temp_end+2)
        ld      de,(atm_mem_handle_op_length+2)
        adc     hl,de
        ld      (atm_mem_handle_temp_end+2),hl
        ret     c
        ld      hl,(atm_mem_handle_temp_record)
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ; Compare end against recorded UINT32 logical length, high byte first.
        ld      de,atm_mem_handle_temp_end+3
        ld      b,4
atm_mem_handle_range_compare:
        ld      a,(de)
        cp      (hl)
        jp      c,atm_mem_handle_range_ok
        jp      nz,atm_mem_handle_range_fail
        dec     de
        dec     hl
        djnz    atm_mem_handle_range_compare
atm_mem_handle_range_ok:
        or      a
        ret
atm_mem_handle_range_fail:
        scf
        ret

; A=handle id. Returns HL=6-byte handle record, carry set if invalid/free.
atm_mem_handle_find_record:
        or      a
        jp      z,atm_mem_handle_lookup_fail
        cp      ATM_SCATTER_HANDLE_COUNT+1
        jp      nc,atm_mem_handle_lookup_fail
        dec     a
        ld      hl,atm_mem_scatter_handles
        ld      de,6
        jp      z,atm_mem_handle_lookup_check
atm_mem_handle_lookup_step:
        add     hl,de
        dec     a
        jp      nz,atm_mem_handle_lookup_step
atm_mem_handle_lookup_check:
        ld      a,(hl)
        ld      b,a
        ld      a,(atm_mem_handle_temp_id)
        cp      b
        jp      nz,atm_mem_handle_lookup_fail
        or      a
        ret
atm_mem_handle_lookup_fail:
        scf
        ret

; Resolve handle-relative cursor into physical UINT32 atm_mem_work_offset.
; A=handle id, HL=pointer to UINT32 logical cursor.
atm_mem_handle_resolve:
        ld      (atm_mem_handle_temp_id),a
        ld      (atm_mem_handle_cursor_ptr),hl
        call    atm_mem_handle_find_record
        ret     c
        ld      (atm_mem_handle_temp_record),hl
        ; Vector base = extents + (handle-1)*232.
        ld      a,(atm_mem_handle_temp_id)
        dec     a
        ld      hl,atm_mem_scatter_extents
        ld      de,ATM_SCATTER_EXTENT_BYTES
        or      a
        jp      z,atm_mem_handle_vector_base_ready
atm_mem_handle_vector_base_loop:
        add     hl,de
        dec     a
        jp      nz,atm_mem_handle_vector_base_loop
atm_mem_handle_vector_base_ready:
        ld      (atm_mem_handle_temp_vector),hl
        ; Page index = (cursor >> 14), with cursor guaranteed in range.
        ld      hl,(atm_mem_handle_cursor_ptr)
        inc     hl
        inc     hl
        ld      a,(hl)
        add     a,a
        add     a,a
        ld      b,a
        dec     hl
        ld      a,(hl)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        or      b
        ld      b,a
        ld      hl,(atm_mem_handle_temp_vector)
        ld      de,4
        ld      a,b
        or      a
        jp      z,atm_mem_handle_extent_ready
atm_mem_handle_extent_step:
        add     hl,de
        djnz    atm_mem_handle_extent_step
atm_mem_handle_extent_ready:
        ld      de,atm_mem_work_offset
        ld      bc,4
        ldir
        ; Add cursor's intra-page offset (low 14 bits) to physical base.
        ld      hl,(atm_mem_handle_cursor_ptr)
        ld      a,(hl)
        ld      e,a
        inc     hl
        ld      a,(hl)
        and     #3F
        ld      d,a
        ld      hl,(atm_mem_work_offset)
        add     hl,de
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_work_offset+2)
        ld      de,0
        adc     hl,de
        ld      (atm_mem_work_offset+2),hl
        or      a
        ret

atm_mem_handle_copy_one:
        ld      hl,atm_mem_source_cursor
        ld      (atm_mem_handle_cursor_ptr),hl
        ld      a,(atm_mem_handle_source)
        call    atm_mem_handle_resolve
        ret     c
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(hl)
        ld      (atm_mem_copy_byte),a
        ld      hl,atm_mem_destination_cursor
        ld      (atm_mem_handle_cursor_ptr),hl
        ld      a,(atm_mem_handle_destination)
        call    atm_mem_handle_resolve
        ret     c
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(atm_mem_copy_byte)
        ld      (hl),a
        or      a
        ret

atm_mem_handle_source:             db 0
atm_mem_handle_destination:        db 0
atm_mem_handle_source_offset:      defs 4,0
atm_mem_handle_destination_offset: defs 4,0
atm_mem_handle_op_length:          defs 4,0
atm_mem_handle_fill_value:         db 0
atm_mem_handle_temp_id:            db 0
atm_mem_handle_temp_record:        dw 0
atm_mem_handle_temp_offset_ptr:    dw 0
atm_mem_handle_temp_vector:        dw 0
atm_mem_handle_cursor_ptr:         dw 0
atm_mem_handle_temp_end:            defs 4,0


; =========================================================================
; Runtime acceptance test for logical scatter-handle data operations.
; Allocates two 0x4001-byte objects, fills/copies across an extent boundary,
; verifies both sides of the boundary, then checks overlapping COPY.
; =========================================================================
atm_mem_handle_ops_selftest::
        ld      a,1
        ld      (atm_mem_handle_test_stage),a
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_scatter_alloc
        jp      c,atm_mem_handle_test_fail
        ld      (atm_mem_handle_test_source),a

        ld      a,2
        ld      (atm_mem_handle_test_stage),a
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_scatter_alloc
        jp      c,atm_mem_handle_test_fail
        ld      (atm_mem_handle_test_destination),a

        ; FILL source with a known byte over the full logical 0x4001 range.
        ld      a,3
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_source)
        ld      (atm_mem_handle_destination),a
        ld      hl,0
        ld      (atm_mem_handle_destination_offset),hl
        ld      (atm_mem_handle_destination_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_handle_op_length),hl
        ld      hl,0
        ld      (atm_mem_handle_op_length+2),hl
        ld      a,#A5
        ld      (atm_mem_handle_fill_value),a
        call    atm_mem_handle_fill
        jp      c,atm_mem_handle_test_fail

        ; READ object -> transfer object. Both descriptors are opaque handles.
        ld      a,4
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_source)
        ld      (atm_mem_handle_source),a
        ld      a,(atm_mem_handle_test_destination)
        ld      (atm_mem_handle_destination),a
        ld      hl,0
        ld      (atm_mem_handle_source_offset),hl
        ld      (atm_mem_handle_source_offset+2),hl
        ld      (atm_mem_handle_destination_offset),hl
        ld      (atm_mem_handle_destination_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_handle_op_length),hl
        ld      hl,0
        ld      (atm_mem_handle_op_length+2),hl
        call    atm_mem_handle_read
        jp      c,atm_mem_handle_test_fail

        ; Verify first byte, last byte of extent 0, and first byte of extent 1.
        ld      a,5
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        ld      hl,atm_mem_handle_test_cursor
        ld      de,0
        call    atm_mem_handle_test_set_cursor
        call    atm_mem_handle_test_verify_a5
        jp      c,atm_mem_handle_test_fail

        ld      a,(atm_mem_handle_test_destination)
        ld      hl,atm_mem_handle_test_cursor
        ld      de,#3FFF
        call    atm_mem_handle_test_set_cursor
        call    atm_mem_handle_test_verify_a5
        jp      c,atm_mem_handle_test_fail

        ld      a,(atm_mem_handle_test_destination)
        ld      hl,atm_mem_handle_test_cursor
        ld      de,#4000
        call    atm_mem_handle_test_set_cursor
        call    atm_mem_handle_test_verify_a5
        jp      c,atm_mem_handle_test_fail

        ; Seed 11 22 33 44 55 at logical offset zero.
        ld      a,6
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        ld      hl,atm_mem_handle_test_cursor
        call    atm_mem_handle_test_set_zero_cursor
        call    atm_mem_handle_resolve
        jp      c,atm_mem_handle_test_fail
        call    atm_mem_map_work_offset
        jp      c,atm_mem_handle_test_fail
        ld      (hl),#11
        inc     hl
        ld      (hl),#22
        inc     hl
        ld      (hl),#33
        inc     hl
        ld      (hl),#44
        inc     hl
        ld      (hl),#55

        ; Same-handle overlap: [0..3] -> [1..4], memmove semantics required.
        ld      a,7
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        ld      (atm_mem_handle_source),a
        ld      (atm_mem_handle_destination),a
        ld      hl,0
        ld      (atm_mem_handle_source_offset),hl
        ld      (atm_mem_handle_source_offset+2),hl
        ld      hl,1
        ld      (atm_mem_handle_destination_offset),hl
        ld      hl,0
        ld      (atm_mem_handle_destination_offset+2),hl
        ld      hl,4
        ld      (atm_mem_handle_op_length),hl
        ld      hl,0
        ld      (atm_mem_handle_op_length+2),hl
        call    atm_mem_handle_copy
        jp      c,atm_mem_handle_test_fail

        ; Check resulting bytes: 11 11 22 33 44.
        ld      a,8
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        ld      hl,atm_mem_handle_test_cursor
        call    atm_mem_handle_test_set_zero_cursor
        call    atm_mem_handle_resolve
        jp      c,atm_mem_handle_test_fail
        call    atm_mem_map_work_offset
        jp      c,atm_mem_handle_test_fail
        ld      a,(hl)
        cp      #11
        jp      nz,atm_mem_handle_test_fail
        inc     hl
        ld      a,(hl)
        cp      #11
        jp      nz,atm_mem_handle_test_fail
        inc     hl
        ld      a,(hl)
        cp      #22
        jp      nz,atm_mem_handle_test_fail
        inc     hl
        ld      a,(hl)
        cp      #33
        jp      nz,atm_mem_handle_test_fail
        inc     hl
        ld      a,(hl)
        cp      #44
        jp      nz,atm_mem_handle_test_fail

        ; Reject a one-byte range beginning exactly at logical end.
        ld      a,9
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        ld      (atm_mem_handle_destination),a
        ld      hl,#4001
        ld      (atm_mem_handle_destination_offset),hl
        ld      hl,0
        ld      (atm_mem_handle_destination_offset+2),hl
        ld      hl,1
        ld      (atm_mem_handle_op_length),hl
        ld      hl,0
        ld      (atm_mem_handle_op_length+2),hl
        call    atm_mem_handle_fill
        jp      nc,atm_mem_handle_test_fail

        ; Release both handles after all checks pass.
        ld      a,10
        ld      (atm_mem_handle_test_stage),a
        ld      a,(atm_mem_handle_test_destination)
        call    atm_mem_scatter_free
        jp      c,atm_mem_handle_test_fail
        ld      a,(atm_mem_handle_test_source)
        call    atm_mem_scatter_free
        jp      c,atm_mem_handle_test_fail
        xor     a
        ret

; A=handle, HL=cursor pointer, DE=16-bit test offset.
atm_mem_handle_test_set_cursor:
        push    af
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        pop     af
        ret

; A=handle, HL=cursor pointer; set logical offset zero.
atm_mem_handle_test_set_zero_cursor:
        push    af
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      hl,atm_mem_handle_test_cursor
        pop     af
        ret

; A=handle, HL=cursor pointer. Verify resolved byte equals #A5.
atm_mem_handle_test_verify_a5:
        ld      (atm_mem_handle_test_expected_handle),a
        call    atm_mem_handle_resolve
        ret     c
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(hl)
        cp      #A5
        ret     z
        scf
        ret

atm_mem_handle_test_fail:
        ld      a,(atm_mem_handle_test_stage)
        scf
        ret

atm_mem_handle_test_source:       db 0
atm_mem_handle_test_destination:  db 0
atm_mem_handle_test_stage:         db 0
atm_mem_handle_test_expected_handle: db 0
atm_mem_handle_test_cursor:        defs 4,0

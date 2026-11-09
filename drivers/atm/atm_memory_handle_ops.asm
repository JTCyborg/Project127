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
        call    atm_mem_handle_find_record
        ret     c
        ld      (atm_mem_handle_temp_record),hl
        ; Compute end = offset + operation length with full carry checking.
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
        ; Compare end against recorded UINT32 logical length, high word first.
        ld      de,atm_mem_handle_temp_end+2
        ld      a,(de)
        cp      (hl)
        jp      c,atm_mem_handle_range_ok
        jp      nz,atm_mem_handle_range_fail
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jp      c,atm_mem_handle_range_ok
        jp      nz,atm_mem_handle_range_fail
        dec     de
        dec     de
        dec     hl
        dec     hl
        ld      a,(de)
        cp      (hl)
        jp      c,atm_mem_handle_range_ok
        jp      nz,atm_mem_handle_range_fail
        inc     de
        inc     hl
        ld      a,(de)
        cp      (hl)
        jp      c,atm_mem_handle_range_ok
        jp      nz,atm_mem_handle_range_fail
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
        ld      a,(hl) ; discard: keep vector pointer in temp
        ld      a,(atm_mem_handle_temp_id)
        ; Re-read cursor pointer saved by caller.
        ld      hl,(atm_mem_handle_cursor_ptr)
        ld      a,(hl+2)
        add     a,a
        add     a,a
        ld      b,a
        inc     hl
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
atm_mem_handle_temp_vector:        dw 0
atm_mem_handle_cursor_ptr:         dw 0
atm_mem_handle_temp_end:            defs 4,0

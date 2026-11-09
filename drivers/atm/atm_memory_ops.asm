; =========================================================================
; Project127 ATM byte-range operations.
;
; Safe single-aperture engine:
;   - only CPU window 3 ($C000-$FFFF) is remapped;
;   - host code remains in window 1, stack in window 2;
;   - the byte scratch and descriptors live with the host image;
;   - no caller-visible 16 KiB limit.
;
; Public descriptors (UINT32 little-endian):
;   atm_mem_source_offset, atm_mem_destination_offset, atm_mem_op_length
; READ/WRITE use the same validated physical copy primitive.
; COPY is memmove-safe (backward when destination > source).
; FILL uses atm_mem_fill_value.
; Carry clear = complete operation; carry set = rejected request.
; =========================================================================

atm_mem_read::
        jp      atm_mem_copy

atm_mem_write::
        jp      atm_mem_copy

; COPY: source -> destination, with memmove overlap semantics.
atm_mem_copy::
        call    atm_mem_validate_pair
        ret     c
        ld      hl,atm_mem_source_offset
        ld      de,atm_mem_source_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_destination_offset
        ld      de,atm_mem_destination_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_op_length
        ld      de,atm_mem_remaining
        ld      bc,4
        ldir
        call    atm_mem_remaining_is_zero
        ret     z
        call    atm_mem_destination_after_source
        jp      nc,atm_mem_copy_forward

        ; Backward copy: move both cursors to their last byte.
        ld      hl,(atm_mem_source_cursor)
        ld      de,(atm_mem_op_length)
        add     hl,de
        ld      (atm_mem_source_cursor),hl
        ld      hl,(atm_mem_source_cursor+2)
        ld      de,(atm_mem_op_length+2)
        adc     hl,de
        ld      (atm_mem_source_cursor+2),hl
        call    atm_mem_source_dec
        ld      hl,(atm_mem_destination_cursor)
        ld      de,(atm_mem_op_length)
        add     hl,de
        ld      (atm_mem_destination_cursor),hl
        ld      hl,(atm_mem_destination_cursor+2)
        ld      de,(atm_mem_op_length+2)
        adc     hl,de
        ld      (atm_mem_destination_cursor+2),hl
        call    atm_mem_destination_dec

atm_mem_copy_backward_loop:
        call    atm_mem_copy_one
        ret     c
        call    atm_mem_source_dec
        call    atm_mem_destination_dec
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jr      nz,atm_mem_copy_backward_loop
        or      a
        ret

atm_mem_copy_forward:
atm_mem_copy_forward_loop:
        call    atm_mem_copy_one
        ret     c
        call    atm_mem_source_inc
        call    atm_mem_destination_inc
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jr      nz,atm_mem_copy_forward_loop
        or      a
        ret

; FILL: destination range is validated in full before the first write.
atm_mem_fill::
        ld      hl,atm_mem_destination_offset
        ld      de,atm_mem_request_offset
        ld      bc,4
        ldir
        ld      hl,atm_mem_op_length
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir
        call    atm_mem_validate_request
        ret     c
        ld      hl,atm_mem_destination_offset
        ld      de,atm_mem_destination_cursor
        ld      bc,4
        ldir
        ld      hl,atm_mem_op_length
        ld      de,atm_mem_remaining
        ld      bc,4
        ldir
        call    atm_mem_remaining_is_zero
        ret     z
atm_mem_fill_loop:
        ld      hl,atm_mem_destination_cursor
        ld      de,atm_mem_work_offset
        ld      bc,4
        ldir
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(atm_mem_fill_value)
        ld      (hl),a
        call    atm_mem_destination_inc
        call    atm_mem_length_dec
        call    atm_mem_remaining_is_zero
        jr      nz,atm_mem_fill_loop
        or      a
        ret

; Validate both complete ranges before modifying either range.
atm_mem_validate_pair:
        ld      hl,atm_mem_source_offset
        ld      de,atm_mem_request_offset
        ld      bc,4
        ldir
        ld      hl,atm_mem_op_length
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir
        call    atm_mem_validate_request
        ret     c
        ld      hl,atm_mem_destination_offset
        ld      de,atm_mem_request_offset
        ld      bc,4
        ldir
        ld      hl,atm_mem_op_length
        ld      de,atm_mem_request_length
        ld      bc,4
        ldir
        jp      atm_mem_validate_request

; Carry clear if destination <= source; carry set if destination > source.
atm_mem_destination_after_source:
        ld      hl,(atm_mem_destination_cursor+2)
        ld      de,(atm_mem_source_offset+2)
        or      a
        sbc     hl,de
        jr      c,atm_mem_destination_not_after
        jr      nz,atm_mem_destination_is_after
        ld      hl,(atm_mem_destination_cursor)
        ld      de,(atm_mem_source_offset)
        or      a
        sbc     hl,de
        jr      c,atm_mem_destination_not_after
        jr      z,atm_mem_destination_not_after
atm_mem_destination_is_after:
        scf
        ret
atm_mem_destination_not_after:
        or      a
        ret

; Z iff all four bytes of operation length are zero.
atm_mem_remaining_is_zero:
        ld      a,(atm_mem_remaining)
        ld      b,a
        ld      a,(atm_mem_remaining+1)
        or      b
        ld      b,a
        ld      a,(atm_mem_remaining+2)
        or      b
        ld      b,a
        ld      a,(atm_mem_remaining+3)
        or      b
        ret

; Copy one byte through the only aperture that this runtime owns.
atm_mem_copy_one:
        ld      hl,atm_mem_source_cursor
        ld      de,atm_mem_work_offset
        ld      bc,4
        ldir
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(hl)
        ld      (atm_mem_copy_byte),a
        ld      hl,atm_mem_destination_cursor
        ld      de,atm_mem_work_offset
        ld      bc,4
        ldir
        call    atm_mem_map_work_offset
        ret     c
        ld      a,(atm_mem_copy_byte)
        ld      (hl),a
        or      a
        ret

; Map atm_mem_work_offset into window 3 and return its CPU address in HL.
; Physical page = (offset >> 14); in-range validation guarantees 0..63.
atm_mem_map_work_offset:
        ld      a,(atm_mem_work_offset+2)
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(atm_mem_work_offset+1)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        or      b
        call    atm_mem_map_page
        ret     c
        ld      a,(atm_mem_work_offset+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(atm_mem_work_offset)
        ld      l,a
        or      a
        ret

atm_mem_source_inc:
        ld      hl,(atm_mem_source_cursor)
        inc     hl
        ld      (atm_mem_source_cursor),hl
        ret     nz
        ld      hl,(atm_mem_source_cursor+2)
        inc     hl
        ld      (atm_mem_source_cursor+2),hl
        ret

atm_mem_destination_inc:
        ld      hl,(atm_mem_destination_cursor)
        inc     hl
        ld      (atm_mem_destination_cursor),hl
        ret     nz
        ld      hl,(atm_mem_destination_cursor+2)
        inc     hl
        ld      (atm_mem_destination_cursor+2),hl
        ret

atm_mem_source_dec:
        ld      hl,(atm_mem_source_cursor)
        ld      de,1
        or      a
        sbc     hl,de
        ld      (atm_mem_source_cursor),hl
        ret     nc
        ld      hl,(atm_mem_source_cursor+2)
        dec     hl
        ld      (atm_mem_source_cursor+2),hl
        ret

atm_mem_destination_dec:
        ld      hl,(atm_mem_destination_cursor)
        ld      de,1
        or      a
        sbc     hl,de
        ld      (atm_mem_destination_cursor),hl
        ret     nc
        ld      hl,(atm_mem_destination_cursor+2)
        dec     hl
        ld      (atm_mem_destination_cursor+2),hl
        ret

atm_mem_length_dec:
        ld      hl,(atm_mem_remaining)
        ld      de,1
        or      a
        sbc     hl,de
        ld      (atm_mem_remaining),hl
        ret     nc
        ld      hl,(atm_mem_remaining+2)
        dec     hl
        ld      (atm_mem_remaining+2),hl
        ret

; Caller descriptors and private cursors/scratch.
atm_mem_source_offset:       defs 4,0
atm_mem_destination_offset:  defs 4,0
atm_mem_op_length:           defs 4,0
atm_mem_source_cursor:       defs 4,0
atm_mem_destination_cursor:  defs 4,0
atm_mem_remaining:           defs 4,0
atm_mem_work_offset:         defs 4,0
atm_mem_fill_value:          db 0
atm_mem_copy_byte:           db 0

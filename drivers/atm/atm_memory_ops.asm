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
        call    atm_mem_restore_window3
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
        call    atm_mem_restore_window3
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
        call    atm_mem_restore_window3
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
        ld      de,(atm_mem_source_cursor+2)
        or      a
        sbc     hl,de
        jr      c,atm_mem_destination_not_after
        jr      nz,atm_mem_destination_is_after
        ld      hl,(atm_mem_destination_cursor)
        ld      de,(atm_mem_source_cursor)
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

; Restore the Project112 runtime mapping: CPU window 3 -> physical page 1.
atm_mem_restore_window3:
        ld      a,1
        jp      atm_mem_map_page

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
        ld      a,h
        or      l
        ret     nz
        ld      hl,(atm_mem_source_cursor+2)
        inc     hl
        ld      (atm_mem_source_cursor+2),hl
        ret

atm_mem_destination_inc:
        ld      hl,(atm_mem_destination_cursor)
        inc     hl
        ld      (atm_mem_destination_cursor),hl
        ld      a,h
        or      l
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


; =========================================================================
; ATM byte-operation runtime self-test.
; Exercises 0x4001-byte FILL/COPY across a 16 KiB page boundary, verifies
; both ends of the second page, then tests overlapping backward COPY.
; =========================================================================
atm_mem_ops_selftest::
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jp      c,atm_mem_ops_test_fail_01
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_test_source),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_test_source+2),hl

        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_alloc
        jp      c,atm_mem_ops_test_fail_02
        ld      hl,(atm_mem_result_offset)
        ld      (atm_mem_test_destination),hl
        ld      hl,(atm_mem_result_offset+2)
        ld      (atm_mem_test_destination+2),hl

        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_destination_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_destination_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_op_length),hl
        ld      hl,0
        ld      (atm_mem_op_length+2),hl
        ld      a,#A5
        ld      (atm_mem_fill_value),a
        call    atm_mem_fill
        jp      c,atm_mem_ops_test_fail_03

        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_source_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_source_offset+2),hl
        ld      hl,(atm_mem_test_destination)
        ld      (atm_mem_destination_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      (atm_mem_destination_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_op_length),hl
        ld      hl,0
        ld      (atm_mem_op_length+2),hl
        call    atm_mem_copy
        jp      c,atm_mem_ops_test_fail_04

        ; Verify first byte at destination.
        ld      hl,(atm_mem_test_destination)
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      (atm_mem_work_offset+2),hl
        call    atm_mem_map_work_offset
        jp      c,atm_mem_ops_test_fail_05
        ld      a,(hl)
        cp      #A5
        jp      nz,atm_mem_ops_test_fail_05

        ; Verify byte at destination + #4000 (first byte of next page).
        ld      hl,(atm_mem_test_destination)
        ld      de,#4000
        add     hl,de
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      de,0
        adc     hl,de
        ld      (atm_mem_work_offset+2),hl
        call    atm_mem_map_work_offset
        jp      c,atm_mem_ops_test_fail_06
        ld      a,(hl)
        cp      #A5
        jp      nz,atm_mem_ops_test_fail_06

        ; Seed five distinct bytes at source start.
        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_work_offset+2),hl
        call    atm_mem_map_work_offset
        jp      c,atm_mem_ops_test_fail_07
        ld      (hl),#11
        inc     hl
        ld      (hl),#22
        inc     hl
        ld      (hl),#33
        inc     hl
        ld      (hl),#44
        inc     hl
        ld      (hl),#55

        ; Overlap: source -> source+1, length 4. Must copy backward.
        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_source_offset),hl
        ld      de,1
        add     hl,de
        ld      (atm_mem_destination_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_source_offset+2),hl
        ld      de,0
        adc     hl,de
        ld      (atm_mem_destination_offset+2),hl
        ld      hl,4
        ld      (atm_mem_op_length),hl
        ld      hl,0
        ld      (atm_mem_op_length+2),hl
        call    atm_mem_copy
        jp      c,atm_mem_ops_test_fail_08

        ; Verify resulting bytes: 11 11 22 33 44.
        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_work_offset+2),hl
        call    atm_mem_map_work_offset
        jp      c,atm_mem_ops_test_fail_09
        ld      a,(hl)
        cp      #11
        jp      nz,atm_mem_ops_test_fail_09
        inc     hl
        ld      a,(hl)
        cp      #11
        jp      nz,atm_mem_ops_test_fail_09
        inc     hl
        ld      a,(hl)
        cp      #22
        jp      nz,atm_mem_ops_test_fail_09
        inc     hl
        ld      a,(hl)
        cp      #33
        jp      nz,atm_mem_ops_test_fail_09
        inc     hl
        ld      a,(hl)
        cp      #44
        jp      nz,atm_mem_ops_test_fail_09

        ; Zero-length FILL at exactly 1 MiB is a valid no-op.
        ld      hl,0
        ld      (atm_mem_destination_offset),hl
        ld      hl,#0010
        ld      (atm_mem_destination_offset+2),hl
        ld      hl,0
        ld      (atm_mem_op_length),hl
        ld      (atm_mem_op_length+2),hl
        call    atm_mem_fill
        jp      c,atm_mem_ops_test_fail_11

        ; Zero-length COPY at exactly 1 MiB is also a valid no-op.
        ld      hl,0
        ld      (atm_mem_source_offset),hl
        ld      hl,#0010
        ld      (atm_mem_source_offset+2),hl
        ld      hl,0
        ld      (atm_mem_destination_offset),hl
        ld      hl,#0010
        ld      (atm_mem_destination_offset+2),hl
        call    atm_mem_copy
        jp      c,atm_mem_ops_test_fail_12

        ; A nonzero FILL beginning at capacity must be rejected.
        ld      hl,1
        ld      (atm_mem_op_length),hl
        ld      hl,0
        ld      (atm_mem_op_length+2),hl
        call    atm_mem_fill
        jp      nc,atm_mem_ops_test_fail_13

        ; Invalid destination COPY must fail before modifying its target.
        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_source_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_source_offset+2),hl
        ld      hl,0
        ld      (atm_mem_destination_offset),hl
        ld      hl,#0010
        ld      (atm_mem_destination_offset+2),hl
        call    atm_mem_copy
        jp      nc,atm_mem_ops_test_fail_14
        ld      hl,(atm_mem_test_destination)
        ld      (atm_mem_work_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      (atm_mem_work_offset+2),hl
        call    atm_mem_map_work_offset
        jp      c,atm_mem_ops_test_fail_14
        ld      a,(hl)
        cp      #A5
        jp      nz,atm_mem_ops_test_fail_14

        ; Invalid source COPY must also be rejected.
        ld      hl,0
        ld      (atm_mem_source_offset),hl
        ld      hl,#0010
        ld      (atm_mem_source_offset+2),hl
        ld      hl,(atm_mem_test_destination)
        ld      (atm_mem_destination_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      (atm_mem_destination_offset+2),hl
        call    atm_mem_copy
        jp      nc,atm_mem_ops_test_fail_15

        ; Free second allocation.
        ld      hl,(atm_mem_test_destination)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_test_destination+2)
        ld      (atm_mem_request_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_free
        jp      c,atm_mem_ops_test_fail_10

        ; Free first allocation.
        ld      hl,(atm_mem_test_source)
        ld      (atm_mem_request_offset),hl
        ld      hl,(atm_mem_test_source+2)
        ld      (atm_mem_request_offset+2),hl
        ld      hl,#4001
        ld      (atm_mem_request_length),hl
        ld      hl,0
        ld      (atm_mem_request_length+2),hl
        call    atm_mem_free
        ret

atm_mem_ops_test_fail_01: ld a,1
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_02: ld a,2
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_03: ld a,3
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_04: ld a,4
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_05: ld a,5
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_06: ld a,6
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_07: ld a,7
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_08: ld a,8
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_09: ld a,9
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_10: ld a,10
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_11: ld a,11
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_12: ld a,12
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_13: ld a,13
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_14: ld a,14
        jr atm_mem_ops_test_fail
atm_mem_ops_test_fail_15:
        ld a,15
atm_mem_ops_test_fail:
        scf
        ret

atm_mem_test_source:      defs 4,0
atm_mem_test_destination: defs 4,0

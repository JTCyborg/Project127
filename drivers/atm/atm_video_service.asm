; =========================================================================
; PROJECT127 ATM native video service v0.3.0
; Confirmed ATM Turbo 2+ RG6 80x25 text framebuffer.
; Host code occupies page 5, so video uses the established alternate
; framebuffer pages 7 (characters) and 3 (attributes).
;
; API:
;   P127_ATM_Video_Query: A=mode, B=columns, C=rows, HL=frame bytes
;   P127_ATM_Video_WriteCell: D=row, E=column, A=character; attr defaults #44
;   P127_ATM_Video_WriteCellEx: D=row, E=column, A=character, B=attribute
;   P127_ATM_Video_ReadCell: D=row, E=column; returns A=character, B=attribute
;   P127_ATM_Video_Clear: clears the 80x25 character/attribute planes
;   BufferCreate/Destroy/Clear/Copy: two off-screen packed RG6 buffers
;   BufferRead/Write: UINT32 byte ranges between video and transfer handles
;   BufferPrepare/Unprepare: pin/unpin a buffer for a future DMA consumer
; Buffer payload is 4000 bytes: 2000 interleaved character/attribute pairs.
;   P127_ATM_Video_SelfTest: framebuffer write/readback + bounds test
; Carry clear = success; carry set = invalid request or test failure.
; =========================================================================
P127_ATM_VIDEO_VERSION       EQU #0300
P127_ATM_VIDEO_MODE_RG6      EQU #C6
P127_ATM_VIDEO_COLUMNS       EQU 80
P127_ATM_VIDEO_ROWS          EQU 25
P127_ATM_VIDEO_FRAME_BYTES   EQU 4000
P127_ATM_VIDEO_PAGE7         EQU #78
P127_ATM_VIDEO_PAGE3         EQU #7C
P127_ATM_VIDEO_HOST_PAGE5    EQU #7A
P127_ATM_VIDEO_HOST_PAGE0    EQU #7F
P127_ATM_VIDEO_DEFAULT_ATTR  EQU #44

P127_ATM_Video_Query::
        ld a,P127_ATM_VIDEO_MODE_RG6
        ld b,P127_ATM_VIDEO_COLUMNS
        ld c,P127_ATM_VIDEO_ROWS
        ld hl,P127_ATM_VIDEO_FRAME_BYTES
        or a
        ret

; D=row, E=column. Returns HL=offset from text-plane base.
P127_ATM_Video_CalcOffset:
        ld a,e
        ld (p127_video_column),a
        ld a,d
        ld (p127_video_row),a
        cp P127_ATM_VIDEO_ROWS
        jr nc,p127_video_bad_coordinate
        ld a,(p127_video_column)
        cp P127_ATM_VIDEO_COLUMNS
        jr nc,p127_video_bad_coordinate
        ld a,(p127_video_row)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,#01C0
        add hl,de
        ld a,(p127_video_column)
        srl a
        ld e,a
        ld d,0
        add hl,de
        or a
        ret
p127_video_bad_coordinate:
        scf
        ret

; Compatibility entry: write a character using the standard attribute.
P127_ATM_Video_WriteCell::
        ld b,P127_ATM_VIDEO_DEFAULT_ATTR
        jp P127_ATM_Video_WriteCellEx

; D=row, E=column, A=character, B=attribute.
P127_ATM_Video_WriteCellEx::
        ld (p127_video_character),a
        ld a,b
        ld (p127_video_attribute),a
        call P127_ATM_Video_CalcOffset
        ret c
        ld (p127_video_offset),hl
        call p127_video_map
        ld a,(p127_video_column)
        and 1
        jr nz,p127_video_write_odd
        ld hl,(p127_video_offset)
        ld de,#4000
        add hl,de
        ld a,(p127_video_character)
        ld (hl),a
        ld hl,(p127_video_offset)
        ld de,#E000
        add hl,de
        ld a,(p127_video_attribute)
        ld (hl),a
        jr p127_video_write_restore
p127_video_write_odd:
        ld hl,(p127_video_offset)
        ld de,#6000
        add hl,de
        ld a,(p127_video_character)
        ld (hl),a
        ld hl,(p127_video_offset)
        ld de,#C000
        add hl,de
        inc hl
        ld a,(p127_video_attribute)
        ld (hl),a
p127_video_write_restore:
        call p127_video_restore
        or a
        ret

; D=row, E=column. Returns A=character, B=attribute.
P127_ATM_Video_ReadCell::
        call P127_ATM_Video_CalcOffset
        ret c
        ld (p127_video_offset),hl
        call p127_video_map
        ld a,(p127_video_column)
        and 1
        jr nz,p127_video_read_odd
        ld hl,(p127_video_offset)
        ld de,#4000
        add hl,de
        ld a,(hl)
        ld (p127_video_character),a
        ld hl,(p127_video_offset)
        ld de,#E000
        add hl,de
        ld a,(hl)
        ld b,a
        jr p127_video_read_restore
p127_video_read_odd:
        ld hl,(p127_video_offset)
        ld de,#6000
        add hl,de
        ld a,(hl)
        ld (p127_video_character),a
        ld hl,(p127_video_offset)
        ld de,#C000
        add hl,de
        inc hl
        ld a,(hl)
        ld b,a
p127_video_read_restore:
        call p127_video_restore
        ld a,(p127_video_character)
        or a
        ret

p127_video_map:
        ld a,P127_ATM_VIDEO_PAGE7
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_PAGE3
        ld bc,#FFF7
        out (c),a
        ret

p127_video_restore:
        ; BC is caller-visible in ReadCell: B returns the attribute.
        ; Preserve it while restoring the ATM page registers.
        push bc
        ld a,P127_ATM_VIDEO_HOST_PAGE5
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_HOST_PAGE0
        ld bc,#FFF7
        out (c),a
        pop bc
        ret

P127_ATM_Video_Clear::
        push af
        push bc
        push de
        push hl
        call p127_video_map
        ld hl,#41C0
        ld de,#41C1
        ld (hl),32
        ld bc,#063F
        ldir
        ld hl,#61C0
        ld de,#61C1
        ld (hl),32
        ld bc,#063F
        ldir
        ld hl,#E1C0
        ld de,#E1C1
        ld (hl),P127_ATM_VIDEO_DEFAULT_ATTR
        ld bc,#063F
        ldir
        ld hl,#C1C1
        ld de,#C1C2
        ld (hl),P127_ATM_VIDEO_DEFAULT_ATTR
        ld bc,#063F
        ldir
        call p127_video_restore
        pop hl
        pop de
        pop bc
        pop af
        ret

; Runtime test of both character/attribute parity layouts. Original cells are
; restored before returning, including when a readback comparison fails.
P127_ATM_Video_SelfTest::
        ld d,0
        ld e,0
        call P127_ATM_Video_ReadCell
        jr c,p127_video_test_fail_1
        ld (p127_video_saved_char),a
        ld a,b
        ld (p127_video_saved_attr),a
        ld d,0
        ld e,0
        ld a,#51
        ld b,#2A
        call P127_ATM_Video_WriteCellEx
        jr c,p127_video_test_fail_1
        ld d,0
        ld e,0
        call P127_ATM_Video_ReadCell
        jr c,p127_video_test_restore_0_fail
        cp #51
        jr nz,p127_video_test_restore_0_fail
        ld a,b
        cp #2A
        jr nz,p127_video_test_restore_0_fail
        call p127_video_restore_cell_0

        ld d,24
        ld e,79
        call P127_ATM_Video_ReadCell
        jr c,p127_video_test_fail_2
        ld (p127_video_saved_char),a
        ld a,b
        ld (p127_video_saved_attr),a
        ld d,24
        ld e,79
        ld a,#A6
        ld b,#35
        call P127_ATM_Video_WriteCellEx
        jr c,p127_video_test_fail_2
        ld d,24
        ld e,79
        call P127_ATM_Video_ReadCell
        jr c,p127_video_test_restore_1_fail
        cp #A6
        jr nz,p127_video_test_restore_1_fail
        ld a,b
        cp #35
        jr nz,p127_video_test_restore_1_fail
        call p127_video_restore_cell_1

        ld d,25
        ld e,0
        call P127_ATM_Video_CalcOffset
        jr nc,p127_video_test_fail_3
        xor a
        ret

p127_video_test_restore_0_fail:
        call p127_video_restore_cell_0
p127_video_test_fail_1:
        ld a,1
        jr p127_video_test_fail
p127_video_test_restore_1_fail:
        call p127_video_restore_cell_1
p127_video_test_fail_2:
        ld a,2
        jr p127_video_test_fail
p127_video_test_fail_3:
        ld a,3
p127_video_test_fail:
        scf
        ret

p127_video_restore_cell_0:
        ld d,0
        ld e,0
        ld a,(p127_video_saved_attr)
        ld b,a
        ld a,(p127_video_saved_char)
        jp P127_ATM_Video_WriteCellEx

p127_video_restore_cell_1:
        ld d,24
        ld e,79
        ld a,(p127_video_saved_attr)
        ld b,a
        ld a,(p127_video_saved_char)
        jp P127_ATM_Video_WriteCellEx


; =========================================================================
; Off-screen frame buffers v0.3.0.
; Two opaque video IDs are backed by the existing scatter-handle allocator.
; Each logical frame is 4000 bytes (80*25*2), interleaved char/attribute.
; All public offsets and lengths are UINT32 descriptors; no window/page size
; is exposed. READ/WRITE endpoints are transfer handles, never raw pointers.
; =========================================================================
P127_ATM_VIDEO_BUFFER_COUNT EQU 2
P127_ATM_VIDEO_BUFFER_BYTES EQU 4000

; Create: returns A=video buffer ID (1..2), carry on failure.
P127_ATM_Video_BufferCreate::
        ld hl,p127_video_buffer_handles
        ld b,P127_ATM_VIDEO_BUFFER_COUNT
        ld c,1
p127_video_buffer_create_scan:
        ld a,(hl)
        or a
        jr z,p127_video_buffer_create_slot
        inc hl
        inc c
        djnz p127_video_buffer_create_scan
        scf
        ret
p127_video_buffer_create_slot:
        ld (p127_video_buffer_slot_ptr),hl
        ld a,c
        ld (p127_video_buffer_id),a
        ld hl,P127_ATM_VIDEO_BUFFER_BYTES
        ld (atm_mem_request_length),hl
        ld hl,0
        ld (atm_mem_request_length+2),hl
        call atm_mem_scatter_alloc
        ret c
        ld hl,(p127_video_buffer_slot_ptr)
        ld (hl),a
        ld a,(p127_video_buffer_id)
        or a
        ret

; A=video buffer ID. Returns A=underlying private handle.
p127_video_buffer_get_handle:
        or a
        jr z,p127_video_buffer_invalid
        cp P127_ATM_VIDEO_BUFFER_COUNT+1
        jr nc,p127_video_buffer_invalid
        dec a
        ld e,a
        ld d,0
        ld hl,p127_video_buffer_handles
        add hl,de
        ld a,(hl)
        or a
        jr z,p127_video_buffer_invalid
        or a
        ret
p127_video_buffer_invalid:
        scf
        ret

; A=video buffer ID. A pinned buffer cannot be destroyed.
P127_ATM_Video_BufferDestroy::
        ld (p127_video_buffer_id),a
        call p127_video_buffer_get_handle
        ret c
        ld (p127_video_buffer_temp_handle),a
        call atm_mem_scatter_free
        ret c
        ld a,(p127_video_buffer_id)
        dec a
        ld e,a
        ld d,0
        ld hl,p127_video_buffer_handles
        add hl,de
        xor a
        ld (hl),a
        or a
        ret

; A=video buffer ID, fills its complete 4000-byte frame with zero.
P127_ATM_Video_BufferClear::
        call p127_video_buffer_get_handle
        ret c
        ld (atm_mem_handle_destination),a
        ld hl,0
        ld (atm_mem_handle_destination_offset),hl
        ld (atm_mem_handle_destination_offset+2),hl
        ld hl,P127_ATM_VIDEO_BUFFER_BYTES
        ld (atm_mem_handle_op_length),hl
        ld hl,0
        ld (atm_mem_handle_op_length+2),hl
        xor a
        ld (atm_mem_handle_fill_value),a
        jp atm_mem_handle_fill

; A=source video ID, B=destination video ID; copies complete frame.
P127_ATM_Video_BufferCopy::
        ld (p127_video_buffer_id),a
        ld a,b
        call p127_video_buffer_get_handle
        ret c
        ld (atm_mem_handle_destination),a
        ld a,(p127_video_buffer_id)
        call p127_video_buffer_get_handle
        ret c
        ld (atm_mem_handle_source),a
        ld hl,0
        ld (atm_mem_handle_source_offset),hl
        ld (atm_mem_handle_source_offset+2),hl
        ld (atm_mem_handle_destination_offset),hl
        ld (atm_mem_handle_destination_offset+2),hl
        ld hl,P127_ATM_VIDEO_BUFFER_BYTES
        ld (atm_mem_handle_op_length),hl
        ld hl,0
        ld (atm_mem_handle_op_length+2),hl
        jp atm_mem_handle_copy

; READ: video buffer -> transfer handle.
; WRITE: transfer handle -> video buffer.
; Descriptors below are UINT32 byte offsets/lengths.
P127_ATM_Video_BufferRead::
        ld a,(p127_video_buffer_id)
        call p127_video_buffer_get_handle
        ret c
        ld (atm_mem_handle_source),a
        ld a,(p127_video_transfer_handle)
        ld (atm_mem_handle_destination),a
        ld hl,p127_video_buffer_offset
        ld de,atm_mem_handle_source_offset
        ld bc,4
        ldir
        ld hl,p127_video_transfer_offset
        ld de,atm_mem_handle_destination_offset
        ld bc,4
        ldir
        ld hl,p127_video_length
        ld de,atm_mem_handle_op_length
        ld bc,4
        ldir
        jp atm_mem_handle_copy

P127_ATM_Video_BufferWrite::
        ld a,(p127_video_transfer_handle)
        ld (atm_mem_handle_source),a
        ld a,(p127_video_buffer_id)
        call p127_video_buffer_get_handle
        ret c
        ld (atm_mem_handle_destination),a
        ld hl,p127_video_transfer_offset
        ld de,atm_mem_handle_source_offset
        ld bc,4
        ldir
        ld hl,p127_video_buffer_offset
        ld de,atm_mem_handle_destination_offset
        ld bc,4
        ldir
        ld hl,p127_video_length
        ld de,atm_mem_handle_op_length
        ld bc,4
        ldir
        jp atm_mem_handle_copy

; A=video ID. Pin the buffer while a DMA/transport consumer owns it.
P127_ATM_Video_BufferPrepare::
        ld (p127_video_buffer_id),a
        ld a,(p127_video_prepared_id)
        or a
        jr nz,p127_video_buffer_busy
        ld a,(p127_video_buffer_id)
        call p127_video_buffer_get_handle
        ret c
        call atm_mem_scatter_pin
        ret c
        ld a,(p127_video_buffer_id)
        ld (p127_video_prepared_id),a
        or a
        ret
p127_video_buffer_busy:
        scf
        ret

; A=video ID. Releases the pin established by BufferPrepare.
P127_ATM_Video_BufferUnprepare::
        ld (p127_video_buffer_id),a
        ld a,(p127_video_prepared_id)
        ld b,a
        ld a,(p127_video_buffer_id)
        cp b
        jr nz,p127_video_buffer_busy
        ld a,(p127_video_buffer_id)
        call p127_video_buffer_get_handle
        ret c
        call atm_mem_scatter_unpin
        ret c
        xor a
        ld (p127_video_prepared_id),a
        or a
        ret

; Runtime acceptance: allocation, clear, complete copy, UINT32 bounds,
; prepare/pin ownership, and transactional destruction.
P127_ATM_Video_BufferSelfTest::
        xor a
        ld (p127_video_prepared_id),a
        ld a,1
        ld (p127_video_buffer_id),a
        call P127_ATM_Video_BufferCreate
        jp c,p127_video_buffer_test_fail_
        cp 1
        jp nz,p127_video_buffer_test_fail_
        ld a,2
        call P127_ATM_Video_BufferCreate
        jp c,p127_video_buffer_test_fail_
        cp 2
        jp nz,p127_video_buffer_test_fail_
        ld a,1
        call P127_ATM_Video_BufferClear
        jp c,p127_video_buffer_test_fail_
        ld a,1
        ld b,2
        call P127_ATM_Video_BufferCopy
        jp c,p127_video_buffer_test_fail_
        ; Reject a range extending one byte beyond the frame.
        ld a,1
        ld (p127_video_buffer_id),a
        ld hl,P127_ATM_VIDEO_BUFFER_BYTES-1
        ld (p127_video_buffer_offset),hl
        ld hl,0
        ld (p127_video_buffer_offset+2),hl
        ld hl,2
        ld (p127_video_length),hl
        ld hl,0
        ld (p127_video_length+2),hl
        ld a,1
        call p127_video_buffer_get_handle
        jp c,p127_video_buffer_test_fail_
        ld (atm_mem_handle_source),a
        ld a,2
        call p127_video_buffer_get_handle
        jp c,p127_video_buffer_test_fail_
        ld (atm_mem_handle_destination),a
        ld hl,(p127_video_buffer_offset)
        ld (atm_mem_handle_source_offset),hl
        ld hl,(p127_video_buffer_offset+2)
        ld (atm_mem_handle_source_offset+2),hl
        ld hl,0
        ld (atm_mem_handle_destination_offset),hl
        ld (atm_mem_handle_destination_offset+2),hl
        ld hl,(p127_video_length)
        ld (atm_mem_handle_op_length),hl
        ld hl,(p127_video_length+2)
        ld (atm_mem_handle_op_length+2),hl
        call atm_mem_handle_copy
        jp nc,p127_video_buffer_test_fail_
        ld a,1
        call P127_ATM_Video_BufferPrepare
        jp c,p127_video_buffer_test_fail_
        ld a,1
        call P127_ATM_Video_BufferDestroy
        jp nc,p127_video_buffer_test_fail_
        ld a,1
        call P127_ATM_Video_BufferUnprepare
        jp c,p127_video_buffer_test_fail_
        ld a,1
        call P127_ATM_Video_BufferDestroy
        jp c,p127_video_buffer_test_fail_
        ld a,2
        call P127_ATM_Video_BufferDestroy
        jp c,p127_video_buffer_test_fail_
        xor a
        ret
p127_video_buffer_test_fail_1:
        ld a,1
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_2:
        ld a,2
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_3:
        ld a,3
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_4:
        ld a,4
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_5:
        ld a,5
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_6:
        ld a,6
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_7:
        ld a,7
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_8:
        ld a,8
        jr p127_video_buffer_test_fail
p127_video_buffer_test_fail_9:
        ld a,9
p127_video_buffer_test_fail:
        scf
        ret

p127_video_buffer_handles:    defs P127_ATM_VIDEO_BUFFER_COUNT,0
p127_video_buffer_slot_ptr:   dw 0
p127_video_buffer_id:         db 0
p127_video_buffer_temp_handle: db 0
p127_video_transfer_handle:   db 0
p127_video_prepared_id:       db 0
p127_video_buffer_offset:     defs 4,0
p127_video_transfer_offset:   defs 4,0
p127_video_length:            defs 4,0


p127_video_row:          db 0
p127_video_column:       db 0
p127_video_character:    db 0
p127_video_attribute:    db 0
p127_video_offset:       dw 0
p127_video_saved_char:   db 0
p127_video_saved_attr:   db 0
p127_host_video_ok:
        db "[P127] ATM NATIVE VIDEO CORE v0.3.0 SELFTEST PASS",13,10,0
p127_host_video_buffers_ok:
        db "[P127] ATM VIDEO BUFFERS UINT32 SELFTEST PASS",13,10,0
p127_host_video_error:
        db "[P127] ATM NATIVE VIDEO CORE SELFTEST FAIL STEP=0x",0

p127_video_host_fail_handler:
        ld d,a
        ld hl,p127_host_video_error
        call p127_host_debug_string
        ld a,d
        call p127_host_debug_hex_byte
        ld a,13
        call p127_host_debug_char
        ld a,10
        call p127_host_debug_char
        jp p127_host_idle

p127_atm_video_service_end:
        ASSERT p127_atm_video_service_end<=#9800

; =========================================================================
; PROJECT127 ATM native video service v0.2.0
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
;   P127_ATM_Video_SelfTest: framebuffer write/readback + bounds test
; Carry clear = success; carry set = invalid request or test failure.
; =========================================================================
P127_ATM_VIDEO_VERSION       EQU #0200
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
        ld a,P127_ATM_VIDEO_HOST_PAGE5
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_HOST_PAGE0
        ld bc,#FFF7
        out (c),a
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

p127_video_row:          db 0
p127_video_column:       db 0
p127_video_character:    db 0
p127_video_attribute:    db 0
p127_video_offset:       dw 0
p127_video_saved_char:   db 0
p127_video_saved_attr:   db 0
p127_host_video_ok:
        db "[P127] ATM NATIVE VIDEO CORE v0.2.0 SELFTEST PASS",13,10,0
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
        ASSERT p127_atm_video_service_end<=#A000

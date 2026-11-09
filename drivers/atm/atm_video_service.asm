; =========================================================================
; PROJECT127 ATM native video service v0.1.0
; Confirmed ATM Turbo 2+ RG6 80x25 text framebuffer.
; Host code occupies page 5, so video uses the established alternate
; framebuffer pages 7 (characters) and 3 (attributes).
;
; API:
;   P127_ATM_Video_Query: A=mode register, B=columns, C=rows, HL=frame bytes
;   P127_ATM_Video_WriteCell: D=row, E=column, A=character; carry=invalid
;   P127_ATM_Video_Clear: clears the 80x25 character/attribute planes
;   P127_ATM_Video_SelfTest: geometry-only test; carry clear=pass
; =========================================================================
P127_ATM_VIDEO_VERSION       EQU #0100
P127_ATM_VIDEO_MODE_RG6      EQU #C6
P127_ATM_VIDEO_COLUMNS       EQU 80
P127_ATM_VIDEO_ROWS          EQU 25
P127_ATM_VIDEO_FRAME_BYTES   EQU 4000
P127_ATM_VIDEO_PAGE7         EQU #78
P127_ATM_VIDEO_PAGE3         EQU #7C
P127_ATM_VIDEO_HOST_PAGE5    EQU #7A
P127_ATM_VIDEO_HOST_PAGE0    EQU #7F

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

P127_ATM_Video_WriteCell::
        ld (p127_video_character),a
        call P127_ATM_Video_CalcOffset
        ret c
        ld (p127_video_offset),hl
        ld a,P127_ATM_VIDEO_PAGE7
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_PAGE3
        ld bc,#FFF7
        out (c),a
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
        ld (hl),#44
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
        ld (hl),#44
p127_video_write_restore:
        ld a,P127_ATM_VIDEO_HOST_PAGE5
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_HOST_PAGE0
        ld bc,#FFF7
        out (c),a
        or a
        ret

P127_ATM_Video_Clear::
        push af
        push bc
        push de
        push hl
        ld a,P127_ATM_VIDEO_PAGE7
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_PAGE3
        ld bc,#FFF7
        out (c),a
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
        ld (hl),#44
        ld bc,#063F
        ldir
        ld hl,#C1C1
        ld de,#C1C2
        ld (hl),#44
        ld bc,#063F
        ldir
        ld a,P127_ATM_VIDEO_HOST_PAGE5
        ld bc,#7FF7
        out (c),a
        ld a,P127_ATM_VIDEO_HOST_PAGE0
        ld bc,#FFF7
        out (c),a
        pop hl
        pop de
        pop bc
        pop af
        ret

; Pure geometry test. No port writes and no framebuffer changes.
P127_ATM_Video_SelfTest::
        ld d,0
        ld e,0
        call P127_ATM_Video_CalcOffset
        jr c,p127_video_test_fail_1
        ld de,#01C0
        or a
        sbc hl,de
        jr nz,p127_video_test_fail_1
        ld d,24
        ld e,79
        call P127_ATM_Video_CalcOffset
        jr c,p127_video_test_fail_2
        ld de,#07E7
        or a
        sbc hl,de
        jr nz,p127_video_test_fail_2
        ld d,25
        ld e,0
        call P127_ATM_Video_CalcOffset
        jr nc,p127_video_test_fail_3
        xor a
        ret
p127_video_test_fail_1:
        ld a,1
        jr p127_video_test_fail
p127_video_test_fail_2:
        ld a,2
        jr p127_video_test_fail
p127_video_test_fail_3:
        ld a,3
p127_video_test_fail:
        scf
        ret

p127_video_row:       db 0
p127_video_column:    db 0
p127_video_character: db 0
p127_video_offset:    dw 0
p127_atm_video_service_end:
        ASSERT p127_atm_video_service_end<=#A000

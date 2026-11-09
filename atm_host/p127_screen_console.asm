; =========================================================================
; PROJECT127 - ATM native 80x25 status console
; Project126-compatible two-zone layout: status panel + scrolling log.
; Lives at #A000 in window 2; host code remains at #6000.
; =========================================================================
P127_VIDEO_PAGE7 EQU #78
P127_VIDEO_PAGE3 EQU #7C
P127_HOST_PAGE5  EQU #7A
P127_HOST_PAGE0  EQU #7F
P127_CONSOLE_TOP EQU 12
P127_CONSOLE_ROWS EQU 13

P127_DebugConsole_Init::
        push af
        push bc
        push de
        push hl
        xor a
        ld (p127_console_row),a
        ld (p127_console_col),a
        ; Project126 ATM2+ shadow-port and RG6 text setup.
        xor a
        ld bc,#EFF7
        out (c),a
        ld a,#18
        ld bc,#7FFD
        out (c),a
        ld (#5C3B),a
        ld bc,p127_console_ports_open
        push bc
        ld bc,#2A53
        push bc
        ld bc,#0177
        ld a,#C3
        jp #3D2F
p127_console_ports_open:
        ld a,#BF
        ld bc,#3FF7
        out (c),a
        ld a,P127_VIDEO_PAGE7
        ld bc,#7FF7
        out (c),a
        ld a,P127_VIDEO_PAGE3
        ld bc,#FFF7
        out (c),a
        ; RG6 80x25 through the documented #FFEC trampoline.
        ld hl,#FFEC
        ld (hl),#01
        inc hl
        ld (hl),#77
        inc hl
        ld (hl),#01
        inc hl
        ld (hl),#ED
        inc hl
        ld (hl),#79
        inc hl
        ld (hl),#C3
        inc hl
        ld (hl),p127_console_video_ready & #FF
        inc hl
        ld (hl),p127_console_video_ready >> 8
        ld a,#C6
        jp #FFEC
p127_console_video_ready:
        call P127_Console_Clear
        ld hl,p127_ui0
        xor a
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui1
        ld a,1
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui2
        ld a,3
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui3
        ld a,5
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui4
        ld a,7
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui5
        ld a,9
        ld c,1
        call P127_Console_PrintAt
        ld hl,p127_ui6
        ld a,11
        ld c,1
        call P127_Console_PrintAt
        call P127_Console_Restore
        pop hl
        pop de
        pop bc
        pop af
        ret

P127_Console_Clear:
        call P127_Console_Map
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
        ld (hl),#4F
        ld bc,#063F
        ldir
        ld hl,#C1C1
        ld de,#C1C2
        ld (hl),#4F
        ld bc,#063F
        ldir
        ld hl,#E4C0
        ld de,#E4C1
        ld (hl),#44
        ld bc,#033F
        ldir
        ld hl,#C4C1
        ld de,#C4C2
        ld (hl),#44
        ld bc,#033F
        ldir
        jp P127_Console_Restore

P127_Console_PrintAt:
        ld (p127_console_text),hl
        ld (p127_console_row_abs),a
        ld a,c
        ld (p127_console_col_abs),a
.print_at:
        ld hl,(p127_console_text)
        ld a,(hl)
        or a
        ret z
        inc hl
        ld (p127_console_text),hl
        ld (p127_console_char),a
        ld a,(p127_console_row_abs)
        ld d,a
        ld a,(p127_console_col_abs)
        ld e,a
        ld a,(p127_console_char)
        call P127_Console_WriteChar
        ld a,(p127_console_col_abs)
        inc a
        cp 80
        jr c,.col_ok
        xor a
        ld (p127_console_col_abs),a
        ld a,(p127_console_row_abs)
        inc a
        ld (p127_console_row_abs),a
        jr .print_at
.col_ok:
        ld (p127_console_col_abs),a
        jr .print_at

P127_DebugConsole_String:
        ld a,(hl)
        or a
        ret z
        call P127_DebugConsole_Char
        inc hl
        jr P127_DebugConsole_String

P127_DebugConsole_Char:
        push af
        push bc
        push de
        push hl
        cp 13
        jr z,.cr
        cp 10
        jr z,.lf
        cp 32
        jr c,.done
        ld (p127_console_char),a
        ld a,(p127_console_row)
        add a,P127_CONSOLE_TOP
        ld d,a
        ld a,(p127_console_col)
        ld e,a
        ld a,(p127_console_char)
        call P127_Console_WriteChar
        ld a,(p127_console_col)
        inc a
        cp 80
        jr c,.store
        xor a
        ld (p127_console_col),a
        call P127_Console_Newline
        jr .done
.store:
        ld (p127_console_col),a
        jr .done
.cr:
        xor a
        ld (p127_console_col),a
        jr .done
.lf:
        call P127_Console_Newline
.done:
        pop hl
        pop de
        pop bc
        pop af
        ret

P127_Console_Newline:
        ld a,(p127_console_row)
        inc a
        cp P127_CONSOLE_ROWS
        jr c,.store
        call P127_Console_Scroll
        ld a,P127_CONSOLE_ROWS-1
.store:
        ld (p127_console_row),a
        xor a
        ld (p127_console_col),a
        ret

P127_Console_Scroll:
        call P127_Console_Map
        ld hl,#4500
        ld de,#44C0
        ld bc,#0300
        ldir
        ld hl,#6500
        ld de,#64C0
        ld bc,#0300
        ldir
        ld hl,#E500
        ld de,#E4C0
        ld bc,#0300
        ldir
        ld hl,#C501
        ld de,#C4C1
        ld bc,#0300
        ldir
        call P127_Console_Restore
        ret

P127_Console_WriteChar:
        push af
        push bc
        push de
        push hl
        ld (p127_console_char),a
        ld a,d
        ld (p127_console_row_tmp),a
        ld a,e
        ld (p127_console_col_tmp),a
        ; offset = #01C0 + row*64 + column/2
        ld a,(p127_console_row_tmp)
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
        ld a,(p127_console_col_tmp)
        srl a
        ld e,a
        ld d,0
        add hl,de
        ld (p127_console_offset),hl
        call P127_Console_Map
        ld a,(p127_console_col_tmp)
        and 1
        jr nz,.odd
        ld hl,(p127_console_offset)
        ld de,#4000
        add hl,de
        ld a,(p127_console_char)
        ld (hl),a
        ld hl,(p127_console_offset)
        ld de,#E000
        add hl,de
        ld (hl),#44
        jr .restore
.odd:
        ld hl,(p127_console_offset)
        ld de,#6000
        add hl,de
        ld a,(p127_console_char)
        ld (hl),a
        ld hl,(p127_console_offset)
        ld de,#C000
        add hl,de
        inc hl
        ld (hl),#44
.restore:
        call P127_Console_Restore
        pop hl
        pop de
        pop bc
        pop af
        ret
P127_Console_Map:
        ld a,P127_VIDEO_PAGE7
        ld bc,#7FF7
        out (c),a
        ld a,P127_VIDEO_PAGE3
        ld bc,#FFF7
        out (c),a
        ret
P127_Console_Restore:
        ld a,P127_HOST_PAGE5
        ld bc,#7FF7
        out (c),a
        ld a,P127_HOST_PAGE0
        ld bc,#FFF7
        out (c),a
        ret

p127_ui0: db "PROJECT127 | ATM TURBO 2+ | SYSTEM MONITOR",0
p127_ui1: db "LOW-LEVEL FOUNDATION  |  TR-DOS HOST",0
p127_ui2: db "ATM MEMORY : 1 MiB  |  UINT32 API  |  SCATTER HANDLES",0
p127_ui3: db "PIN/UNPIN  : IMPLEMENTED - RUNTIME SELFTEST",0
p127_ui4: db "NEOGS RAM  : 4 MiB  |  HOST-MEDIATED DMA ONLY",0
p127_ui5: db "VIDEO: RG6 + BUFFERS   RTC: DS12887   DISK: NEMO IDE / SMUC",0
p127_ui6: db "SPEAKER: PENDING  |  LOG OUTPUT BELOW",0

p127_console_row: db 0
p127_console_col: db 0
p127_console_char: db 0
p127_console_row_tmp: db 0
p127_console_col_tmp: db 0
p127_console_offset: dw 0
p127_console_text: dw 0
p127_console_row_abs: db 0
p127_console_col_abs: db 0
p127_console_end:
        ASSERT p127_console_end <= #C400

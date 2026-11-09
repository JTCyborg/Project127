; ============================================================================
; Project127 ATM-native debug console, ported from Project126
; Source: Project126/atm_host/p126_screen_console.asm
; Module version: 0.1.4
; ATM Turbo 2+ RG6 80x25; upper 12 rows status, lower 13 rows scrolling log.
; Every displayed debug character and static UI label is mirrored to #EF.
; Resident placement: #A000, in the Project126 host display window.
; ============================================================================
P126_ATM_VIDEO_MODE_RG6_TEXT80X25 EQU 6
BIOS_DEBUG_COLUMNS EQU 80
BIOS_DEBUG_ROWS EQU 13
BIOS_DEBUG_TOP EQU 12
P126_VIDEO_PAGE7 EQU #78
P126_VIDEO_PAGE3 EQU #7C
P126_HOST_PAGE5 EQU #7A
P126_HOST_PAGE0 EQU #7F
P126_ATM_TEXT_WIDTH EQU 80
P126_ATM_TEXT_HEIGHT EQU 25
P126_ATM_TEXT_FRAME_SIZE EQU 4000
P127_UI_DEBUG_PORT EQU #00EF

p126_atm_video_mode: db P126_ATM_VIDEO_MODE_RG6_TEXT80X25
p126_atm_video_enabled: db 0
Console_X: db 0
Console_Y: db BIOS_DEBUG_TOP
bios_dbg_row: db 0
bios_dbg_col: db 0
bios_dbg_char: db 0
bios_dbg_write_row: db 0
bios_dbg_write_col: db 0
bios_dbg_parity: db 0
bios_dbg_attr: db 0
bios_dbg_offset: dw 0
bios_dbg_text_ptr: dw 0
bios_dbg_print_row: db 0
bios_dbg_print_col: db 0

p126_atm_video_init::
        push    af
        push    bc
        push    de
        push    hl

        ; Reset the ATM paging/control latch BEFORE enabling permanent
        ; DOSEN. On this board #EFF7 is part of the ATM paging control path;
        ; resetting it after the #0177 shadow-port setup can undo the state
        ; needed by the TR-DOS overlay.
        xor     a
        ld      bc, #EFF7
        out     (c), a

        ; ROM2=1 (D4) is required for TR-DOS overlay; D3 selects alternate
        ; video pages 7/3. This is #18, matching the host display setup.
        ld      a, #18
        ld      bc, #7FFD
        out     (c), a
        ld      (#5C3B), a

        ; Open shadow ports and hold DOSEN permanently (A9=0) using the
        ; documented TR-DOS ROM trampoline. Do this AFTER the paging reset.
        ld      bc, p126_atm_ports_open_done
        push    bc
        ld      bc, #2A53
        push    bc
        ld      bc, #0177
        ld      a, #C3
        jp      #3D2F

p126_atm_ports_open_done:
        ; Window 0 must use ROM with D7=1 so its ROM page selection is
        ; coupled to ROM2/DOSEN. #BF selects the low ROM page with the
        ; DOSEN-controlled low ROM select: BASIC-48 when DOSEN=0, TR-DOS
        ; when DOSEN=1. This is the ATM2+ documented auto-TR-DOS mapping.
        ld      a, #BF
        ld      bc, #3FF7
        out     (c), a


        ; Map the alternate screen pages while the 32-byte mode trampoline
        ; is installed at #FFEC. Window 3 uses a fixed RAM page here; the
        ; TR-DOS auto-select mux is configured separately in window 0.
        ld      a, P126_VIDEO_PAGE7
        ld      bc, #7FF7
        out     (c), a
        ld      a, P126_VIDEO_PAGE3
        ld      bc, #FFF7
        out     (c), a

        ; LD BC,#0177 / OUT (C),A / JP p126_atm_video_mode_ready
        ld      hl, #FFEC
        ld      (hl), #01
        inc     hl
        ld      (hl), #77
        inc     hl
        ld      (hl), #01
        inc     hl
        ld      (hl), #ED
        inc     hl
        ld      (hl), #79
        inc     hl
        ld      (hl), #C3
        inc     hl
        ld      (hl), p126_atm_video_mode_ready & #FF
        inc     hl
        ld      (hl), p126_atm_video_mode_ready >> 8

        ; ATM Turbo 2+ RG=6: hardware text 80x25.
        ld      a,P126_ATM_VIDEO_MODE_RG6_TEXT80X25
        ld      (p126_atm_video_mode),a
        ld      a, #C6
        jp      #FFEC

p126_atm_video_mode_ready:
        ; Restore CPU-visible host/staging pages. Keep D7 clear on #FFF7 so
        ; window 3 remains fixed to RAM page 0 for the TR-DOS staging buffer.
        ld      a, P126_HOST_PAGE5
        ld      bc, #7FF7
        out     (c), a
        ld      a, P126_HOST_PAGE0
        ld      bc, #FFF7
        out     (c), a

        pop     hl
        pop     de
        pop     bc
        pop     af
        ret


; Reopen the permanent ATM shadow-port/DOSEN state after DS12887 access.
; #EFF7 bit 7 is the RTC gate; closing it also closes the permanent DOSEN
; path. Re-enter the TR-DOS #0177 service and restore RG6 text mode exactly
; as in Project126's atm_host implementation.
p126_atm_restore_dosen::
        push    af
        push    bc
        ld      bc,p126_atm_restore_dosen_done
        push    bc
        ld      bc,#2A53
        push    bc
        ld      bc,#0177
        ld      a,P126_ATM_VIDEO_MODE_RG6_TEXT80X25
        ld      (p126_atm_video_mode),a
        ld      a,#C6
        jp      #3D2F
p126_atm_restore_dosen_done:
        pop     bc
        pop     af
        ret


p127_ui_init:
        call p126_atm_video_init
        call BIOS_DebugConsole_Init
        call BIOS_DebugConsole_Clear
        call BIOS_DebugConsole_DrawInterface
        ret

BIOS_DebugConsole_Init::
        xor     a
        ld      (bios_dbg_row), a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        ld      a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        ret

BIOS_DebugConsole_Clear::
        push    af
        push    bc
        push    de
        push    hl
        call    p126_screen_map_video_pages

        ; Clear 25 rows x 64-byte stride in both character parity planes.
        ld      hl, #41C0
        ld      de, #41C1
        ld      (hl), 32
        ld      bc, #063F
        ldir
        ld      hl, #61C0
        ld      de, #61C1
        ld      (hl), 32
        ld      bc, #063F
        ldir

        ; Default attributes, then color the status panel blue/white.
        ld      hl, #E1C0
        ld      de, #E1C1
        ld      (hl), #47
        ld      bc, #063F
        ldir
        ld      hl, #C1C1
        ld      de, #C1C2
        ld      (hl), #47
        ld      bc, #063F
        ldir

        ld      hl, #E1C0
        ld      de, #E1C1
        ld      (hl), #4F
        ld      bc, #02FF
        ldir
        ld      hl, #C1C1
        ld      de, #C1C2
        ld      (hl), #4F
        ld      bc, #02FF
        ldir

        ; Lower log area: black background, green foreground.
        ld      hl, #E4C0
        ld      de, #E4C1
        ld      (hl), #44
        ld      bc, #033F
        ldir
        ld      hl, #C4C1
        ld      de, #C4C2
        ld      (hl), #44
        ld      bc, #033F
        ldir

        call    p126_screen_restore_host_pages
        xor     a
        ld      (bios_dbg_row), a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        ld      a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

BIOS_DebugConsole_DrawInterface::
        push    af
        push    bc
        push    hl

        ld      hl, p126_ui_line0
        ld      a, 0
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt

        ld      hl, p126_ui_line1
        ld      a, 1
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt

        ld      hl, p126_ui_line11
.p126_draw_rtc_line:
        ld      a, 11
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt

        pop     hl
        pop     bc
        pop     af
        ret

; IN: HL=zero-terminated text, A=absolute row 0..24, C=column 0..79.
; Every static UI character is mirrored to port #EF.
BIOS_DebugConsole_PrintAt::
        push    af
        push    bc
        push    de
        push    hl
        call    p127_w3_ui_enter
        jp      c,.p126_print_at_denied
        ; The lease routine uses A; restore the complete caller frame before
        ; consuming the PrintAt row/column parameters.
        pop     hl
        pop     de
        pop     bc
        pop     af
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_text_ptr), hl
        ld      (bios_dbg_print_row), a
        ld      a, c
        ld      (bios_dbg_print_col), a
.p126_print_at_loop:
        ld      hl, (bios_dbg_text_ptr)
        ld      a, (hl)
        or      a
        jp      z, .p126_print_at_done
        ld      (bios_dbg_char), a
        inc     hl
        ld      (bios_dbg_text_ptr), hl
        ld      a, (bios_dbg_print_row)
        ld      d, a
        ld      a, (bios_dbg_print_col)
        ld      e, a
        ld      a, (bios_dbg_char)
        push    af
        ld      bc,P127_UI_DEBUG_PORT
        out     (c),a
        pop     af
        call    p126_screen_write_char
        ld      a, (bios_dbg_print_col)
        inc     a
        cp      BIOS_DEBUG_COLUMNS
        jp      c, .p126_print_at_col_ok
        xor     a
        ld      (bios_dbg_print_col), a
        ld      a, (bios_dbg_print_row)
        inc     a
        ld      (bios_dbg_print_row), a
        jp      .p126_print_at_loop
.p126_print_at_col_ok:
        ld      (bios_dbg_print_col), a
        jp      .p126_print_at_loop
.p126_print_at_done:
        call    p127_w3_ui_leave
        ld      bc,P127_UI_DEBUG_PORT
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
.p126_print_at_denied:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=character. CR/LF/BS are handled; printable ASCII is rendered.
BIOS_DebugConsole_PrintChar::
        push    af
        call    p127_w3_ui_enter
        jp      c,.p126_console_denied
        pop     af
        push    af
        push    bc
        ld      bc,P127_UI_DEBUG_PORT
        out     (c),a
        pop     bc
        push    bc
        push    de
        push    hl
        cp      13
        jp      z, .p126_console_cr
        cp      10
        jp      z, .p126_console_lf
        cp      8
        jp      z, .p126_console_bs
        cp      32
        jp      c, .p126_console_done
        cp      128
        jp      c, .p126_console_char_ok
        ld      a, '?'
.p126_console_char_ok:
        ld      (bios_dbg_char), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      d, a
        ld      a, (bios_dbg_col)
        ld      e, a
        ld      a, (bios_dbg_char)
        call    p126_screen_write_char
        ld      a, (bios_dbg_col)
        inc     a
        cp      BIOS_DEBUG_COLUMNS
        jp      c, .p126_console_store_col
        xor     a
        ld      (bios_dbg_col), a
        call    bios_dbg_newline
        jp      .p126_console_sync_cursor
.p126_console_store_col:
        ld      (bios_dbg_col), a
.p126_console_sync_cursor:
        ld      a, (bios_dbg_col)
        ld      (Console_X), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        jp      .p126_console_done
.p126_console_cr:
        xor     a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        jp      .p126_console_done
.p126_console_lf:
        call    bios_dbg_newline
        jp      .p126_console_sync_cursor
.p126_console_bs:
        ld      a, (bios_dbg_col)
        or      a
        jp      z, .p126_console_done
        dec     a
        ld      (bios_dbg_col), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      d, a
        ld      a, (bios_dbg_col)
        ld      e, a
        ld      a, 32
        call    p126_screen_write_char
        jp      .p126_console_sync_cursor
.p126_console_done:
        call    p127_w3_ui_leave
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
.p126_console_denied:
        pop     af
        ret


p126_screen_write_char:
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_char), a
        ld      a, d
        ld      (bios_dbg_write_row), a
        ld      a, e
        ld      (bios_dbg_write_col), a

        call    p126_screen_map_video_pages

        ; Offset = #01C0 + row*64 + column/2.
        ld      a, (bios_dbg_write_row)
        ld      l, a
        ld      h, 0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      de, #01C0
        add     hl, de
        ld      a, (bios_dbg_write_col)
        ld      c, a
        and     1
        ld      (bios_dbg_parity), a
        ld      a, c
        srl     a
        ld      e, a
        ld      d, 0
        add     hl, de
        ld      (bios_dbg_offset), hl

        ; Header rows use blue/white; the lower log uses green/black.
        ld      a, (bios_dbg_write_row)
        cp      BIOS_DEBUG_TOP
        ld      a, #44
        jp      nc, .p126_attr_ready
        ld      a, #4F
.p126_attr_ready:
        ld      (bios_dbg_attr), a

        ld      hl, (bios_dbg_offset)
        ld      a, (bios_dbg_parity)
        or      a
        jp      nz, .p126_write_odd

        ld      de, #4000
        add     hl, de
        ld      a, (bios_dbg_char)
        ld      (hl), a
        ld      hl, (bios_dbg_offset)
        ld      de, #E000
        add     hl, de
        ld      a, (bios_dbg_attr)
        ld      (hl), a
        jp      .p126_write_done

.p126_write_odd:
        ld      de, #6000
        add     hl, de
        ld      a, (bios_dbg_char)
        ld      (hl), a
        ld      hl, (bios_dbg_offset)
        ld      de, #C000
        add     hl, de
        inc     hl
        ld      a, (bios_dbg_attr)
        ld      (hl), a

.p126_write_done:
        call    p126_screen_restore_host_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=character, B=ATM-native attribute, D=row, E=column.

p126_screen_map_video_pages:
        ld      a, P126_VIDEO_PAGE7
        ld      bc, #7FF7
        out     (c), a
        ld      a, P126_VIDEO_PAGE3
        ld      bc, #FFF7
        out     (c), a
        ret

p126_screen_restore_host_pages:
        ld      a, P126_HOST_PAGE5
        ld      bc, #7FF7
        out     (c), a
        ld      a, P126_HOST_PAGE0
        ld      bc, #FFF7
        out     (c), a
        ret


; Advance one row in the 13-row log; scroll rows 13..24 at the bottom.
bios_dbg_newline:
        ld      a, (bios_dbg_row)
        inc     a
        cp      BIOS_DEBUG_ROWS
        jp      c, .p126_newline_store
        call    P126_ScrollConsoleUp
        ld      a, BIOS_DEBUG_ROWS - 1
.p126_newline_store:
        ld      (bios_dbg_row), a
        xor     a
        ld      (bios_dbg_col), a
        ret

; Move log rows 13..24 up by one. Each hardware text row has a 64-byte
; stride; the 40 visible bytes are copied together with the row padding.
P126_ScrollConsoleUp::
        push    af
        push    bc
        push    de
        push    hl
        call    p126_screen_map_video_pages

        ; Even character plane: page 7, window #4000.
        ld      hl, #4500
        ld      de, #44C0
        ld      bc, #0300
        ldir
        ; Odd character plane: page 7, window #6000.
        ld      hl, #6500
        ld      de, #64C0
        ld      bc, #0300
        ldir
        ; Even attributes: page 3, window #E000.
        ld      hl, #E500
        ld      de, #E4C0
        ld      bc, #0300
        ldir
        ; Odd attributes: page 3, window #C000, odd-byte skew +1.
        ld      hl, #C501
        ld      de, #C4C1
        ld      bc, #0300
        ldir

        ; Clear the new bottom row.
        ld      hl, #47C0
        ld      de, #47C1
        ld      (hl), 32
        ld      bc, #003F
        ldir
        ld      hl, #67C0
        ld      de, #67C1
        ld      (hl), 32
        ld      bc, #003F
        ldir
        ld      hl, #E7C0
        ld      de, #E7C1
        ld      (hl), #44
        ld      bc, #003F
        ldir
        ld      hl, #C7C1
        ld      de, #C7C2
        ld      (hl), #44
        ld      bc, #003F
        ldir

        call    p126_screen_restore_host_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret


p126_ui_line0: db "PROJECT127 | ATM TURBO 2+ | SYSTEM CORE",0
p126_ui_line1: db "SYSTEM STARTUP / HARDWARE DIAGNOSTICS",0
p126_ui_line11: db "RTC: NOT INITIALIZED | SYSTEM READY",0

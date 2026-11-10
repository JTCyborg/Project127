; ============================================================================
; Project127 — ATM XT keyboard interface
; Version: 0.2.2
;
; ATM Turbo 2+ host reads the Unreal Speccy ATM_KBD interface through ULA
; port #FE. The emulator must have [Input] ATMKBD=1.
;
; ATM_KBD protocol:
;   read B=#55 -> #AA handshake
;   read B=#08 -> command 8 (select mode)
;   read B=mode -> #FF acknowledgement
;   mode 2: B=#00/#40/#80/#C0 reads R2/R3/R4/R5
;   mode 3: B=#00 reads and clears lastscan
;
; No NeoGS, DMA mailbox, external keyboard controller or IRQ is assumed.
; If ATMKBD is disabled, retain a ZX 8x5 matrix diagnostic fallback only.
; IM/EI remain disabled.
; ============================================================================
P127_KBD_PORT              EQU #FE
P127_KBD_MODE_XT           EQU 2
P127_KBD_MODE_EVENT        EQU 3
; 5120 paced windows ~= 10 s at the ATM Turbo 2+ 7 MHz test clock.
P127_KBD_IDLE_WINDOWS       EQU #1400
P127_KBD_ROW_MASK          EQU #1F

; Public boot monitor. All reads are performed by the ATM Z80.
p127_keyboard_monitor:
        xor     a
        ld      (p127_kbd_xt_active),a
        ld      (p127_kbd_snapshot_valid),a
        ld      hl,p127_kbd_msg_init
        call    p127_puts
        call    p127_keyboard_reset_idle

        ld      a,P127_KBD_MODE_XT
        call    p127_keyboard_set_mode
        jr      c,p127_keyboard_legacy_init

        ld      a,1
        ld      (p127_kbd_xt_active),a
        ld      hl,p127_kbd_msg_xt_ready
        call    p127_puts
        jr      p127_keyboard_monitor_loop

p127_keyboard_legacy_init:
        ld      hl,p127_kbd_msg_legacy
        call    p127_puts

p127_keyboard_monitor_loop:
        xor     a
        ld      (p127_kbd_activity),a
        ld      a,(p127_kbd_xt_active)
        or      a
        jr      z,p127_keyboard_monitor_legacy
        call    p127_keyboard_poll_xt
        jr      p127_keyboard_monitor_pace
p127_keyboard_monitor_legacy:
        call    p127_keyboard_poll_matrix
p127_keyboard_monitor_pace:
        ; Any make/break or modifier/matrix transition restarts the idle window.
        ld      a,(p127_kbd_activity)
        or      a
        call    nz,p127_keyboard_reset_idle
        ; Bounded software pacing; no PIT or interrupt dependency.
        ld      de,#0200
p127_keyboard_monitor_delay:
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_keyboard_monitor_delay
        ld      hl,(p127_kbd_idle_windows)
        dec     hl
        ld      (p127_kbd_idle_windows),hl
        ld      a,h
        or      l
        jr      nz,p127_keyboard_monitor_loop
        ld      hl,p127_kbd_msg_done
        call    p127_puts
        jp      p127_idle

; Enter ATM_KBD mode A using the exact Unreal Speccy ATM_KBD::read handshake.
; Carry is set if any of the three protocol responses is unexpected.
p127_keyboard_set_mode:
        ld      (p127_kbd_requested_mode),a
        ld      bc,#55FE
        in      a,(c)
        cp      #AA
        jr      nz,p127_keyboard_mode_fail
        ld      bc,#08FE
        in      a,(c)
        cp      8
        jr      nz,p127_keyboard_mode_fail
        ld      a,(p127_kbd_requested_mode)
        ld      b,a
        ld      c,P127_KBD_PORT
        in      a,(c)
        cp      #FF
        jr      nz,p127_keyboard_mode_fail
        or      a
        ret
p127_keyboard_mode_fail:
        scf
        ret

; Read mode 2 registers. R2 is read-to-clear; R3/R4/R5 are state registers.
p127_keyboard_read_mode2:
        ld      bc,#00FE
        in      a,(c)
        ld      (p127_kbd_r2),a
        ld      bc,#40FE
        in      a,(c)
        ld      (p127_kbd_r3),a
        ld      bc,#80FE
        in      a,(c)
        ld      (p127_kbd_r4),a
        ld      bc,#C0FE
        in      a,(c)
        ld      (p127_kbd_r5),a
        ret

; Poll one event plus the current ATM modifier/extended-key registers.
; lastscan bit 7 means key release. R5 carries key-class/extended metadata.
p127_keyboard_poll_xt:
        call    p127_keyboard_read_mode2
        ld      a,P127_KBD_MODE_EVENT
        call    p127_keyboard_set_mode
        jr      c,p127_keyboard_xt_recover
        ld      bc,#00FE
        in      a,(c)
        ld      (p127_kbd_lastscan),a

        ld      a,P127_KBD_MODE_XT
        call    p127_keyboard_set_mode
        jr      c,p127_keyboard_xt_recover

        ld      a,(p127_kbd_lastscan)
        or      a
        jr      nz,p127_keyboard_xt_activity
        ld      a,(p127_kbd_r3)
        ld      b,a
        ld      a,(p127_kbd_prev_r3)
        cp      b
        jr      nz,p127_keyboard_xt_activity
        ld      a,(p127_kbd_r4)
        ld      b,a
        ld      a,(p127_kbd_prev_r4)
        cp      b
        jr      nz,p127_keyboard_xt_activity
        ld      a,(p127_kbd_r5)
        ld      b,a
        ld      a,(p127_kbd_prev_r5)
        cp      b
        ret     z

p127_keyboard_xt_activity:
        ld      a,1
        ld      (p127_kbd_activity),a
p127_keyboard_xt_log:
        call    p127_keyboard_log_xt
        ld      a,(p127_kbd_r3)
        ld      (p127_kbd_prev_r3),a
        ld      a,(p127_kbd_r4)
        ld      (p127_kbd_prev_r4),a
        ld      a,(p127_kbd_r5)
        ld      (p127_kbd_prev_r5),a
        ret

; If mode switching fails, retry the mode-2 handshake on the next pass.
p127_keyboard_xt_recover:
        ld      a,P127_KBD_MODE_XT
        call    p127_keyboard_set_mode
        ret

p127_keyboard_log_xt:
        ld      hl,p127_kbd_msg_event
        call    p127_puts
        ld      a,(p127_kbd_lastscan)
        call    p127_put_hex8
        ld      hl,p127_kbd_msg_r2
        call    p127_puts
        ld      a,(p127_kbd_r2)
        call    p127_put_hex8
        ld      hl,p127_kbd_msg_r3
        call    p127_puts
        ld      a,(p127_kbd_r3)
        call    p127_put_hex8
        ld      hl,p127_kbd_msg_r4
        call    p127_puts
        ld      a,(p127_kbd_r4)
        call    p127_put_hex8
        ld      hl,p127_kbd_msg_r5
        call    p127_puts
        ld      a,(p127_kbd_r5)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        ret

; Compatibility fallback when ATMKBD=1 is not enabled in the emulator.
p127_keyboard_poll_matrix:
        call    p127_keyboard_scan_matrix
        ld      a,(p127_kbd_snapshot_valid)
        or      a
        jr      z,p127_keyboard_matrix_changed
        ld      hl,p127_kbd_matrix
        ld      de,p127_kbd_previous
        ld      b,8
p127_keyboard_matrix_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_keyboard_matrix_changed
        inc     de
        inc     hl
        djnz    p127_keyboard_matrix_compare
        ret
p127_keyboard_matrix_changed:
        ld      a,1
        ld      (p127_kbd_activity),a
        ld      hl,p127_kbd_matrix
        ld      de,p127_kbd_previous
        ld      bc,8
        ldir
        ld      a,1
        ld      (p127_kbd_snapshot_valid),a
        ld      hl,p127_kbd_msg_matrix
        call    p127_puts
        ld      hl,p127_kbd_matrix
        ld      b,8
p127_keyboard_matrix_log_loop:
        push    bc
        push    hl
        ld      a,(hl)
        call    p127_put_hex8
        ld      a,' '
        call    p127_put_char
        pop     hl
        pop     bc
        inc     hl
        djnz    p127_keyboard_matrix_log_loop
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        ret

p127_keyboard_scan_matrix:
        push    bc
        push    de
        push    hl
        ld      c,P127_KBD_PORT
        ld      b,#FE
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+0),a
        ld      b,#FD
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+1),a
        ld      b,#FB
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+2),a
        ld      b,#F7
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+3),a
        ld      b,#EF
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+4),a
        ld      b,#DF
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+5),a
        ld      b,#BF
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+6),a
        ld      b,#7F
        in      a,(c)
        and     P127_KBD_ROW_MASK
        ld      (p127_kbd_matrix+7),a
        pop     hl
        pop     de
        pop     bc
        ret

p127_kbd_msg_init:
        db "[KBD v0.2.2] INIT",13,10,0
p127_kbd_msg_xt_ready:
        db "[KBD] ATM XT ACTIVE",13,10,0
p127_kbd_msg_legacy:
        db "[KBD] ZX MATRIX FALLBACK",13,10,0
p127_kbd_msg_event:
        db "[KBD] LAST=",0
p127_kbd_msg_r2:
        db " R2=",0
p127_kbd_msg_r3:
        db " R3=",0
p127_kbd_msg_r4:
        db " R4=",0
p127_kbd_msg_r5:
        db " R5=",0
p127_kbd_msg_matrix:
        db "[KBD] ZX MATRIX=",0
p127_kbd_msg_done:
        db "[KBD] TEST COMPLETE; 10S IDLE",13,10,0

p127_kbd_idle_windows:
        dw P127_KBD_IDLE_WINDOWS
p127_kbd_activity:
        db 0

p127_keyboard_reset_idle:
        ld      hl,P127_KBD_IDLE_WINDOWS
        ld      (p127_kbd_idle_windows),hl
        ret

p127_kbd_requested_mode:
        db 0
p127_kbd_xt_active:
        db 0
p127_kbd_lastscan:
        db 0
p127_kbd_r2:
        db 0
p127_kbd_r3:
        db 0
p127_kbd_r4:
        db 0
p127_kbd_r5:
        db 0
p127_kbd_prev_r3:
        db #FF
p127_kbd_prev_r4:
        db #FF
p127_kbd_prev_r5:
        db #FF
p127_kbd_matrix:
        ds 8,#1F
p127_kbd_previous:
        ds 8,#1F
p127_kbd_snapshot_valid:
        db 0

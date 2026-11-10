; ============================================================================
; Project127 — ATM keyboard matrix scanner + NeoGS DMA mailbox
; Version: 0.1.0
;
; ATM Z80 owns the physical Spectrum-compatible keyboard matrix.
; Eight active-low rows are sampled on the ATM host. The unchanged eight-byte
; snapshot is sent to NeoGS through the established host-to-NeoGS ZX DMA path.
; GSCOM is used only for CMD_HOST_INPUT / DMA_END doorbells; no DBIT/GSDAT
; payload transfer and no NeoGS-local external-device I/O are used here.
;
; Mailbox contract (Project125):
;   CMD_HOST_INPUT = #10
;   NeoGS arms ZX DMA to physical #00F000 (page 03, offset 3000)
;   ATM writes eight bytes through DMA aperture #0000..#3FFF
;   CMD_DMA_END = #FF; NeoGS disables DMA and acknowledges via CBIT clear.
; ============================================================================
P127_KBD_GSCOM             EQU #BB
P127_KBD_GSSTAT            EQU #BB
P127_KBD_CBIT              EQU 0
P127_KBD_CMD_HOST_INPUT    EQU #10
P127_KBD_CMD_DMA_END       EQU #FF
P127_KBD_DMA_WINDOW        EQU #0000
P127_KBD_MATRIX_BYTES      EQU 8
P127_KBD_ROW_MASK          EQU #1F
P127_KBD_TIMEOUT_WINDOWS   EQU 8

; Public: continuously scan, report changed snapshots and publish them to NeoGS.
; This is the boot-time input acceptance monitor; it does not enable IRQ/IM/EI.
p127_keyboard_monitor:
        xor     a
        ld      (p127_kbd_snapshot_valid),a
        ld      hl,p127_kbd_msg_monitor
        call    p127_puts

p127_keyboard_monitor_loop:
        call    p127_keyboard_poll
        ; Short bounded software pacing. No PIT or interrupt dependency.
        ld      de,#0200
p127_keyboard_monitor_delay:
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_keyboard_monitor_delay
        jr      p127_keyboard_monitor_loop

; Sample all eight Spectrum matrix rows. C=#FE selects the keyboard port;
; B selects the row. Bit 0..4 are active-low columns.
; OUT: p127_kbd_matrix[0..7]. Clobbers AF; preserves BC/DE/HL.
p127_keyboard_scan:
        push    bc
        push    de
        push    hl
        ld      c,#FE
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

; Scan once. First snapshot is always published; later snapshots are sent only
; when at least one of the eight row bytes changes.
p127_keyboard_poll:
        call    p127_keyboard_scan
        ld      a,(p127_kbd_snapshot_valid)
        or      a
        jr      z,p127_keyboard_snapshot_changed

        ld      hl,p127_kbd_matrix
        ld      de,p127_kbd_previous
        ld      b,P127_KBD_MATRIX_BYTES
p127_keyboard_compare_loop:
        ld      a,(de)
        cp      (hl)
        jr      nz,p127_keyboard_snapshot_changed
        inc     de
        inc     hl
        djnz    p127_keyboard_compare_loop
        ret

p127_keyboard_snapshot_changed:
        ld      hl,p127_kbd_matrix
        ld      de,p127_kbd_previous
        ld      bc,P127_KBD_MATRIX_BYTES
        ldir
        ld      a,1
        ld      (p127_kbd_snapshot_valid),a

        call    p127_keyboard_log_matrix
        call    p127_keyboard_dma_send
        ret

; Print all eight raw active-low row bytes. A pressed key clears its column bit.
p127_keyboard_log_matrix:
        ld      hl,p127_kbd_msg_matrix
        call    p127_puts
        ld      hl,p127_kbd_matrix
        ld      b,P127_KBD_MATRIX_BYTES
p127_keyboard_log_matrix_loop:
        push    bc
        push    hl
        ld      a,(hl)
        call    p127_put_hex8
        ld      a,' '
        call    p127_put_char
        pop     hl
        pop     bc
        inc     hl
        djnz    p127_keyboard_log_matrix_loop
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        ret

; ATM host-to-NeoGS DMA transaction. NeoGS owns DMA register programming.
; Do not log or call UI code between READY and the final payload byte/END.
p127_keyboard_dma_send:
        ld      a,P127_KBD_CMD_HOST_INPUT
        out     (P127_KBD_GSCOM),a
        call    p127_keyboard_dma_wait_cbit_clear
        jr      c,p127_keyboard_dma_ready_timeout

        ld      hl,p127_kbd_matrix
        ld      de,P127_KBD_DMA_WINDOW
        ld      bc,P127_KBD_MATRIX_BYTES
        ldir

        ld      a,P127_KBD_CMD_DMA_END
        out     (P127_KBD_GSCOM),a
        call    p127_keyboard_dma_wait_cbit_clear
        jr      c,p127_keyboard_dma_end_timeout

        ld      hl,p127_kbd_msg_dma_ok
        call    p127_puts
        or      a
        ret

p127_keyboard_dma_ready_timeout:
        ld      hl,p127_kbd_msg_dma_ready_timeout
        call    p127_puts
        scf
        ret

p127_keyboard_dma_end_timeout:
        ld      hl,p127_kbd_msg_dma_end_timeout
        call    p127_puts
        scf
        ret

; Wait for NeoGS to clear CBIT. Eight independent #FFFF windows match the
; bounded Project125/126 host transport watchdog. OUT: carry set on timeout.
p127_keyboard_dma_wait_cbit_clear:
        ld      d,P127_KBD_TIMEOUT_WINDOWS
p127_keyboard_dma_wait_outer:
        ld      bc,#FFFF
p127_keyboard_dma_wait_inner:
        in      a,(P127_KBD_GSSTAT)
        bit     P127_KBD_CBIT,a
        jr      z,p127_keyboard_dma_wait_ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,p127_keyboard_dma_wait_inner
        dec     d
        jr      nz,p127_keyboard_dma_wait_outer
        scf
        ret
p127_keyboard_dma_wait_ok:
        or      a
        ret

p127_kbd_msg_monitor:
        db "[KBD] ATM 8X5 MATRIX MONITOR; ACTIVE-LOW; IRQ DISABLED",13,10,0
p127_kbd_msg_matrix:
        db "[KBD] MATRIX=",0
p127_kbd_msg_dma_ok:
        db "[KBD] DMA OK",13,10,0
p127_kbd_msg_dma_ready_timeout:
        db "[KBD] DMA READY TIMEOUT",13,10,0
p127_kbd_msg_dma_end_timeout:
        db "[KBD] DMA END TIMEOUT",13,10,0

p127_kbd_matrix:
        ds P127_KBD_MATRIX_BYTES,#1F
p127_kbd_previous:
        ds P127_KBD_MATRIX_BYTES,#1F
p127_kbd_snapshot_valid:
        db 0

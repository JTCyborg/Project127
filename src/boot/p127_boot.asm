; ============================================================================
; Project127 — milestone 0: minimal ATM host entry
; Target: ATM Turbo 2+ Z80
; Load/entry address: 6000h
; No device initialization is permitted in this milestone.
; ============================================================================

        DEVICE ZXSPECTRUM128

P127_LOAD_ADDRESS  EQU 06000h
P127_STACK_TOP     EQU 0BFFFh
P127_DEBUG_PORT    EQU 00EFh

        ORG P127_LOAD_ADDRESS

p127_entry:
        jp      p127_start
        defs    6, 0

p127_start:
        di
        ld      sp, P127_STACK_TOP

        ld      hl, p127_msg_start
        call    p127_puts

        ld      hl, p127_msg_ok
        call    p127_puts

p127_idle:
        jr      p127_idle

; Input: HL -> zero-terminated string.
p127_puts:
        ld      a, (hl)
        or      a
        ret     z
        inc     hl
        push    hl
        ld      bc, P127_DEBUG_PORT
        out     (c), a
        pop     hl
        jr      p127_puts

p127_msg_start:
        db      "P127 START", 13, 10, 0

p127_msg_ok:
        db      "P127 BOOT0 OK", 13, 10, 0

p127_end:

        ASSERT  p127_entry = P127_LOAD_ADDRESS
        ASSERT  p127_end > p127_entry

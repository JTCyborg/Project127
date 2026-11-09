; ============================================================================
; Project127 ATM Core — linked kernel image layout measurement
; Module version: 0.1.0
;
; Measures the actual assembled Stage2 kernel span [p127_entry,p127_end).
; It is not a fixed reservation: the linked end label determines the size.
; The current loader contract places the image at 6000h and bounds it by A000h.
; Both live host pages used by that CPU window (P5 and P2) must be RESERVED.
; This module validates placement only; it does not relocate or map pages.
; ============================================================================
P127_LAYOUT_VERSION_MAJOR EQU 0
P127_LAYOUT_VERSION_MINOR EQU 1
P127_LAYOUT_VERSION_PATCH EQU 0
P127_LAYOUT_START         EQU 06000h
P127_LAYOUT_LIMIT         EQU 0A000h
P127_LAYOUT_MAX_BYTES     EQU P127_LAYOUT_LIMIT-P127_LAYOUT_START

p127_layout_selftest:
        ; The linked entry must match the BASIC loader's CODE address.
        ld      hl,p127_entry
        ld      de,P127_LAYOUT_START
        or      a
        sbc     hl,de
        jp      nz,p127_layout_reject

        ; Require a non-empty image and an end no higher than the UI window.
        ld      hl,p127_end
        ld      de,p127_entry
        or      a
        sbc     hl,de
        jp      c,p127_layout_reject
        jp      z,p127_layout_reject
        ld      (p127_kernel_size),hl
        ld      a,h
        cp      041h
        jp      nc,p127_layout_reject

        ld      hl,p127_end
        ld      de,P127_LAYOUT_LIMIT
        or      a
        sbc     hl,de
        jp      c,p127_layout_end_ok
        jp      z,p127_layout_end_ok
        jp      p127_layout_reject
p127_layout_end_ok:
        ; P5 backs the #6000..#7FFF portion; P2 backs #8000..#9FFF.
        ld      a,(p127_mem_page_state+5)
        cp      P127_MEM_RESERVED
        jp      nz,p127_layout_reject
        ld      a,(p127_mem_page_state+2)
        cp      P127_MEM_RESERVED
        jp      nz,p127_layout_reject
        or      a
        ret

p127_layout_reject:
        scf
        ret

; Report the measured byte count in hexadecimal, high byte first.
p127_layout_report:
        ld      hl,p127_msg_kernel_size
        call    p127_puts
        ld      a,(p127_kernel_size+1)
        call    p127_put_hex8
        ld      a,(p127_kernel_size)
        call    p127_put_hex8
        ld      hl,p127_msg_kernel_size_tail
        jp      p127_puts

p127_kernel_size:
        dw      0
p127_msg_kernel_size:
        db      "[P127] KERNEL IMAGE SIZE=0x",0
p127_msg_kernel_size_tail:
        db      " BYTES; P5/P2 BOUNDS PASS",13,10,0

ASSERT P127_LAYOUT_MAX_BYTES = 04000h
ASSERT p127_entry = P127_LAYOUT_START
ASSERT p127_end <= P127_LAYOUT_LIMIT

; ============================================================================
; Project127 ATM Turbo 2+ beeper output driver
; Module version: 0.1.0
;
; Hardware: Spectrum/ATM #FE, D4 = speaker, D3 = tape output,
; D0..D2 = border colour. OUT (#FE),A also presents A3 from A's bit 3
; on ATM, so the caller-supplied D3 state is preserved.
;
; This is a low-level output latch only. It does not invent a timer,
; enable interrupts, block the main loop, or emulate an IBM PC speaker.
; The Z80 host owns this physical port. NeoGS must request sound through
; the host transport/DMA and must never issue physical port I/O.
;
; API:
;   p127_speaker_init  IN A = initial #FE low nibble (border + tape)
;   p127_speaker_set   IN A bit 0 = speaker level (0/1)
;   p127_speaker_toggle
;   p127_speaker_stop
;   p127_speaker_get   OUT A = shadow latch
;
; Caller must initialize with the actual current border/tape state before
; using set/toggle/stop. No safe hardware readback of the #FE output latch
; is assumed.
; ============================================================================
P127_SPEAKER_VERSION_MAJOR EQU 0
P127_SPEAKER_VERSION_MINOR EQU 1
P127_SPEAKER_VERSION_PATCH EQU 0

P127_SPEAKER_PORT EQU 0FEh
P127_SPEAKER_MASK EQU 010h
P127_SPEAKER_LOW_MASK EQU 00Fh

p127_speaker_init:
        and     P127_SPEAKER_LOW_MASK
        ld      (p127_speaker_shadow),a
        ret

; Set D4 while preserving border D0..D2 and tape D3.
; OUT (#FE),A intentionally uses A3 as part of the ATM border/BRIGHT
; address decode; preserving D3 also preserves that address-line state.
p127_speaker_set:
        push    bc
        ld      b,a
        ld      a,(p127_speaker_shadow)
        and     P127_SPEAKER_LOW_MASK
        ld      c,a
        ld      a,b
        and     1
        jr      z,p127_speaker_set_low
        ld      a,c
        or      P127_SPEAKER_MASK
        jr      p127_speaker_write
p127_speaker_set_low:
        ld      a,c
p127_speaker_write:
        ld      (p127_speaker_shadow),a
        out     (P127_SPEAKER_PORT),a
        pop     bc
        ret

; Invert only D4. Border/tape state remains unchanged.
p127_speaker_toggle:
        ld      a,(p127_speaker_shadow)
        xor     P127_SPEAKER_MASK
        ld      (p127_speaker_shadow),a
        out     (P127_SPEAKER_PORT),a
        ret

; Force speaker low without changing D0..D3.
p127_speaker_stop:
        ld      a,(p127_speaker_shadow)
        and     0EFh
        ld      (p127_speaker_shadow),a
        out     (P127_SPEAKER_PORT),a
        ret

p127_speaker_get:
        ld      a,(p127_speaker_shadow)
        ret


; Audible hardware smoke test. Approximately 0.5 s at 7 MHz or 1 s at
; 3.5 MHz; pitch therefore depends on the active ATM CPU clock. This is
; intentionally a one-shot diagnostic, not the asynchronous sound service.
; A=low #FE nibble to preserve (caller must supply the live border/tape state).
p127_speaker_test_tone:
        push    af
        push    bc
        push    de
        push    hl
        and     P127_SPEAKER_LOW_MASK
        call    p127_speaker_init
        ld      de,0600h
p127_speaker_test_loop:
        call    p127_speaker_toggle
        ld      b,0FFh
p127_speaker_test_delay1:
        djnz    p127_speaker_test_delay1
        ld      b,0FFh
p127_speaker_test_delay2:
        djnz    p127_speaker_test_delay2
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_speaker_test_loop
        call    p127_speaker_stop
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p127_speaker_shadow: db 0

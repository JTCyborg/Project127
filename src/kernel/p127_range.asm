; ============================================================================
; Project127 ATM Core — UINT32 physical range validator
; Module version: 0.1.1
; ABI:
;   p127_range_start  = 4-byte little-endian physical start address
;   p127_range_length = 4-byte little-endian byte length
;   call p127_range_validate; carry=1 if invalid, clear if valid
; Semantics: half-open [start, start+length), bounded by 1 MiB.
; Zero-length ranges are valid when start <= 1 MiB.
; This is arithmetic/accounting only; it does not map or access RAM.
; ============================================================================
P127_RANGE_VERSION_MAJOR EQU 0
P127_RANGE_VERSION_MINOR EQU 1
P127_RANGE_VERSION_PATCH EQU 1
P127_RANGE_LIMIT         EQU 0100000h

p127_range_validate:
        ; Add the unsigned 32-bit length to the unsigned start.
        ld      hl,p127_range_start
        ld      de,p127_range_length
        ld      a,(hl)
        add     a,(de)
        ld      (p127_range_end),a
        inc     hl
        inc     de
        ld      a,(hl)
        adc     a,(de)
        ld      (p127_range_end+1),a
        inc     hl
        inc     de
        ld      a,(hl)
        adc     a,(de)
        ld      (p127_range_end+2),a
        inc     hl
        inc     de
        ld      a,(hl)
        adc     a,(de)
        ld      (p127_range_end+3),a
        ret     c                       ; unsigned 32-bit addition overflow

        ; End-exclusive address must be <= 0x00100000.
        ld      a,(p127_range_end+3)
        or      a
        jp      nz,p127_range_invalid
        ld      a,(p127_range_end+2)
        cp      010h
        jp      c,p127_range_valid
        jp      nz,p127_range_invalid
        ld      a,(p127_range_end+1)
        or      a
        jp      nz,p127_range_invalid
        ld      a,(p127_range_end)
        or      a
        jp      nz,p127_range_invalid
p127_range_valid:
        or      a
        ret
p127_range_invalid:
        scf
        ret

; Regression tests exercise the 1 MiB boundary, zero length and uint32 wrap.
; OUT: carry=1 on any failed assertion.
p127_range_selftest:
        ; [0, 0) is valid.
        xor     a
        ld      hl,p127_range_start
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      hl,p127_range_length
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        call    p127_range_validate
        jp      c,p127_range_test_fail

        ; Last byte of physical RAM: [0x000FFFFF, 0x00100000).
        ld      a,0FFh
        ld      (p127_range_start),a
        ld      a,0FFh
        ld      (p127_range_start+1),a
        ld      a,00Fh
        ld      (p127_range_start+2),a
        xor     a
        ld      (p127_range_start+3),a
        ld      a,1
        ld      (p127_range_length),a
        xor     a
        ld      (p127_range_length+1),a
        ld      (p127_range_length+2),a
        ld      (p127_range_length+3),a
        call    p127_range_validate
        jp      c,p127_range_test_fail

        ; One byte beyond the physical limit must fail.
        ld      a,2
        ld      (p127_range_length),a
        call    p127_range_validate
        jp      nc,p127_range_test_fail

        ; Entire physical address space [0, 1 MiB) is valid.
        xor     a
        ld      hl,p127_range_start
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      a,010h
        ld      (p127_range_length+2),a
        ld      a,0
        ld      (p127_range_length),a
        ld      (p127_range_length+1),a
        ld      (p127_range_length+3),a
        call    p127_range_validate
        jp      c,p127_range_test_fail

        ; start == 1 MiB with zero length is valid; one byte is not.
        ld      a,010h
        ld      (p127_range_start+2),a
        xor     a
        ld      (p127_range_start),a
        ld      (p127_range_start+1),a
        ld      (p127_range_start+3),a
        xor     a
        ld      (p127_range_length),a
        ld      (p127_range_length+1),a
        ld      (p127_range_length+2),a
        ld      (p127_range_length+3),a
        call    p127_range_validate
        jp      c,p127_range_test_fail
        ld      a,1
        ld      (p127_range_length),a
        call    p127_range_validate
        jp      nc,p127_range_test_fail

        ; 0xFFFFFFFF + 1 must be rejected as uint32 overflow.
        ld      a,0FFh
        ld      hl,p127_range_start
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      a,1
        ld      (p127_range_length),a
        xor     a
        ld      (p127_range_length+1),a
        ld      (p127_range_length+2),a
        ld      (p127_range_length+3),a
        call    p127_range_validate
        jp      nc,p127_range_test_fail

        or      a
        ret
p127_range_test_fail:
        scf
        ret

p127_range_start:
        ds      4,0
p127_range_length:
        ds      4,0
p127_range_end:
        ds      4,0

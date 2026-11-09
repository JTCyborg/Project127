; ============================================================================
; Project127 — managed logical span preflight
; Module version: 0.1.0
; Validates all logical pages touched by a UINT32 byte span before transfer.
; Metadata only: no byte access/copy, mapping, OUT, DMA, IRQ, IM or EI.
; ============================================================================
P127_AS_SPAN_VERSION_MAJOR EQU 0
P127_AS_SPAN_VERSION_MINOR EQU 1
P127_AS_SPAN_VERSION_PATCH EQU 0
P127_AS_SPAN_LIMIT_HI EQU 040h

; Input: p127_as_span_start and p127_as_span_length, uint32 little-endian.
; Carry clear if every page intersecting the span is mapped; carry set otherwise.
; Empty span accepts start in [0, 4 MiB], inclusive.
p127_as_span_check:
        ld      a,(p127_as_span_length)
        ld      b,a
        ld      a,(p127_as_span_length+1)
        or      b
        ld      b,a
        ld      a,(p127_as_span_length+2)
        or      b
        ld      b,a
        ld      a,(p127_as_span_length+3)
        or      b
        jp      z,p127_as_span_check_empty

        ld      a,(p127_as_span_start+3)
        or      a
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_start+2)
        cp      P127_AS_SPAN_LIMIT_HI
        jp      nc,p127_as_span_reject

        ; end = start + length; reject UINT32 overflow.
        ld      a,(p127_as_span_start)
        ld      b,a
        ld      a,(p127_as_span_length)
        add     a,b
        ld      (p127_as_span_end),a
        ld      a,(p127_as_span_start+1)
        ld      b,a
        ld      a,(p127_as_span_length+1)
        adc     a,b
        ld      (p127_as_span_end+1),a
        ld      a,(p127_as_span_start+2)
        ld      b,a
        ld      a,(p127_as_span_length+2)
        adc     a,b
        ld      (p127_as_span_end+2),a
        ld      a,(p127_as_span_start+3)
        ld      b,a
        ld      a,(p127_as_span_length+3)
        adc     a,b
        ld      (p127_as_span_end+3),a
        jp      c,p127_as_span_reject

        ; End-exclusive address may equal 4 MiB, but may not exceed it.
        ld      a,(p127_as_span_end+3)
        or      a
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_end+2)
        cp      P127_AS_SPAN_LIMIT_HI
        jp      c,p127_as_span_end_valid
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_end+1)
        or      a
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_end)
        or      a
        jp      nz,p127_as_span_reject

p127_as_span_end_valid:
        ; last = end - 1.
        ld      hl,(p127_as_span_end)
        ld      de,(p127_as_span_end+2)
        ld      a,h
        or      l
        jr      nz,p127_as_span_last_low_nonzero
        dec     de
p127_as_span_last_low_nonzero:
        dec     hl
        ld      (p127_as_span_last),hl
        ld      (p127_as_span_last+2),de

        ; Page index = (address[2] << 2) | (address[1] >> 6).
        ld      a,(p127_as_span_start+1)
        rrca
        rrca
        rrca
        rrca
        rrca
        rrca
        and     003h
        ld      b,a
        ld      a,(p127_as_span_start+2)
        add     a,a
        add     a,a
        or      b
        ld      (p127_as_span_first_page),a

        ld      a,(p127_as_span_last+1)
        rrca
        rrca
        rrca
        rrca
        rrca
        rrca
        and     003h
        ld      b,a
        ld      a,(p127_as_span_last+2)
        add     a,a
        add     a,a
        or      b
        ld      (p127_as_span_last_page),a

        ; Count = last - first + 1 (1..256).
        ld      a,(p127_as_span_last_page)
        ld      b,a
        ld      a,(p127_as_span_first_page)
        ld      c,a
        ld      a,b
        sub     c
        inc     a
        jr      nz,p127_as_span_count_ready
        ld      bc,0100h
        jr      p127_as_span_scan_setup
p127_as_span_count_ready:
        ld      c,a
        ld      b,0

p127_as_span_scan_setup:
        ld      a,(p127_as_span_first_page)
        ld      e,a
        ld      d,0
        ld      hl,p127_as_page_table
        add     hl,de
p127_as_span_scan:
        ld      a,(hl)
        cp      P127_AS_UNMAPPED
        jp      z,p127_as_span_reject
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,p127_as_span_scan
        or      a
        ret

p127_as_span_check_empty:
        ld      a,(p127_as_span_start+3)
        or      a
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_start+2)
        cp      P127_AS_SPAN_LIMIT_HI
        jp      c,p127_as_span_empty_ok
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_start+1)
        or      a
        jp      nz,p127_as_span_reject
        ld      a,(p127_as_span_start)
        or      a
        jp      nz,p127_as_span_reject
p127_as_span_empty_ok:
        or      a
        ret
p127_as_span_reject:
        scf
        ret

; Startup regression: two mapped adjacent pages, unmapped gap and 4 MiB edge.
p127_as_span_selftest:
        call    p127_as_init
        call    p127_mem_alloc
        jp      c,p127_as_span_test_fail
        ld      (p127_as_span_test_page_a),a
        call    p127_mem_alloc
        jp      c,p127_as_span_test_free_a
        ld      (p127_as_span_test_page_b),a

        ld      a,(p127_as_span_test_page_a)
        ld      b,a
        xor     a
        call    p127_as_bind
        jp      c,p127_as_span_test_free_b
        ld      a,(p127_as_span_test_page_b)
        ld      b,a
        ld      a,1
        call    p127_as_bind
        jp      c,p127_as_span_test_unbind_a

        ; Two bytes crossing 3FFFh/4000h require both mappings.
        ld      a,0FFh
        ld      (p127_as_span_start),a
        ld      a,03Fh
        ld      (p127_as_span_start+1),a
        xor     a
        ld      (p127_as_span_start+2),a
        ld      (p127_as_span_start+3),a
        ld      a,2
        ld      (p127_as_span_length),a
        xor     a
        ld      (p127_as_span_length+1),a
        ld      (p127_as_span_length+2),a
        ld      (p127_as_span_length+3),a
        call    p127_as_span_check
        jp      c,p127_as_span_test_unbind_b

        ; 7FFFh..8000h crosses into unmapped logical page 2.
        ld      a,0FFh
        ld      (p127_as_span_start),a
        ld      a,07Fh
        ld      (p127_as_span_start+1),a
        ld      a,2
        ld      (p127_as_span_length),a
        call    p127_as_span_check
        jp      nc,p127_as_span_test_unbind_b

        ; Empty span at 4 MiB is valid.
        xor     a
        ld      (p127_as_span_length),a
        ld      (p127_as_span_length+1),a
        ld      (p127_as_span_length+2),a
        ld      (p127_as_span_length+3),a
        ld      (p127_as_span_start),a
        ld      (p127_as_span_start+1),a
        ld      a,040h
        ld      (p127_as_span_start+2),a
        xor     a
        ld      (p127_as_span_start+3),a
        call    p127_as_span_check
        jp      c,p127_as_span_test_unbind_b

        ; Non-empty span at 4 MiB is invalid.
        ld      a,1
        ld      (p127_as_span_length),a
        call    p127_as_span_check
        jp      nc,p127_as_span_test_unbind_b

        ld      a,1
        call    p127_as_unbind
        jp      c,p127_as_span_test_unbind_b
        xor     a
        call    p127_as_unbind
        jp      c,p127_as_span_test_free_b
        ld      a,(p127_as_span_test_page_b)
        call    p127_mem_free
        jp      c,p127_as_span_test_free_a
        ld      a,(p127_as_span_test_page_a)
        call    p127_mem_free
        ret

p127_as_span_test_unbind_b:
        ld      a,1
        call    p127_as_unbind
p127_as_span_test_unbind_a:
        xor     a
        call    p127_as_unbind
p127_as_span_test_free_b:
        ld      a,(p127_as_span_test_page_b)
        call    p127_mem_free
p127_as_span_test_free_a:
        ld      a,(p127_as_span_test_page_a)
        call    p127_mem_free
p127_as_span_test_fail:
        scf
        ret

p127_as_span_start:
        ds      4,0
p127_as_span_length:
        ds      4,0
p127_as_span_end:
        ds      4,0
p127_as_span_last:
        ds      4,0
p127_as_span_first_page:
        db      0
p127_as_span_last_page:
        db      0
p127_as_span_test_page_a:
        db      0
p127_as_span_test_page_b:
        db      0

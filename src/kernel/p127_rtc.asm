; ============================================================================
; Project127 DS12887 real-time clock service
; Module version: 0.1.0
; Ported from Project126/atm_host/ds12887_rtc.asm.
; Read-only: no writes to RTC time/control registers.
; Native GLUK (#EFF7/#DFF7/#BFF7) first; SMUC (#FFBA/#DFBA) fallback.
; Public: p127_rtc_probe, p127_rtc_read_current.
; Time output buffers: p127_rtc_hour/minute/second (two ASCII digits each).
; ============================================================================
P127_RTC_VERSION_MAJOR EQU 0
P127_RTC_VERSION_MINOR EQU 1
P127_RTC_VERSION_PATCH EQU 0

p127_rtc_probe:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,p127_rtc_msg_probe
        call    p127_puts
        xor     a
        ld      (p127_rtc_backend),a
        call    p127_rtc_open
        call    p127_rtc_read_status
        call    p127_rtc_validate_status
        jr      nc,p127_rtc_probe_backend_ready
        call    p127_rtc_close
        ld      a,1
        ld      (p127_rtc_backend),a
        call    p127_rtc_open
        call    p127_rtc_read_status
        call    p127_rtc_validate_status
        jr      nc,p127_rtc_probe_backend_ready
        call    p127_rtc_close
        xor     a
        ld      (p127_rtc_available),a
        ld      hl,p127_rtc_msg_missing
        call    p127_puts
        jr      p127_rtc_probe_done

p127_rtc_probe_backend_ready:
        ld      a,1
        ld      (p127_rtc_available),a
        call    p127_rtc_close
        call    p127_rtc_read_current
        jr      c,p127_rtc_probe_read_failed
        ld      hl,p127_rtc_msg_time
        call    p127_puts
        ld      a,(p127_rtc_hour)
        call    p127_put_char
        ld      a,(p127_rtc_hour+1)
        call    p127_put_char
        ld      a,':'
        call    p127_put_char
        ld      a,(p127_rtc_minute)
        call    p127_put_char
        ld      a,(p127_rtc_minute+1)
        call    p127_put_char
        ld      a,':'
        call    p127_put_char
        ld      a,(p127_rtc_second)
        call    p127_put_char
        ld      a,(p127_rtc_second+1)
        call    p127_put_char
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        ld      hl,p127_rtc_msg_ready
        call    p127_puts
        jr      p127_rtc_probe_done

p127_rtc_probe_read_failed:
        xor     a
        ld      (p127_rtc_available),a
        ld      hl,p127_rtc_msg_read_failed
        call    p127_puts

p127_rtc_probe_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Public read API. Carry clear on success; carry set on unavailable hardware,
; UIP timeout or unstable seconds. Output buffers are always initialized.
p127_rtc_read_current:
        ld      a,(p127_rtc_available)
        or      a
        jr      nz,p127_rtc_read_current_open
        call    p127_rtc_set_unknown
        scf
        ret
p127_rtc_read_current_open:
        call    p127_rtc_open
        call    p127_rtc_read_snapshot
        jr      c,p127_rtc_read_current_failed
        call    p127_rtc_convert_snapshot
        call    p127_rtc_close
        or      a
        ret
p127_rtc_read_current_failed:
        call    p127_rtc_close
        call    p127_rtc_set_unknown
        scf
        ret

p127_rtc_set_unknown:
        ld      a,'?'
        ld      (p127_rtc_hour),a
        ld      (p127_rtc_hour+1),a
        ld      (p127_rtc_minute),a
        ld      (p127_rtc_minute+1),a
        ld      (p127_rtc_second),a
        ld      (p127_rtc_second+1),a
        ret

p127_rtc_read_status:
        ld      a,#0D
        call    p127_rtc_read_reg
        ld      (p127_rtc_status_d),a
        ld      a,#0A
        call    p127_rtc_read_reg
        ld      (p127_rtc_status_a),a
        ld      a,#0B
        call    p127_rtc_read_reg
        ld      (p127_rtc_status_b),a
        ret

p127_rtc_validate_status:
        ld      a,(p127_rtc_status_d)
        cp      #80
        jr      nz,p127_rtc_status_invalid
        ld      a,(p127_rtc_status_a)
        and     #70
        cp      #20
        jr      nz,p127_rtc_status_invalid
        or      a
        ret
p127_rtc_status_invalid:
        scf
        ret

; GLUK close must restore the resident DOSEN/RG6 path through the ROM.
p127_rtc_open:
        push    af
        push    bc
        ld      a,(p127_rtc_backend)
        or      a
        jr      nz,p127_rtc_open_smuc
        ld      bc,#EFF7
        ld      a,#80
        out     (c),a
        jr      p127_rtc_open_done
p127_rtc_open_smuc:
        ld      bc,#FFBA
        ld      a,#71
        out     (c),a
p127_rtc_open_done:
        pop     bc
        pop     af
        ret

p127_rtc_close:
        push    af
        push    bc
        ld      a,(p127_rtc_backend)
        or      a
        jr      nz,p127_rtc_close_done
        ld      bc,#EFF7
        xor     a
        out     (c),a
        call    p126_atm_restore_dosen
p127_rtc_close_done:
        pop     bc
        pop     af
        ret

; A=RTC register, returns byte in A. BC is preserved.
p127_rtc_read_reg:
        push    bc
        ld      c,a
        ld      a,(p127_rtc_backend)
        or      a
        jr      nz,p127_rtc_read_reg_smuc
        ld      a,c
        ld      bc,#DFF7
        out     (c),a
        ld      bc,#BFF7
        in      a,(c)
        pop     bc
        ret
p127_rtc_read_reg_smuc:
        ld      a,c
        ld      bc,#DFBA
        out     (c),a
        in      a,(c)
        pop     bc
        ret

; UIP-bounded, stable seconds/minutes/hours/seconds snapshot.
p127_rtc_read_snapshot:
        ld      b,4
p127_rtc_snapshot_retry:
        call    p127_rtc_wait_uip
        ret     c
        ld      a,#00
        call    p127_rtc_read_reg
        ld      (p127_rtc_seconds_raw),a
        ld      a,#02
        call    p127_rtc_read_reg
        ld      (p127_rtc_minutes_raw),a
        ld      a,#04
        call    p127_rtc_read_reg
        ld      (p127_rtc_hours_raw),a
        ld      a,#00
        call    p127_rtc_read_reg
        ld      c,a
        ld      a,(p127_rtc_seconds_raw)
        cp      c
        jr      z,p127_rtc_snapshot_stable
        djnz    p127_rtc_snapshot_retry
        scf
        ret
p127_rtc_snapshot_stable:
        ld      a,c
        ld      (p127_rtc_seconds_raw),a
        or      a
        ret

; 256 bounded polls maximum.
p127_rtc_wait_uip:
        push    bc
        ld      b,0
p127_rtc_uip_loop:
        ld      a,#0A
        call    p127_rtc_read_reg
        bit     7,a
        jr      nz,p127_rtc_uip_busy
        or      a
        pop     bc
        ret
p127_rtc_uip_busy:
        djnz    p127_rtc_uip_loop
        scf
        pop     bc
        ret

; Status B selects binary/BCD and 12/24-hour conversion.
p127_rtc_convert_snapshot:
        ld      a,(p127_rtc_hours_raw)
        ld      b,a
        ld      a,(p127_rtc_status_b)
        bit     1,a
        jr      nz,p127_rtc_hour_24
        ld      a,b
        and     #80
        ld      (p127_rtc_hour_pm),a
        ld      a,b
        and     #7F
        call    p127_rtc_to_binary
        ld      (p127_rtc_hour_binary),a
        ld      a,(p127_rtc_hour_pm)
        or      a
        jr      z,p127_rtc_hour_am
        ld      a,(p127_rtc_hour_binary)
        cp      12
        jr      z,p127_rtc_hour_ready
        add     a,12
        jr      p127_rtc_hour_ready
p127_rtc_hour_am:
        ld      a,(p127_rtc_hour_binary)
        cp      12
        jr      nz,p127_rtc_hour_ready
        xor     a
        jr      p127_rtc_hour_ready
p127_rtc_hour_24:
        ld      a,b
        call    p127_rtc_to_binary
p127_rtc_hour_ready:
        ld      hl,p127_rtc_hour
        call    p127_rtc_to_decimal
        ld      a,(p127_rtc_minutes_raw)
        call    p127_rtc_to_binary
        ld      hl,p127_rtc_minute
        call    p127_rtc_to_decimal
        ld      a,(p127_rtc_seconds_raw)
        call    p127_rtc_to_binary
        ld      hl,p127_rtc_second
        jp      p127_rtc_to_decimal

p127_rtc_to_binary:
        ld      b,a
        ld      a,(p127_rtc_status_b)
        bit     2,a
        ld      a,b
        ret     nz
        ld      b,a
        and     #0F
        ld      c,a
        ld      a,b
        and     #F0
        rrca
        rrca
        rrca
        rrca
        ld      b,a
        add     a,a
        ld      d,a
        add     a,a
        add     a,a
        add     a,d
        add     a,c
        ret

p127_rtc_to_decimal:
        ld      b,0
p127_rtc_decimal_tens:
        cp      10
        jr      c,p127_rtc_decimal_ones
        sub     10
        inc     b
        jr      p127_rtc_decimal_tens
p127_rtc_decimal_ones:
        ld      d,a
        ld      a,b
        add     a,'0'
        ld      (hl),a
        inc     hl
        ld      a,d
        add     a,'0'
        ld      (hl),a
        ret

p127_rtc_msg_probe:       db "[RTC] DS12887 PROBE GLUK/SMUC",13,10,0
p127_rtc_msg_missing:     db "[RTC] DS12887 NOT DETECTED",13,10,0
p127_rtc_msg_read_failed: db "[RTC] READ FAILED; UIP/TIMEOUT",13,10,0
p127_rtc_msg_time:        db "[RTC] TIME=",0
p127_rtc_msg_ready:       db "[RTC] READ OK",13,10,0

p127_rtc_available:      db 0
p127_rtc_backend:        db 0
p127_rtc_status_a:       db 0
p127_rtc_status_b:       db 0
p127_rtc_status_d:       db 0
p127_rtc_seconds_raw:    db 0
p127_rtc_minutes_raw:    db 0
p127_rtc_hours_raw:      db 0
p127_rtc_hour_pm:        db 0
p127_rtc_hour_binary:    db 0
p127_rtc_hour:           db "??"
p127_rtc_minute:         db "??"
p127_rtc_second:         db "??"

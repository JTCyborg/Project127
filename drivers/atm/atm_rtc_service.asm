; =========================================================================
; PROJECT127 - ATM Turbo 2+ DS12887 RTC service
; Version: P127_ATM_RTC v0.1.0
;
; Native ATM/GLUK interface (Project125/126 reference):
;   EFF7 bit 7: open DS12887 register gate
;   DFF7: register index
;   BFF7: register data
;
; The driver is read-only: it never writes DS12887 registers.
; The gate is closed through the documented TR-DOS ROM trampoline and
; DOSEN/RG6 state is restored before returning.
;
; API:
;   P127_RTC_Init: probes Status D/A; A=1 available, A=0 unavailable,
;                  carry set when unavailable.
;   P127_RTC_ReadTime: A=hour (0..23), B=minute, C=second; carry on error.
;   P127_RTC_SelfTest: tests conversion vectors only; no hardware writes.
;
; DS12887 Status B selects BCD/binary and 12/24-hour formats.
; =========================================================================
P127_RTC_VERSION EQU #0100

P127_RTC_Init::
        xor a
        ld (p127_rtc_available),a
        ld (p127_rtc_backend),a
        ; Project126 order: native GLUK first, then SMUC fallback.
        call P127_RTC_ProbeBackend
        jr nc,p127_rtc_init_available
        ld a,1
        ld (p127_rtc_backend),a
        call P127_RTC_ProbeBackend
        jr nc,p127_rtc_init_available
        xor a
        ld (p127_rtc_available),a
        scf
        ret
p127_rtc_init_available:
        ld a,1
        ld (p127_rtc_available),a
        or a
        ret

; Probe the currently selected backend. Carry means no valid RTC response.
; Status D must report VRT=1 and Status A must have divider bits #20.
P127_RTC_ProbeBackend:
        call P127_RTC_Open
        ld a,#0D
        call P127_RTC_ReadReg
        cp #80
        jr nz,p127_rtc_probe_bad
        ld a,#0A
        call P127_RTC_ReadReg
        and #70
        cp #20
        jr nz,p127_rtc_probe_bad
        ld a,#0B
        call P127_RTC_ReadReg
        ld (p127_rtc_status_b),a
        call P127_RTC_ReadSnapshot
        push af
        call P127_RTC_Close
        pop af
        ret
p127_rtc_probe_bad:
        call P127_RTC_Close
        scf
        ret

; Returns A=hour, B=minute, C=second, all binary.
P127_RTC_ReadTime::
        ld a,(p127_rtc_available)
        or a
        jr z,p127_rtc_read_unavailable
        call P127_RTC_Open
        call P127_RTC_ReadSnapshot
        push af
        call P127_RTC_Close
        pop af
        ret c

        ld a,(p127_rtc_hours)
        ld b,a
        ld a,(p127_rtc_status_b)
        bit 1,a
        jr nz,p127_rtc_hour_24
        ld a,b
        and #80
        ld (p127_rtc_pm),a
        ld a,b
        and #7F
        call P127_RTC_ToBinary
        ld (p127_rtc_hour_tmp),a
        ld a,(p127_rtc_pm)
        or a
        jr z,p127_rtc_hour_am
        ld a,(p127_rtc_hour_tmp)
        cp 12
        jr z,p127_rtc_hour_ready
        add a,12
        jr p127_rtc_hour_ready
p127_rtc_hour_am:
        ld a,(p127_rtc_hour_tmp)
        cp 12
        jr nz,p127_rtc_hour_ready
        xor a
        jr p127_rtc_hour_ready
p127_rtc_hour_24:
        ld a,b
        call P127_RTC_ToBinary
p127_rtc_hour_ready:
        push af
        ld a,(p127_rtc_minutes)
        call P127_RTC_ToBinary
        ld b,a
        ld a,(p127_rtc_seconds)
        call P127_RTC_ToBinary
        ld c,a
        pop af
        or a
        ret
p127_rtc_read_unavailable:
        scf
        ret

; Runtime test: read valid time, then poll until the seconds field changes.
; Four bounded ~0.2-0.4s polling intervals prevent a hung RTC from stalling boot.
; The final sampled time is retained for the startup diagnostic.
P127_RTC_RuntimeSelfTest::
        call P127_RTC_ReadTime
        ret c
        call P127_RTC_ValidateTime
        ret c
        ld a,c
        ld (p127_rtc_previous_second),a
        ld a,4
        ld (p127_rtc_tick_attempts),a
p127_rtc_tick_wait:
        ld bc,#FFFF
p127_rtc_tick_delay:
        dec bc
        ld a,b
        or c
        jr nz,p127_rtc_tick_delay
        call P127_RTC_ReadTime
        ret c
        call P127_RTC_ValidateTime
        ret c
        ld (p127_rtc_last_hour),a
        ld a,b
        ld (p127_rtc_last_minute),a
        ld a,c
        ld (p127_rtc_last_second),a
        ld d,a
        ld a,(p127_rtc_previous_second)
        cp d
        jr nz,p127_rtc_tick_pass
        ld a,(p127_rtc_tick_attempts)
        dec a
        ld (p127_rtc_tick_attempts),a
        jr nz,p127_rtc_tick_wait
        scf
        ret
p127_rtc_tick_pass:
        or a
        ret

; A=hour, B=minute, C=second. Carry if any field is out of range.
P127_RTC_ValidateTime:
        push af
        cp 24
        jr nc,p127_rtc_time_invalid
        ld a,b
        cp 60
        jr nc,p127_rtc_time_invalid
        ld a,c
        cp 60
        jr nc,p127_rtc_time_invalid
        pop af
        or a
        ret
p127_rtc_time_invalid:
        pop af
        scf
        ret

; A=0..99, HL=two-character ASCII destination.
P127_RTC_Format2:
        ld b,0
p127_rtc_format_tens:
        cp 10
        jr c,p127_rtc_format_ones
        sub 10
        inc b
        jr p127_rtc_format_tens
p127_rtc_format_ones:
        ld d,a
        ld a,b
        add a,'0'
        ld (hl),a
        inc hl
        ld a,d
        add a,'0'
        ld (hl),a
        ret

; Hardware-free format conversion self-test.
P127_RTC_SelfTest::
        ld a,#42
        call P127_RTC_BCDToBinary
        cp 42
        jr nz,p127_rtc_test_fail_1
        ld a,#09
        call P127_RTC_BCDToBinary
        cp 9
        jr nz,p127_rtc_test_fail_2
        ld a,#59
        call P127_RTC_BCDToBinary
        cp 59
        jr nz,p127_rtc_test_fail_3
        xor a
        ret
p127_rtc_test_fail_1:
        ld a,1
        jr p127_rtc_test_fail
p127_rtc_test_fail_2:
        ld a,2
        jr p127_rtc_test_fail
p127_rtc_test_fail_3:
        ld a,3
p127_rtc_test_fail:
        scf
        ret

; Startup diagnostics are kept in this service module so the host
; resident image remains within its established #6000-#7FFF load window.
P127_RTC_Startup::
        call P127_RTC_SelfTest
        jr c,p127_rtc_start_format_fail
        ld hl,p127_rtc_log_selftest
        call p127_host_debug_string
        call P127_RTC_Init
        jr c,p127_rtc_start_unavailable
        ld a,(p127_rtc_backend)
        or a
        jr nz,p127_rtc_start_smuc
        ld hl,p127_rtc_log_gluk
        call p127_host_debug_string
        jr p127_rtc_start_available_log
p127_rtc_start_smuc:
        ld hl,p127_rtc_log_smuc
        call p127_host_debug_string
p127_rtc_start_available_log:
        ld hl,p127_rtc_log_available
        call p127_host_debug_string
        call P127_RTC_RuntimeSelfTest
        jr c,p127_rtc_start_runtime_fail
        ld hl,p127_rtc_log_runtime_pass
        call p127_host_debug_string
        ld hl,p127_rtc_log_time
        call p127_host_debug_string
        ld a,(p127_rtc_last_hour)
        ld hl,p127_rtc_time_buffer
        call P127_RTC_Format2
        ld a,(p127_rtc_last_minute)
        inc hl
        inc hl
        call P127_RTC_Format2
        ld a,(p127_rtc_last_second)
        inc hl
        inc hl
        call P127_RTC_Format2
        ld hl,p127_rtc_time_buffer
        call p127_host_debug_string
        ld a,13
        call p127_host_debug_char
        ld a,10
        call p127_host_debug_char
        ret
p127_rtc_start_runtime_fail:
        ld hl,p127_rtc_log_runtime_fail
        call p127_host_debug_string
        ret
p127_rtc_start_unavailable:
        ld hl,p127_rtc_log_unavailable
        call p127_host_debug_string
        ret
p127_rtc_start_format_fail:
        ld hl,p127_rtc_log_selftest_fail
        jp p127_host_debug_string

p127_host_ui_ready:
        db "[P127] PROJECT127 HOST CONSOLE READY",13,10,0

; Open native ATM DS12887 register gate.
P127_RTC_Open:
        push af
        push bc
        ld a,(p127_rtc_backend)
        or a
        jr nz,p127_rtc_open_smuc
        ld bc,#EFF7
        ld a,#80
        out (c),a
        jr p127_rtc_open_done
p127_rtc_open_smuc:
        ; Verified SMUC RTC address/read mode. Do not write zero to FFBA:
        ; #71 preserves the multiplexed ISA/NVRAM control pattern.
        ld bc,#FFBA
        ld a,#71
        out (c),a
p127_rtc_open_done:
        pop bc
        pop af
        ret

; Close gate and restore the known-working DOSEN + RG6 mode.
P127_RTC_Close:
        push af
        push bc
        ld a,(p127_rtc_backend)
        or a
        jr nz,p127_rtc_close_smuc
        ld bc,p127_rtc_close_done
        push bc
        ld bc,#2A53
        push bc
        ld bc,#0177
        ld a,#C6
        jp #3D2F
p127_rtc_close_done:
        ; Native GLUK gate closure uses the established ROM trampoline.
        call P127_Console_Restore
        pop bc
        pop af
        ret
p127_rtc_close_smuc:
        ; Keep the SMUC RTC address/read selector in place.
        pop bc
        pop af
        ret

; A=register index, returns A=data. Caller opened gate.
P127_RTC_ReadReg:
        push bc
        ld c,a
        ld a,(p127_rtc_backend)
        or a
        jr nz,p127_rtc_read_smuc
        ld a,c
        ld bc,#DFF7
        out (c),a
        ld bc,#BFF7
        in a,(c)
        pop bc
        ret
p127_rtc_read_smuc:
        ld a,c
        ld bc,#DFBA
        out (c),a
        in a,(c)
        pop bc
        ret

; Wait for UIP clear and take a stable seconds/minutes/hours snapshot.
P127_RTC_ReadSnapshot:
        ld b,4
p127_rtc_snapshot_retry:
        call P127_RTC_WaitUIP
        ret c
        ld a,#00
        call P127_RTC_ReadReg
        ld (p127_rtc_seconds),a
        ld a,#02
        call P127_RTC_ReadReg
        ld (p127_rtc_minutes),a
        ld a,#04
        call P127_RTC_ReadReg
        ld (p127_rtc_hours),a
        ld a,#00
        call P127_RTC_ReadReg
        ld c,a
        ld a,(p127_rtc_seconds)
        cp c
        jr z,p127_rtc_snapshot_ok
        djnz p127_rtc_snapshot_retry
        scf
        ret
p127_rtc_snapshot_ok:
        ld a,c
        ld (p127_rtc_seconds),a
        or a
        ret

P127_RTC_WaitUIP:
        push bc
        ld b,0
p127_rtc_uip_loop:
        ld a,#0A
        call P127_RTC_ReadReg
        bit 7,a
        jr z,p127_rtc_uip_ready
        djnz p127_rtc_uip_loop
        scf
        pop bc
        ret
p127_rtc_uip_ready:
        or a
        pop bc
        ret

; Convert A according to Status B bit 2 (binary=1, BCD=0).
P127_RTC_ToBinary:
        push bc
        ld b,a
        ld a,(p127_rtc_status_b)
        bit 2,a
        ld a,b
        pop bc
        ret nz
P127_RTC_BCDToBinary:
        push bc
        ld b,a
        and #0F
        ld c,a
        ld a,b
        and #F0
        rrca
        rrca
        rrca
        rrca
        ld b,a
        add a,a
        ld d,a
        add a,a
        add a,a
        add a,d
        add a,c
        pop bc
        ret

p127_rtc_available: db 0
p127_rtc_backend: db 0       ; 0=GLUK DFF7/BFF7, 1=SMUC DFBA/FFBA
p127_rtc_status_b: db 0
p127_rtc_seconds: db 0
p127_rtc_minutes: db 0
p127_rtc_hours: db 0
p127_rtc_pm: db 0
p127_rtc_hour_tmp: db 0
p127_rtc_previous_second: db 0
p127_rtc_tick_attempts: db 0
p127_rtc_last_hour: db 0
p127_rtc_last_minute: db 0
p127_rtc_last_second: db 0
p127_rtc_time_buffer: db "00:00:00",0

p127_rtc_log_gluk:
        db "[P127] RTC BACKEND GLUK",13,10,0
p127_rtc_log_smuc:
        db "[P127] RTC BACKEND SMUC",13,10,0
p127_rtc_log_available:
        db "[P127] RTC DS12887 AVAILABLE",13,10,0
p127_rtc_log_runtime_pass:
        db "[P127] RTC READ/TICK SELFTEST PASS",13,10,0
p127_rtc_log_runtime_fail:
        db "[P127] RTC READ/TICK SELFTEST FAIL",13,10,0
p127_rtc_log_time:
        db "[P127] RTC TIME ",0
p127_rtc_log_unavailable:
        db "[P127] RTC DS12887 NOT DETECTED",13,10,0
p127_rtc_log_selftest:
        db "[P127] RTC FORMAT SELFTEST PASS",13,10,0
p127_rtc_log_selftest_fail:
        db "[P127] RTC FORMAT SELFTEST FAIL",13,10,0
p127_rtc_service_end:
        ASSERT p127_rtc_service_end<=#A000

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
        call P127_RTC_Open
        ld a,#0D
        call P127_RTC_ReadReg
        cp #80
        jr nz,p127_rtc_init_bad
        ld a,#0A
        call P127_RTC_ReadReg
        and #70
        cp #20
        jr nz,p127_rtc_init_bad
        ld a,#0B
        call P127_RTC_ReadReg
        ld (p127_rtc_status_b),a
        call P127_RTC_ReadSnapshot
        push af
        call P127_RTC_Close
        pop af
        jr c,p127_rtc_init_bad_closed
        ld a,1
        ld (p127_rtc_available),a
        or a
        ret
p127_rtc_init_bad:
        call P127_RTC_Close
p127_rtc_init_bad_closed:
        xor a
        ld (p127_rtc_available),a
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

; Open native ATM DS12887 register gate.
P127_RTC_Open:
        push af
        push bc
        ld bc,#EFF7
        ld a,#80
        out (c),a
        pop bc
        pop af
        ret

; Close gate and restore the known-working DOSEN + RG6 mode.
P127_RTC_Close:
        push af
        push bc
        ld bc,p127_rtc_close_done
        push bc
        ld bc,#2A53
        push bc
        ld bc,#0177
        ld a,#C6
        jp #3D2F
p127_rtc_close_done:
        pop bc
        pop af
        ret

; A=register index, returns A=data. Caller opened gate.
P127_RTC_ReadReg:
        push bc
        ld c,a
        ld a,c
        ld bc,#DFF7
        out (c),a
        ld bc,#BFF7
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
p127_rtc_status_b: db 0
p127_rtc_seconds: db 0
p127_rtc_minutes: db 0
p127_rtc_hours: db 0
p127_rtc_pm: db 0
p127_rtc_hour_tmp: db 0

p127_rtc_log_available:
        db "[P127] RTC DS12887 AVAILABLE",13,10,0
p127_rtc_log_unavailable:
        db "[P127] RTC DS12887 NOT DETECTED",13,10,0
p127_rtc_log_selftest:
        db "[P127] RTC FORMAT SELFTEST PASS",13,10,0
p127_rtc_log_selftest_fail:
        db "[P127] RTC FORMAT SELFTEST FAIL",13,10,0
p127_rtc_service_end:
        ASSERT p127_rtc_service_end<=#A000

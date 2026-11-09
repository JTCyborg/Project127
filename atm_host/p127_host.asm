; =========================================================================
; PROJECT127 - ATM Turbo 2+ host entry
; Version: P127_ATM_HOST v0.3.1
; First ATM memory-core milestone: capability/range validation only.
; =========================================================================

        DEVICE ZXSPECTRUM128

P127_HOST_LOAD_ADDRESS EQU 24576
P127_HOST_ENTRY_POINT  EQU P127_HOST_LOAD_ADDRESS+9
P127_HOST_STACK_TOP    EQU #AFFF

        ORG P127_HOST_LOAD_ADDRESS
p127_host_program_start:
        jp      p127_host_entry
        BLOCK   6,0

p127_host_entry:
        di
        ld      sp,P127_HOST_STACK_TOP
        ld      hl,p127_host_banner
        call    p127_host_debug_string
        call    atm_mem_range_selftest
        jr      c,p127_host_range_fail
        ld      hl,p127_host_range_ok
        call    p127_host_debug_string
        jr      p127_host_idle
p127_host_range_fail:
        ld      d,a
        ld      hl,p127_host_range_error
        call    p127_host_debug_string
        ld      a,d
        add     a,'0'
        call    p127_host_debug_char
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
p127_host_idle:
        halt
        jr      p127_host_idle

p127_host_debug_char:
        ld      bc,#00EF
        out     (c),a
        ret

p127_host_debug_string:
        ld      a,(hl)
        or      a
        ret     z
        ld      bc,#00EF
        out     (c),a
        inc     hl
        jr      p127_host_debug_string

p127_host_banner:
        db "[P127] ATM HOST ENTRY v0.3.1",13,10
        db "[P127] TR-DOS BOOT OK",13,10
        db "[P127] ATM RAM RANGE CORE 1 MiB",13,10,0
p127_host_range_ok:
        db "[P127] UINT32 RANGE SELFTEST PASS",13,10,0
p127_host_range_error:
        db "[P127] UINT32 RANGE SELFTEST FAIL TEST ",0

        INCLUDE "drivers/atm/atm_memory_backend.asm"

p127_host_program_end:
        ASSERT p127_host_program_start=P127_HOST_LOAD_ADDRESS
        ASSERT p127_host_entry=P127_HOST_ENTRY_POINT

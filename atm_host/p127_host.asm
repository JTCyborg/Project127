; =========================================================================
; PROJECT127 - ATM Turbo 2+ host entry
; Version: P127_ATM_HOST v0.7.0
; ATM allocator record-copy fix.
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
        call    atm_mem_init
        jr      c,p127_host_memory_init_fail
        call    atm_mem_range_selftest
        jr      c,p127_host_range_fail
        ld      hl,p127_host_range_ok
        call    p127_host_debug_string
        call    atm_mem_allocator_selftest
        jr      c,p127_host_allocator_fail
        ld      hl,p127_host_allocator_ok
        call    p127_host_debug_string
        call    atm_mem_ops_selftest
        jr      c,p127_host_ops_fail
        ld      hl,p127_host_ops_ok
        call    p127_host_debug_string
        jp      p127_host_idle
p127_host_ops_fail:
        ld      d,a
        ld      hl,p127_host_ops_error
        call    p127_host_debug_string
        ld      a,d
        call    p127_host_debug_hex_byte
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
        jr      p127_host_idle
p127_host_memory_init_fail:
        ld      hl,p127_host_memory_init_error
        call    p127_host_debug_string
        jr      p127_host_idle
p127_host_allocator_fail:
        ld      d,a
        ld      hl,p127_host_allocator_error
        call    p127_host_debug_string
        ld      hl,p127_host_allocator_stage
        call    p127_host_debug_string
        ld      a,d
        call    p127_host_debug_hex_byte
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
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
        ld      a,d
        cp      4
        jr      nz,p127_host_idle
        ld      hl,p127_host_diag_offset
        call    p127_host_debug_string
        ld      hl,p127_range_offset
        call    p127_host_debug_hex4
        ld      hl,p127_host_diag_length_pre
        call    p127_host_debug_string
        ld      hl,atm_mem_test4_length_snapshot
        call    p127_host_debug_hex4
        ld      hl,p127_host_diag_length
        call    p127_host_debug_string
        ld      hl,p127_range_length
        call    p127_host_debug_hex4
        ld      hl,p127_host_diag_capacity
        call    p127_host_debug_string
        ld      hl,p127_range_capacity
        call    p127_host_debug_hex4
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

p127_host_debug_hex4:
        ld      a,(hl)
        call    p127_host_debug_hex_byte
        inc     hl
        ld      a,(hl)
        call    p127_host_debug_hex_byte
        inc     hl
        ld      a,(hl)
        call    p127_host_debug_hex_byte
        inc     hl
        ld      a,(hl)
        call    p127_host_debug_hex_byte
        ret

p127_host_debug_hex_byte:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    p127_host_debug_hex_nibble
        pop     af
        and     #0F
p127_host_debug_hex_nibble:
        cp      10
        jr      c,p127_host_debug_hex_digit
        add     a,'A'-10
        jr      p127_host_debug_char
p127_host_debug_hex_digit:
        add     a,'0'
        jr      p127_host_debug_char

p127_host_debug_string:
        ld      a,(hl)
        or      a
        ret     z
        ld      bc,#00EF
        out     (c),a
        inc     hl
        jr      p127_host_debug_string

p127_host_banner:
        db "[P127] ATM HOST ENTRY v0.7.0",13,10
        db "[P127] TR-DOS BOOT OK",13,10
        db "[P127] ATM RAM RANGE CORE 1 MiB",13,10,0
p127_host_range_ok:
        db "[P127] UINT32 RANGE SELFTEST PASS",13,10,0
p127_host_allocator_ok:
        db "[P127] ATM PAGE ALLOCATOR SELFTEST PASS",13,10,0
p127_host_ops_ok:
        db "[P127] ATM MEMORY OPS SELFTEST PASS",13,10,0
p127_host_ops_error:
        db "[P127] ATM MEMORY OPS SELFTEST FAIL STEP=0x",0
p127_host_allocator_error:
        db "[P127] ATM PAGE ALLOCATOR SELFTEST FAIL",0
p127_host_allocator_stage:
        db " STEP=0x",0
p127_host_allocator_error_nl:
        db 13,10,0
p127_host_memory_init_error:
        db "[P127] ATM MEMORY INIT FAIL",13,10,0
p127_host_range_error:
        db "[P127] UINT32 RANGE SELFTEST FAIL TEST ",0
p127_host_diag_offset:
        db " OFFSET=",0
p127_host_diag_length_pre:
        db " LENGTH_PRE=",0
p127_host_diag_length:
        db " LENGTH_POST=",0
p127_host_diag_capacity:
        db " CAPACITY=",0

        INCLUDE "drivers/atm/atm_memory_backend.asm"

p127_host_program_end:
        ASSERT p127_host_program_start=P127_HOST_LOAD_ADDRESS
        ASSERT p127_host_entry=P127_HOST_ENTRY_POINT
        ASSERT p127_host_program_end <= #8000

; =========================================================================
; PROJECT127 — ATM Turbo 2+ host entry
; Version: P127_ATM_HOST v0.1.0
;
; This bootable host entry links the first ATM memory-core milestone.
; Allocator, physical page mapping, streaming and DMA are still gated work;
; no Project126 overlay runtime is linked.
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

p127_host_idle:
        halt
        jr      p127_host_idle

p127_host_debug_string:
        ld      a,(hl)
        or      a
        ret     z
        ld      bc,#00EF
        out     (c),a
        inc     hl
        jr      p127_host_debug_string

p127_host_banner:
        db "[P127] ATM HOST ENTRY v0.1.0",13,10
        db "[P127] TR-DOS BOOT OK",13,10
        db "[P127] LOW-LEVEL FOUNDATION NOT YET INITIALIZED",13,10,0

p127_host_program_end:
        ASSERT p127_host_program_start=P127_HOST_LOAD_ADDRESS
        ASSERT p127_host_entry=P127_HOST_ENTRY_POINT

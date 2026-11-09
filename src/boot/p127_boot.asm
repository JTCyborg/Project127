; ============================================================================
; Project127 — boot stage 0.4.1
; ATM Turbo 2+ Z80, loaded and entered at 6000h.
; Debug channel: ATM debug port EFh. Each line is a reached execution point.
; ============================================================================
        DEVICE ZXSPECTRUM128

P127_LOAD_ADDRESS  EQU 06000h
P127_STACK_TOP     EQU 0BFFFh
P127_DEBUG_PORT    EQU 00EFh

        ORG P127_LOAD_ADDRESS

p127_entry:
        ; Preserve the known-good BASIC USR entry diagnostic.
        ld      bc, P127_DEBUG_PORT
        ld      a, '>'
        out     (c), a
        jp      p127_start

p127_start:
        di
        ld      sp, P127_STACK_TOP

        ld      hl, p127_msg_entry
        call    p127_puts

        ld      hl, p127_msg_stack
        call    p127_puts

        ld      hl, p127_msg_exec
        call    p127_puts

        ld      hl, p127_msg_pass
        call    p127_puts

        ; Initialize Project126's ATM-native debug console after BOOT0.
        call    p127_ui_init
        ld      a,1
        ld      (p127_ui_ready),a
        ld      hl,p127_msg_ui_ready
        call    p127_puts

        ; Stage 1/2: software page accounting plus video and active boot-map reserves.
        call    p127_mem_init
        ld      hl,p127_msg_mem_init
        call    p127_puts
        call    p127_mem_reserve_video
        jr      c,p127_mem_map_failed
        ld      hl,p127_msg_video_reserved
        call    p127_puts
        call    p127_mem_reserve_boot
        jr      c,p127_mem_boot_failed
        ld      hl,p127_msg_boot_reserved
        call    p127_puts
        call    p127_mem_selftest
        jr      c,p127_mem_failed
        ld      hl,p127_msg_mem_pass
        call    p127_puts
        jr      p127_idle
p127_mem_map_failed:
        ld      hl,p127_msg_mem_map_fail
        call    p127_puts
        jr      p127_idle
p127_mem_boot_failed:
        ld      hl,p127_msg_boot_reserve_fail
        call    p127_puts
        jr      p127_idle
p127_mem_failed:
        ld      hl,p127_msg_mem_fail
        call    p127_puts

p127_idle:
        halt
        jr      p127_idle

; Input: HL -> zero-terminated string.
; Clobbers AF, BC, HL. Preserves caller's stack frame.
p127_puts:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        push    hl
        push    af
        ld      a,(p127_ui_ready)
        or      a
        jr      z,p127_puts_ef
        pop     af
        call    BIOS_DebugConsole_PrintChar
        pop     hl
        jr      p127_puts
p127_puts_ef:
        pop     af
        ld      bc,P127_DEBUG_PORT
        out     (c),a
        pop     hl
        jr      p127_puts

p127_ui_ready: db 0
p127_msg_ui_ready: db "[P127] UI READY; ALL DEBUG OUTPUT MIRRORED TO EF",13,10,0
p127_msg_entry:
        db      "[P127] S2 ENTRY @6000", 13, 10, 0
p127_msg_stack:
        db      "[P127] STACK SET BFFF", 13, 10, 0
p127_msg_exec:
        db      "[P127] DEBUG TX EF", 13, 10, 0
p127_msg_pass:
        db      "[P127] BOOT0 PASS; IDLE", 13, 10, 0
p127_msg_mem_init:
        db      "[P127] MEM INIT 1MB/64P", 13, 10, 0
p127_msg_video_reserved:
        db      "[P127] VIDEO RAM RESERVED P1,P3,P5,P7", 13, 10, 0
p127_msg_boot_reserved:
        db      "[P127] BOOT MAP RESERVED P0,P2; P5 ACTIVE", 13, 10, 0
p127_msg_boot_reserve_fail:
        db      "[P127] BOOT RAM RESERVE FAIL", 13, 10, 0
p127_msg_mem_map_fail:
        db      "[P127] VIDEO RAM RESERVE FAIL", 13, 10, 0
p127_msg_mem_pass:
        db      "[P127] MEM PAGE TEST PASS", 13, 10, 0
p127_msg_mem_fail:
        db      "[P127] MEM PAGE TEST FAIL", 13, 10, 0

        INCLUDE "src/kernel/p127_mem.asm"

p127_end:
        ASSERT  p127_entry = P127_LOAD_ADDRESS
        ASSERT  p127_end > p127_entry
        ASSERT  p127_end <= P127_LOAD_ADDRESS + 04000h

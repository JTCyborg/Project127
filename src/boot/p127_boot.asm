; ============================================================================
; Project127 — boot stage 0.7.9
; ATM Turbo 2+ Z80, loaded and entered at 6000h.
; Debug channel: ATM debug port EFh. Each line is a reached execution point.
; ============================================================================
        DEVICE ZXSPECTRUM128

P127_LOAD_ADDRESS  EQU 06000h
P127_STACK_TOP     EQU 0BFFFh
P127_DEBUG_PORT    EQU 00EFh

; Reserved physical page for the future IM2 vector table (accounting only).
P127_IRQ_TABLE_PAGE EQU 4
P127_IRQ_TABLE_WINDOW EQU 3
P127_IRQ_TABLE_BASE EQU 0C000h
P127_IRQ_TABLE_BYTES EQU 257
P127_IRQ_TABLE_END EQU P127_IRQ_TABLE_BASE+P127_IRQ_TABLE_BYTES
P127_IRQ_TABLE_I EQU 0C0h

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

        ; Initialize software W3 ownership before bringing up the UI.
        call    p127_w3_init
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
        jp      c,p127_mem_map_failed
        ld      hl,p127_msg_video_reserved
        call    p127_puts
        call    p127_mem_reserve_boot
        jp      c,p127_mem_boot_failed
        ld      hl,p127_msg_boot_reserved
        call    p127_puts
        call    p127_mem_reserve_irq_table
        jp      c,p127_mem_irq_reserve_failed
        ld      hl,p127_msg_irq_page_reserved
        call    p127_puts
        ; Stage 3.4: measure the linked kernel span and validate its live pages.
        call    p127_layout_selftest
        jp      c,p127_layout_failed
        call    p127_layout_report
        call    p127_mem_selftest
        jp      c,p127_mem_failed
        ld      hl,p127_msg_mem_pass
        call    p127_puts
        ld      hl,p127_msg_mem_negative_pass
        call    p127_puts
        ; Stage 3.1: UINT32 arithmetic and physical 1 MiB bounds contract.
        call    p127_range_selftest
        jp      c,p127_range_failed
        ld      hl,p127_msg_range_pass
        call    p127_puts
        ; Stage 3.2: top-down contiguous physical page arena, accounting only.
        call    p127_arena_selftest
        jp      c,p127_arena_failed
        ld      hl,p127_msg_arena_pass
        call    p127_puts
        ; Stage 6.1: managed logical page table and address translation model.
        call    p127_as_selftest
        jp      c,p127_as_failed
        ld      hl,p127_msg_as_pass
        call    p127_puts
        ; Stage 6.2: preflight every logical page touched by a byte span.
        call    p127_as_span_selftest
        jp      c,p127_as_span_failed
        ld      hl,p127_msg_as_span_pass
        call    p127_puts

        ; Stage 2.4: pure software mapper model; hardware OUT remains disabled.
        call    p127_map_init
        call    p127_map_selftest
        jp      c,p127_map_failed
        call    p127_map_handoff_selftest
        jp      c,p127_handoff_failed
        call    p127_map_txn_selftest
        jp      c,p127_map_txn_failed
        ld      hl,p127_msg_map_txn_pass
        call    p127_puts
        call    p127_handoff_stack_probe
        jp      c,p127_stack_probe_failed
        ld      hl,p127_msg_stack_probe_pass
        call    p127_puts
        ; Stage 2.7: verify the fixed resident-window contract. This test
        ; supplies a synthetic quiesced-UI state; it does not quiesce UI.
        call    p127_resident_selftest
        jp      c,p127_resident_failed
        call    p127_w3_selftest
        jp      c,p127_w3_failed
        ld      hl,p127_msg_w3_pass
        call    p127_puts
        ; Stage 2.9: software-only W3 snapshot/rollback recovery tests.
        call    p127_w3_recovery_selftest
        jp      c,p127_w3_recovery_failed
        ld      hl,p127_msg_w3_recovery_pass
        call    p127_puts
        ; Stage 2.11: enforce the explicit DI-only interrupt ownership contract.
        call    p127_irq_init
        call    p127_irq_selftest
        jp      c,p127_irq_failed
        call    p127_irq_gate_selftest
        jp      c,p127_irq_failed
        call    p127_irq_table_preflight
        jp      c,p127_irq_failed
        call    p127_irq_context_selftest
        jp      c,p127_irq_failed
        ld      hl,p127_msg_irq_context_pass
        call    p127_puts
        ; Stage 2.16: one batch exhausts all readiness masks and rejection
        ; paths. ATM source/vector/acknowledge behavior remains unresolved.
        call    p127_irq_batch_selftest
        jp      c,p127_irq_failed
        ld      hl,p127_msg_irq_batch_pass
        call    p127_puts
        ld      hl,p127_msg_irq_page_pass
        call    p127_puts
        ld      hl,p127_msg_irq_pass
        call    p127_puts
        ; Stage 2.10: verify the resident trampoline's real linked placement,
        ; resident data placement, live W2 stack and DI-only entry contract.
        call    p127_resident_trampoline_preflight
        jp      c,p127_trampoline_preflight_failed
        ld      hl,p127_msg_trampoline_preflight_pass
        call    p127_puts
        ld      hl,p127_msg_resident_pass
        call    p127_puts
        ld      hl,p127_msg_handoff_pass
        call    p127_puts
        ld      hl,p127_msg_map_pass
        call    p127_puts
        ; Stage 2.17: exercise real W3 physical page selection and RAM data.
        ; Test code executes from W2; stack remains in W2; UI is quiesced.
        call    p127_physmem_batch_selftest
        jp      c,p127_physmem_failed
        ld      hl,p127_msg_physmem_pass
        call    p127_puts
        ; Stage 2.20: public page allocator and guarded W3 lease API.
        call    p127_physmem_api_selftest
        jp      c,p127_physmem_api_failed
        ld      hl,p127_msg_physmem_api_pass
        call    p127_puts
        ; Stage 6.3: copy logical spans through a bounded W3 lease.
        call    p127_as_copy_selftest
        jp      c,p127_as_copy_failed
        ld      hl,p127_msg_as_copy_pass
        call    p127_puts
        jp      p127_idle
p127_as_copy_failed:
        ld      hl,p127_msg_as_copy_fail
        call    p127_puts
        jp      p127_idle
p127_physmem_api_failed:
        ld      hl,p127_msg_physmem_api_fail
        call    p127_puts
        jp      p127_idle
p127_physmem_failed:
        ld      hl,p127_msg_physmem_fail
        call    p127_puts
        ld      hl,p127_msg_physmem_error
        call    p127_puts
        ld      a,(p127_physmem_error)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        jp      p127_idle
p127_map_txn_failed:
        ld      hl,p127_msg_map_txn_fail
        call    p127_puts
        jp      p127_idle
p127_stack_probe_failed:
        ld      hl,p127_msg_stack_probe_fail
        call    p127_puts
        jp      p127_idle
p127_w3_failed:
        ld      hl,p127_msg_w3_fail
        call    p127_puts
        jp      p127_idle
p127_w3_recovery_failed:
        ld      hl,p127_msg_w3_recovery_fail
        call    p127_puts
        jp      p127_idle
p127_irq_failed:
        ld      hl,p127_msg_irq_fail
        call    p127_puts
        jp      p127_idle
p127_trampoline_preflight_failed:
        ld      hl,p127_msg_trampoline_preflight_fail
        call    p127_puts
        jp      p127_idle
p127_resident_failed:
        ld      hl,p127_msg_resident_fail
        call    p127_puts
        jp      p127_idle
p127_handoff_failed:
        ld      hl,p127_msg_handoff_fail
        call    p127_puts
        jp      p127_idle
p127_map_failed:
        ld      hl,p127_msg_map_fail
        call    p127_puts
        jp      p127_idle
p127_mem_map_failed:
        ld      hl,p127_msg_mem_map_fail
        call    p127_puts
        jp      p127_idle
p127_mem_irq_reserve_failed:
        ld      hl,p127_msg_irq_page_fail
        call    p127_puts
        jp      p127_idle
p127_mem_boot_failed:
        ld      hl,p127_msg_boot_reserve_fail
        call    p127_puts
        jp      p127_idle
p127_mem_failed:
        ld      hl,p127_msg_mem_fail
        call    p127_puts
        jp      p127_idle
p127_range_failed:
        ld      hl,p127_msg_range_fail
        call    p127_puts
        jp      p127_idle
p127_layout_failed:
        ld      hl,p127_msg_layout_fail
        call    p127_puts
        jp      p127_idle
p127_arena_failed:
        ld      hl,p127_msg_arena_fail
        call    p127_puts
        jp      p127_idle
p127_as_failed:
        ld      hl,p127_msg_as_fail
        call    p127_puts
        jp      p127_idle
p127_as_span_failed:
        ld      hl,p127_msg_as_span_fail
        call    p127_puts
        jp      p127_idle

p127_idle:
        halt
        jp      p127_idle

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

; Emit A as two hexadecimal digits to the existing #EF/UI console sink.
p127_put_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    p127_put_hex_nibble
        pop     af
        jp      p127_put_hex_nibble

p127_put_hex_nibble:
        and     00Fh
        add     a,'0'
        cp      '9'+1
        jr      c,p127_put_char
        add     a,7
p127_put_char:
        push    af
        ld      a,(p127_ui_ready)
        or      a
        jr      z,p127_put_char_ef
        pop     af
        jp      BIOS_DebugConsole_PrintChar
p127_put_char_ef:
        pop     af
        ld      bc,P127_DEBUG_PORT
        out     (c),a
        ret

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
p127_msg_layout_fail:
        db      "[P127] KERNEL IMAGE LAYOUT FAIL",13,10,0
p127_msg_mem_init:
        db      "[P127] MEM INIT 1MB/64P", 13, 10, 0
p127_msg_video_reserved:
        db      "[P127] VIDEO RAM RESERVED P1,P3,P5,P7", 13, 10, 0
p127_msg_boot_reserved:
        db      "[P127] BOOT MAP RESERVED P0,P2; P5 ACTIVE", 13, 10, 0
p127_msg_irq_page_reserved:
        db      "[P127] IRQ TABLE PAGE RESERVED P4; IM2 DISABLED",13,10,0
p127_msg_irq_page_pass:
        db      "[P127] IRQ TABLE SLOT PREFLIGHT PASS; OUT DISABLED",13,10,0
p127_msg_irq_page_fail:
        db      "[P127] IRQ TABLE PAGE RESERVE FAIL",13,10,0
p127_msg_boot_reserve_fail:
        db      "[P127] BOOT RAM RESERVE FAIL", 13, 10, 0
p127_msg_mem_map_fail:
        db      "[P127] VIDEO RAM RESERVE FAIL", 13, 10, 0
p127_msg_mem_pass:
        db      "[P127] MEM PAGE TEST PASS", 13, 10, 0
p127_msg_mem_negative_pass:
        db      "[P127] MEM NEGATIVE-PATH TEST PASS; DOUBLE-FREE/RANGE/RESERVE GUARDED",13,10,0
p127_msg_mem_fail:
        db      "[P127] MEM PAGE TEST FAIL", 13, 10, 0
p127_msg_range_pass:
        db      "[P127] UINT32 RANGE 1MB BOUNDS TEST PASS; NO MAP/OUT",13,10,0
p127_msg_range_fail:
        db      "[P127] UINT32 RANGE 1MB BOUNDS TEST FAIL",13,10,0
p127_msg_arena_pass:
        db      "[P127] TOP-DOWN ARENA P8..P63 / 56P TEST PASS; NO MAP/OUT",13,10,0
p127_msg_arena_fail:
        db      "[P127] TOP-DOWN ARENA TEST FAIL",13,10,0
p127_msg_as_pass:
        db      "[P127] LOGICAL PAGE TABLE/BOUNDARY TRANSLATION PASS; NO MAP/OUT",13,10,0
p127_msg_as_fail:
        db      "[P127] LOGICAL ADDRESS SPACE TEST FAIL",13,10,0
p127_msg_as_span_pass:
        db      "[P127] LOGICAL SPAN PREFLIGHT PASS; NO COPY/MAP/OUT",13,10,0
p127_msg_as_span_fail:
        db      "[P127] LOGICAL SPAN PREFLIGHT FAIL",13,10,0
p127_msg_as_copy_pass:
        db      "[P127] LOGICAL SPAN COPY PASS; CROSS-PAGE/W3 RESTORE VERIFIED",13,10,0
p127_msg_as_copy_fail:
        db      "[P127] LOGICAL SPAN COPY TEST FAIL",13,10,0
p127_msg_map_txn_pass:
        db      "[P127] MAP TXN COMMIT/ROLLBACK PASS; OUT DISABLED",13,10,0
p127_msg_map_txn_fail:
        db      "[P127] MAP TXN COMMIT/ROLLBACK FAIL",13,10,0
p127_msg_map_pass:
        db      "[P127] MAP MODEL TEST PASS; SOFTWARE SHADOW", 13, 10, 0
p127_msg_physmem_pass:
        db      "[P127] PHYS W3 FULL FREE-PAGE SWEEP/ALLOCATOR/RESERVES/P0 RESTORE PASS",13,10,0
p127_msg_physmem_api_pass:
        db      "[P127] PAGE ALLOC/FREE + GUARDED W3 LEASE API PASS; IM/EI DISABLED",13,10,0
p127_msg_physmem_api_fail:
        db      "[P127] PAGE ALLOC/FREE + GUARDED W3 LEASE API FAIL",13,10,0
p127_msg_physmem_fail:
        db      "[P127] PHYS W3 PAGE SWITCH/MEMORY TEST FAIL",13,10,0
p127_msg_physmem_error:
        db      "[P127] PHYSMEM ERROR=",0
p127_msg_map_fail:
        db      "[P127] MAP MODEL TEST FAIL", 13, 10, 0
p127_msg_stack_probe_pass:
        db      "[P127] RESIDENT STACK PROBE PASS; OUT DISABLED",13,10,0
p127_msg_stack_probe_fail:
        db      "[P127] RESIDENT STACK PROBE FAIL",13,10,0
p127_msg_resident_pass:
        db      "[P127] RESIDENT WINDOW CONTRACT PASS; OUT DISABLED",13,10,0
p127_msg_resident_fail:
        db      "[P127] RESIDENT WINDOW CONTRACT FAIL",13,10,0
p127_msg_handoff_pass:
        db      "[P127] HANDOFF GUARD TEST PASS; OUT DISABLED",13,10,0
p127_msg_handoff_fail:
        db      "[P127] HANDOFF GUARD TEST FAIL",13,10,0
p127_msg_w3_pass:
        db      "[P127] UI QUIESCE/W3 OWNERSHIP PASS; OUT DISABLED",13,10,0
p127_msg_w3_fail:
        db      "[P127] UI QUIESCE/W3 OWNERSHIP FAIL",13,10,0
p127_msg_w3_recovery_pass:
        db      "[P127] W3 ROLLBACK/RECOVERY PASS; OUT DISABLED",13,10,0
p127_msg_w3_recovery_fail:
        db      "[P127] W3 ROLLBACK/RECOVERY FAIL",13,10,0
p127_msg_irq_context_pass:
        db "[P127] IRQ FRAME ROUNDTRIP PASS; VECTOR DISABLED",13,10,0
p127_msg_irq_batch_pass:
        db "[P127] IRQ BATCH 16-CHECK PASS; SOURCE UNRESOLVED; IM/EI/OUT DISABLED",13,10,0
p127_msg_irq_pass:
        db "[P127] IRQ MASK/VECTOR CONTRACT PASS; EI DISABLED",13,10,0
p127_msg_irq_fail:
        db "[P127] IRQ MASK/VECTOR CONTRACT FAIL",13,10,0
p127_msg_trampoline_preflight_pass:
        db      "[P127] RESIDENT TRAMPOLINE PREFLIGHT PASS; OUT DISABLED",13,10,0
p127_msg_trampoline_preflight_fail:
        db      "[P127] RESIDENT TRAMPOLINE PREFLIGHT FAIL",13,10,0

        INCLUDE "src/kernel/p127_layout.asm"

; Keep the remap-critical code/data at the start of the Stage2 image so it
; remains inside W1/P5. The preflight below verifies the actual linked bounds.
        INCLUDE "src/kernel/p127_resident.asm"
        INCLUDE "src/kernel/p127_irq.asm"
        INCLUDE "src/kernel/p127_mem.asm"
        INCLUDE "src/kernel/p127_range.asm"
        INCLUDE "src/kernel/p127_arena.asm"
        INCLUDE "src/kernel/p127_as.asm"
        INCLUDE "src/kernel/p127_as_span.asm"
        INCLUDE "src/kernel/p127_as_copy.asm"
        INCLUDE "src/kernel/p127_map.asm"
        INCLUDE "src/kernel/p127_handoff.asm"

p127_end:
        ASSERT  p127_entry = P127_LOAD_ADDRESS
        ASSERT  p127_end > p127_entry
        ASSERT  p127_end <= P127_LOAD_ADDRESS + 04000h

; ============================================================================
; Project127 — interrupt safety contract / preflight
; Module version: 0.3.0
; This is deliberately a DI-only bootstrap contract, not an IRQ dispatcher.
; No EI, IM instruction, vector write, or hardware page OUT is permitted.
; ============================================================================
P127_IRQ_VERSION_MAJOR EQU 0
P127_IRQ_VERSION_MINOR EQU 3
P127_IRQ_VERSION_PATCH EQU 0
P127_IRQ_MASKED EQU 1
P127_IRQ_VECTOR_NONE EQU 0
P127_IRQ_MODE_UNSET EQU 0

; Boot owns the CPU in a DI-protected phase. A stock Z80 cannot read IM0/1/2
; directly; LD A,I exposes IFF2 in P/V but is not a general IFF restore path.
; Therefore this module never guesses prior interrupt state and never EI/IM.
; Until a real vector table/handler is installed, vector ownership is NONE.
; Interrupts may not be enabled until all three prerequisites are explicitly
; established by later stages: writable/owned vector table, verified table
; mapping, and installed resident handler. No current boot code sets these.
P127_IRQ_READY_VECTOR EQU 1
P127_IRQ_READY_MAP EQU 2
P127_IRQ_READY_HANDLER EQU 4
P127_IRQ_READY_ALL EQU 7

p127_irq_init:
        di
        ld      a,P127_IRQ_MASKED
        ld      (p127_irq_mask_state),a
        xor     a
        ld      (p127_irq_vector_owner),a
        ld      (p127_irq_mode_policy),a
        ld      (p127_irq_ready_flags),a
        or      a
        ret

; OUT: carry clear only while the documented DI-only/no-vector contract holds.
p127_irq_validate:
        ld      a,(p127_irq_mask_state)
        cp      P127_IRQ_MASKED
        jp      nz,p127_irq_reject
        ld      a,(p127_irq_vector_owner)
        cp      P127_IRQ_VECTOR_NONE
        jp      nz,p127_irq_reject
        ld      a,(p127_irq_mode_policy)
        cp      P127_IRQ_MODE_UNSET
        jp      nz,p127_irq_reject
        or      a
        ret

; Fault-injection tests reject enabled-state, vector-owner and guessed-IM claims.
p127_irq_selftest:
        call    p127_irq_init
        call    p127_irq_validate
        jp      c,p127_irq_test_fail
        xor     a
        ld      (p127_irq_mask_state),a
        call    p127_irq_validate
        jp      nc,p127_irq_test_fail
        ld      a,P127_IRQ_MASKED
        ld      (p127_irq_mask_state),a
        ld      a,1
        ld      (p127_irq_vector_owner),a
        call    p127_irq_validate
        jp      nc,p127_irq_test_fail
        xor     a
        ld      (p127_irq_vector_owner),a
        ld      a,1
        ld      (p127_irq_mode_policy),a
        call    p127_irq_validate
        jp      nc,p127_irq_test_fail
        call    p127_irq_init
        call    p127_irq_validate
        ret


; Readiness gate only. Carry is set unless vector ownership, mapped table,
; and resident handler are all explicitly committed. This routine NEVER EI.
p127_irq_enable_preflight:
        ld      a,(p127_irq_ready_flags)
        cp      P127_IRQ_READY_ALL
        jp      nz,p127_irq_reject
        ld      a,(p127_irq_vector_owner)
        or      a
        jp      z,p127_irq_reject
        ld      a,(p127_irq_mode_policy)
        or      a
        jp      z,p127_irq_reject
        or      a
        ret

; Prove the gate is closed by default and opens only for the complete
; synthetic prerequisite tuple. Restore the real safe boot tuple afterward.
p127_irq_gate_selftest:
        call    p127_irq_init
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail
        ld      a,P127_IRQ_READY_VECTOR
        ld      (p127_irq_ready_flags),a
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail
        ld      a,P127_IRQ_READY_ALL
        ld      (p127_irq_ready_flags),a
        ld      a,1
        ld      (p127_irq_vector_owner),a
        ld      a,2
        ld      (p127_irq_mode_policy),a
        call    p127_irq_enable_preflight
        jp      c,p127_irq_test_fail
        call    p127_irq_init
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail
        or      a
        ret

; Validate the future IM2 table reservation and address geometry. The page
; remains unmapped: W3 must still describe physical page 0 in the live map.
; No table bytes are written, no I register is loaded, and no IM is selected.
p127_irq_table_preflight:
        ld      hl,p127_mem_page_state+P127_IRQ_TABLE_PAGE
        ld      a,(hl)
        cp      1                       ; P127_MEM_RESERVED
        jp      nz,p127_irq_reject
        ld      a,(p127_map_shadow+P127_IRQ_TABLE_WINDOW)
        or      a
        jp      nz,p127_irq_reject      ; W3 still maps bootstrap page 0
        ld      hl,P127_IRQ_TABLE_BASE
        ld      a,h
        cp      P127_IRQ_TABLE_I
        jp      nz,p127_irq_reject
        ld      hl,P127_IRQ_TABLE_END
        ld      de,10000h
        or      a
        sbc     hl,de
        jp      nc,p127_irq_reject
        or      a
        ret

        ASSERT P127_IRQ_TABLE_WINDOW = 3
        ASSERT P127_IRQ_TABLE_BASE = 0C000h
        ASSERT P127_IRQ_TABLE_I = 0C0h
        ASSERT P127_IRQ_TABLE_BYTES = 257
        ASSERT P127_IRQ_TABLE_END = 0C101h
        ASSERT P127_IRQ_TABLE_END <= 10000h

p127_irq_reject:
        scf
        ret
p127_irq_test_fail:
        call    p127_irq_init
        scf
        ret
p127_irq_mask_state: db 0
p127_irq_vector_owner: db 0
p127_irq_mode_policy: db 0
p127_irq_ready_flags: db 0

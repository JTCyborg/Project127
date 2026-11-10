; ============================================================================
; Project127 — interrupt safety contract / preflight
; Module version: 0.5.0
; This is deliberately a DI-only bootstrap contract, not an IRQ dispatcher.
; No EI, IM instruction, vector write, or hardware page OUT is permitted.
; ============================================================================
P127_IRQ_VERSION_MAJOR EQU 0
P127_IRQ_VERSION_MINOR EQU 5
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

; Stage 2.16 batch: exhaust the complete 3-bit readiness mask and all
; prerequisite failure paths in one boot. This is a software contract test:
; it does not model or claim an ATM interrupt source/vector/acknowledge cycle.
; On success the real boot tuple is restored to DI + no owner + no mode.
p127_irq_batch_selftest:
        call    p127_irq_init
        call    p127_irq_validate
        jp      c,p127_irq_test_fail

        ; Exhaust all eight combinations of VECTOR/MAP/HANDLER readiness.
        ; A nonzero synthetic owner/mode is supplied only for this gate test.
        ld      a,1
        ld      (p127_irq_vector_owner),a
        ld      (p127_irq_mode_policy),a
        ld      b,0
p127_irq_batch_mask_loop:
        ld      a,b
        ld      (p127_irq_ready_flags),a
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_batch_mask_open
        ld      a,b
        cp      P127_IRQ_READY_ALL
        jp      z,p127_irq_test_fail
        jr      p127_irq_batch_mask_next
p127_irq_batch_mask_open:
        ld      a,b
        cp      P127_IRQ_READY_ALL
        jp      nz,p127_irq_test_fail
p127_irq_batch_mask_next:
        inc     b
        ld      a,b
        cp      8
        jr      nz,p127_irq_batch_mask_loop

        ; All readiness bits without vector ownership must remain closed.
        ld      a,P127_IRQ_READY_ALL
        ld      (p127_irq_ready_flags),a
        xor     a
        ld      (p127_irq_vector_owner),a
        ld      a,1
        ld      (p127_irq_mode_policy),a
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail

        ; All readiness bits without a selected policy must remain closed.
        ld      a,1
        ld      (p127_irq_vector_owner),a
        xor     a
        ld      (p127_irq_mode_policy),a
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail

        ; Contract validator must reject each forbidden boot-state mutation.
        call    p127_irq_init
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

        ; Restore and verify the actual safe boot state; gate remains closed.
        call    p127_irq_init
        call    p127_irq_validate
        jp      c,p127_irq_test_fail
        call    p127_irq_enable_preflight
        jp      nc,p127_irq_test_fail
        or      a
        ret

; Validate the future IM2 table reservation and address geometry.
; The table is in fixed W2/P2; W3 remains free for leased remapping.
; No table bytes are written, no I register is loaded, and no IM is selected.
p127_irq_table_preflight:
        ld      hl,p127_mem_page_state+P127_IRQ_TABLE_PAGE
        ld      a,(hl)
        cp      1                       ; P127_MEM_RESERVED
        jp      nz,p127_irq_reject
        ld      a,(p127_map_shadow+P127_IRQ_TABLE_WINDOW)
        cp      P127_IRQ_TABLE_PAGE
        jp      nz,p127_irq_reject      ; fixed W2 still maps reserved P2
        ld      hl,P127_IRQ_TABLE_BASE
        ld      a,h
        cp      P127_IRQ_TABLE_I
        jp      nz,p127_irq_reject
        ld      hl,P127_IRQ_TABLE_END
        ld      de,0B101h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_reject
        or      a
        ret

        ASSERT P127_IRQ_TABLE_WINDOW = 2
        ASSERT P127_IRQ_TABLE_PAGE = 2
        ASSERT P127_IRQ_TABLE_BASE = 0B000h
        ASSERT P127_IRQ_TABLE_I = 0B0h
        ASSERT P127_IRQ_TABLE_BYTES = 257
        ASSERT P127_IRQ_TABLE_END = 0B101h
        ASSERT P127_IRQ_TABLE_END <= 10000h
        ASSERT P127_IRQ_TABLE_END < 0B7F0h

p127_irq_reject:
        scf
        ret
p127_irq_test_fail:
        call    p127_irq_init
        scf
        ret


; Stage 2.15: resident interrupt frame protocol.
; Hardware vector installation and IM selection are deliberately separate.
; Entry contract: CPU has already pushed the interrupted PC; W1/P5 code and
; W2/P2 stack remain mapped. The dispatcher may freely clobber all registers.
; RETI restores IFF1 from IFF2; this routine never executes EI or IM.
p127_irq_entry:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'

        call    p127_irq_dispatch

        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        reti

; The source dispatcher is intentionally inert until an ATM interrupt
; source, acknowledgement policy and vector ownership are specified.
; The test-only branch aggressively clobbers both register banks so the
; frame round-trip can be checked without enabling asynchronous IRQs.
p127_irq_dispatch:
        ld      a,(p127_irq_test_clobber)
        or      a
        ret     z
        ld      a,0EEh
        ld      bc,0EEEEh
        ld      de,0DDDDh
        ld      hl,0CCCCh
        ld      ix,0BBBBh
        ld      iy,0AAAAh
        exx
        ld      bc,09999h
        ld      de,08888h
        ld      hl,07777h
        exx
        ex      af,af'
        ld      a,0DDh
        or      a
        ex      af,af'
        ret

; CALL-based synthetic entry test. It saves the caller's complete register
; set, loads sentinels into primary/alternate banks, invokes the same entry
; routine used by a future vector, and verifies exact register restoration.
; DI is mandatory here: RETI copies IFF2 to IFF1, and both must remain zero.
p127_irq_context_selftest:
        di
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'

        xor     a
        ld      (p127_irq_context_result),a
        ld      a,1
        ld      (p127_irq_test_clobber),a

        ld      bc,01234h
        ld      de,05678h
        ld      hl,09ABCh
        ld      ix,01357h
        ld      iy,02468h
        exx
        ld      bc,0ABCDh
        ld      de,09876h
        ld      hl,05432h
        exx
        ex      af,af'
        ld      a,0A5h
        or      a
        ex      af,af'
        ld      a,05Ah
        or      a

        call    p127_irq_entry

        ld      (p127_irq_test_bc),bc
        ld      (p127_irq_test_de),de
        ld      (p127_irq_test_hl),hl
        ld      (p127_irq_test_ix),ix
        ld      (p127_irq_test_iy),iy
        push    af
        pop     hl
        ld      (p127_irq_test_af),hl
        exx
        ld      (p127_irq_test_bc_alt),bc
        ld      (p127_irq_test_de_alt),de
        ld      (p127_irq_test_hl_alt),hl
        exx
        ex      af,af'
        push    af
        pop     hl
        ld      (p127_irq_test_af_alt),hl
        ex      af,af'

        xor     a
        ld      (p127_irq_test_clobber),a

        ld      hl,(p127_irq_test_af)
        ld      de,05A0Ch
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_bc)
        ld      de,01234h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_de)
        ld      de,05678h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_hl)
        ld      de,09ABCh
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_ix)
        ld      de,01357h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_iy)
        ld      de,02468h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_af_alt)
        ld      de,0A5A4h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_bc_alt)
        ld      de,0ABCDh
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_de_alt)
        ld      de,09876h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore
        ld      hl,(p127_irq_test_hl_alt)
        ld      de,05432h
        or      a
        sbc     hl,de
        jp      nz,p127_irq_context_restore

        ; LD A,I exposes IFF2 in P/V; after DI + RETI it must still be zero.
        ld      a,i
        jp      pe,p127_irq_context_restore
        ld      a,1
        ld      (p127_irq_context_result),a

p127_irq_context_restore:
        xor     a
        ld      (p127_irq_test_clobber),a
        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      a,(p127_irq_context_result)
        or      a
        ret     nz
        scf
        ret

p127_irq_test_clobber: db 0
p127_irq_context_result: db 0
p127_irq_test_af: dw 0
p127_irq_test_bc: dw 0
p127_irq_test_de: dw 0
p127_irq_test_hl: dw 0
p127_irq_test_ix: dw 0
p127_irq_test_iy: dw 0
p127_irq_test_af_alt: dw 0
p127_irq_test_bc_alt: dw 0
p127_irq_test_de_alt: dw 0
p127_irq_test_hl_alt: dw 0

p127_irq_mask_state: db 0
p127_irq_vector_owner: db 0
p127_irq_mode_policy: db 0
p127_irq_ready_flags: db 0

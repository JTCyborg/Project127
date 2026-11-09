; ============================================================================
; Project127 — resident-window contract / software preflight
; Module version: 0.4.0
; Defines the only first-stage remap candidate without touching hardware.
; W1/P5 owns resident execution+data; W2/P2 owns resident stack/control.
; W3 is the only candidate target and may be used only after UI quiescence.
; W0 is ROM. No OUT instruction is permitted here.
; ============================================================================
P127_RESIDENT_VERSION_MAJOR EQU 0
P127_RESIDENT_VERSION_MINOR EQU 4
P127_RESIDENT_VERSION_PATCH EQU 0

; The remap-critical resident module is deliberately placed first after the
; Stage2 boot body. W1/P5 is the fixed execution/data window; W2/P2 is the
; fixed stack window; W3 is the only target. This preflight checks the linked
; addresses and current live stack at runtime. It performs no page OUT.
p127_resident_start:

P127_RESIDENT_CODE_WINDOW  EQU 1
P127_RESIDENT_CODE_PAGE    EQU 5
P127_RESIDENT_STACK_WINDOW EQU 2
P127_RESIDENT_STACK_PAGE   EQU 2
P127_RESIDENT_TARGET       EQU 3
P127_RESIDENT_UI_QUIESCED  EQU 1

; IN: A=target window, B=resident code window, C=resident stack window,
;     D=flags (bit 0 set means UI is quiesced).
; OUT: carry=0 if the fixed resident contract is satisfied; carry=1 otherwise.
; This is a software contract check, not a physical mapping operation.
p127_resident_validate:
        ld      (p127_resident_arg_target),a
        ld      a,b
        ld      (p127_resident_arg_code),a
        ld      a,c
        ld      (p127_resident_arg_stack),a
        ld      a,d
        ld      (p127_resident_arg_flags),a

        ld      a,(p127_resident_arg_target)
        cp      P127_RESIDENT_TARGET
        jp      nz,p127_resident_reject
        ld      a,(p127_resident_arg_code)
        cp      P127_RESIDENT_CODE_WINDOW
        jp      nz,p127_resident_reject
        ld      a,(p127_resident_arg_stack)
        cp      P127_RESIDENT_STACK_WINDOW
        jp      nz,p127_resident_reject
        ld      a,(p127_resident_arg_flags)
        and     P127_RESIDENT_UI_QUIESCED
        jp      z,p127_resident_reject
        ; Explicitly assert target is distinct from both resident windows.
        ld      a,(p127_resident_arg_target)
        cp      P127_RESIDENT_CODE_WINDOW
        jp      z,p127_resident_reject
        cp      P127_RESIDENT_STACK_WINDOW
        jp      z,p127_resident_reject
        or      a
        ret

p127_resident_reject:
        scf
        ret

; Synthetic software-only tests: accepted W3 with UI quiesced; reject W1,
; reject W2, reject active UI, and reject a displaced resident code window.
p127_resident_selftest:
        ld      a,3
        ld      b,1
        ld      c,2
        ld      d,1
        call    p127_resident_validate
        jp      c,p127_resident_test_fail

        ld      a,1
        ld      b,1
        ld      c,2
        ld      d,1
        call    p127_resident_validate
        jp      nc,p127_resident_test_fail

        ld      a,2
        ld      b,1
        ld      c,2
        ld      d,1
        call    p127_resident_validate
        jp      nc,p127_resident_test_fail

        ld      a,3
        ld      b,1
        ld      c,2
        ld      d,0
        call    p127_resident_validate
        jp      nc,p127_resident_test_fail

        ld      a,3
        ld      b,0
        ld      c,2
        ld      d,1
        call    p127_resident_validate
        jp      nc,p127_resident_test_fail
        or      a
        ret

p127_resident_test_fail:
        scf
        ret

p127_resident_arg_target:
        db      0
p127_resident_arg_code:
        db      0
p127_resident_arg_stack:
        db      0
p127_resident_arg_flags:
        db      0


; W3 ownership / UI quiesce state machine. Software only; no page OUT.
P127_W3_STATE_UI_ACTIVE EQU 1
P127_W3_STATE_QUIESCED EQU 2
P127_W3_OWNER_UI EQU 1
P127_W3_OWNER_NONE EQU 0
P127_W3_OWNER_HANDOFF EQU 2

p127_w3_init:
        ld      a,P127_W3_STATE_UI_ACTIVE
        ld      (p127_w3_state),a
        ld      a,P127_W3_OWNER_UI
        ld      (p127_w3_owner),a
        xor     a
        ld      (p127_w3_busy),a
        or      a
        ret

p127_w3_ui_enter:
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_UI_ACTIVE
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_UI
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_busy)
        or      a
        jr      nz,p127_w3_reject
        ld      a,1
        ld      (p127_w3_busy),a
        or      a
        ret

p127_w3_ui_leave:
        xor     a
        ld      (p127_w3_busy),a
        ret

p127_w3_quiesce:
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_UI_ACTIVE
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_UI
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_busy)
        or      a
        jr      nz,p127_w3_reject
        ld      a,P127_W3_STATE_QUIESCED
        ld      (p127_w3_state),a
        xor     a
        ld      (p127_w3_owner),a
        or      a
        ret

p127_w3_handoff_acquire:
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_QUIESCED
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_owner)
        or      a
        jr      nz,p127_w3_reject
        ld      a,P127_W3_OWNER_HANDOFF
        ld      (p127_w3_owner),a
        or      a
        ret

p127_w3_handoff_release:
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_QUIESCED
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_HANDOFF
        jr      nz,p127_w3_reject
        xor     a
        ld      (p127_w3_owner),a
        or      a
        ret

p127_w3_resume:
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_QUIESCED
        jr      nz,p127_w3_reject
        ld      a,(p127_w3_owner)
        or      a
        jr      nz,p127_w3_reject
        ld      a,P127_W3_OWNER_UI
        ld      (p127_w3_owner),a
        ld      a,P127_W3_STATE_UI_ACTIVE
        ld      (p127_w3_state),a
        or      a
        ret

p127_w3_reject:
        scf
        ret

p127_w3_selftest:
        call    p127_w3_init
        call    p127_w3_ui_enter
        jp      c,p127_w3_test_fail
        call    p127_w3_quiesce
        jp      nc,p127_w3_test_fail
        call    p127_w3_ui_leave
        call    p127_w3_quiesce
        jp      c,p127_w3_test_fail
        call    p127_w3_ui_enter
        jp      nc,p127_w3_test_fail
        call    p127_w3_handoff_acquire
        jp      c,p127_w3_test_fail
        call    p127_w3_quiesce
        jp      nc,p127_w3_test_fail
        call    p127_w3_ui_enter
        jp      nc,p127_w3_test_fail
        call    p127_w3_handoff_release
        jp      c,p127_w3_test_fail
        call    p127_w3_resume
        jp      c,p127_w3_test_fail
        call    p127_w3_resume
        jp      nc,p127_w3_test_fail
        call    p127_w3_ui_enter
        jp      c,p127_w3_test_fail
        call    p127_w3_ui_leave
        or      a
        ret

p127_w3_test_fail:
        call    p127_w3_init
        scf
        ret

; Save/restore the complete software W3 ownership tuple.
; Snapshot and rollback are RAM-only; they never touch page registers.
p127_w3_snapshot:
        ld      a,(p127_w3_state)
        ld      (p127_w3_saved_state),a
        ld      a,(p127_w3_owner)
        ld      (p127_w3_saved_owner),a
        ld      a,(p127_w3_busy)
        ld      (p127_w3_saved_busy),a
        or      a
        ret

p127_w3_rollback:
        ld      a,(p127_w3_saved_state)
        ld      (p127_w3_state),a
        ld      a,(p127_w3_saved_owner)
        ld      (p127_w3_owner),a
        ld      a,(p127_w3_saved_busy)
        ld      (p127_w3_busy),a
        or      a
        ret

; Recovery tests: reject a competing acquire, preserve a busy UI when
; quiesce is refused, roll back a partial HANDOFF acquire, reject a
; transition from HANDOFF, then resume and prove UI admission works again.
p127_w3_recovery_selftest:
        call    p127_w3_init

        ; Acquisition from UI_ACTIVE/UI must fail without mutating state.
        call    p127_w3_snapshot
        call    p127_w3_handoff_acquire
        jp      nc,p127_w3_recovery_fail
        call    p127_w3_rollback
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_UI_ACTIVE
        jp      nz,p127_w3_recovery_fail
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_UI
        jp      nz,p127_w3_recovery_fail

        ; A busy UI cannot quiesce; rollback must retain the active lease.
        call    p127_w3_ui_enter
        jp      c,p127_w3_recovery_fail
        call    p127_w3_snapshot
        call    p127_w3_quiesce
        jp      nc,p127_w3_recovery_fail
        call    p127_w3_rollback
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_UI_ACTIVE
        jp      nz,p127_w3_recovery_fail
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_UI
        jp      nz,p127_w3_recovery_fail
        ld      a,(p127_w3_busy)
        cp      1
        jp      nz,p127_w3_recovery_fail
        call    p127_w3_ui_leave

        ; Quiesce, snapshot, acquire HANDOFF, reject an invalid transition,
        ; then restore the complete pre-acquire state.
        call    p127_w3_quiesce
        jp      c,p127_w3_recovery_fail
        call    p127_w3_snapshot
        call    p127_w3_handoff_acquire
        jp      c,p127_w3_recovery_fail
        call    p127_w3_quiesce
        jp      nc,p127_w3_recovery_fail
        call    p127_w3_rollback
        ld      a,(p127_w3_state)
        cp      P127_W3_STATE_QUIESCED
        jp      nz,p127_w3_recovery_fail
        ld      a,(p127_w3_owner)
        cp      P127_W3_OWNER_NONE
        jp      nz,p127_w3_recovery_fail
        ld      a,(p127_w3_busy)
        or      a
        jp      nz,p127_w3_recovery_fail

        ; Recovery must leave the UI usable, not merely restore bytes.
        call    p127_w3_resume
        jp      c,p127_w3_recovery_fail
        call    p127_w3_ui_enter
        jp      c,p127_w3_recovery_fail
        call    p127_w3_ui_leave
        or      a
        ret

p127_w3_recovery_fail:
        call    p127_w3_init
        scf
        ret

p127_w3_state: db 0
p127_w3_owner: db 0
p127_w3_busy: db 0
p127_w3_saved_state: db 0
p127_w3_saved_owner: db 0
p127_w3_saved_busy: db 0


; ---------------------------------------------------------------------------
; Stage 2.10 — real-address resident trampoline preflight (software only).
; Requires DI on entry; DI is asserted again and interrupts remain disabled.
; Z80 does not provide a general instruction to read/restore prior IFF1, so
; this entry contract intentionally does not attempt an EI/IFF round trip.
; W1 is #4000-#7FFF; W2 is #8000-#BFFF. The linked resident module must fit
; wholly in W1, all resident state is inside that module, and the live stack
; must be in W2. No page register is written.
p127_resident_trampoline_preflight:
        di
        ; Linked code and data must remain wholly inside the fixed W1 window.
        ld      hl,p127_resident_start
        ld      de,06000h
        or      a
        sbc     hl,de
        jp      c,p127_resident_trampoline_fail

        ld      hl,p127_resident_end
        ld      de,08000h
        or      a
        sbc     hl,de
        jp      nc,p127_resident_trampoline_fail

        ; Representative mutable state must be within the resident module.
        ld      hl,p127_w3_state
        ld      de,p127_resident_start
        or      a
        sbc     hl,de
        jp      c,p127_resident_trampoline_fail

        ld      hl,p127_w3_state
        ld      de,p127_resident_end
        or      a
        sbc     hl,de
        jp      nc,p127_resident_trampoline_fail

        ; CALL has already pushed its return address. The live stack must
        ; still be within W2, independent of W3's mapping.
        ld      hl,0
        add     hl,sp
        ld      de,0B000h
        or      a
        sbc     hl,de
        jp      c,p127_resident_trampoline_fail

        ld      hl,0
        add     hl,sp
        ld      de,0C000h
        or      a
        sbc     hl,de
        jp      nc,p127_resident_trampoline_fail

        or      a
        ret

p127_resident_trampoline_fail:
        scf
        ret

p127_resident_end:

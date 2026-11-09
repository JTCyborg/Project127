; ============================================================================
; Project127 — resident-window contract / software preflight
; Module version: 0.1.0
; Defines the only first-stage remap candidate without touching hardware.
; W1/P5 owns resident execution+data; W2/P2 owns resident stack/control.
; W3 is the only candidate target and may be used only after UI quiescence.
; W0 is ROM. No OUT instruction is permitted here.
; ============================================================================
P127_RESIDENT_VERSION_MAJOR EQU 0
P127_RESIDENT_VERSION_MINOR EQU 1
P127_RESIDENT_VERSION_PATCH EQU 0

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
p127_resident_end:

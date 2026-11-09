; ============================================================================
; Project127 — resident stack handoff probe
; Module version: 0.1.0
; Runs from the resident Stage2 image in W1/P5. Scratch stack is a bounded
; test area in the still-mapped W2/P2. No page port is written.
; ============================================================================
P127_HANDOFF_VERSION_MAJOR EQU 0
P127_HANDOFF_VERSION_MINOR EQU 1
P127_HANDOFF_VERSION_PATCH EQU 0

; Current bootstrap stack is at #BFFF in W2/P2. Keep at least 128 bytes
; between its low-water boundary and the scratch stack.
P127_HANDOFF_MIN_OLD_SP    EQU 0B900h
P127_HANDOFF_STACK_BOTTOM  EQU 0B800h
P127_HANDOFF_STACK_TOP     EQU 0B880h
P127_HANDOFF_GUARD_LO      EQU 0B7FEh
P127_HANDOFF_GUARD_HI      EQU 0B7FFh

; IN: none.
; OUT: carry=1 on failure; carry=0 on success.
; Preserves BC, DE, HL, IX and IY. AF/flags are return status.
; Requires interrupts disabled. DI is asserted defensively and this routine
; returns with interrupts disabled. IM and interrupt vectors are untouched.
; The active stack must be at/above #B900 after this routine's save frame.
; This is a stack-integrity probe only: W2 remains mapped throughout.
p127_handoff_stack_probe:
        di
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ld      (p127_handoff_saved_sp),sp

        ; Refuse if the live stack has crossed its declared low-water limit.
        ld      hl,0
        add     hl,sp
        ld      de,P127_HANDOFF_MIN_OLD_SP
        or      a
        sbc     hl,de
        jp      c,p127_handoff_stack_refuse

        ; Canary bytes bracket the unused gap below the scratch stack.
        ld      a,0A5h
        ld      (P127_HANDOFF_GUARD_LO),a
        ld      a,05Ah
        ld      (P127_HANDOFF_GUARD_HI),a

        ; Switch only the software stack pointer. W2/P2 stays mapped.
        ld      sp,P127_HANDOFF_STACK_TOP
        ld      hl,01357h
        push    hl
        ld      de,02468h
        push    de
        call    p127_handoff_stack_inner
        jp      c,p127_handoff_stack_fail
        pop     de
        ld      hl,02468h
        or      a
        sbc     hl,de
        jp      nz,p127_handoff_stack_fail
        pop     hl
        ld      de,01357h
        or      a
        sbc     hl,de
        jp      nz,p127_handoff_stack_fail

        ld      a,(P127_HANDOFF_GUARD_LO)
        cp      0A5h
        jp      nz,p127_handoff_stack_fail
        ld      a,(P127_HANDOFF_GUARD_HI)
        cp      05Ah
        jp      nz,p127_handoff_stack_fail

        xor     a
        ld      (p127_handoff_result),a
        jp      p127_handoff_stack_restore

p127_handoff_stack_fail:
        ld      a,1
        ld      (p127_handoff_result),a
        jp      p127_handoff_stack_restore

p127_handoff_stack_refuse:
        ld      a,2
        ld      (p127_handoff_result),a

p127_handoff_stack_restore:
        ; Restore the exact saved SP before touching the caller's saved frame.
        ld      sp,(p127_handoff_saved_sp)
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      a,(p127_handoff_result)
        or      a
        ret     z
        scf
        ret

; Nested CALL/PUSH/POP test on the scratch stack; BC is preserved.
p127_handoff_stack_inner:
        push    bc
        ld      bc,0A55Ah
        push    bc
        pop     bc
        ld      a,b
        cp      0A5h
        jp      nz,p127_handoff_inner_fail
        ld      a,c
        cp      05Ah
        jp      nz,p127_handoff_inner_fail
        pop     bc
        or      a
        ret
p127_handoff_inner_fail:
        pop     bc
        scf
        ret

p127_handoff_saved_sp:
        dw      0
p127_handoff_result:
        db      0
p127_handoff_end:

; ============================================================================
; Project127 ATM Core — pure software page-mapper model
; Module version: 0.3.0
; No hardware OUT instructions are permitted in this stage.
; ============================================================================
P127_MAP_VERSION_MAJOR EQU 0
P127_MAP_VERSION_MINOR EQU 3
P127_MAP_VERSION_PATCH EQU 0

P127_MAP_WINDOW_COUNT  EQU 4
P127_MAP_ROM            EQU 0FFh

; Shadow map reflects the verified bootstrap layout:
; W0=TR-DOS ROM, W1=RAM P5, W2=RAM P2, W3=RAM P0.
; This table is descriptive state only; it does not program hardware.
p127_map_init:
        ld      a,P127_MAP_ROM
        ld      (p127_map_shadow),a
        ld      a,5
        ld      (p127_map_shadow+1),a
        ld      a,2
        ld      (p127_map_shadow+2),a
        ld      a,0
        ld      (p127_map_shadow+3),a
        or      a
        ret

; Encode physical RAM page ID as the ATM dispatcher byte.
; IN: A=physical page 0..63.
; OUT: A=7Fh-page; carry=1 for invalid page.
p127_map_encode_page:
        cp      64
        jp      nc,p127_map_invalid
        ld      b,a
        ld      a,07Fh
        sub     b
        or      a
        ret

; Return the hardware shadow-port address for a CPU window.
; IN: A=window 0..3. OUT: HL=port; carry=1 for invalid window.
; This routine returns an address only; it never performs I/O.
p127_map_window_port:
        or      a
        jr      z,p127_map_port_w0
        cp      1
        jr      z,p127_map_port_w1
        cp      2
        jr      z,p127_map_port_w2
        cp      3
        jr      z,p127_map_port_w3
        scf
        ret
p127_map_port_w0:
        ld      hl,03FF7h
        or      a
        ret
p127_map_port_w1:
        ld      hl,07FF7h
        or      a
        ret
p127_map_port_w2:
        ld      hl,0BFF7h
        or      a
        ret
p127_map_port_w3:
        ld      hl,0FFF7h
        or      a
        ret

; Read the software shadow entry.
; IN: A=window 0..3. OUT: A=page ID or FFh (ROM); carry=1 if invalid.
p127_map_get_shadow:
        cp      P127_MAP_WINDOW_COUNT
        jp      nc,p127_map_invalid
        ld      e,a
        ld      d,0
        ld      hl,p127_map_shadow
        add     hl,de
        ld      a,(hl)
        or      a
        ret

; Stage 0.1 self-test: encoding, invalid page, all window ports and shadow map.
; OUT: carry=1 on any mismatch. No hardware registers are touched.
p127_map_selftest:
        ld      a,0
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      07Fh
        jp      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      07Eh
        jp      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      07Ch
        jp      nz,p127_map_test_fail
        ld      a,5
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      07Ah
        jp      nz,p127_map_test_fail
        ld      a,7
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      078h
        jp      nz,p127_map_test_fail
        ld      a,63
        call    p127_map_encode_page
        jp      c,p127_map_test_fail
        cp      040h
        jp      nz,p127_map_test_fail
        ld      a,64
        call    p127_map_encode_page
        jp      nc,p127_map_test_fail

        ld      a,0
        call    p127_map_window_port
        jp      c,p127_map_test_fail
        ld      de,03FF7h
        or      a
        sbc     hl,de
        jp      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_window_port
        jp      c,p127_map_test_fail
        ld      de,07FF7h
        or      a
        sbc     hl,de
        jp      nz,p127_map_test_fail
        ld      a,2
        call    p127_map_window_port
        jp      c,p127_map_test_fail
        ld      de,0BFF7h
        or      a
        sbc     hl,de
        jp      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_window_port
        jp      c,p127_map_test_fail
        ld      de,0FFF7h
        or      a
        sbc     hl,de
        jp      nz,p127_map_test_fail
        ld      a,4
        call    p127_map_window_port
        jp      nc,p127_map_test_fail

        call    p127_map_init
        ld      a,0
        call    p127_map_get_shadow
        cp      P127_MAP_ROM
        jp      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_get_shadow
        cp      5
        jp      nz,p127_map_test_fail
        ld      a,2
        call    p127_map_get_shadow
        cp      2
        jp      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_get_shadow
        cp      0
        jp      nz,p127_map_test_fail
        ld      a,4
        call    p127_map_get_shadow
        jp      nc,p127_map_test_fail
        or      a
        ret


; ---------------------------------------------------------------------------
; Safe-remap preparation gate (software-only).
; IN: A=target window 0..3, B=new physical page 0..63,
;     C=bitmask of protected windows (bit 0=W0 ... bit 3=W3).
; OUT: carry=1 if invalid/protected; carry=0 if a pending request is staged.
; This routine NEVER writes a page port and NEVER changes the active map.
; Caller must include execution, stack, UI, interrupt and host/staging windows
; in C. The bootstrap currently protects all four windows (#0F).
p127_map_handoff_prepare:
        ; Keep the target in E, invalidate any older staged request, then
        ; validate the page/window and index the four-byte mask with DE=0:E.
        ld      e,a
        xor     a
        ld      (p127_map_pending_valid),a
        ld      a,b
        cp      64
        jp      nc,p127_map_handoff_reject
        ld      a,e
        cp      P127_MAP_WINDOW_COUNT
        jp      nc,p127_map_handoff_reject
        ld      d,0
        ld      hl,p127_map_window_mask
        add     hl,de
        ld      a,(hl)
        and     c
        jp      nz,p127_map_handoff_reject
        ld      a,e
        ld      (p127_map_pending_window),a
        ld      a,b
        ld      (p127_map_pending_page),a
        ld      a,1
        ld      (p127_map_pending_valid),a
        or      a
        ret

; Cancel a staged request. No hardware state is modified.
p127_map_handoff_abort:
        xor     a
        ld      (p127_map_pending_valid),a
        ret

; Exercise protected-window rejection and a synthetic safe-window preparation.
; This test does not issue OUT and does not commit a physical mapping.
p127_map_handoff_selftest:
        call    p127_map_handoff_abort
        ld      b,10
        ld      c,0Fh
        ld      a,0
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,1
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,2
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,3
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail

        ; Synthetic case: W0 is declared stable; W1-W3 remain protected.
        ld      b,10
        ld      c,0Eh
        ld      a,0
        call    p127_map_handoff_prepare
        jp      c,p127_map_test_fail
        ld      a,(p127_map_pending_valid)
        cp      1
        jp      nz,p127_map_test_fail
        ld      a,(p127_map_pending_window)
        or      a
        jp      nz,p127_map_test_fail
        ld      a,(p127_map_pending_page)
        cp      10
        jp      nz,p127_map_test_fail
        ; A rejected request must invalidate a previously staged request.
        ld      b,10
        ld      c,0Fh
        ld      a,0
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,(p127_map_pending_valid)
        or      a
        jp      nz,p127_map_test_fail

        ; Explicit abort remains idempotent.
        call    p127_map_handoff_abort
        ld      a,(p127_map_pending_valid)
        or      a
        jp      nz,p127_map_test_fail

        ; Reject invalid window and page even if no windows are protected.
        ld      b,10
        ld      c,0
        ld      a,4
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,(p127_map_pending_valid)
        or      a
        jp      nz,p127_map_test_fail
        ld      b,64
        ld      a,0
        call    p127_map_handoff_prepare
        jp      nc,p127_map_test_fail
        ld      a,(p127_map_pending_valid)
        or      a
        jp      nz,p127_map_test_fail
        or      a
        ret

p127_map_window_mask:
        db      1,2,4,8
p127_map_pending_valid:
        db      0
p127_map_pending_window:
        db      0
p127_map_pending_page:
        db      0

; Shared rejection target for handoff preflight (carry=1).
p127_map_handoff_reject:
        scf
        ret

p127_map_invalid:
        scf
        ret
p127_map_test_fail:
        scf
        ret

p127_map_shadow:
        ds      P127_MAP_WINDOW_COUNT,0
; ---------------------------------------------------------------------------
; Stage 2.14 — software-only transactional shadow-map update.
; Full four-window snapshot; commit changes RAM shadow state only.
; Rollback restores all four bytes, including after injected post-commit fault.
; No page-port OUT is performed by any routine in this block.
;
; txn_begin: A=window, B=new RAM page, C=protected-window mask.
; txn_commit: commits pending page into software shadow map.
; txn_rollback: restores complete snapshot and closes transaction.
; txn_accept: closes committed transaction while retaining new shadow map.
; ---------------------------------------------------------------------------
p127_map_txn_begin:
        call    p127_map_handoff_prepare
        ret     c
        ld      hl,p127_map_shadow
        ld      de,p127_map_txn_snapshot
        ld      bc,P127_MAP_WINDOW_COUNT
        ldir
        ld      a,(p127_map_pending_window)
        ld      (p127_map_txn_window),a
        ld      a,(p127_map_pending_page)
        ld      (p127_map_txn_page),a
        ld      a,1
        ld      (p127_map_txn_active),a
        xor     a
        ld      (p127_map_txn_committed),a
        or      a
        ret

p127_map_txn_commit:
        ld      a,(p127_map_txn_active)
        cp      1
        jp      nz,p127_map_txn_reject
        ld      a,(p127_map_pending_valid)
        cp      1
        jp      nz,p127_map_txn_reject
        ld      a,(p127_map_pending_window)
        ld      b,a
        ld      a,(p127_map_txn_window)
        cp      b
        jp      nz,p127_map_txn_reject
        ld      a,(p127_map_pending_page)
        ld      b,a
        ld      a,(p127_map_txn_page)
        cp      b
        jp      nz,p127_map_txn_reject
        ld      a,(p127_map_txn_window)
        cp      P127_MAP_WINDOW_COUNT
        jp      nc,p127_map_txn_reject
        ld      e,a
        ld      d,0
        ld      hl,p127_map_shadow
        add     hl,de
        ld      a,(p127_map_txn_page)
        ld      (hl),a
        ld      a,1
        ld      (p127_map_txn_committed),a
        or      a
        ret

p127_map_txn_rollback:
        ld      a,(p127_map_txn_active)
        cp      1
        jp      nz,p127_map_txn_reject
        ld      hl,p127_map_txn_snapshot
        ld      de,p127_map_shadow
        ld      bc,P127_MAP_WINDOW_COUNT
        ldir
        xor     a
        ld      (p127_map_txn_active),a
        ld      (p127_map_txn_committed),a
        ld      (p127_map_pending_valid),a
        or      a
        ret

p127_map_txn_accept:
        ld      a,(p127_map_txn_active)
        cp      1
        jp      nz,p127_map_txn_reject
        ld      a,(p127_map_txn_committed)
        cp      1
        jp      nz,p127_map_txn_reject
        xor     a
        ld      (p127_map_txn_active),a
        ld      (p127_map_txn_committed),a
        ld      (p127_map_pending_valid),a
        or      a
        ret

p127_map_txn_selftest:
        call    p127_map_init
        call    p127_map_handoff_abort
        ld      b,10
        ld      c,0Eh
        ld      a,0
        call    p127_map_txn_begin
        jp      c,p127_map_txn_test_fail
        call    p127_map_txn_commit
        jp      c,p127_map_txn_test_fail
        ld      a,(p127_map_shadow)
        cp      10
        jp      nz,p127_map_txn_test_fail
        ; Inject a failure after the software shadow-map commit.
        call    p127_map_txn_rollback
        jp      c,p127_map_txn_test_fail
        ld      a,(p127_map_shadow)
        cp      P127_MAP_ROM
        jp      nz,p127_map_txn_test_fail
        ld      a,(p127_map_shadow+1)
        cp      5
        jp      nz,p127_map_txn_test_fail
        ld      a,(p127_map_shadow+2)
        cp      2
        jp      nz,p127_map_txn_test_fail
        ld      a,(p127_map_shadow+3)
        or      a
        jp      nz,p127_map_txn_test_fail
        ; Successful software commit retains the new shadow entry.
        ld      b,11
        ld      c,0Eh
        ld      a,0
        call    p127_map_txn_begin
        jp      c,p127_map_txn_test_fail
        call    p127_map_txn_commit
        jp      c,p127_map_txn_test_fail
        call    p127_map_txn_accept
        jp      c,p127_map_txn_test_fail
        ld      a,(p127_map_shadow)
        cp      11
        jp      nz,p127_map_txn_test_fail
        call    p127_map_init
        call    p127_map_handoff_abort
        or      a
        ret

p127_map_txn_test_fail:
        ld      a,(p127_map_txn_active)
        cp      1
        call    z,p127_map_txn_rollback
        call    p127_map_init
        call    p127_map_handoff_abort
        scf
        ret

p127_map_txn_reject:
        scf
        ret

p127_map_txn_active: db 0
p127_map_txn_committed: db 0
p127_map_txn_window: db 0
p127_map_txn_page: db 0
p127_map_txn_snapshot:
        ds      P127_MAP_WINDOW_COUNT,0
p127_map_end:

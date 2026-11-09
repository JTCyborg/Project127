; ============================================================================
; Project127 ATM Core — pure software page-mapper model
; Module version: 0.1.0
; No hardware OUT instructions are permitted in this stage.
; ============================================================================
P127_MAP_VERSION_MAJOR EQU 0
P127_MAP_VERSION_MINOR EQU 1
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
        jr      nc,p127_map_invalid
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
        jr      nc,p127_map_invalid
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
        jr      c,p127_map_test_fail
        cp      07Fh
        jr      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_encode_page
        jr      c,p127_map_test_fail
        cp      07Eh
        jr      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_encode_page
        jr      c,p127_map_test_fail
        cp      07Ch
        jr      nz,p127_map_test_fail
        ld      a,5
        call    p127_map_encode_page
        jr      c,p127_map_test_fail
        cp      07Ah
        jr      nz,p127_map_test_fail
        ld      a,7
        call    p127_map_encode_page
        jr      c,p127_map_test_fail
        cp      078h
        jr      nz,p127_map_test_fail
        ld      a,63
        call    p127_map_encode_page
        jr      c,p127_map_test_fail
        cp      040h
        jr      nz,p127_map_test_fail
        ld      a,64
        call    p127_map_encode_page
        jr      nc,p127_map_test_fail

        ld      a,0
        call    p127_map_window_port
        jr      c,p127_map_test_fail
        ld      de,03FF7h
        or      a
        sbc     hl,de
        jr      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_window_port
        jr      c,p127_map_test_fail
        ld      de,07FF7h
        or      a
        sbc     hl,de
        jr      nz,p127_map_test_fail
        ld      a,2
        call    p127_map_window_port
        jr      c,p127_map_test_fail
        ld      de,0BFF7h
        or      a
        sbc     hl,de
        jr      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_window_port
        jr      c,p127_map_test_fail
        ld      de,0FFF7h
        or      a
        sbc     hl,de
        jr      nz,p127_map_test_fail
        ld      a,4
        call    p127_map_window_port
        jr      nc,p127_map_test_fail

        call    p127_map_init
        ld      a,0
        call    p127_map_get_shadow
        cp      P127_MAP_ROM
        jr      nz,p127_map_test_fail
        ld      a,1
        call    p127_map_get_shadow
        cp      5
        jr      nz,p127_map_test_fail
        ld      a,2
        call    p127_map_get_shadow
        cp      2
        jr      nz,p127_map_test_fail
        ld      a,3
        call    p127_map_get_shadow
        cp      0
        jr      nz,p127_map_test_fail
        ld      a,4
        call    p127_map_get_shadow
        jr      nc,p127_map_test_fail
        or      a
        ret

p127_map_invalid:
        scf
        ret
p127_map_test_fail:
        scf
        ret

p127_map_shadow:
        ds      P127_MAP_WINDOW_COUNT,0
p127_map_end:

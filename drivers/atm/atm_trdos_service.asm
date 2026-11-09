; =========================================================================
; PROJECT127 TR-DOS catalog service core
; TR-DOS directory: 128 entries x 16 bytes, supplied as a memory buffer.
; No direct hardware assumptions: disk transport will be attached separately.
; API:
;   p127_trdos_catalog_begin: HL=directory buffer, BC=byte length
;   p127_trdos_catalog_next: carry set=end/error; HL=entry, A=index
;   p127_trdos_catalog_count: returns BC=active entries, carry clear
;   selftest: carry clear=pass, A=step on failure
; =========================================================================

P127_TRDOS_DIR_ENTRIES EQU 128
P127_TRDOS_ENTRY_SIZE  EQU 16
P127_TRDOS_DIR_BYTES   EQU 2048

p127_trdos_catalog_begin::
        ld (p127_trdos_dir_base),hl
        ld (p127_trdos_dir_length),bc
        xor a
        ld (p127_trdos_dir_index),a
        ld (p127_trdos_dir_error),a
        ld a,b
        cp 8
        jr c,p127_trdos_catalog_bad_length
        jr nz,p127_trdos_catalog_length_ok
        ld a,c
        or a
        jr z,p127_trdos_catalog_length_ok
p127_trdos_catalog_bad_length:
        ld a,1
        ld (p127_trdos_dir_error),a
        scf
        ret
p127_trdos_catalog_length_ok:
        or a
        ret

; Returns next live directory entry. Free (#00) and deleted (#01) skipped.
; Carry set with A=0 means end; A=1 means malformed input.
p127_trdos_catalog_next::
        ld a,(p127_trdos_dir_error)
        or a
        jr nz,p127_trdos_catalog_next_error
p127_trdos_catalog_next_loop:
        ld a,(p127_trdos_dir_index)
        cp P127_TRDOS_DIR_ENTRIES
        jr nc,p127_trdos_catalog_next_end
        ; offset=index*16
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(p127_trdos_dir_base)
        add hl,de
        ld a,(hl)
        or a
        jr z,p127_trdos_catalog_skip
        cp 1
        jr z,p127_trdos_catalog_skip
        ; A live entry must have a supported TR-DOS file type byte.
        push hl
        ld de,8
        add hl,de
        ld a,(hl)
        cp 'B'
        jr z,p127_trdos_catalog_type_ok
        cp 'C'
        jr z,p127_trdos_catalog_type_ok
        cp 'D'
        jr z,p127_trdos_catalog_type_ok
        cp '#'
        jr z,p127_trdos_catalog_type_ok
        cp '$'
        jr z,p127_trdos_catalog_type_ok
        pop hl
        ld a,2
        ld (p127_trdos_dir_error),a
        jr p127_trdos_catalog_next_error
p127_trdos_catalog_type_ok:
        pop hl
        ld a,(p127_trdos_dir_index)
        inc a
        ld (p127_trdos_dir_index),a
        dec a
        or a
        ret
p127_trdos_catalog_skip:
        ld a,(p127_trdos_dir_index)
        inc a
        ld (p127_trdos_dir_index),a
        jr p127_trdos_catalog_next_loop
p127_trdos_catalog_next_end:
        xor a
        scf
        ret
p127_trdos_catalog_next_error:
        ld a,(p127_trdos_dir_error)
        scf
        ret

; Count all live records, preserving iterator-independent directory base.
p127_trdos_catalog_count::
        ld hl,(p127_trdos_dir_base)
        ld bc,P127_TRDOS_DIR_BYTES
        call p127_trdos_catalog_begin
        ret c
        ld bc,0
p127_trdos_catalog_count_loop:
        push bc
        call p127_trdos_catalog_next
        pop bc
        jr c,p127_trdos_catalog_count_done
        inc bc
        jr p127_trdos_catalog_count_loop
p127_trdos_catalog_count_done:
        ld a,(p127_trdos_dir_error)
        or a
        jr nz,p127_trdos_catalog_count_error
        or a
        ret
p127_trdos_catalog_count_error:
        ld a,(p127_trdos_dir_error)
        scf
        ret

; Synthetic test: one free, one deleted, two live records, final boundary.
p127_trdos_catalog_selftest::
        ld hl,p127_trdos_test_directory
        ld bc,P127_TRDOS_DIR_BYTES
        call p127_trdos_catalog_begin
        jr c,p127_trdos_test_fail_1
        call p127_trdos_catalog_count
        jr c,p127_trdos_test_fail_2
        ld a,b
        or a
        jr nz,p127_trdos_test_fail_3
        ld a,c
        cp 2
        jr nz,p127_trdos_test_fail_3
        ; First live record must be directory index 2.
        ld hl,p127_trdos_test_directory
        ld bc,P127_TRDOS_DIR_BYTES
        call p127_trdos_catalog_begin
        call p127_trdos_catalog_next
        jr c,p127_trdos_test_fail_4
        cp 2
        jr nz,p127_trdos_test_fail_4
        ; Next live record must be index 127 (last directory slot).
        call p127_trdos_catalog_next
        jr c,p127_trdos_test_fail_5
        cp 127
        jr nz,p127_trdos_test_fail_5
        call p127_trdos_catalog_next
        jr nc,p127_trdos_test_fail_6
        or a
        jr nz,p127_trdos_test_fail_6
        xor a
        ret
p127_trdos_test_fail_1: ld a,1
        jr p127_trdos_test_fail
p127_trdos_test_fail_2: ld a,2
        jr p127_trdos_test_fail
p127_trdos_test_fail_3: ld a,3
        jr p127_trdos_test_fail
p127_trdos_test_fail_4: ld a,4
        jr p127_trdos_test_fail
p127_trdos_test_fail_5: ld a,5
        jr p127_trdos_test_fail
p127_trdos_test_fail_6: ld a,6
p127_trdos_test_fail:
        scf
        ret

p127_trdos_dir_base: dw 0
p127_trdos_dir_length: dw 0
p127_trdos_dir_index: db 0
p127_trdos_dir_error: db 0
p127_trdos_test_directory:
        ; Slots 0-1 are free; slot 2 is a one-sector BASIC file.
        defs 2*P127_TRDOS_ENTRY_SIZE,0
        db "TEST    ",'B',0,0,1,1,0,0
        ; Slots 3-126 are free; slot 127 is a 512-byte CODE file.
        defs (P127_TRDOS_DIR_ENTRIES-3-1)*P127_TRDOS_ENTRY_SIZE,0
        db "LAST    ",'C',0,0,0,2,0,0
p127_trdos_test_directory_end:
p127_trdos_service_end:
        ASSERT p127_trdos_test_directory_end-p127_trdos_test_directory=P127_TRDOS_DIR_BYTES
        ASSERT p127_trdos_service_end<=#A000

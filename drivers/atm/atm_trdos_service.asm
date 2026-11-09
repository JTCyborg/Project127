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


; -------------------------------------------------------------------------
; Read and dump the real TR-DOS catalog of drive A.
; Uses the proven TR-DOS ROM gateway at #3D13 and the canonical 8-sector
; catalog buffer at #C800. This is a read-only operation.
; -------------------------------------------------------------------------
P127_TRDOS_DumpCatalog::
        ld      hl,p127_trdos_log_read
        call    p127_host_debug_string
        xor     a
        ld      (#5D19),a
        ld      (#5CF6),a
        ld      (#5CF8),a
        ld      (#5CF9),a
        ld      (#5D09),a
        ld      (#5D19),a
        ld      bc,1
        call    P127_TRDOS_ExecuteCommand
        ; Read track 0, sectors 0..7 into the proven catalog buffer.
        ld      bc,#0805
        ld      de,0
        ld      hl,#C800
        call    P127_TRDOS_ExecuteCommand
        ; Wait for the TR-DOS command-active flag to clear, bounded.
        ld      de,#FFFF
p127_trdos_wait_done:
        ld      a,(#5D11)
        or      a
        jr      z,p127_trdos_catalog_read_done
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_trdos_wait_done
        call    P127_Console_Restore
        ld      hl,p127_trdos_log_timeout
        jp      p127_host_debug_string
p127_trdos_catalog_read_done:
        call    P127_Console_Restore
        ld      hl,#C800
        ld      bc,P127_TRDOS_DIR_BYTES
        call    p127_trdos_catalog_begin
        jr      c,p127_trdos_catalog_dump_error
        ld      hl,p127_trdos_log_header
        call    p127_host_debug_string
p127_trdos_catalog_dump_next:
        call    p127_trdos_catalog_next
        jr      c,p127_trdos_catalog_dump_end
        ld      (p127_trdos_dump_entry),hl
        call    p127_trdos_format_entry
        ld      hl,p127_trdos_log_file
        call    p127_host_debug_string
        ld      hl,p127_trdos_dump_name
        call    p127_host_debug_string
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
        jr      p127_trdos_catalog_dump_next
p127_trdos_catalog_dump_end:
        or      a
        jr      nz,p127_trdos_catalog_dump_error
        ld      hl,p127_trdos_log_pass
        jp      p127_host_debug_string
p127_trdos_catalog_dump_error:
        ld      hl,p127_trdos_log_fail
        jp      p127_host_debug_string

; HL points to a validated 16-byte TR-DOS descriptor.
; Output: p127_trdos_dump_name = trimmed 8-char name + '.' + type.
p127_trdos_format_entry:
        ld      (p127_trdos_dump_entry),hl
        ld      de,p127_trdos_dump_name
        ld      b,8
p127_trdos_format_name:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,p127_trdos_format_name_next
        ld      (de),a
        inc     de
p127_trdos_format_name_next:
        djnz    p127_trdos_format_name
        ld      a,'.'
        ld      (de),a
        inc     de
        ld      hl,(p127_trdos_dump_entry)
        ld      bc,8
        add     hl,bc
        ld      a,(hl)
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        ret

; TR-DOS command gateway, ported from Project127/0/disk.asm.
; Input: BC, DE, HL command parameters. Preserves caller register context.
P127_TRDOS_ExecuteCommand:
        ld      (p127_trdos_save_bc),bc
        ld      (p127_trdos_save_de),de
        ld      (p127_trdos_save_hl),hl
        push    af
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
        push    bc
        ld      a,#10
        ld      bc,#7FFD
        out     (c),a
        pop     bc
        xor     a
        ld      (#5D11),a
        ld      iy,#5C3A
        ld      (p127_trdos_saved_sp),sp
        ld      sp,#FFFF
        ld      bc,(p127_trdos_save_bc)
        ld      de,(p127_trdos_save_de)
        ld      hl,(p127_trdos_save_hl)
        di
        call    #3D13
        di
        ld      sp,(p127_trdos_saved_sp)
        xor     a
        ld      (#5D11),a
        ld      (#5C48),a
        push    bc
        ld      a,#10
        ld      bc,#7FFD
        out     (c),a
        ld      (#5C3B),a
        pop     bc
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
        pop     af
        ret


p127_trdos_dump_entry: dw 0
p127_trdos_save_bc: dw 0
p127_trdos_save_de: dw 0
p127_trdos_save_hl: dw 0
p127_trdos_saved_sp: dw 0
p127_trdos_dump_name: defs 16,0
p127_trdos_log_read: db "[P127] TRDOS CATALOG READ A:",13,10,0
p127_trdos_log_header: db "[P127] TRDOS FILE LIST",13,10,0
p127_trdos_log_file: db "[P127] TRDOS FILE ",0
p127_trdos_log_pass: db "[P127] TRDOS CATALOG READ PASS",13,10,0
p127_trdos_log_fail: db "[P127] TRDOS CATALOG READ FAIL",13,10,0
p127_trdos_log_timeout: db "[P127] TRDOS CATALOG READ TIMEOUT",13,10,0

p127_trdos_dir_base: dw 0
p127_trdos_dir_length: dw 0
p127_trdos_dir_index: db 0
p127_trdos_dir_error: db 0
p127_trdos_test_directory:
        ; Slots 0-1 are free; slot 2 is a one-sector BASIC file.
        defs 2*P127_TRDOS_ENTRY_SIZE,0
        db "TEST    ",'B',0,0,1,1,0,0,1
        ; Slots 3-126 are free; slot 127 is a 512-byte CODE file.
        defs (P127_TRDOS_DIR_ENTRIES-3-1)*P127_TRDOS_ENTRY_SIZE,0
        db "LAST    ",'C',0,2,0,0,0,0,1
p127_trdos_test_directory_end:
p127_trdos_service_end:
        ASSERT p127_trdos_test_directory_end-p127_trdos_test_directory=P127_TRDOS_DIR_BYTES
        ASSERT p127_trdos_service_end<=#A000

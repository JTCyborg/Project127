; ============================================================================
; Project127 TR-DOS directory reader
; Module version: 0.1.0
; Reads track 0 sectors 1..8 via the documented TR-DOS ROM entry #3D13.
; Directory snapshot: 128 * 16 bytes at #C800 (reserved host/staging page P0).
; Read-only: no file-data reads, writes, DMA, IM/EI or raw paging OUT.
; ============================================================================
P127_TRDOS_VERSION_MAJOR EQU 0
P127_TRDOS_VERSION_MINOR EQU 1
P127_TRDOS_VERSION_PATCH EQU 0
P127_TRDOS_DIRECTORY_BUFFER EQU 0C800h
P127_TRDOS_DIRECTORY_BYTES EQU 0800h
P127_TRDOS_ENTRY_COUNT EQU 128
P127_TRDOS_ENTRY_SIZE EQU 16

; Public entry. Returns carry set on sector-read error.
; Output is mirrored by p127_puts/p127_put_char to the visible console and #EF.
p127_trdos_directory:
        ld      hl,p127_trdos_msg_begin
        call    p127_puts
        call    p127_trdos_read_directory
        jr      c,p127_trdos_directory_read_error

        ld      hl,p127_trdos_msg_read_ok
        call    p127_puts
        call    p127_trdos_dump_directory
        ld      hl,p127_trdos_msg_done
        call    p127_puts
        or      a
        ret

p127_trdos_directory_read_error:
        ld      hl,p127_trdos_msg_read_error
        call    p127_puts
        ld      a,(p127_trdos_io_error)
        call    p127_put_hex8
        ld      hl,p127_trdos_msg_status
        call    p127_puts
        ld      a,(p127_trdos_io_status)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        scf
        ret

; Read exactly eight 256-byte directory sectors. The TR-DOS ROM routine
; accepts a zero-based sector in E and internally selects physical sector E+1.
; Its scratch stack is isolated at #BFFF; the caller's live stack is restored.
p127_trdos_read_directory:
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

        ld      (p127_trdos_saved_sp),sp
        ld      sp,0BFFFh
        xor     a
        ld      (p127_trdos_io_error),a
        ld      (p127_trdos_io_status),a
        ld      (p127_trdos_sector_index),a
        ld      hl,P127_TRDOS_DIRECTORY_BUFFER
        ld      (p127_trdos_buffer_ptr),hl

p127_trdos_read_sector:
        ld      a,(p127_trdos_sector_index)
        cp      8
        jr      nc,p127_trdos_read_restore

        ld      e,a
        ld      d,0
        ld      hl,(p127_trdos_buffer_ptr)
        ld      b,1
        ld      c,5
        xor     a
        ld      (05D0Fh),a
        ld      (05D10h),a
        call    03D13h

        ld      a,(05D0Fh)
        ld      (p127_trdos_io_error),a
        ld      b,a
        ld      a,(05D10h)
        ld      (p127_trdos_io_status),a
        or      b
        jr      nz,p127_trdos_read_restore

        ld      hl,(p127_trdos_buffer_ptr)
        ld      de,0100h
        add     hl,de
        ld      (p127_trdos_buffer_ptr),hl
        ld      a,(p127_trdos_sector_index)
        inc     a
        ld      (p127_trdos_sector_index),a
        jr      p127_trdos_read_sector

p127_trdos_read_restore:
        ld      (p127_trdos_read_failed),a
        ld      sp,(p127_trdos_saved_sp)
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
        ld      a,(p127_trdos_read_failed)
        or      a
        jr      nz,p127_trdos_read_return_error
        or      a
        ret
p127_trdos_read_return_error:
        scf
        ret

; Dump every live directory descriptor. TR-DOS descriptor fields used here:
; name[0..7], type[8], sectors[12], first sector[13], logical track[14].
; This is a catalogue display only; it does not dereference file extents.
p127_trdos_dump_directory:
        ld      hl,p127_trdos_msg_dump
        call    p127_puts
        ld      hl,P127_TRDOS_DIRECTORY_BUFFER
        ld      (p127_trdos_entry_ptr),hl
        ld      a,P127_TRDOS_ENTRY_COUNT
        ld      (p127_trdos_slots_left),a
        xor     a
        ld      (p127_trdos_file_count),a

p127_trdos_dump_next:
        ld      ix,(p127_trdos_entry_ptr)
        ld      a,(ix+0)
        or      a
        jr      z,p127_trdos_dump_skip
        cp      1
        jr      z,p127_trdos_dump_skip
        ld      a,(ix+8)
        cp      'B'
        jr      z,p127_trdos_dump_valid
        cp      'C'
        jr      z,p127_trdos_dump_valid
        cp      'D'
        jr      z,p127_trdos_dump_valid
        cp      '#'
        jr      nz,p127_trdos_dump_skip

p127_trdos_dump_valid:
        ld      a,(p127_trdos_file_count)
        inc     a
        ld      (p127_trdos_file_count),a
        ld      hl,p127_trdos_msg_entry
        call    p127_puts

        ld      ix,(p127_trdos_entry_ptr)
        ld      b,8
p127_trdos_dump_name:
        ld      a,(ix+0)
        inc     ix
        call    p127_put_char
        djnz    p127_trdos_dump_name

        ld      a,'.'
        call    p127_put_char
        ld      a,(ix+0)
        call    p127_put_char
        ld      hl,p127_trdos_msg_sectors
        call    p127_puts
        ld      a,(ix+4)
        call    p127_put_hex8
        ld      hl,p127_trdos_msg_start
        call    p127_puts
        ld      a,(ix+6)
        call    p127_put_hex8
        ld      a,':'
        call    p127_put_char
        ld      a,(ix+5)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char

p127_trdos_dump_skip:
        ld      hl,(p127_trdos_entry_ptr)
        ld      de,P127_TRDOS_ENTRY_SIZE
        add     hl,de
        ld      (p127_trdos_entry_ptr),hl
        ld      a,(p127_trdos_slots_left)
        dec     a
        ld      (p127_trdos_slots_left),a
        jr      nz,p127_trdos_dump_next

        ld      hl,p127_trdos_msg_count
        call    p127_puts
        ld      a,(p127_trdos_file_count)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char
        ret

p127_trdos_msg_begin:      db "[TRDOS] DIRECTORY READ BEGIN",13,10,0
p127_trdos_msg_read_ok:    db "[TRDOS] DIRECTORY READ OK; 8 SECTORS / 2048 BYTES",13,10,0
p127_trdos_msg_read_error: db "[TRDOS] DIRECTORY READ ERROR #5D0F=",0
p127_trdos_msg_status:     db " #5D10=",0
p127_trdos_msg_dump:      db "[TRDOS] DIRECTORY ENTRIES:",13,10,0
p127_trdos_msg_entry:     db "[TRDOS] ",0
p127_trdos_msg_sectors:   db " SEC=",0
p127_trdos_msg_start:     db " START=",0
p127_trdos_msg_count:     db "[TRDOS] FILE COUNT=",0
p127_trdos_msg_done:      db "[TRDOS] DIRECTORY DUMP COMPLETE",13,10,0

p127_trdos_saved_sp:      dw 0
p127_trdos_buffer_ptr:    dw P127_TRDOS_DIRECTORY_BUFFER
p127_trdos_entry_ptr:     dw P127_TRDOS_DIRECTORY_BUFFER
p127_trdos_sector_index:  db 0
p127_trdos_slots_left:    db 0
p127_trdos_file_count:    db 0
p127_trdos_io_error:      db 0
p127_trdos_io_status:     db 0
p127_trdos_read_failed:   db 0

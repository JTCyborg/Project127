; ============================================================================
; Project127 Nemo IDE HDD read-only transport
; Module version: 0.1.2
; Port map and LBA28 protocol adapted from Project127/113/src/nemo_ide.asm.
; Only single-sector ATA READ SECTORS (20h) is exposed in this stage.
; No ATA write command, DMA, IRQ, IM/EI or page-port access is used.
; ============================================================================
P127_HDD_VERSION_MAJOR EQU 0
P127_HDD_VERSION_MINOR EQU 1
P127_HDD_VERSION_PATCH EQU 2

P127_HDD_PORT_DATA_LO   EQU 00010h
P127_HDD_PORT_DATA_HI   EQU 00011h
P127_HDD_PORT_COUNT     EQU 00050h
P127_HDD_PORT_LBA_LOW   EQU 00070h
P127_HDD_PORT_LBA_MID   EQU 00090h
P127_HDD_PORT_LBA_HIGH  EQU 000B0h
P127_HDD_PORT_DRIVE     EQU 000D0h
P127_HDD_PORT_STATUS    EQU 000F0h
P127_HDD_PORT_COMMAND   EQU 000F0h

P127_HDD_SECTOR_BYTES   EQU 512
P127_HDD_SECTOR_BUFFER  EQU 0C800h
P127_HDD_PARTITION_LBA  EQU 63

; Probe the Master device and read the legacy Project113 partition boot sector.
; OUT: carry=1 on failure, p127_hdd_error contains the reason.
p127_hdd_probe_read:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy

        xor     a
        ld      (p127_hdd_error),a
        ld      hl,p127_hdd_msg_probe
        call    p127_puts

        ; Non-destructive bus probe before selecting the Master device.
        ld      hl,p127_hdd_msg_status_pre
        call    p127_puts
        ld      bc,P127_HDD_PORT_STATUS
        in      a,(c)
        ld      (p127_hdd_last_status),a
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char

        ld      a,0E0h
        ld      bc,P127_HDD_PORT_DRIVE
        out     (c),a

        ; Read back the task-file device/head register and Status after select.
        ld      hl,p127_hdd_msg_drive_readback
        call    p127_puts
        ld      bc,P127_HDD_PORT_DRIVE
        in      a,(c)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char

        ld      hl,p127_hdd_msg_status_post
        call    p127_puts
        ld      bc,P127_HDD_PORT_STATUS
        in      a,(c)
        ld      (p127_hdd_last_status),a
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char

        call    p127_hdd_wait_ready
        jp      c,p127_hdd_probe_not_ready

        ld      hl,p127_hdd_msg_ready
        call    p127_puts

        ld      a,P127_HDD_PARTITION_LBA
        ld      (p127_hdd_lba),a
        xor     a
        ld      (p127_hdd_lba+1),a
        ld      (p127_hdd_lba+2),a
        ld      (p127_hdd_lba+3),a
        call    p127_hdd_read_sector_lba28
        jp      c,p127_hdd_probe_read_failed

        ld      a,(P127_HDD_SECTOR_BUFFER+11)
        or      a
        jp      nz,p127_hdd_probe_bad_bpb
        ld      a,(P127_HDD_SECTOR_BUFFER+12)
        cp      2
        jp      nz,p127_hdd_probe_bad_bpb

        ld      a,(P127_HDD_SECTOR_BUFFER+510)
        cp      055h
        jp      nz,p127_hdd_probe_bad_signature
        ld      a,(P127_HDD_SECTOR_BUFFER+511)
        cp      0AAh
        jp      nz,p127_hdd_probe_bad_signature

        ld      hl,p127_hdd_msg_read_ok
        call    p127_puts
        jp      p127_hdd_probe_done

p127_hdd_probe_not_ready:
        ld      a,1
        ld      (p127_hdd_error),a
        jp      p127_hdd_probe_report_error
p127_hdd_probe_read_failed:
        jp      p127_hdd_probe_report_error
p127_hdd_probe_bad_bpb:
        ld      a,4
        ld      (p127_hdd_error),a
        jp      p127_hdd_probe_report_error
p127_hdd_probe_bad_signature:
        ld      a,5
        ld      (p127_hdd_error),a

p127_hdd_probe_report_error:
        ld      hl,p127_hdd_msg_error
        call    p127_puts
        ld      a,(p127_hdd_error)
        call    p127_put_hex8
        ld      hl,p127_hdd_msg_status
        call    p127_puts
        ld      a,(p127_hdd_last_status)
        call    p127_put_hex8
        ld      a,13
        call    p127_put_char
        ld      a,10
        call    p127_put_char

p127_hdd_probe_done:
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      a,(p127_hdd_error)
        or      a
        ret     z
        scf
        ret

; Read one 512-byte sector using LBA28.
; Input: p127_hdd_lba = unsigned 28-bit LBA.
; Output: #C800..#C9FF, carry=1 on error.
p127_hdd_read_sector_lba28:
        push    af
        push    bc
        push    de
        push    hl
        push    ix

        xor     a
        ld      (p127_hdd_error),a
        ld      a,(p127_hdd_lba+3)
        and     0F0h
        jp      nz,p127_hdd_read_bad_lba

        call    p127_hdd_wait_ready
        jp      c,p127_hdd_read_io_error

        ld      a,1
        ld      bc,P127_HDD_PORT_COUNT
        out     (c),a
        ld      a,(p127_hdd_lba)
        ld      bc,P127_HDD_PORT_LBA_LOW
        out     (c),a
        ld      a,(p127_hdd_lba+1)
        ld      bc,P127_HDD_PORT_LBA_MID
        out     (c),a
        ld      a,(p127_hdd_lba+2)
        ld      bc,P127_HDD_PORT_LBA_HIGH
        out     (c),a
        ld      a,(p127_hdd_lba+3)
        and     00Fh
        or      0E0h
        ld      bc,P127_HDD_PORT_DRIVE
        out     (c),a

        ld      a,020h
        ld      bc,P127_HDD_PORT_COMMAND
        out     (c),a

        call    p127_hdd_wait_drq
        jp      c,p127_hdd_read_io_error

        ld      ix,P127_HDD_SECTOR_BUFFER
        ld      de,256
p127_hdd_read_word_loop:
        ld      bc,P127_HDD_PORT_DATA_LO
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,P127_HDD_PORT_DATA_HI
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jp      nz,p127_hdd_read_word_loop

        call    p127_hdd_wait_complete
        jp      c,p127_hdd_read_io_error
        jp      p127_hdd_read_done

p127_hdd_read_bad_lba:
        ld      a,2
        ld      (p127_hdd_error),a
        jp      p127_hdd_read_done
p127_hdd_read_io_error:
        ld      a,3
        ld      (p127_hdd_error),a

p127_hdd_read_done:
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      a,(p127_hdd_error)
        or      a
        ret     z
        scf
        ret

p127_hdd_wait_ready:
        push    de
        ld      de,0FFFFh
p127_hdd_ready_loop:
        ld      bc,P127_HDD_PORT_STATUS
        in      a,(c)
        ld      (p127_hdd_last_status),a
        cp      0FFh
        jp      z,p127_hdd_ready_fail
        or      a
        jr      z,p127_hdd_ready_tick
        bit     7,a
        jr      nz,p127_hdd_ready_tick
        bit     0,a
        jp      nz,p127_hdd_ready_fail
        ; Match Project126 ATM bridge: DF is not a READY/DRQ gate.
        bit     6,a
        jr      nz,p127_hdd_ready_ok
p127_hdd_ready_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_hdd_ready_loop
p127_hdd_ready_fail:
        pop     de
        scf
        ret
p127_hdd_ready_ok:
        pop     de
        or      a
        ret

p127_hdd_wait_drq:
        push    de
        ld      de,0FFFFh
p127_hdd_drq_loop:
        ld      bc,P127_HDD_PORT_STATUS
        in      a,(c)
        ld      (p127_hdd_last_status),a
        cp      0FFh
        jp      z,p127_hdd_drq_fail
        or      a
        jr      z,p127_hdd_drq_tick
        bit     7,a
        jr      nz,p127_hdd_drq_tick
        bit     0,a
        jp      nz,p127_hdd_drq_fail
        ; Match Project126 ATM bridge: DF is not a READY/DRQ gate.
        bit     3,a
        jr      nz,p127_hdd_drq_ok
p127_hdd_drq_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_hdd_drq_loop
p127_hdd_drq_fail:
        pop     de
        scf
        ret
p127_hdd_drq_ok:
        pop     de
        or      a
        ret

p127_hdd_wait_complete:
        push    de
        ld      de,0FFFFh
p127_hdd_complete_loop:
        ld      bc,P127_HDD_PORT_STATUS
        in      a,(c)
        ld      (p127_hdd_last_status),a
        cp      0FFh
        jp      z,p127_hdd_complete_fail
        or      a
        jr      z,p127_hdd_complete_tick
        bit     7,a
        jr      nz,p127_hdd_complete_tick
        bit     0,a
        jp      nz,p127_hdd_complete_fail
        ; Match Project126 ATM bridge: DF is not a READY/DRQ gate.
        bit     3,a
        jr      z,p127_hdd_complete_ok
p127_hdd_complete_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,p127_hdd_complete_loop
p127_hdd_complete_fail:
        pop     de
        scf
        ret
p127_hdd_complete_ok:
        pop     de
        or      a
        ret

p127_hdd_msg_probe:   db "[HDD] NEMO IDE LBA28 PROBE",13,10,0
p127_hdd_msg_status_pre: db "[HDD] STATUS PRE-SELECT=",0
p127_hdd_msg_drive_readback: db "[HDD] DRIVE REG READBACK=",0
p127_hdd_msg_status_post: db "[HDD] STATUS POST-SELECT=",0
p127_hdd_msg_ready:   db "[HDD] MASTER READY",13,10,0
p127_hdd_msg_read_ok: db "[HDD] LBA 63 READ OK; 512B / BPB / 55AA",13,10,0
p127_hdd_msg_error:   db "[HDD] ERROR=",0
p127_hdd_msg_status:  db " STATUS=",0

p127_hdd_error: db 0
p127_hdd_last_status: db 0
p127_hdd_lba:   db 0,0,0,0

; FAT16 root-directory support is in p127_hdd_fat16.asm.

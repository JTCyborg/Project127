; =========================================================================
; PROJECT127 — ATM physical storage backend v0.1.0
; Nemo IDE ATA PIO backend. ATM Z80 only.
; Safe startup probe: IDENTIFY DEVICE (no writes during detection).
;
; Public low-level API:
;   P127_Storage_Startup       -> carry clear if supported LBA28 device found
;   P127_Storage_ReadSector   -> IX=512-byte destination, LBA in descriptor
;   P127_Storage_WriteSector  -> IX=512-byte source, LBA in descriptor
;   P127_Storage_Flush        -> flush cache
;   P127_Storage_SetLBA       -> HL=low16, DE=high16 (upper nibble must be 0)
;
; Status: A=0 success, A=error code and carry set on failure.
; Error codes: 1 no device/not ready, 2 ATA ERR, 3 timeout,
;              4 LBA28 unsupported, 5 invalid LBA.
; =========================================================================

; ATM Nemo IDE uses the 16-bit port decode from Project126/kernel/main.asm.
; Do not use the NeoGS-side low-byte aliases (#10..#F0) on the ATM host.
P127_NEMO_DATA_LO       EQU #FE0F
P127_NEMO_DATA_HI       EQU #FF0F
P127_NEMO_ERROR         EQU #FE2F
P127_NEMO_SECTOR_COUNT  EQU #FE4F
P127_NEMO_LBA_LOW       EQU #FE6F
P127_NEMO_LBA_MID       EQU #FE8F
P127_NEMO_LBA_HIGH      EQU #FEAF
P127_NEMO_DRIVE_HEAD    EQU #FECF
P127_NEMO_STATUS_CMD    EQU #FEEF
P127_NEMO_WAIT_LIMIT    EQU #FFFF
P127_STORAGE_VERSION    EQU #0100

P127_Storage_Startup:
        xor     a
        ld      (p127_storage_available),a
        ld      hl,p127_storage_log_select
        call    p127_host_debug_string
        ld      hl,p127_storage_log_wait_ready
        call    p127_host_debug_string
        ; Match the proven Project127/0 sequence: select Master and poll
        ; immediately. Do not run console/debug code between these operations.
        ld      a,#E0                 ; master, LBA mode
        ld      bc,P127_NEMO_DRIVE_HEAD
        out     (c),a
        call    p127_storage_wait_ready
        jr      nc,p127_storage_start_ready
        push    af
        ld      hl,p127_storage_log_status
        call    p127_host_debug_string
        ld      a,(p127_storage_last_status)
        call    p127_host_debug_hex_byte
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
        pop     af
        ret
p127_storage_start_ready:
        ld      hl,p127_storage_log_ready_status
        call    p127_host_debug_string
        ld      a,#EC                 ; IDENTIFY DEVICE
        ld      bc,P127_NEMO_STATUS_CMD
        out     (c),a
        ld      hl,p127_storage_log_identify
        call    p127_host_debug_string
        call    p127_storage_wait_drq
        ret     c
        ld      hl,p127_storage_log_drq
        call    p127_host_debug_string
        ld      ix,p127_storage_identify
        call    p127_storage_read_256_words
        ret     c
        call    p127_storage_wait_complete
        ret     c

        ; Word 49 bit 9 must advertise LBA support.
        ld      a,(p127_storage_identify+99)
        bit     1,a
        jr      z,p127_storage_no_lba
        ; LBA28 capacity is words 60..61 (little-endian).
        ld      hl,(p127_storage_identify+120)
        ld      de,(p127_storage_identify+122)
        ld      (p127_storage_capacity),hl
        ld      (p127_storage_capacity+2),de
        ld      a,h
        or      l
        or      d
        or      e
        jr      z,p127_storage_no_lba
        ; Reject a device whose reported capacity exceeds the LBA28 range.
        ld      a,d
        and     #F0
        jr      nz,p127_storage_no_lba
        ld      a,1
        ld      (p127_storage_available),a
        xor     a
        ret
p127_storage_no_lba:
        ld      a,4
        scf
        ret

; HL=low 16 bits, DE=high 16 bits. Only 28-bit LBA is accepted.
P127_Storage_SetLBA:
        ld      a,d
        and     #F0
        jr      nz,p127_storage_bad_lba
        ld      (p127_storage_lba),hl
        ld      (p127_storage_lba+2),de
        or      a
        ret
p127_storage_bad_lba:
        ld      a,5
        scf
        ret

; IX points to exactly 512 bytes. One ATA sector is transferred per call.
P127_Storage_ReadSector:
        ld      a,#20
        jr      p127_storage_rw_sector
P127_Storage_WriteSector:
        ld      a,#30
p127_storage_rw_sector:
        ld      (p127_storage_command),a
        call    p127_storage_validate_request
        ret     c
        call    p127_storage_program_lba
        ret     c
        ld      a,(p127_storage_command)
        ld      bc,P127_NEMO_STATUS_CMD
        out     (c),a
        call    p127_storage_wait_drq
        ret     c
        ld      a,(p127_storage_command)
        cp      #20
        jr      z,p127_storage_read_data
        call    p127_storage_write_256_words
        jr      c,p127_storage_rw_done
        call    p127_storage_wait_complete
        jr      p127_storage_rw_done
p127_storage_read_data:
        call    p127_storage_read_256_words
        jr      c,p127_storage_rw_done
        call    p127_storage_wait_complete
p127_storage_rw_done:
        ret

P127_Storage_Flush:
        ld      a,(p127_storage_available)
        or      a
        jp      z,p127_storage_not_ready
        ld      a,#E7                 ; FLUSH CACHE
        ld      bc,P127_NEMO_STATUS_CMD
        out     (c),a
        jp      p127_storage_wait_complete

p127_storage_validate_request:
        ld      a,(p127_storage_available)
        or      a
        jp      z,p127_storage_not_ready
        ; Unsigned 32-bit compare: high word first, then low word.
        ld      hl,(p127_storage_lba+2)
        ld      de,(p127_storage_capacity+2)
        or      a
        sbc     hl,de
        jr      c,p127_storage_lba_valid
        jr      nz,p127_storage_bad_lba
        ld      hl,(p127_storage_lba)
        ld      de,(p127_storage_capacity)
        or      a
        sbc     hl,de
        jr      nc,p127_storage_bad_lba
p127_storage_lba_valid:
        or      a
        ret

p127_storage_program_lba:
        ld      a,1
        ld      bc,P127_NEMO_SECTOR_COUNT
        out     (c),a
        ld      hl,(p127_storage_lba)
        ld      a,l
        ld      bc,P127_NEMO_LBA_LOW
        out     (c),a
        ld      a,h
        ld      bc,P127_NEMO_LBA_MID
        out     (c),a
        ld      hl,(p127_storage_lba+2)
        ld      a,l
        ld      bc,P127_NEMO_LBA_HIGH
        out     (c),a
        ld      a,h
        and     #0F
        or      #E0
        ld      bc,P127_NEMO_DRIVE_HEAD
        out     (c),a
        ret

p127_storage_wait_ready:
        ld      de,P127_NEMO_WAIT_LIMIT
.ready:
        ld      bc,P127_NEMO_STATUS_CMD
        in      a,(c)
        ld      (p127_storage_last_status),a
        bit     7,a
        jr      nz,.tick
        bit     0,a
        jp      nz,p127_storage_ata_error
        bit     6,a
        jr      nz,p127_storage_ok
.tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.ready
        jr      p127_storage_timeout

p127_storage_wait_drq:
        ld      de,P127_NEMO_WAIT_LIMIT
.drq:
        ld      bc,P127_NEMO_STATUS_CMD
        in      a,(c)
        bit     7,a
        jr      nz,.tick
        bit     0,a
        jr      nz,p127_storage_ata_error
        bit     3,a
        jr      nz,p127_storage_ok
.tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.drq
        jr      p127_storage_timeout

p127_storage_wait_complete:
        ld      de,P127_NEMO_WAIT_LIMIT
.complete:
        ld      bc,P127_NEMO_STATUS_CMD
        in      a,(c)
        bit     7,a
        jr      nz,.tick
        bit     0,a
        jr      nz,p127_storage_ata_error
        bit     3,a
        jr      z,p127_storage_ok
.tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.complete
        jr      p127_storage_timeout

p127_storage_read_256_words:
        ld      de,256
.read_word:
        ld      bc,P127_NEMO_DATA_LO
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,P127_NEMO_DATA_HI
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,.read_word
        or      a
        ret

p127_storage_write_256_words:
        ld      de,256
.write_word:
        ld      a,(ix+0)
        ld      bc,P127_NEMO_DATA_LO
        out     (c),a
        inc     ix
        ld      a,(ix+0)
        ld      bc,P127_NEMO_DATA_HI
        out     (c),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,.write_word
        or      a
        ret

p127_storage_ok:
        xor     a
        ret
p127_storage_not_ready:
        ld      a,1
        scf
        ret
p127_storage_ata_error:
        ld      a,2
        scf
        ret
p127_storage_timeout:
        ld      a,3
        scf
        ret

p127_storage_available: db 0
p127_storage_last_status: db 0
p127_storage_command:   db 0
p127_storage_lba:       dd 0
p127_storage_capacity:  dd 0
p127_storage_identify:  defs 512,0
p127_storage_log_select:
        db "[P127] HDD PROBE SELECT MASTER",13,10,0
p127_storage_log_wait_ready:
        db "[P127] HDD PROBE WAIT READY",13,10,0
p127_storage_log_status:
        db "[P127] HDD ATA STATUS=0x",0
p127_storage_log_ready_status:
        db "[P127] HDD PROBE DEVICE READY",13,10,0
p127_storage_log_identify:
        db "[P127] HDD PROBE IDENTIFY SENT",13,10,0
p127_storage_log_drq:
        db "[P127] HDD PROBE DRQ RECEIVED",13,10,0
p127_storage_log_ready:
        db "[P127] HDD NEMO IDE LBA28 IDENTIFY PASS",13,10,0
p127_storage_log_missing:
        db "[P127] HDD NEMO IDE NOT AVAILABLE",13,10,0
p127_storage_end:
        ASSERT p127_storage_end <= #D000

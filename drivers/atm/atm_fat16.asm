; =========================================================================
; PROJECT127 — read-only FAT16 mount core v0.1.0
; ATM Z80 / Nemo IDE backend. No disk writes.
;
; API:
;   P127_FAT16_Mount
;       Carry clear: FAT16 partition mounted.
;       Carry set: A=error (20 invalid MBR, 21 no FAT16 partition,
;                  22 invalid BPB; storage errors are passed through).
;   P127_FAT16_ReadRootSector
;       HL = zero-based sector index in FAT16 root directory.
;       Reads one sector into p127_fat16_sector_buffer.
;       Carry clear on success; A=error on failure.
;
; Geometry exported as 32-bit little-endian values:
;   p127_fat16_partition_lba, p127_fat16_fat_lba,
;   p127_fat16_root_lba, p127_fat16_data_lba
; =========================================================================

P127_FAT16_VERSION       EQU #0100
P127_FAT16_ERR_MBR       EQU 20
P127_FAT16_ERR_PARTITION EQU 21
P127_FAT16_ERR_BPB       EQU 22

; Combined storage + filesystem startup is kept outside the 8 KiB host image.
P127_StorageAndFAT16_Startup:
        ld      hl,p127_fat16_log_probe_start
        call    p127_host_debug_string
        call    P127_Storage_Startup
        jr      c,p127_fat16_storage_missing
        ld      hl,p127_storage_log_ready
        call    p127_host_debug_string
        call    P127_FAT16_Mount
        jr      c,p127_fat16_mount_missing
        ld      hl,p127_fat16_log_mounted
        call    p127_host_debug_string
        jp      P127_FAT16_DumpRootDirectory
p127_fat16_storage_missing:
        ld      hl,p127_storage_log_missing
        jp      p127_host_debug_string
p127_fat16_mount_missing:
        ld      hl,p127_fat16_log_failed
        jp      p127_host_debug_string

P127_FAT16_Mount:
        xor     a
        ld      (p127_fat16_available),a
        ld      hl,0
        ld      de,0
        ld      (p127_fat16_io_lba),hl
        ld      (p127_fat16_io_lba+2),de
        call    p127_fat16_read_lba
        ret     c

        ; MBR signature 55 AA.
        ld      a,(p127_fat16_sector_buffer+510)
        cp      #55
        jp      nz,p127_fat16_bad_mbr
        ld      a,(p127_fat16_sector_buffer+511)
        cp      #AA
        jp      nz,p127_fat16_bad_mbr

        ; Search the four primary partition entries for FAT16 types 04/06/0E.
        ld      ix,p127_fat16_sector_buffer+446
        ld      b,4
p127_fat16_partition_scan:
        ld      a,(ix+4)
        cp      #04
        jp      z,p127_fat16_partition_found
        cp      #06
        jp      z,p127_fat16_partition_found
        cp      #0E
        jp      z,p127_fat16_partition_found
        ld      de,16
        add     ix,de
        djnz    p127_fat16_partition_scan
        jp      p127_fat16_no_partition

p127_fat16_partition_found:
        ld      l,(ix+8)
        ld      h,(ix+9)
        ld      e,(ix+10)
        ld      d,(ix+11)
        ld      (p127_fat16_partition_lba),hl
        ld      (p127_fat16_partition_lba+2),de
        ld      (p127_fat16_io_lba),hl
        ld      (p127_fat16_io_lba+2),de
        call    p127_fat16_read_lba
        ret     c

        ; BPB: bytes/sector must be 512.
        ld      hl,(p127_fat16_sector_buffer+11)
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,p127_fat16_bad_bpb

        ; Sectors/cluster must be non-zero.
        ld      a,(p127_fat16_sector_buffer+13)
        or      a
        jp      z,p127_fat16_bad_bpb
        ld      (p127_fat16_sectors_per_cluster),a

        ; Reserved sectors must be non-zero.
        ld      hl,(p127_fat16_sector_buffer+14)
        ld      a,h
        or      l
        jp      z,p127_fat16_bad_bpb
        ld      (p127_fat16_reserved_sectors),hl

        ; One or two FAT copies are supported.
        ld      a,(p127_fat16_sector_buffer+16)
        cp      1
        jp      z,p127_fat16_fat_count_ok
        cp      2
        jp      nz,p127_fat16_bad_bpb
p127_fat16_fat_count_ok:
        ld      (p127_fat16_fat_count),a

        ; Root entry count and FAT size must both be non-zero.
        ld      hl,(p127_fat16_sector_buffer+17)
        ld      a,h
        or      l
        jp      z,p127_fat16_bad_bpb
        ld      (p127_fat16_root_entries),hl
        ld      hl,(p127_fat16_sector_buffer+22)
        ld      a,h
        or      l
        jp      z,p127_fat16_bad_bpb
        ld      (p127_fat16_sectors_per_fat),hl

        ; FAT_LBA = partition_LBA + reserved_sectors.
        ld      hl,(p127_fat16_partition_lba)
        ld      de,(p127_fat16_reserved_sectors)
        add     hl,de
        ld      (p127_fat16_fat_lba),hl
        ld      hl,(p127_fat16_partition_lba+2)
        ld      de,0
        adc     hl,de
        ld      (p127_fat16_fat_lba+2),hl

        ; ROOT_LBA = FAT_LBA + (FAT_count * sectors_per_FAT).
        ld      hl,(p127_fat16_fat_lba)
        ld      de,(p127_fat16_sectors_per_fat)
        add     hl,de
        ld      (p127_fat16_root_lba),hl
        ld      hl,(p127_fat16_fat_lba+2)
        ld      de,0
        adc     hl,de
        ld      (p127_fat16_root_lba+2),hl
        ld      a,(p127_fat16_fat_count)
        cp      2
        jp      nz,p127_fat16_root_lba_ready
        ld      hl,(p127_fat16_root_lba)
        ld      de,(p127_fat16_sectors_per_fat)
        add     hl,de
        ld      (p127_fat16_root_lba),hl
        ld      hl,(p127_fat16_root_lba+2)
        ld      de,0
        adc     hl,de
        ld      (p127_fat16_root_lba+2),hl
p127_fat16_root_lba_ready:

        ; Root directory sectors = ceil(root_entries / 16).
        ld      hl,(p127_fat16_root_entries)
        ld      de,15
        add     hl,de
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (p127_fat16_root_sectors),hl

        ; DATA_LBA = ROOT_LBA + root_directory_sectors.
        ld      hl,(p127_fat16_root_lba)
        ld      de,(p127_fat16_root_sectors)
        add     hl,de
        ld      (p127_fat16_data_lba),hl
        ld      hl,(p127_fat16_root_lba+2)
        ld      de,0
        adc     hl,de
        ld      (p127_fat16_data_lba+2),hl

        ld      a,1
        ld      (p127_fat16_available),a
        xor     a
        ret

P127_FAT16_ReadRootSector:
        ld      a,(p127_fat16_available)
        or      a
        jp      z,p127_fat16_bad_bpb
        ; Reject root-sector indices >= root_sectors.
        ld      de,(p127_fat16_root_sectors)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jp      nc,p127_fat16_bad_bpb
        ld      de,(p127_fat16_root_lba)
        add     hl,de
        ld      (p127_fat16_io_lba),hl
        ld      hl,(p127_fat16_root_lba+2)
        ld      de,0
        adc     hl,de
        ld      (p127_fat16_io_lba+2),hl
        jp      p127_fat16_read_lba

p127_fat16_read_lba:
        ld      hl,(p127_fat16_io_lba)
        ld      de,(p127_fat16_io_lba+2)
        call    P127_Storage_SetLBA
        ret     c
        ld      ix,p127_fat16_sector_buffer
        call    P127_Storage_ReadSector
        ret

p127_fat16_bad_mbr:
        ld      a,P127_FAT16_ERR_MBR
        scf
        ret
p127_fat16_no_partition:
        ld      a,P127_FAT16_ERR_PARTITION
        scf
        ret
p127_fat16_bad_bpb:
        ld      a,P127_FAT16_ERR_BPB
        scf
        ret


; -------------------------------------------------------------------------
; Dump the complete FAT16 root directory, reading every root sector.
; Read-only; stops at the first 00h entry and caps output at 32 names.
; -------------------------------------------------------------------------
P127_FAT16_DumpRootDirectory:
        ld      hl,p127_fat16_log_list_start
        call    p127_host_debug_string
        xor     a
        ld      (p127_fat16_scan_sector),a
        ld      (p127_fat16_scan_sector+1),a
        ld      (p127_fat16_dump_count),a
p127_fat16_dump_sector:
        ld      hl,(p127_fat16_scan_sector)
        ld      de,(p127_fat16_root_sectors)
        or      a
        sbc     hl,de
        jr      nc,p127_fat16_dump_pass
        ld      hl,(p127_fat16_scan_sector)
        call    P127_FAT16_ReadRootSector
        jr      c,p127_fat16_dump_read_fail
        xor     a
        ld      (p127_fat16_entry_index),a
p127_fat16_dump_entry:
        ld      a,(p127_fat16_entry_index)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,p127_fat16_sector_buffer
        add     hl,de
        push    hl
        pop     ix
        ld      a,(ix+0)
        or      a
        jr      z,p127_fat16_dump_pass
        cp      #E5
        jr      z,p127_fat16_dump_skip
        cp      '.'
        jr      z,p127_fat16_dump_skip
        ld      a,(ix+11)
        cp      #0F
        jr      z,p127_fat16_dump_skip
        and     #08
        jr      nz,p127_fat16_dump_skip
        call    p127_fat16_format_entry
        ld      hl,p127_fat16_log_file
        call    p127_host_debug_string
        ld      hl,p127_fat16_dump_name
        call    p127_host_debug_string
        ld      a,13
        call    p127_host_debug_char
        ld      a,10
        call    p127_host_debug_char
        ld      a,(p127_fat16_dump_count)
        inc     a
        ld      (p127_fat16_dump_count),a
        cp      32
        jr      nc,p127_fat16_dump_truncated
p127_fat16_dump_skip:
        ld      a,(p127_fat16_entry_index)
        inc     a
        ld      (p127_fat16_entry_index),a
        cp      16
        jr      c,p127_fat16_dump_entry
        ld      hl,(p127_fat16_scan_sector)
        inc     hl
        ld      (p127_fat16_scan_sector),hl
        jr      p127_fat16_dump_sector
p127_fat16_dump_pass:
        ld      hl,p127_fat16_log_list_pass
        jp      p127_host_debug_string
p127_fat16_dump_truncated:
        ld      hl,p127_fat16_log_list_truncated
        jp      p127_host_debug_string
p127_fat16_dump_read_fail:
        ld      hl,p127_fat16_log_list_read_fail
        jp      p127_host_debug_string

; IX points to one 32-byte FAT16 directory entry.
; Formats trimmed 8.3 names and appends " <DIR>" for directories.
p127_fat16_format_entry:
        push    ix
        pop     hl
        ld      (p127_fat16_entry_ptr),hl
        ld      de,p127_fat16_dump_name
        ld      b,8
p127_fat16_format_base:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,p127_fat16_format_base_next
        ld      (de),a
        inc     de
p127_fat16_format_base_next:
        djnz    p127_fat16_format_base
        ld      hl,(p127_fat16_entry_ptr)
        ld      bc,8
        add     hl,bc
        ld      b,3
        xor     a
        ld      (p127_fat16_ext_present),a
p127_fat16_check_ext:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,p127_fat16_check_ext_next
        ld      a,1
        ld      (p127_fat16_ext_present),a
p127_fat16_check_ext_next:
        djnz    p127_fat16_check_ext
        ld      a,(p127_fat16_ext_present)
        or      a
        jr      z,p127_fat16_format_attr
        ld      a,'.'
        ld      (de),a
        inc     de
        ld      hl,(p127_fat16_entry_ptr)
        ld      bc,8
        add     hl,bc
        ld      b,3
p127_fat16_format_ext:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,p127_fat16_format_ext_next
        ld      (de),a
        inc     de
p127_fat16_format_ext_next:
        djnz    p127_fat16_format_ext
p127_fat16_format_attr:
        ld      hl,(p127_fat16_entry_ptr)
        ld      bc,11
        add     hl,bc
        ld      a,(hl)
        and     #10
        jr      z,p127_fat16_format_close
        ld      a,' '
        ld      (de),a
        inc     de
        ld      a,'<'
        ld      (de),a
        inc     de
        ld      a,'D'
        ld      (de),a
        inc     de
        ld      a,'I'
        ld      (de),a
        inc     de
        ld      a,'R'
        ld      (de),a
        inc     de
        ld      a,'>'
        ld      (de),a
        inc     de
p127_fat16_format_close:
        xor     a
        ld      (de),a
        ret


p127_fat16_scan_sector: dw 0
p127_fat16_dump_count: db 0
p127_fat16_entry_index: db 0
p127_fat16_entry_ptr: dw 0
p127_fat16_ext_present: db 0
p127_fat16_dump_name: defs 20,0
p127_fat16_log_list_start: db "[P127] HDD FAT16 ROOT DIRECTORY",13,10,0
p127_fat16_log_file: db "[P127] HDD FILE ",0
p127_fat16_log_list_pass: db "[P127] HDD ROOT DIRECTORY READ PASS",13,10,0
p127_fat16_log_list_truncated: db "[P127] HDD ROOT LIST TRUNCATED AT 32 ENTRIES",13,10,0
p127_fat16_log_list_read_fail: db "[P127] HDD ROOT DIRECTORY SECTOR READ FAIL",13,10,0

p127_fat16_available:       db 0
p127_fat16_sectors_per_cluster: db 0
p127_fat16_fat_count:       db 0
p127_fat16_reserved_sectors: dw 0
p127_fat16_root_entries:    dw 0
p127_fat16_sectors_per_fat: dw 0
p127_fat16_root_sectors:    dw 0
p127_fat16_partition_lba:  dd 0
p127_fat16_io_lba:         dd 0
p127_fat16_fat_lba:        dd 0
p127_fat16_root_lba:       dd 0
p127_fat16_data_lba:       dd 0
p127_fat16_sector_buffer:  defs 512,0
p127_fat16_log_probe_start:
        db "[P127] HDD STORAGE PROBE ENTER",13,10,0
p127_fat16_log_mounted:
        db "[P127] FAT16 READ-ONLY MOUNT PASS",13,10,0
p127_fat16_log_failed:
        db "[P127] FAT16 MOUNT NOT AVAILABLE",13,10,0
p127_fat16_end:
        ASSERT p127_fat16_end <= #C000

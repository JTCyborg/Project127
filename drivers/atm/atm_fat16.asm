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
p127_fat16_log_mounted:
        db "[P127] FAT16 READ-ONLY MOUNT PASS",13,10,0
p127_fat16_log_failed:
        db "[P127] FAT16 MOUNT NOT AVAILABLE",13,10,0
p127_fat16_end:
        ASSERT p127_fat16_end <= #C000

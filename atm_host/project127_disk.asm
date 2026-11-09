; =========================================================================
; PROJECT127 — clean TR-DOS disk image
; Contains only BOOT.B and the initial ATM host entry image.
; No Project126 x86 overlays or fixed 16 KiB module layout are included.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "disk_A.trd"

        PAGE 0
        INCLUDE "atm_host/p127_host.asm"
        SAVETRD "disk_A.trd", "P127HOST.C", P127_HOST_LOAD_ADDRESS, p127_host_program_end-P127_HOST_LOAD_ADDRESS

        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END-BASIC_START

        PAGE 0

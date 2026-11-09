; =========================================================================
; PROJECT127 — clean TR-DOS disk image
; Contains BOOT.B, the ATM host image and Project126-style native status console.
; No Project126 x86 overlays or fixed 16 KiB module layout are included.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "disk_A.trd"

        PAGE 0
        INCLUDE "atm_host/p127_host.asm"

        ; TR-DOS catalog core at 8000h; UI remains at A000h.
        PAGE 0
        ORG #8000
        INCLUDE "drivers/atm/atm_trdos_service.asm"

        ; Keep the proven single-file TR-DOS boot path.
        PAGE 0
        ORG #A000
        INCLUDE "atm_host/p127_screen_console.asm"
        SAVETRD "disk_A.trd", "@@HOST_NAME@@.C", P127_HOST_LOAD_ADDRESS, p127_console_end-P127_HOST_LOAD_ADDRESS

        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END-BASIC_START

        PAGE 0

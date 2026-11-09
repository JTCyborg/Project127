; =========================================================================
; PROJECT127 — clean TR-DOS disk image
; Contains BOOT.B, the ATM host image and Project127 native status console.
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

        ; ATM native RG6 text framebuffer service.
        PAGE 0
        ORG #9000
        INCLUDE "drivers/atm/atm_video_service.asm"

        ; Keep the RTC in its own non-overlapping range after the v0.2 video core.
        ORG #9800
        INCLUDE "drivers/atm/atm_rtc_service.asm"

        ; Keep the proven single-file TR-DOS boot path.
        PAGE 0
        ORG #A000
        INCLUDE "atm_host/p127_screen_console.asm"
        ORG #A400
        INCLUDE "drivers/atm/atm_storage_nemo.asm"
        ASSERT p127_storage_end <= #B000

        ; FAT16 code and its 512-byte sector buffer must be included in the
        ; TR-DOS host file. Keep it after the complete Nemo IDE module.
        ORG #B000
        INCLUDE "drivers/atm/atm_fat16.asm"
        SAVETRD "disk_A.trd", "@@HOST_NAME@@.C", P127_HOST_LOAD_ADDRESS, p127_fat16_end-P127_HOST_LOAD_ADDRESS

        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END-BASIC_START

        PAGE 0

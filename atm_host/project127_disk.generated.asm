; =========================================================================
; PROJECT127 ??? clean TR-DOS disk image
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

        ; Memory backend must execute outside the remapped C000-FFFF aperture.
        ; Keep it in A000-BFFF; the host stack ends at 9FFF and is not overwritten
        ; when physical RAM pages are selected through #FFF7.
        PAGE 0
        ORG #A000
        INCLUDE "drivers/atm/atm_memory_backend.asm"
p127_memory_backend_end:
        ASSERT p127_memory_backend_end <= #C000

        ; Resident services live in the default window-3 page. Memory operations
        ; temporarily replace this window and restore physical page 1 on return.
        ORG #C000
        INCLUDE "atm_host/p127_screen_console.asm"
        ASSERT p127_console_end <= #C400

        ORG #C400
        INCLUDE "drivers/atm/atm_storage_nemo.asm"
        ASSERT p127_storage_end <= #D000

        ORG #D000
        INCLUDE "drivers/atm/atm_fat16.asm"
        ASSERT p127_fat16_end <= #E000

        ; One contiguous TR-DOS CODE file loads host and every resident module.
        SAVETRD "disk_A.trd", "p127host.C", P127_HOST_LOAD_ADDRESS, p127_fat16_end-P127_HOST_LOAD_ADDRESS

        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END-BASIC_START

        PAGE 0


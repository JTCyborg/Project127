; =========================================================================
; PROJECT127 — TR-DOS BASIC BOOT.B loader
; Derived from the proven Project126 ATM/TR-DOS boot sequence.
; The build replaces @@HOST_NAME@@ with the 8.3 host program name.
; =========================================================================

CLEAR       EQU     $FD
RANDOMIZE   EQU     $F9
USR         EQU     $C0
REM         EQU     $EA
VAL         EQU     $B0
OUT_CMD     EQU     $DF

BASIC_START:
basic_loader:
        ; Establish the same safe BASIC memory boundary as Project126.
        DB      0, 10
        DW      LINE10_END-LINE10
LINE10:
        DB      OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "1", $0E, $00, $00, $01, $00, $00
        DB      ":"
        DB      CLEAR
        DB      "24000", $0E, $00, $00, $5D, $C0, $00
        DB      $0D
LINE10_END:

        ; Startup marker on ATM debug port #EF.
        DB      0, 11
        DW      LINE11_END-LINE11
LINE11:
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "80", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "49", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "50", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "55", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "83", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "65", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "82", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "13", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "10", 34
        DB      $0D
LINE11_END:

        ; Mark the ROM hand-off separately from the actual CODE load.
        DB      0, 20
        DW      LINE20_END-LINE20
LINE20:
        DB      RANDOMIZE
        DB      USR, "15619", $0E, 0, 0
        DW      15619
        DB      0
        DB      $3A, OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "3", $0E, $00, $00, $03, $00, $00
        DB      $3A
        DB      "LOAD ", 34, "@@HOST_NAME@@", 34, " CODE 24576", $0D
LINE20_END:

        ; This marker is reached only after TR-DOS LOAD has returned.
        DB      0, 25
        DW      LINE25_END-LINE25
LINE25:
        DB      OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "4", $0E, $00, $00, $04, $00, $00
        DB      $0D
LINE25_END:

        ; Enter the host program at 6009h, exactly as Project126 does.
        DB      0, 30
        DW      LINE30_END-LINE30
LINE30:
        DB      OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "2", $0E, $00, $00, $02, $00, $00
        DB      ":"
        DB      RANDOMIZE
        DB      USR
        DB      VAL
        DB      34
        DEFM    "24585"
        DB      34
        DB      $0D
LINE30_END:

        DB      $80
BASIC_END:

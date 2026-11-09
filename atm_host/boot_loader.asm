; =========================================================================
; PROJECT127 — minimal TR-DOS BASIC boot
; Keep BASIC resident area short: the host image loads at 6000h.
; =========================================================================

CLEAR       EQU     $FD
RANDOMIZE   EQU     $F9
USR         EQU     $C0
REM         EQU     $EA

BASIC_START:
basic_loader:

; 10 CLEAR 24575
        DB      0,10
        DW      L10_END-L10
L10:
        DB      CLEAR
        DB      "24575",$0E,0,0
        DW      24575
        DB      0,$0D
L10_END:

; 20 RANDOMIZE USR 15619 : REM : LOAD "p127host" CODE 24576
; TR-DOS trap at 15619 handles the LOAD command following REM.
        DB      0,20
        DW      L20_END-L20
L20:
        DB      RANDOMIZE,USR
        DB      "15619",$0E,0,0
        DW      15619
        DB      0
        DB      $3A,REM,$3A
        DB      "LOAD ",34,"p127host",34," CODE 24576",$0D
L20_END:

        DB      $80
BASIC_END:

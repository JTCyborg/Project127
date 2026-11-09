; =========================================================================
; PROJECT127 ??? minimal TR-DOS BASIC boot
; Boot program is deliberately independent of the host implementation.
; =========================================================================

CLEAR       EQU     $FD
RANDOMIZE   EQU     $F9
USR         EQU     $C0
REM         EQU     $EA
VAL         EQU     $B0
OUT_CMD     EQU     $DF

BASIC_START:
basic_loader:

; 10 CLEAR 24000
        DB      0,10
        DW      L10_END-L10
L10:
        DB      CLEAR
        DB      "24575",$0E,0,0
        DW      24575
        DB      0,$0D
L10_END:

; 20 OUT 239,50:... "P127 START"... (debug only)
        DB      0,20
        DW      L20_END-L20
L20:
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"31",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"32",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"37",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"32",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"83",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"84",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"65",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"82",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"84",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"13",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"10",34
        DB      $0D
L20_END:

; 30 RANDOMIZE USR 15619 : REM : LOAD "p127host" CODE 24576
; The TR-DOS trap must be the first statement on this line.
        DB      0,30
        DW      L30_END-L30
L30:
        DB      RANDOMIZE,USR
        DB      "15619",$0E,0,0
        DW      15619
        DB      0
        DB      $3A,REM,$3A
        DB      "LOAD ",34,"p127host",34," CODE 24576",$0D
L30_END:

; 40 OUT 239,76... "LOADED"
        DB      0,40
        DW      L40_END-L40
L40:
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"76",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"79",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"65",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"68",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"69",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"68",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"13",34,":"
        DB      OUT_CMD,VAL,34,"239",34,",",VAL,34,"10",34
        DB      $0D
L40_END:

; 50 OUT 239,2: RANDOMIZE USR 24576
        DB      0,50
        DW      L50_END-L50
L50:
        DB      OUT_CMD
        DB      "239",$0E,0,0
        DW      239
        DB      0,","
        DB      "2",$0E,0,0
        DW      2
        DB      0,":"
        DB      RANDOMIZE,USR
        DB      "24576",$0E,0,0
        DW      24576
        DB      0,$0D
L50_END:

        DB      $80
BASIC_END:


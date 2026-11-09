; ============================================================================
; Project127 ATM Core — top-down physical program-page arena
; Module version: 0.1.2
;
; Arena discovers the highest contiguous FREE physical run from the page-state
; map. The current reservation map yields P8..P63; P6 remains isolated below
; reserved P7. Physical pages are 16 KiB and P63 ends at 0x100000.
;
; API:
;   p127_arena_init: discovers and validates the highest contiguous FREE run.
;   p127_arena_alloc: IN B=page count; OUT A=first page, carry=1 on failure.
;                    Allocates downward from the current high boundary.
;   p127_arena_free: IN A=first page, B=count; only most-recent block accepted.
;                   Frees it and contracts the high boundary upward.
;
; This is page-granular accounting only. It does not map pages, access RAM,
; provide byte-granular allocation, or promise a seamless legacy 16-bit ABI.
; Free is intentionally LIFO until per-process ownership/coalescing exists.
; ============================================================================
P127_ARENA_VERSION_MAJOR EQU 0
P127_ARENA_VERSION_MINOR EQU 1
P127_ARENA_VERSION_PATCH EQU 2
P127_ARENA_HIGH_PAGE      EQU 64
P127_ARENA_PAGE_SIZE      EQU 04000h

; Discover the highest contiguous FREE run from the actual page-state map.
; The first RESERVED/ALLOCATED page below that run is the lower guard.
; An all-FREE map is rejected: required system reservations are missing.
p127_arena_init:
        ld      hl,p127_mem_page_state+P127_ARENA_HIGH_PAGE-1
        ld      c,P127_ARENA_HIGH_PAGE-1
        ld      b,P127_ARENA_HIGH_PAGE
.p127_arena_init_scan:
        ld      a,(hl)
        or      a
        jp      nz,.p127_arena_init_guard_found
        dec     hl
        dec     c
        djnz    .p127_arena_init_scan
        jp      p127_arena_reject
.p127_arena_init_guard_found:
        inc     c
        ld      a,c
        cp      P127_ARENA_HIGH_PAGE
        jp      nc,p127_arena_reject
        ld      (p127_arena_low_page),a
        ld      a,P127_ARENA_HIGH_PAGE
        sub     c
        jp      z,p127_arena_reject
        ld      (p127_arena_page_count),a
        ld      a,P127_ARENA_HIGH_PAGE
        ld      (p127_arena_next_page),a
        or      a
        ret

; IN B=non-zero page count. OUT A=first page of the new block.
; Validate the complete block before changing any page state.
p127_arena_alloc:
        ld      a,b
        or      a
        jp      z,p127_arena_reject
        ld      a,(p127_arena_next_page)
        sub     b
        jp      c,p127_arena_reject
        ld      (p127_arena_first_page),a
        ld      c,a
        ld      a,(p127_arena_low_page)
        ld      e,a
        ld      a,c
        sub     e
        jp      c,p127_arena_reject
        ld      c,b
        ld      a,(p127_arena_first_page)
        ld      e,a
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
.p127_arena_alloc_check:
        ld      a,(hl)
        or      a
        jp      nz,p127_arena_reject
        inc     hl
        dec     c
        jr      nz,.p127_arena_alloc_check

        ld      a,(p127_arena_first_page)
        ld      e,a
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      c,b
.p127_arena_alloc_mark:
        ld      (hl),P127_MEM_ALLOCATED
        inc     hl
        dec     c
        jr      nz,.p127_arena_alloc_mark
        ld      a,(p127_arena_first_page)
        ld      (p127_arena_next_page),a
        or      a
        ret

; IN A=first page, B=page count. Only the most recent allocation may be
; released; otherwise the arena boundary cannot safely move upward.
p127_arena_free:
        ld      (p127_arena_free_first),a
        ld      c,a
        ld      a,b
        or      a
        jp      z,p127_arena_reject
        ld      a,c
        ld      e,a
        ld      a,(p127_arena_low_page)
        ld      d,a
        ld      a,e
        sub     d
        jp      c,p127_arena_reject
        ld      a,(p127_arena_next_page)
        cp      c
        jp      nz,p127_arena_reject
        ld      a,c
        add     a,b
        jp      c,p127_arena_reject
        cp      P127_ARENA_HIGH_PAGE+1
        jp      nc,p127_arena_reject
        ld      (p127_arena_end_page),a
        ld      e,c
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      c,b
.p127_arena_free_check:
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_arena_reject
        inc     hl
        dec     c
        jr      nz,.p127_arena_free_check

        ld      a,(p127_arena_free_first)
        ld      e,a
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      c,b
.p127_arena_free_mark:
        ld      (hl),P127_MEM_FREE
        inc     hl
        dec     c
        jr      nz,.p127_arena_free_mark
        ld      a,(p127_arena_end_page)
        ld      (p127_arena_next_page),a
        or      a
        ret

p127_arena_reject:
        scf
        ret

p127_arena_selftest:
        call    p127_arena_init
        ret     c
        ld      a,(p127_arena_low_page)
        cp      8
        jp      nz,p127_arena_test_fail
        ld      a,(p127_arena_page_count)
        cp      56
        jp      nz,p127_arena_test_fail
        ld      b,2
        call    p127_arena_alloc
        jp      c,p127_arena_test_fail
        cp      62
        jp      nz,p127_arena_test_fail
        ld      (p127_arena_test_first),a

        ld      b,1
        call    p127_arena_alloc
        jp      c,p127_arena_test_fail
        cp      61
        jp      nz,p127_arena_test_fail

        ld      a,(p127_arena_test_first)
        ld      b,2
        call    p127_arena_free
        jp      nc,p127_arena_test_fail

        ld      a,61
        ld      b,1
        call    p127_arena_free
        jp      c,p127_arena_test_fail
        ld      a,(p127_arena_test_first)
        ld      b,2
        call    p127_arena_free
        jp      c,p127_arena_test_fail
        ld      a,(p127_arena_next_page)
        cp      P127_ARENA_HIGH_PAGE
        jp      nz,p127_arena_test_fail

        ld      a,(p127_arena_page_count)
        ld      b,a
        call    p127_arena_alloc
        jp      c,p127_arena_test_fail
        ld      c,a
        ld      a,(p127_arena_low_page)
        cp      c
        jp      nz,p127_arena_test_fail
        ld      b,1
        call    p127_arena_alloc
        jp      nc,p127_arena_test_fail
        ld      a,(p127_arena_low_page)
        ld      b,a
        ld      a,(p127_arena_page_count)
        ld      c,a
        ld      a,b
        ld      b,c
        call    p127_arena_free
        jp      c,p127_arena_test_fail
        ld      a,(p127_arena_next_page)
        cp      P127_ARENA_HIGH_PAGE
        jp      nz,p127_arena_test_fail
        or      a
        ret

p127_arena_test_fail:
        scf
        ret

p127_arena_low_page:
        db 0
p127_arena_page_count:
        db 0
p127_arena_next_page:
        db P127_ARENA_HIGH_PAGE
p127_arena_first_page:
        db 0
p127_arena_end_page:
        db 0
p127_arena_free_first:
        db 0
p127_arena_test_first:
        db 0

ASSERT P127_ARENA_HIGH_PAGE*P127_ARENA_PAGE_SIZE = 0100000h

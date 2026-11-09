; ============================================================================
; Project127 ATM Core — physical page-state manager
; Module version: 0.1.0
; ABI: reserve A=first page, B=count; alloc -> A=page, C=exhausted;
;      free A=page, C=invalid/not allocated.
; Model: 64 physical 16 KiB page IDs = exactly 1 MiB.
; NOTE: IDs are accounting handles only. Hardware page-register encoding and
;       video/kernel reservations are deliberately supplied by later map code.
; ============================================================================
P127_MEM_VERSION_MAJOR EQU 0
P127_MEM_VERSION_MINOR EQU 1
P127_MEM_VERSION_PATCH EQU 0
P127_MEM_PAGE_COUNT    EQU 64
P127_MEM_PAGE_SIZE     EQU 04000h
P127_MEM_FREE          EQU 0
P127_MEM_RESERVED      EQU 1
P127_MEM_ALLOCATED     EQU 2

p127_mem_init:
        ld      hl,p127_mem_page_state
        ld      de,p127_mem_page_state+1
        ld      bc,P127_MEM_PAGE_COUNT-1
        ld      (hl),P127_MEM_FREE
        ldir
        ret

; Reserve a contiguous physical-page range.
; IN: A=first page, B=count. OUT: carry=1 on invalid range/conflict.
; A zero-length reservation is accepted as a no-op.
p127_mem_reserve:
        ld      c,a
        ld      a,c
        cp      P127_MEM_PAGE_COUNT
        jr      nc,p127_mem_error
        ld      a,c
        add     a,b
        jr      c,p127_mem_error
        cp      P127_MEM_PAGE_COUNT+1
        jr      nc,p127_mem_error
        ld      a,b
        or      a
        ret     z
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      d,b
p127_mem_reserve_check:
        ld      a,(hl)
        or      a
        jr      nz,p127_mem_error
        inc     hl
        dec     d
        jr      nz,p127_mem_reserve_check
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      d,b
p127_mem_reserve_set:
        ld      (hl),P127_MEM_RESERVED
        inc     hl
        dec     d
        jr      nz,p127_mem_reserve_set
        or      a
        ret

; Allocate the first free physical page.
; OUT: A=page ID, carry=1 when exhausted.
p127_mem_alloc:
        ld      hl,p127_mem_page_state
        ld      b,P127_MEM_PAGE_COUNT
        ld      c,0
p127_mem_alloc_scan:
        ld      a,(hl)
        or      a
        jr      z,p127_mem_alloc_found
        inc     hl
        inc     c
        djnz    p127_mem_alloc_scan
        scf
        ret
p127_mem_alloc_found:
        ld      (hl),P127_MEM_ALLOCATED
        ld      a,c
        or      a
        ret

; Release only pages owned by the allocator. Reserved pages cannot be freed.
; IN: A=page ID. OUT: carry=1 for invalid ID or non-allocated page.
p127_mem_free:
        cp      P127_MEM_PAGE_COUNT
        jr      nc,p127_mem_error
        ld      c,a
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jr      nz,p127_mem_error
        ld      (hl),P127_MEM_FREE
        or      a
        ret

p127_mem_error:
        scf
        ret

; Runtime smoke test: allocate -> free -> allocate same first-fit page -> free.
; OUT: carry=1 on failure. Does not reserve or retain any page.
p127_mem_selftest:
        call    p127_mem_alloc
        ret     c
        ld      (p127_mem_test_page),a
        call    p127_mem_free
        ret     c
        ld      a,(p127_mem_test_page)
        call    p127_mem_alloc
        ret     c
        ld      b,a
        ld      a,(p127_mem_test_page)
        cp      b
        jr      nz,p127_mem_test_fail
        ld      a,b
        call    p127_mem_free
        ret
p127_mem_test_fail:
        scf
        ret

p127_mem_test_page:
        db      0
p127_mem_page_state:
        ds      P127_MEM_PAGE_COUNT,0
p127_mem_end:

        ASSERT  P127_MEM_PAGE_COUNT*P127_MEM_PAGE_SIZE = 100000h
        ASSERT  p127_mem_end-p127_mem_page_state = P127_MEM_PAGE_COUNT

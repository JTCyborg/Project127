; ============================================================================
; Project127 ATM Core — physical page-state manager
; Module version: 0.4.4
; ABI: reserve A=first page, B=count; alloc -> A=page, C=exhausted;
;      free A=page, C=invalid/not allocated.
; Model: 64 physical 16 KiB page IDs = exactly 1 MiB.
; ATM Turbo 2+ page IDs are physical 16 KiB RAM pages. Bootstrap reservations
; reflect the active ZX-128 map: page 5 (window 1), page 2 (window 2), and
; page 0 (window 3). Page 5 is already covered by the video-page union.
; ============================================================================
P127_MEM_VERSION_MAJOR EQU 0
P127_MEM_VERSION_MINOR EQU 4
P127_MEM_VERSION_PATCH EQU 4
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
        ld      hl,p127_mem_pin_count
        ld      de,p127_mem_pin_count+1
        ld      bc,P127_MEM_PAGE_COUNT-1
        ld      (hl),0
        ldir
        ret

; Reserve a contiguous physical-page range.
; IN: A=first page, B=count. OUT: carry=1 on invalid range/conflict.
; A zero-length reservation is accepted as a no-op.
p127_mem_reserve:
        ld      c,a
        ld      a,b
        or      a
        ret     z
        ld      a,c
        cp      P127_MEM_PAGE_COUNT
        jp      nc,p127_mem_error
        ld      a,c
        add     a,b
        jp      c,p127_mem_error
        cp      P127_MEM_PAGE_COUNT+1
        jp      nc,p127_mem_error
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      d,b
p127_mem_reserve_check:
        ld      a,(hl)
        or      a
        jp      nz,p127_mem_error
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

; Reserve ATM video RAM used by the complete Project112 mode set.
; Project112 ATM710: ZX uses page 5 or 7; ATM640/EGA/Text use page
; pairs 5+1 or 7+3. Reserve the union so any supported mode can be selected.
; OUT: carry=1 if a reservation conflicts or is out of range.
p127_mem_reserve_video:
        ld      a,1
        ld      b,1
        call    p127_mem_reserve
        ret     c
        ld      a,3
        ld      b,1
        call    p127_mem_reserve
        ret     c
        ld      a,5
        ld      b,1
        call    p127_mem_reserve
        ret     c
        ld      a,7
        ld      b,1
        call    p127_mem_reserve
        ret     c
        or      a
        ret

; Reserve bootstrap pages that are live in the current ZX-128 host map.
; Window 1/page 5 contains P127BOOT.C; window 2/page 2 contains the resident
; UI and stack; window 3/page 0 is retained as the host/staging page.
; Page 5 is already RESERVED by p127_mem_reserve_video.
; OUT: carry=1 if either reservation conflicts.
p127_mem_reserve_boot:
        ld      a,0
        ld      b,1
        call    p127_mem_reserve
        ret     c
        ld      a,2
        ld      b,1
        call    p127_mem_reserve
        ret     c
        ; P4 is a fixed system page below the P7 arena guard. Keep it out
        ; of the general allocator even though the active boot window is P5.
        ld      a,4
        ld      b,1
        call    p127_mem_reserve
        ret

; The IM2 table now resides in W2/P2, which is already RESERVED by the
; active bootstrap map (resident UI/stack). Do not reserve P2 a second time:
; validate the existing ownership instead. No table bytes are written here.
p127_mem_reserve_irq_table:
        ld      hl,p127_mem_page_state+P127_IRQ_TABLE_PAGE
        ld      a,(hl)
        cp      P127_MEM_RESERVED
        jp      nz,p127_mem_error
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
        jp      nc,p127_mem_error
        ld      c,a
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_mem_error
        push    hl
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        pop     hl
        or      a
        jp      nz,p127_mem_error
        ld      (hl),P127_MEM_FREE
        or      a
        ret

; Pin an allocated physical page. Repeated PIN calls are reference-counted.
; IN: A=page ID. OUT: carry=1 for invalid/non-allocated page or count overflow.
p127_mem_pin:
        cp      P127_MEM_PAGE_COUNT
        jp      nc,p127_mem_error
        ld      c,a
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_mem_error
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        cp      0FFh
        jp      z,p127_mem_error
        inc     (hl)
        or      a
        ret

; Release one PIN reference. An unmatched UNPIN is rejected.
; IN: A=page ID. OUT: carry=1 for invalid/non-allocated page or zero count.
p127_mem_unpin:
        cp      P127_MEM_PAGE_COUNT
        jp      nc,p127_mem_error
        ld      c,a
        ld      hl,p127_mem_page_state
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_mem_error
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      a,(hl)
        or      a
        jp      z,p127_mem_error
        dec     (hl)
        or      a
        ret

p127_mem_error:
        scf
        ret

; Runtime smoke test: video and bootstrap pages are immutable; allocation/free works.
; OUT: carry=1 on failure. Does not retain any allocated page.
p127_mem_selftest:
        ld      a,0
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,1
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,2
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,3
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,5
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,P127_IRQ_TABLE_PAGE
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
        ld      a,7
        call    p127_mem_free
        jp      nc,p127_mem_test_fail
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
        jp      nz,p127_mem_test_fail
        ld      a,b
        call    p127_mem_free
        ret     c

        ; Reject a second free of the same page (double-free protection).
        ld      a,(p127_mem_test_page)
        call    p127_mem_free
        jp      nc,p127_mem_test_fail

        ; Reject physical page ID 64, immediately beyond the 0..63 map.
        ld      a,P127_MEM_PAGE_COUNT
        call    p127_mem_free
        jp      nc,p127_mem_test_fail

        ; Existing video reservation must reject an overlapping reservation.
        ld      a,1
        ld      b,1
        call    p127_mem_reserve
        jp      nc,p127_mem_test_fail

        ; A range extending beyond the final physical page must be rejected.
        ld      a,63
        ld      b,2
        call    p127_mem_reserve
        jp      nc,p127_mem_test_fail

        ; Rejected operations must not consume or corrupt the released page.
        call    p127_mem_alloc
        jp      c,p127_mem_test_fail
        ld      b,a
        ld      a,(p127_mem_test_page)
        cp      b
        jp      nz,p127_mem_test_fail
        ld      a,b
        call    p127_mem_free
        ret
p127_mem_test_fail:
        scf
        ret

; PIN/UNPIN contract test: repeated references, guarded FREE, unmatched UNPIN,
; invalid IDs, and successful FREE only after the final UNPIN.
p127_mem_pin_selftest:
        call    p127_mem_alloc
        ret     c
        ld      (p127_mem_test_page),a
        call    p127_mem_pin
        jp      c,p127_mem_pin_test_fail
        ld      a,(p127_mem_test_page)
        call    p127_mem_pin
        jp      c,p127_mem_pin_test_fail
        ld      a,(p127_mem_test_page)
        call    p127_mem_free
        jp      nc,p127_mem_pin_test_fail

        ; First UNPIN leaves one outstanding reference; FREE stays blocked.
        ld      a,(p127_mem_test_page)
        call    p127_mem_unpin
        jp      c,p127_mem_pin_test_fail
        ld      a,(p127_mem_test_page)
        call    p127_mem_free
        jp      nc,p127_mem_pin_test_fail

        ; The second UNPIN releases the final reference.
        ld      a,(p127_mem_test_page)
        call    p127_mem_unpin
        jp      c,p127_mem_pin_test_fail

        ; Extra UNPIN must fail and must not underflow the reference count.
        ld      a,(p127_mem_test_page)
        call    p127_mem_unpin
        jp      nc,p127_mem_pin_test_fail
        ld      a,(p127_mem_test_page)
        call    p127_mem_free
        ret     c

        ; Reserved and out-of-range pages cannot be pinned or unpinned.
        ld      a,1
        call    p127_mem_pin
        jp      nc,p127_mem_pin_test_fail
        ld      a,1
        call    p127_mem_unpin
        jp      nc,p127_mem_pin_test_fail
        ld      a,P127_MEM_PAGE_COUNT
        call    p127_mem_pin
        jp      nc,p127_mem_pin_test_fail
        ld      a,P127_MEM_PAGE_COUNT
        call    p127_mem_unpin
        jp      nc,p127_mem_pin_test_fail

        ; Saturated reference count must reject another PIN without wrapping.
        call    p127_mem_alloc
        ret     c
        ld      (p127_mem_test_page),a
        ld      c,a
        ld      b,0
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      (hl),0FFh
        ld      a,c
        call    p127_mem_pin
        jp      nc,p127_mem_pin_test_fail
        ld      a,c
        call    p127_mem_free
        jp      nc,p127_mem_pin_test_fail
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      (hl),0
        ld      a,c
        call    p127_mem_free
        ret     c
        or      a
        ret

p127_mem_pin_test_fail:
        ; Best-effort cleanup of the test allocation and its synthetic count.
        ld      a,(p127_mem_test_page)
        ld      c,a
        ld      b,0
        ld      hl,p127_mem_pin_count
        ld      e,c
        ld      d,0
        add     hl,de
        ld      (hl),0
        ld      a,c
        call    p127_mem_free
        scf
        ret

; Repeated full-pool allocator stress. This is a software-state test only:
; it never maps a physical page or writes through a RAM window. Each round
; allocates all 57 free pages, confirms exhaustion, frees them in reverse
; order, then checks deterministic first-fit recovery (page 6).
p127_mem_allocator_stress_selftest:
        xor     a
        ld      (p127_mem_stress_round),a
p127_mem_stress_round_begin:
        xor     a
        ld      (p127_mem_stress_count),a
        ld      hl,p127_mem_stress_pages
p127_mem_stress_alloc:
        ; p127_mem_alloc uses HL as its page-state scan pointer.
        push    hl
        call    p127_mem_alloc
        pop     hl
        jp      c,p127_mem_stress_fail
        ld      (hl),a
        inc     hl
        ld      a,(p127_mem_stress_count)
        inc     a
        ld      (p127_mem_stress_count),a
        cp      57
        jr      c,p127_mem_stress_alloc

        ; The 58th allocation must report exhaustion.
        call    p127_mem_alloc
        jp      nc,p127_mem_stress_fail

        ld      a,57
        ld      (p127_mem_stress_count),a
        ld      hl,p127_mem_stress_pages+57
p127_mem_stress_free:
        dec     hl
        ld      a,(hl)
        ; p127_mem_free also uses HL to address the page-state table.
        push    hl
        call    p127_mem_free
        pop     hl
        jp      c,p127_mem_stress_fail
        ld      a,(p127_mem_stress_count)
        dec     a
        ld      (p127_mem_stress_count),a
        jr      nz,p127_mem_stress_free

        ; All pages must be back in the pool; first-fit must restart at P6.
        call    p127_mem_alloc
        jp      c,p127_mem_stress_fail
        cp      6
        jp      nz,p127_mem_stress_fail
        call    p127_mem_free
        jp      c,p127_mem_stress_fail

        ld      a,(p127_mem_stress_round)
        inc     a
        ld      (p127_mem_stress_round),a
        cp      8
        jr      c,p127_mem_stress_round_begin
        or      a
        ret
p127_mem_stress_fail:
        scf
        ret

p127_mem_stress_round: db 0
p127_mem_stress_count: db 0
p127_mem_stress_pages: ds 57,0

p127_mem_test_page:
        db      0
p127_mem_page_state:
        ds      P127_MEM_PAGE_COUNT,0
p127_mem_page_state_end:
; Per-page PIN reference count. FREE is rejected while this byte is nonzero.
p127_mem_pin_count:
        ds      P127_MEM_PAGE_COUNT,0
p127_mem_pin_count_end:
p127_mem_end:

        ASSERT  P127_MEM_PAGE_COUNT*P127_MEM_PAGE_SIZE = 100000h
        ASSERT  p127_mem_page_state_end-p127_mem_page_state = P127_MEM_PAGE_COUNT
        ASSERT  p127_mem_pin_count_end-p127_mem_pin_count = P127_MEM_PAGE_COUNT
        ASSERT  p127_mem_end-p127_mem_page_state = P127_MEM_PAGE_COUNT*2

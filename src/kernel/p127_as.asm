; ============================================================================
; Project127 ATM Core — managed logical address-space page table
; Module version: 0.1.0
;
; 4 MiB logical space: 256 logical pages x 16 KiB. A logical page maps to one
; allocator-owned physical ATM page (0..63). Translation metadata only:
; no CPU-window mapping, physical byte access, IN/OUT or DMA.
;
; API:
;   p127_as_init: clear all slots to FFh (unmapped).
;   p127_as_bind: A=logical page 0..255, B=allocated physical page 0..63.
;   p127_as_unbind: A=logical page; removes metadata, does not free RAM.
;   p127_as_translate: p127_as_address (uint32 LE) -> A=physical page,
;                      HL=14-bit page offset; carry=1 if invalid/unmapped.
; Caller must unbind before releasing a physical page.
; ============================================================================
P127_AS_VERSION_MAJOR EQU 0
P127_AS_VERSION_MINOR EQU 1
P127_AS_VERSION_PATCH EQU 0
P127_AS_LOGICAL_PAGE_COUNT EQU 256
P127_AS_PAGE_SIZE EQU 04000h
P127_AS_UNMAPPED EQU 0FFh

p127_as_init:
        ld      hl,p127_as_page_table
        ld      (hl),P127_AS_UNMAPPED
        ld      de,p127_as_page_table+1
        ld      bc,P127_AS_LOGICAL_PAGE_COUNT-1
        ldir
        or      a
        ret

; Bind an allocator-owned physical page. Physical aliases are forbidden.
p127_as_bind:
        ld      (p127_as_logical_temp),a
        ld      a,b
        cp      P127_MEM_PAGE_COUNT
        jp      nc,p127_as_reject
        ld      (p127_as_physical_temp),a
        ld      e,a
        ld      d,0
        ld      hl,p127_mem_page_state
        add     hl,de
        ld      a,(hl)
        cp      P127_MEM_ALLOCATED
        jp      nz,p127_as_reject

        ld      a,(p127_as_logical_temp)
        ld      e,a
        ld      d,0
        ld      hl,p127_as_page_table
        add     hl,de
        ld      a,(hl)
        cp      P127_AS_UNMAPPED
        jp      nz,p127_as_reject

        ld      hl,p127_as_page_table
        ld      b,0
.p127_as_bind_scan:
        ld      a,(hl)
        cp      P127_AS_UNMAPPED
        jr      z,.p127_as_bind_next
        ld      c,a
        ld      a,(p127_as_physical_temp)
        cp      c
        jp      z,p127_as_reject
.p127_as_bind_next:
        inc     hl
        djnz    .p127_as_bind_scan

        ld      a,(p127_as_logical_temp)
        ld      e,a
        ld      d,0
        ld      hl,p127_as_page_table
        add     hl,de
        ld      a,(p127_as_physical_temp)
        ld      (hl),a
        or      a
        ret

; Remove one logical mapping. Does not release the physical page.
p127_as_unbind:
        ld      e,a
        ld      d,0
        ld      hl,p127_as_page_table
        add     hl,de
        ld      a,(hl)
        cp      P127_AS_UNMAPPED
        jp      z,p127_as_reject
        ld      (hl),P127_AS_UNMAPPED
        or      a
        ret

; Translate a 32-bit logical byte address in [0, 4 MiB).
; Page index = address >> 14; offset = address & 3FFFh.
p127_as_translate:
        ld      a,(p127_as_address+3)
        or      a
        jp      nz,p127_as_reject
        ld      a,(p127_as_address+2)
        cp      040h
        jp      nc,p127_as_reject

        ; Compose the 8-bit logical page index from address bits 14..21.
        ld      a,(p127_as_address+1)
        ld      c,a
        and     03Fh
        ld      h,a
        ld      a,c
        rrca
        rrca
        and     003h
        ld      b,a
        ld      a,(p127_as_address+2)
        add     a,a
        add     a,a
        or      b
        ld      e,a
        ld      d,0
        ld      hl,p127_as_page_table
        add     hl,de
        ld      a,(hl)
        cp      P127_AS_UNMAPPED
        jp      z,p127_as_reject
        ld      (p127_as_result_page),a

        ; Return the low 14 address bits as the in-page offset.
        ld      a,(p127_as_address)
        ld      l,a
        ld      a,(p127_as_address+1)
        and     03Fh
        ld      h,a
        ld      a,(p127_as_result_page)
        or      a
        ret

p127_as_reject:
        scf
        ret

; Startup regression: adjacent logical pages, exact boundary, unmapped slot,
; duplicate physical alias, 4 MiB limit, unbind and physical-page release.
p127_as_selftest:
        call    p127_as_init
        call    p127_mem_alloc
        jp      c,p127_as_test_fail
        ld      (p127_as_test_page_a),a
        call    p127_mem_alloc
        jp      c,p127_as_test_free_a
        ld      (p127_as_test_page_b),a

        xor     a
        ld      b,a
        ld      a,(p127_as_test_page_a)
        ld      b,a
        xor     a
        call    p127_as_bind
        jp      c,p127_as_test_free_b

        ld      a,(p127_as_test_page_b)
        ld      b,a
        ld      a,1
        call    p127_as_bind
        jp      c,p127_as_test_unbind_a

        ; One physical page cannot be aliased into another logical slot.
        ld      a,(p127_as_test_page_a)
        ld      b,a
        ld      a,2
        call    p127_as_bind
        jp      nc,p127_as_test_unbind_b

        ; Last byte of logical page 0 -> physical A, offset 3FFFh.
        ld      a,0FFh
        ld      (p127_as_address),a
        ld      a,03Fh
        ld      (p127_as_address+1),a
        xor     a
        ld      (p127_as_address+2),a
        ld      (p127_as_address+3),a
        call    p127_as_translate
        jp      c,p127_as_test_unbind_b
        ld      (p127_as_test_result),a
        ld      b,a
        ld      a,(p127_as_test_page_a)
        cp      b
        jp      nz,p127_as_test_unbind_b
        ld      a,h
        cp      03Fh
        jp      nz,p127_as_test_unbind_b
        ld      a,l
        cp      0FFh
        jp      nz,p127_as_test_unbind_b

        ; First byte of logical page 1 -> physical B, offset zero.
        xor     a
        ld      (p127_as_address),a
        ld      a,040h
        ld      (p127_as_address+1),a
        call    p127_as_translate
        jp      c,p127_as_test_unbind_b
        ld      b,a
        ld      a,(p127_as_test_page_b)
        cp      b
        jp      nz,p127_as_test_unbind_b
        ld      a,h
        or      l
        jp      nz,p127_as_test_unbind_b

        ; Logical page 2 is unmapped.
        xor     a
        ld      (p127_as_address),a
        ld      a,080h
        ld      (p127_as_address+1),a
        call    p127_as_translate
        jp      nc,p127_as_test_unbind_b

        ; 4 MiB is outside the logical address space.
        xor     a
        ld      (p127_as_address),a
        ld      (p127_as_address+1),a
        ld      a,040h
        ld      (p127_as_address+2),a
        call    p127_as_translate
        jp      nc,p127_as_test_unbind_b

        ld      a,1
        call    p127_as_unbind
        jp      c,p127_as_test_unbind_b
        xor     a
        call    p127_as_unbind
        jp      c,p127_as_test_free_b
        xor     a
        call    p127_as_unbind
        jp      nc,p127_as_test_free_b

        ld      a,(p127_as_test_page_b)
        call    p127_mem_free
        jp      c,p127_as_test_free_a
        ld      a,(p127_as_test_page_a)
        call    p127_mem_free
        ret

p127_as_test_unbind_b:
        ld      a,1
        call    p127_as_unbind
p127_as_test_unbind_a:
        xor     a
        call    p127_as_unbind
p127_as_test_free_b:
        ld      a,(p127_as_test_page_b)
        call    p127_mem_free
p127_as_test_free_a:
        ld      a,(p127_as_test_page_a)
        call    p127_mem_free
p127_as_test_fail:
        scf
        ret

p127_as_address:
        ds      4,0
p127_as_result_page:
        db      P127_AS_UNMAPPED
p127_as_logical_temp:
        db      0
p127_as_physical_temp:
        db      0
p127_as_test_page_a:
        db      0
p127_as_test_page_b:
        db      0
p127_as_test_result:
        db      0
p127_as_page_table:
        ds      P127_AS_LOGICAL_PAGE_COUNT,P127_AS_UNMAPPED

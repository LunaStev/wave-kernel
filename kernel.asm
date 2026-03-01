; =========================================
; Multiboot2 + Minimal 64bit Long Mode
; =========================================

bits 32

section .text
align 8

; -----------------------------------------
; Multiboot2 Header (must be in first 32KB)
; -----------------------------------------
multiboot2_header:
    dd 0xe85250d6
    dd 0
    dd header_end - multiboot2_header
    dd -(0xe85250d6 + 0 + (header_end - multiboot2_header))
    dw 0
    dw 0
    dd 8
header_end:

global _start
extern k_main

_start:
    cli

    ; -------------------------------------
    ; Temporary 32bit stack
    ; -------------------------------------
    mov esp, stack_top

    ; -------------------------------------
    ; Setup page tables (identity 2MB)
    ; -------------------------------------

    ; PML4[0] = pdp_table | present | writable
    mov eax, pdp_table
    or eax, 0x3
    mov [pml4_table], eax
    mov dword [pml4_table + 4], 0

    ; PDP[0] = pd_table | present | writable
    mov eax, pd_table
    or eax, 0x3
    mov [pdp_table], eax
    mov dword [pdp_table + 4], 0

    ; PD[0] = 2MB page, present | writable | PS
    mov dword [pd_table], 0x00000083
    mov dword [pd_table + 4], 0

    ; -------------------------------------
    ; Enable PAE
    ; -------------------------------------
    mov eax, cr4
    or eax, 1 << 5        ; PAE
    mov cr4, eax

    ; -------------------------------------
    ; Load CR3 with PML4
    ; -------------------------------------
    mov eax, pml4_table
    mov cr3, eax

    ; -------------------------------------
    ; Enable Long Mode (EFER.LME)
    ; -------------------------------------
    mov ecx, 0xC0000080   ; IA32_EFER
    rdmsr
    or eax, 1 << 8        ; LME
    wrmsr

    ; -------------------------------------
    ; Enable Paging
    ; -------------------------------------
    mov eax, cr0
    or eax, 1 << 31       ; PG
    mov cr0, eax

    ; -------------------------------------
    ; Load 64bit GDT
    ; -------------------------------------
    lgdt [gdt64_ptr]

    ; -------------------------------------
    ; Far jump to 64bit
    ; -------------------------------------
    jmp 0x08:long_mode_entry

; =========================================
; 64bit mode begins here
; =========================================

bits 64
long_mode_entry:

    mov rsp, stack_top
    mov rbp, 0

    call k_main

.hang:
    hlt
    jmp .hang


; =========================================
; Page Tables (4KB aligned)
; =========================================

section .bss
align 4096

pml4_table:
    resq 512

pdp_table:
    resq 512

pd_table:
    resq 512

; =========================================
; 64bit GDT
; =========================================

section .data
align 8

gdt64:
    dq 0x0000000000000000       ; null
    dq 0x00af9a000000ffff       ; 64bit code
    dq 0x00af92000000ffff       ; 64bit data
gdt64_end:

gdt64_ptr:
    dw gdt64_end - gdt64 - 1
    dq gdt64


; =========================================
; Stack
; =========================================

section .bss
align 16

stack_bottom:
    resb 16384
stack_top:
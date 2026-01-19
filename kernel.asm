bits 64

section .multiboot2
align 8
multiboot2_header:
    dd 0xe85250d6          ; magic
    dd 0                  ; architecture
    dd header_end - multiboot2_header
    dd -(0xe85250d6 + 0 + (header_end - multiboot2_header))

    ; end tag
    dw 0
    dw 0
    dd 8
header_end:

section .text
global _start
extern kmain

_start:
    cli
    call kmain
.hang:
    hlt
    jmp .hang

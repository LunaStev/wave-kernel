; =========================================
; Wave Kernel Example (x86_64, Multiboot2)
; - Long mode bootstrap
; - IDT + PIC remap + PIT timer
; - Keyboard IRQ handler
; =========================================

bits 32

section .multiboot2
align 8

multiboot2_header:
    dd 0xe85250d6
    dd 0
    dd header_end - multiboot2_header
    dd -(0xe85250d6 + 0 + (header_end - multiboot2_header))

    ; end tag
    dw 0
    dw 0
    dd 8
header_end:

section .text
align 16

global _start
extern k_main
extern k_on_timer_tick
extern k_on_keyboard_scancode
extern k_on_exception

_start:
    cli

    ; temporary 32-bit stack
    mov esp, stack_top

    ; -------------------------------------
    ; Minimal paging: identity map first 2MiB
    ; -------------------------------------

    ; PML4[0] -> PDP
    mov eax, pdp_table
    or eax, 0x3
    mov [pml4_table], eax
    mov dword [pml4_table + 4], 0

    ; PDP[0] -> PD
    mov eax, pd_table
    or eax, 0x3
    mov [pdp_table], eax
    mov dword [pdp_table + 4], 0

    ; PD[0] -> 2MiB page (PS|RW|P)
    mov dword [pd_table], 0x00000083
    mov dword [pd_table + 4], 0

    ; enable PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; load CR3
    mov eax, pml4_table
    mov cr3, eax

    ; enable IA32_EFER.LME
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; enable paging
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ; load 64-bit GDT and jump
    lgdt [gdt64_ptr]
    jmp 0x08:long_mode_entry

; =========================================
; 64-bit mode
; =========================================

bits 64

long_mode_entry:
    ; set data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax

    mov rsp, stack_top
    mov rbp, 0

    call setup_idt
    call remap_pic
    call init_pit_100hz

    ; transfer control to Wave kernel
    call k_main

.hang:
    hlt
    jmp .hang

; -----------------------------------------
; Exported helper functions for Wave
; -----------------------------------------

global asm_enable_interrupts
asm_enable_interrupts:
    sti
    ret

global asm_disable_interrupts
asm_disable_interrupts:
    cli
    ret

global asm_halt
asm_halt:
    hlt
    ret

global asm_reboot
asm_reboot:
    ; keyboard controller reset pulse
    mov al, 0xFE
    out 0x64, al
.wait:
    hlt
    jmp .wait

global asm_out8
asm_out8:
    mov dx, di
    mov al, sil
    out dx, al
    ret

global asm_in8
asm_in8:
    mov dx, di
    in al, dx
    ret

; -----------------------------------------
; IDT setup
; -----------------------------------------

%macro INSTALL_GATE 2
    lea rax, [%2]
    mov ecx, %1
    call set_idt_gate
%endmacro

setup_idt:
    ; CPU exception vectors 0..31
    INSTALL_GATE 0, isr_exc0
    INSTALL_GATE 1, isr_exc1
    INSTALL_GATE 2, isr_exc2
    INSTALL_GATE 3, isr_exc3
    INSTALL_GATE 4, isr_exc4
    INSTALL_GATE 5, isr_exc5
    INSTALL_GATE 6, isr_exc6
    INSTALL_GATE 7, isr_exc7
    INSTALL_GATE 8, isr_exc8
    INSTALL_GATE 9, isr_exc9
    INSTALL_GATE 10, isr_exc10
    INSTALL_GATE 11, isr_exc11
    INSTALL_GATE 12, isr_exc12
    INSTALL_GATE 13, isr_exc13
    INSTALL_GATE 14, isr_exc14
    INSTALL_GATE 15, isr_exc15
    INSTALL_GATE 16, isr_exc16
    INSTALL_GATE 17, isr_exc17
    INSTALL_GATE 18, isr_exc18
    INSTALL_GATE 19, isr_exc19
    INSTALL_GATE 20, isr_exc20
    INSTALL_GATE 21, isr_exc21
    INSTALL_GATE 22, isr_exc22
    INSTALL_GATE 23, isr_exc23
    INSTALL_GATE 24, isr_exc24
    INSTALL_GATE 25, isr_exc25
    INSTALL_GATE 26, isr_exc26
    INSTALL_GATE 27, isr_exc27
    INSTALL_GATE 28, isr_exc28
    INSTALL_GATE 29, isr_exc29
    INSTALL_GATE 30, isr_exc30
    INSTALL_GATE 31, isr_exc31

    ; PIC remapped IRQs
    INSTALL_GATE 32, isr_timer
    INSTALL_GATE 33, isr_keyboard

    lidt [idtr]
    ret

; in: ecx=vector, rax=handler address
set_idt_gate:
    lea rdx, [idt_table]
    mov r8, rcx
    shl r8, 4
    add rdx, r8

    ; offset[15:0]
    mov word [rdx + 0], ax
    ; selector
    mov word [rdx + 2], 0x08
    ; IST
    mov byte [rdx + 4], 0
    ; type attrs: present + DPL0 + interrupt gate
    mov byte [rdx + 5], 0x8E

    ; offset[31:16]
    shr rax, 16
    mov word [rdx + 6], ax

    ; offset[63:32]
    shr rax, 16
    mov dword [rdx + 8], eax

    ; reserved
    mov dword [rdx + 12], 0
    ret

; -----------------------------------------
; PIC / PIT
; -----------------------------------------

remap_pic:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al

    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    ; unmask IRQ0(timer), IRQ1(keyboard)
    mov al, 0xFC
    out 0x21, al
    ; keep slave masked
    mov al, 0xFF
    out 0xA1, al

    ret

init_pit_100hz:
    mov al, 0x36
    out 0x43, al

    mov ax, 11931
    out 0x40, al
    mov al, ah
    out 0x40, al
    ret

; -----------------------------------------
; Handlers
; -----------------------------------------

%macro PUSH_GPRS 0
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro POP_GPRS 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro

%macro EXC_NOERR 1
isr_exc%1:
    PUSH_GPRS
    mov edi, %1
    xor esi, esi
    call k_on_exception
    POP_GPRS
    iretq
%endmacro

%macro EXC_ERR 1
isr_exc%1:
    PUSH_GPRS
    mov edi, %1
    mov rsi, [rsp + 120]
    call k_on_exception
    POP_GPRS
    add rsp, 8
    iretq
%endmacro

EXC_NOERR 0
EXC_NOERR 1
EXC_NOERR 2
EXC_NOERR 3
EXC_NOERR 4
EXC_NOERR 5
EXC_NOERR 6
EXC_NOERR 7
EXC_ERR   8
EXC_NOERR 9
EXC_ERR   10
EXC_ERR   11
EXC_ERR   12
EXC_ERR   13
EXC_ERR   14
EXC_NOERR 15
EXC_NOERR 16
EXC_ERR   17
EXC_NOERR 18
EXC_NOERR 19
EXC_NOERR 20
EXC_ERR   21
EXC_NOERR 22
EXC_NOERR 23
EXC_NOERR 24
EXC_NOERR 25
EXC_NOERR 26
EXC_NOERR 27
EXC_NOERR 28
EXC_ERR   29
EXC_ERR   30
EXC_NOERR 31

isr_timer:
    PUSH_GPRS

    call k_on_timer_tick

    mov al, 0x20
    out 0x20, al

    POP_GPRS
    iretq

isr_keyboard:
    PUSH_GPRS

    xor edi, edi
    in al, 0x60
    mov dil, al
    call k_on_keyboard_scancode

    mov al, 0x20
    out 0x20, al

    POP_GPRS
    iretq

; =========================================
; Data tables
; =========================================

section .data
align 8

gdt64:
    dq 0x0000000000000000
    dq 0x00af9a000000ffff
    dq 0x00af92000000ffff
gdt64_end:

gdt64_ptr:
    dw gdt64_end - gdt64 - 1
    dq gdt64

idtr:
    dw (256 * 16) - 1
    dq idt_table

section .bss
align 4096

pml4_table:
    resq 512

pdp_table:
    resq 512

pd_table:
    resq 512

idt_table:
    resb 256 * 16

align 16
stack_bottom:
    resb 16384
stack_top:

; =============================================
; sysutils.asm - Utility macros for x86_64 Linux
; =============================================

section .data
    ; Newline character for printing
    sysutils_newline db 0xa

; =============================================
; PRINT buffer, length
;   Prints a buffer of given length to stdout.
;   Args:
;     %1: buffer address
;     %2: length of buffer
;   Clobbers: rax, rdi, rsi, rdx
; =============================================
%macro PRINT 2
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, %1     ; buffer
    mov rdx, %2     ; length
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; =============================================
; PRINTF fd, buffer, length
;   Writes a buffer of given length to a file descriptor.
;   Args:
;     %1: file descriptor
;     %2: buffer address
;     %3: length of buffer
;   Clobbers: rax, rdi, rsi, rdx
; =============================================
%macro PRINTF 3
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 1      ; sys_write
    mov rdi, %1     ; file descriptor
    mov rsi, %2     ; buffer
    mov rdx, %3     ; length
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; =============================================
; PRINTN buffer, length
;   Prints a buffer of given length to stdout, followed by a newline.
;   Args:
;     %1: buffer address
;     %2: length of buffer
;   Clobbers: rax, rdi, rsi, rdx
; =============================================
%macro PRINTN 2
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, %1     ; buffer
    mov rdx, %2     ; length
    syscall

    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, sysutils_newline
    mov rdx, 1
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; =============================================
; LF
;   Prints a newline to stdout.
;   Clobbers: rax, rdi, rsi, rdx
; =============================================
%macro LF 0
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, sysutils_newline
    mov rdx, 1
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; =============================================
; EXIT status
;   Exits the program with the given status.
;   Args:
;     %1: exit status
;   Clobbers: rax, rdi
; =============================================
%macro EXIT 1
    mov rax, 60     ; sys_exit
    mov rdi, %1     ; exit status
    syscall
%endmacro

; =============================================
; STRLEN string_ptr, out_reg
;   Calculates the length of a null-terminated string.
;   Args:
;     %1: pointer to string
;     %2: register to store length
;   Clobbers: rax
; =============================================
%macro STRLEN 2
    push rax
    push rbx

    mov %2, 0
%%loop:
    mov bl, [%1 + %2]
    cmp bl, 0
    je %%done
    inc %2
    jmp %%loop

%%done:
    pop rbx
    pop rax
%endmacro

; =============================================
; APPEND dest, src, length
;   Appends a source buffer to a destination buffer.
;   Args:
;     %1: destination buffer address (updated as bytes are copied)
;     %2: source buffer address
;     %3: number of bytes to copy
;   Clobbers: rax, rsi, rcx
;   Notes:
;     - The destination address is incremented as bytes are copied.
;     - Does not null-terminate the destination.
; =============================================
%macro APPEND 3
    mov rsi, %2
    mov rcx, %3
%%loop:
    cmp rcx, 0
    je %%done
    mov al, [rsi]
    mov [%1], al
    inc rsi
    inc %1
    dec rcx
    jmp %%loop
%%done:
%endmacro

; =============================================
; AAPPEND dest, src
;   Appends a null-terminated string to a destination buffer.
;   Args:
;     %1: destination buffer address (incremented as bytes are copied)
;     %2: source string address (null-terminated)
;   Clobbers: rsi, rcx
; =============================================
%macro AAPPEND 2
    STRLEN %2, rcx ; get length into rcx (clobbers rax, rbx internally)
    mov rsi, %2

%%loop:
    cmp rcx, 0
    je %%done
    mov al, [rsi]
    mov [%1], al
    inc rsi
    inc %1
    dec rcx
    jmp %%loop
%%done:
%endmacro

; =============================================
; GET_ARG index, out_reg
;   Gets the command-line argument at the given index (1-based).
;   Args:
;     %1: index of argument (1 = first real arg)
;     %2: register to store the result
;   Clobbers: none
; =============================================
%macro GET_ARG 2
    mov %2, [rsp + ((%1 + 1) * 8)]
%endmacro

; =============================================
; GET_ARGC out_reg
;   Gets the number of command-line arguments.
;   Args:
;     %1: register to store the result
;   Clobbers: none
; =============================================
%macro GET_ARGC 1
    mov %1, [rsp]
%endmacro

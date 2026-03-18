; sysutils.asm - Utility macros for x86_64 Linux

section .data
    sysutils_newline  db 0xa

    sysutils_ts_fmt    db "%H:%M:%S", 0              ; strftime format
    sysutils_ts_buf    db 0, 0, 0, 0, 0, 0, 0, 0, 0  ; "HH:MM:SS\0"
    sysutils_timespec  dq 0, 0                       ; tv_sec, tv_nsec
    sysutils_tm_buf    times 64 db 0                 ; struct tm

; PRINT buffer, length
;   Writes a buffer to stdout.
;   Args:
;     %1: buffer address
;     %2: length
;   Clobbers: rax, rdi, rsi, rdx
%macro PRINT 2
    push rax
    push rdi
    push rsi
    push rdx

    ; write(fd, buffer, count)
    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, %1
    mov rdx, %2
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; PRINTF fd, buffer, length
;   Writes a buffer to a file descriptor.
;   Args:
;     %1: file descriptor
;     %2: buffer address
;     %3: length
;   Clobbers: rax, rdi, rsi, rdx
%macro PRINTF 3
    push rax
    push rdi
    push rsi
    push rdx

    ; write(fd, buffer, count)
    mov rax, 1      ; sys_write
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; PRINTN buffer, length
;   Writes a buffer to stdout, followed by a newline.
;   Args:
;     %1: buffer address
;     %2: length
;   Clobbers: rax, rdi, rsi, rdx
%macro PRINTN 2
    push rax
    push rdi
    push rsi
    push rdx

    ; write(fd, buffer, count)
    mov rax, 1      ; sys_write
    mov rdi, 1      ; stdout
    mov rsi, %1
    mov rdx, %2
    syscall

    ; write(fd, buffer, count)
    mov rax, 1                 ; newline
    mov rdi, 1                 ; stdout
    mov rsi, sysutils_newline
    mov rdx, 1
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; LF
;   Prints a newline to stdout.
;   Clobbers: rax, rdi, rsi, rdx
%macro LF 0
    push rax
    push rdi
    push rsi
    push rdx

    ; write(fd, buffer, count)
    mov rax, 1                 ; sys_write
    mov rdi, 1                 ; stdout
    mov rsi, sysutils_newline
    mov rdx, 1
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

; ITOA num_reg, buf_ptr, out_len_reg
;   Converts an unsigned 64-bit integer to decimal ASCII.
;   Args:
;     %1: register containing the number
;     %2: pointer to a buffer of at least 20 bytes
;     %3: register to store resulting string length
;   Clobbers: rax, rbx, rcx, rdx, rdi, rsi
%macro ITOA 3
    mov rax, %1
    lea rdi, [%2 + 19]

    mov byte [rdi], 0
    xor %3, %3

%%loop:
    xor rdx, rdx

    mov rcx, 10
    div rcx

    add dl, '0'
    dec rdi

    mov [rdi], dl
    inc %3

    test rax, rax
    jnz %%loop

    lea rsi, [rdi]
    lea rdi, [%2]
    mov rcx, %3

    rep movsb
%endmacro

; ATOI buf_ptr, out_reg
;   Converts a null-terminated decimal ASCII string to an unsigned 64-bit integer.
;   Args:
;     %1: pointer to the string buffer
;     %2: register to store the resulting integer
;   Clobbers: rax, rbx, rsi
%macro ATOI 2
    xor %2, %2
    lea rsi, [%1]

%%loop:
    movzx rbx, byte [rsi]

    cmp bl, 0
    je %%done

    imul %2, %2, 10
    sub bl, '0'
    add %2, rbx

    inc rsi
    jmp %%loop

%%done:
%endmacro

; GET_ARG index, out_reg
;   Gets a command-line argument by 1-based index.
;   Args:
;     %1: argument index (1 = first real arg)
;     %2: register to store pointer
;   Clobbers: none
%macro GET_ARG 2
    mov %2, [rsp + ((%1 + 1) * 8)]
%endmacro

; GET_ARGC out_reg
;   Gets the number of command-line arguments (argc).
;   Args:
;     %1: register to store count
;   Clobbers: none
%macro GET_ARGC 1
    mov %1, [rsp]
%endmacro

; EXIT status
;   Exits the program with the given status.
;   Args:
;     %1: exit status
;   Clobbers: rax, rdi
%macro EXIT 1
    mov rax, 60     ; sys_exit
    mov rdi, %1     ; exit status
    syscall
%endmacro
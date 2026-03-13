; fileutils.asm - File operation macros for x86_64 Linux

; FILE_EXISTS path
;   Checks whether a file exists on disk.
;   Args:
;     %1: null-terminated path
;   Returns:
;     rax = 1 if exists, 0 otherwise
;   Clobbers: rax, rdi, rsi
%macro FILE_EXISTS 1
    mov rax, 21     ; sys_access
    mov rdi, %1
    mov rsi, 0      ; F_OK
    syscall

    cmp rax, 0
    je %%exists

    mov rax, 0
    jmp %%done

%%exists:
    mov rax, 1

%%done:
%endmacro

; READ_FILE fd, buffer, length
;   Reads up to `length` bytes from a file descriptor into a buffer.
;   Args:
;     %1: file descriptor
;     %2: buffer address
;     %3: buffer size
;   Returns:
;     rax = bytes read, or negative errno on error
;   Clobbers: rax, rdi, rsi, rdx
%macro READ_FILE 3
    mov rax, 0      ; sys_read
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall
%endmacro

; OPEN_FILE path
;   Opens a file for reading.
;   Args:
;     %1: null-terminated path
;   Returns:
;     rax = file descriptor, or negative errno on error
;   Clobbers: rax, rdi, rsi, rdx
%macro OPEN_FILE 1
    mov rax, 2      ; sys_open
    mov rdi, %1
    mov rsi, 0      ; O_RDONLY
    mov rdx, 0
    syscall
%endmacro
%macro FILE_EXISTS 1
; takes file_path (nul terminated) = rdi
; returns 1 or 0 in rax

    ; access(path, mode)
    mov rax, 21 
    mov rdi, %1
    mov rsi, 0 ; F_OK

    syscall

    cmp rax, 0
    je %%exists

    jmp %%not_found

%%exists:
    mov rax, 1
    jmp %%done

%%not_found:
    mov rax, 0

%%done:

%endmacro

%macro READ_FILE 3
; %1: file descriptor
; %2: buffer startaddr
; %3: buffer length
; rax will have the syscall status

    ; read(fd, buffer, buffer_size)
    mov rax, 0
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3

    syscall
%endmacro

%macro OPEN_FILE 1
; %1: nul-terminated path
; returns fd in rax, or negative on error
    mov rax, 2      ; open
    mov rdi, %1
    mov rsi, 0      ; O_RDONLY
    mov rdx, 0
    syscall
%endmacro
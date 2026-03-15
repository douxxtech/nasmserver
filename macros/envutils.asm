; envutils.asm - .env file parsing utilities for NASMServer

section .bss
    env_buf  resb 4096 ; Idk yet the number of bytes a file with comments could have

; GET_ENV_VALUE path, key, out_buf, out_buf_size
;   Reads a .env file and extracts the value for a given key.
;   Args:
;     %1: null-terminated path to the .env file
;     %2: null-terminated key string label
;     %3: output buffer
;     %4: output buffer max size
;   Returns:
;     rax = length of value written, or -1 on failure (file not found, key not found)
;   Clobbers: rax, rbx, rcx, rdx, rdi, rsi, r8, r9
%macro GET_ENV_VALUE 4
    ; open and read the file

    OPEN_FILE %1
    cmp rax, 0
    jl %%fail

    mov rbx, rax                  ; rbx = fd

    READ_FILE rbx, env_buf, 4096
    cmp rax, 0
    jl %%close_fail

    ; close the fd since we have the data
    push rax
    mov rax, 3
    mov rdi, rbx
    syscall
    pop rax

    STRLEN %2, rcx                ; rcx = key length

    lea r8, [env_buf]             ; r8  = current scan pointer
    mov r9, r8
    add r9, rax                   ; r9 = end of buffer

%%line_start:
    cmp r8, r9
    jge %%fail               ; past end of buffer

    ; skip comment lines
    cmp byte [r8], '#'
    je %%skip_line

    ; skip blank lines
    cmp byte [r8], 0x0a
    je %%next_char

    ; try to match key: compare r8..r8+key_len with %2
    lea rsi, [r8]
    lea rdi, [%2]

    push rcx                 ; repe cmpsb clobbers rcx
    repe cmpsb 
    pop rcx

    jne %%skip_line          ; mismatch

    ; matched key bytes, next char must be '='
    cmp byte [r8 + rcx], '='  
    jne %%skip_line

    ; found it
    lea rsi, [r8 + rcx + 1]
    jmp %%extract

%%skip_line:
    ; advance r8 to the next '\n' (no, we won't support CRLF)
    cmp r8, r9
    jge %%fail

    cmp byte [r8], 0x0a
    je %%next_char
    
    inc r8
    jmp %%skip_line

%%next_char:
    inc r8
    jmp %%line_start

%%extract:
    ; rsi = pointer to value start
    lea rdi, [%3]
    mov rcx, %4
    xor rbx, rbx   ; rbx = bytes written

%%copy_loop:
    cmp rsi, r9
    jge %%copy_done  ; end of buffer

    mov al, [rsi]

    cmp al, 0x0a     ; \n
    je %%copy_done

    cmp al, 0        ; null
    je %%copy_done

    dec rcx
    jz %%copy_done   ; out buf full

    mov [rdi], al
    inc rdi
    inc rsi
    inc rbx
    jmp %%copy_loop

%%copy_done:
    mov byte [rdi], 0  ; nul-terminate
    mov rax, rbx       ; return value length
    jmp %%done

%%close_fail:
    mov rdi, rbx
    mov rax, 3
    syscall

%%fail:
    mov rax, -1

%%done:
%endmacro

; ENV_DEFAULT path, key, out_buf, out_buf_size, default
;   Wraps GET_ENV_VALUE; copies default into out_buf if key not found.
;   Args:
;     %1-%4: same as GET_ENV_VALUE
;     %5: default string label (null-terminated)
;   Returns:
;     rax = length of value written (from env or default)
;   Clobbers: same as GET_ENV_VALUE
%macro ENV_DEFAULT 5
    GET_ENV_VALUE %1, %2, %3, %4

    cmp rax, -1
    jne %%done              ; found it, rax already set

    ; copy default into out_buf
    lea rsi, [%5]
    lea rdi, [%3]
    mov rcx, %4
    xor rbx, rbx

%%default_copy:
    mov al, [rsi]
    cmp al, 0
    je %%default_done

    dec rcx
    jz %%default_done    ; out buf full

    mov [rdi], al
    inc rsi
    inc rdi
    inc rbx
    jmp %%default_copy

%%default_done:
    mov byte [rdi], 0  ; nul-terminate
    mov rax, rbx

%%done:
%endmacro
; httputils.asm - HTTP/1.0 parsing utilities

; IS_HTTP_REQUEST buffer, length
;   Checks for "GET " prefix and "HTTP/1.x" just before the first CRLF.
;   Intentional note: We're treating 'HTTP/1.1' as a valid one, even if we return HTTP/1.0.
;   The clients will handle that by themselves, like big boys.
;   Args:
;     %1: buffer address
;     %2: buffer length
;   Returns:
;     rax = 1 if valid, 0 otherwise
;   Clobbers: rax, rsi, r8
%macro IS_HTTP_REQUEST 2
    push rsi
    push r8

    xor rax, rax
    mov rsi, %1

    cmp dword [rsi], 0x20544547 ; "GET "
    jne %%invalid

    xor r8, r8
%%find_crlf:
    cmp r8, %2
    jge %%invalid
    cmp word [rsi + r8], 0x0a0d ; \r\n
    je %%check_version
    inc r8
    jmp %%find_crlf

%%check_version:
    cmp r8, 8
    jl %%invalid
    cmp dword [rsi + r8 - 8], 0x50545448 ; "HTTP"
    jne %%invalid
    cmp dword [rsi + r8 - 4], 0x302e312f ; "/1.0"
    je %%valid
    cmp dword [rsi + r8 - 4], 0x312e312f ; "/1.1"
    jne %%invalid

%%valid:
    mov rax, 1

%%invalid:
    pop r8
    pop rsi
%endmacro

; PARSE_HTTP_PATH buffer, length, path_out, path_len_out
;   Skips the method and spaces, then copies the path until the next space.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer for path (must be >= 256 bytes)
;     %4: register to store path length (0 if nothing extracted)
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_HTTP_PATH 4
    xor %4, %4      ; default path length = 0
    mov rsi, %1
    mov rdi, %3
    mov rcx, %2

    xor r8, r8      ; offset

%%skip_method:
    cmp r8, rcx
    jge %%parse_done
    mov al, [rsi + r8]
    cmp al, 0x20    ; space
    je %%skip_spaces
    inc r8
    jmp %%skip_method

%%skip_spaces:
    cmp r8, rcx
    jge %%parse_done
    mov al, [rsi + r8]
    cmp al, 0x20
    jne %%copy_path
    inc r8
    jmp %%skip_spaces

%%copy_path:
    xor r9, r9      ; path length counter
%%copy_loop:
    cmp r8, rcx
    jge %%parse_done
    mov al, [rsi + r8]
    cmp al, 0x20    ; space = end of path (HTTP/version follows)
    je %%parse_done
    mov [rdi + r9], al
    inc r8
    inc r9
    cmp r9, 255     ; sanity check, max path length
    jge %%parse_done
    jmp %%copy_loop

%%parse_done:
    mov %4, r9
%endmacro
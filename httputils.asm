; =============================================
; httputils.asm - HTTP/1.0 parsing utilities
; =============================================

; =============================================
; IS_HTTP_REQUEST buffer, length
;   Validates if a buffer contains a valid HTTP/1.0 request.
;   Args:
;     %1: buffer address
;     %2: buffer length
;   Returns:
;     rax = 1 if valid HTTP/1.0 request, 0 otherwise
;   Clobbers: rax, rsi, rcx, r8, r9
; =============================================
%macro IS_HTTP_REQUEST 2
    push rsi
    push r8

    xor rax, rax
    mov rsi, %1

    ; "GET " check
    cmp dword [rsi], 0x20544547
    jne %%invalid

    ; find \r\n and check if "HTTP/1.0" is just before it
    xor r8, r8
%%find_crlf:
    cmp r8, %2
    jge %%invalid
    cmp word [rsi + r8], 0x0a0d
    je %%check_version
    inc r8
    jmp %%find_crlf

%%check_version:
    cmp r8, 8
    jl %%invalid
    cmp dword [rsi + r8 - 8], 0x50545448 ; "HTTP"
    jne %%invalid
    cmp dword [rsi + r8 - 4], 0x302e312f ; "/1.0"
    jne %%invalid

    mov rax, 1

%%invalid:
    pop r8
    pop rsi
%endmacro

; =============================================
; PARSE_HTTP_PATH buffer, length, path_out, path_len_out
;   Extracts the path from an HTTP request line.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer for path
;     %4: register to store path length
;   Returns:
;     path_len_out = length of extracted path (0 if invalid)
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
; =============================================
%macro PARSE_HTTP_PATH 4
    xor %4, %4  ; path length = 0 by default
    mov rsi, %1 ; buffer pointer
    mov rdi, %3        ; output path buffer
    mov rcx, %2         ; length

    ; Skip method (GET + space)
    xor r8, r8          ; offset

%%skip_method:
    cmp r8, rcx
    jge %%parse_done
    
    mov al, [rsi + r8]
    cmp al, 0x20        ; space
    je %%skip_method_spaces
    
    inc r8
    jmp %%skip_method

%%skip_method_spaces:
    ; Skip spaces
    cmp r8, rcx
    jge %%parse_done
    
    mov al, [rsi + r8]
    cmp al, 0x20
    jne %%path_start
    
    inc r8
    jmp %%skip_method_spaces

%%path_start:
    ; r8 now points to start of path
    ; Copy until we hit a space (which precedes HTTP/version)
    xor r9, r9          ; path length counter

%%copy_path:
    cmp r8, rcx
    jge %%parse_done
    
    mov al, [rsi + r8]
    cmp al, 0x20        ; space terminates path
    je %%parse_done
    
    mov [rdi + r9], al
    inc r8
    inc r9
    
    cmp r9, 255         ; sanity check, max path length
    jge %%parse_done
    
    jmp %%copy_path

%%parse_done:
    mov %4, r9          ; store path length

%endmacro
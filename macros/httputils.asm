; httputils.asm - HTTP/1.0 parsing utilities

; IS_HTTP_REQUEST buffer, length
;   Checks for "GET " prefix and "HTTP/1.x" just before the first CRLF.
;   Intentional note: We're treating 'HTTP/1.1' as a valid one, even if we return HTTP/1.0.
;   The clients will handle that by themselves, like big boys.
;   Args:
;     %1: buffer address
;     %2: buffer length
;   Returns:
;     rax = 1 if valid, -400 if invalid, and -405 if the method isn't allowed
;   Clobbers: rax, rsi, r8
%macro IS_HTTP_REQUEST 2
    push rsi
    push r8

    xor rax, rax
    mov rsi, %1

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
    je %%is_http

    cmp dword [rsi + r8 - 4], 0x312e312f ; "/1.1"
    jne %%invalid

%%is_http:
    ; check if its a GET request (static file host, we don't allow other requests)
    cmp dword [rsi], 0x20544547             ; "GET "
    jne %%method_not_allowed

%%valid:
    mov rax, 1
    jmp %%done

%%method_not_allowed:
    mov rax, -405 ; negative codes are often used for errors in asm
    jmp %%done

%%invalid:
    mov rax, -400

%%done:
    pop r8
    pop rsi
%endmacro

; PARSE_HTTP_PATH buffer, length, path_out, path_len_out
;   Skips the method and spaces, then copies the path until the next space.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer for path
;     %4: register to store path length (0 if nothing extracted)
;     %5: path max length
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_HTTP_PATH 5
    xor %4, %4   ; default path length = 0
    mov rsi, %1
    mov rdi, %3
    mov rcx, %2

    xor r8, r8   ; offset

%%skip_method:
    cmp r8, rcx
    jge %%parse_done
    mov al, [rsi + r8]
    cmp al, 0x20        ; space
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
    cmp al, 0x20        ; space = end of path (HTTP/version follows)

    je %%parse_done
    mov [rdi + r9], al

    inc r8
    inc r9

    cmp r9, %5          ; sanity check, max path length
    jge %%parse_done
    
    jmp %%copy_loop

%%parse_done:
    ; preventing path traversals by cutting out '..' values
    ; here, rdi is the output buffer, and r9 is the path length
    xor r8, r8

%%traversal_loop:
    cmp r8, r9
    jge %%path_ok

    cmp byte [rdi + r8], '.'
    jne %%traversal_next

    cmp byte [rdi + r8 + 1], '.'  ; [r8, r8 + 1], if both are '.', a path traversal is detected
    je %%path_bad                 ; <- traversal detected

%%traversal_next:
    inc r8
    jmp %%traversal_loop

%%path_bad:
    xor r9, r9  ; length = 0 if bad path

%%path_ok:
    mov %4, r9

%endmacro

; PARSE_AUTH_HEADER buffer, length, out_decoded, out_len, max_len
;   Scans headers for "Authorization: Basic ", then decodes the base64
;   token directly into out_decoded using B64_DECODE.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer for decoded credentials (e.g. "user:pass")
;     %4: register to store decoded length (0 if not found)
;     %5: output buffer max length (respected by B64_DECODE's own termination)
;   Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8, r9
%macro PARSE_AUTH_HEADER 5
    xor %4, %4
    mov rsi, %1

    xor r8, r8      ; offset

%%auth_scan:
    ; need at least 22 bytes left: "Authorization: Basic " (21) + 1 byte of token
    mov rax, r8
    add rax, 22
    cmp rax, %2
    jg %%done

    cmp byte [rsi + r8], 'A'
    jne %%auth_next

    ; "Authorization: Basic " split into dwords:
    ;   [+0]  "Auth" = 0x68747541
    ;   [+4]  "oriz" = 0x7a69726f
    ;   [+8]  "atio" = 0x6f697461
    ;   [+12] "n: B" = 0x42203a6e
    ;   [+16] "asic" = 0x63697361
    ;   [+20] " "   = 0x20
    cmp dword [rsi + r8 +  0], 0x68747541
    jne %%auth_next

    cmp dword [rsi + r8 +  4], 0x7a69726f
    jne %%auth_next

    cmp dword [rsi + r8 +  8], 0x6f697461
    jne %%auth_next

    cmp dword [rsi + r8 + 12], 0x42203a6e
    jne %%auth_next

    cmp dword [rsi + r8 + 16], 0x63697361
    jne %%auth_next

    cmp byte  [rsi + r8 + 20], 0x20
    jne %%auth_next

    ; token starts at r8 + 21
    add r8, 21

    xor r9, r9

%%auth_token_len:
    mov rax, r8
    add rax, r9
    cmp rax, %2
    jge %%auth_copy

    movzx rax, byte [rsi + rax]
    B64_CHAR_VAL al
    cmp al, 0xff
    je %%auth_copy

    inc r9
    cmp r9, %5 - 1
    jge %%auth_copy
    jmp %%auth_token_len

%%auth_copy:
    ; B64_DECODE needs a null-terminated source, so temporarily null-terminate
    ; the token in the buffer and restore the original byte after
    mov rax, r8
    add rax, r9

    mov cl, [rsi + rax]
    mov byte [rsi + rax], 0

    lea rdi, [rsi + r8]      ; token start -> rdi (B64_DECODE's src)
    push rsi                 ; save base pointer (B64_DECODE clobbers rsi)
    push rax                 ; save restore index too (B64_DECODE clobbers rax)

    B64_DECODE rdi, %3, %4

    pop rax
    pop rsi
    mov [rsi + rax], cl      ; restore clobbered byte

    jmp %%done

%%auth_next:
    inc r8
    jmp %%auth_scan

%%done:
%endmacro
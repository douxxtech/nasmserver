; httputils.asm - HTTP/1.0 parsing utilities

extern gmtime_r
extern strftime
extern strptime
extern timegm

section .data
    http_date_fmt  db "%a, %d %b %Y %H:%M:%S GMT", 0  ; RFC 7231 date format
    date_timespec  dq 0, 0                            ; tv_sec, tv_nsec (reused for expire calc)

section .bss
    date_tm_buf    resb 64  ; struct tm

; IS_HTTP_REQUEST buffer, length
;   Checks for "GET "/"HEAD " prefix and "HTTP/1.x" just before the first CRLF.
;   Intentional note: We're treating 'HTTP/1.1' as a valid one, even if we return HTTP/1.0.
;   The clients will handle that by themselves, like big boys.
;   Args:
;     %1: buffer address
;     %2: buffer length
;   Returns:
;     rax = 200 if GET, -200 if HEAD, -400 if invalid, and -405 if the method isn't allowed
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
    ; check if its a supported request (GET, HEAD)
    cmp dword [rsi], 0x20544547     ; "GET "
    je %%get

    cmp dword [rsi], 0x44414548     ; "HEAD"
    jne %%method_not_allowed
    cmp byte  [rsi + 4], 0x20       ; " "
    je %%head

    jmp %%method_not_allowed       


%%get:
    mov rax, 200
    jmp %%done

%%method_not_allowed:
    mov rax, -405 ; negative codes are often used for errors in asm
    jmp %%done


%%head:
    mov rax, -200
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

; PARSE_AUTH_HEADER buffer, length, out_decoded, max_len
;   Scans headers for "Authorization: Basic ", then decodes the base64
;   token directly into out_decoded using B64_DECODE.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer for decoded credentials (e.g. "user:pass")
;     %4: output buffer max length
;   Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8, r9
%macro PARSE_AUTH_HEADER 4
    mov rsi, %1

    xor r8, r8      ; offset

%%auth_scan:
    ; need at least 22 bytes left: "Authorization: Basic " (21) + 1 byte of token
    mov rax, r8
    add rax, 22
    cmp rax, %2
    jg %%not_found

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
    cmp r9, ((%4 - 1 + 2) / 3) * 4  ; cap input so decoded output fits in %4 - 1 bytes
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

    B64_DECODE rdi, %3, r9

    pop rax
    pop rsi
    mov [rsi + rax], cl      ; restore clobbered byte

    jmp %%done

%%auth_next:
    inc r8
    jmp %%auth_scan

%%not_found:
    mov byte [%3], 0  ; null-term on failure (already done on success by b64_dec)

%%done:
%endmacro

; PARSE_IMS_HEADER buffer, length, out_buf
;   Scans headers for "If-Modified-Since: " and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer (min 32 bytes), zeroed on failure
;   Clobbers: rax, rsi, r8, r9, rdi
%macro PARSE_IMS_HEADER 3
    mov rsi, %1
    xor r8, r8

%%ims_scan:
    mov rax, r8
    add rax, 20               ; "If-Modified-Since: " = 19 bytes + 1 byte value

    cmp rax, %2
    jg %%not_found

    cmp byte [rsi + r8], 'I'
    jne %%ims_next

    cmp r8, 2
    jl %%ims_next

    cmp word [rsi + r8 - 2], 0x0a0d
    jne %%ims_next

    ; "If-M" = 0x4d2d6649
    ; "odif" = 0x6669646f
    ; "ied-" = 0x2d646569
    ; "Sinc" = 0x636e6953
    ; "e: "  = 0x3a65 (word) + 0x20 (byte)
    cmp dword [rsi + r8 +  0], 0x4d2d6649
    jne %%ims_next
    cmp dword [rsi + r8 +  4], 0x6669646f
    jne %%ims_next
    cmp dword [rsi + r8 +  8], 0x2d646569
    jne %%ims_next
    cmp dword [rsi + r8 + 12], 0x636e6953
    jne %%ims_next
    cmp word  [rsi + r8 + 16], 0x3a65     ; "e:"
    jne %%ims_next
    cmp byte  [rsi + r8 + 18], 0x20       ; " "
    jne %%ims_next

    add r8, 19     ; skip past "If-Modified-Since: "
    xor r9, r9
    lea rdi, [%3]

%%ims_copy:
    mov rax, r8
    add rax, r9

    cmp rax, %2
    jge %%ims_done

    movzx rax, byte [rsi + rax]
    
    cmp al, 0x0d                 ; \r = end of header value
    je %%ims_done

    mov [rdi + r9], al
    inc r9

    cmp r9, 31
    jge %%ims_done

    jmp %%ims_copy

%%ims_done:
    mov byte [rdi + r9], 0
    jmp %%done

%%ims_next:
    inc r8
    jmp %%ims_scan

%%not_found:
    mov byte [%3], 0

%%done:
%endmacro

; PARSE_UA_HEADER buffer, length, out_buf, max_len
;   Scans headers for "User-Agent: " and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer, zeroed on failure
;     %4: max bytes to copy (should be resb size - 1)
;   Clobbers: rax, rsi, rdi, r8, r9
%macro PARSE_UA_HEADER 4
    mov rsi, %1
    xor r8, r8


%%ua_scan:
    mov rax, r8
    add rax, 13               ; "User-Agent: " = 12 bytes + 1 byte value

    cmp rax, %2
    jg %%ua_not_found

    cmp byte [rsi + r8], 'U'
    jne %%ua_next

    cmp r8, 2
    jl %%ua_next

    cmp word [rsi + r8 - 2], 0x0a0d
    jne %%ua_next

    ; "User" = 0x72657355
    ; "-Age" = 0x6567412d
    ; "nt: " = 0x203a746e
    cmp dword [rsi + r8 +  0], 0x72657355
    jne %%ua_next
    cmp dword [rsi + r8 +  4], 0x6567412d
    jne %%ua_next
    cmp dword [rsi + r8 +  8], 0x203a746e
    jne %%ua_next

    add r8, 12                ; skip past "User-Agent: "
    xor r9, r9
    lea rdi, [%3]


%%ua_copy:
    mov rax, r8
    add rax, r9

    cmp rax, %2
    jge %%ua_done

    movzx rax, byte [rsi + rax]

    cmp al, 0x0d              ; \r = end of header value
    je %%ua_done

    mov [rdi + r9], al
    inc r9

    cmp r9, %4
    jge %%ua_done

    jmp %%ua_copy


%%ua_done:
    mov byte [rdi + r9], 0
    jmp %%done


%%ua_next:
    inc r8
    jmp %%ua_scan


%%ua_not_found:
    mov byte [%3], 0


%%done:
%endmacro


; PARSE_REFERER_HEADER buffer, length, out_buf, max_len
;   Scans headers for "Referer: " and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer, zeroed on failure
;     %4: max bytes to copy (should be resb size - 1)
;   Clobbers: rax, rsi, rdi, r8, r9
%macro PARSE_REFERER_HEADER 4
    mov rsi, %1
    xor r8, r8


%%ref_scan:
    mov rax, r8
    add rax, 10               ; "Referer: " = 9 bytes + 1 byte value

    cmp rax, %2
    jg %%ref_not_found

    cmp byte [rsi + r8], 'R'
    jne %%ref_next

    cmp r8, 2
    jl %%ref_next

    cmp word [rsi + r8 - 2], 0x0a0d
    jne %%ref_next

    ; "Refe" = 0x65666552
    ; "rer:" = 0x3a726572
    ; " "   = 0x20
    cmp dword [rsi + r8 + 0], 0x65666552
    jne %%ref_next
    cmp dword [rsi + r8 + 4], 0x3a726572
    jne %%ref_next
    cmp byte  [rsi + r8 + 8], 0x20
    jne %%ref_next

    add r8, 9                 ; skip past "Referer: "
    xor r9, r9
    lea rdi, [%3]


%%ref_copy:
    mov rax, r8
    add rax, r9

    cmp rax, %2
    jge %%ref_done

    movzx rax, byte [rsi + rax]

    cmp al, 0x0d              ; \r = end of header value
    je %%ref_done

    mov [rdi + r9], al
    inc r9

    cmp r9, %4
    jge %%ref_done

    jmp %%ref_copy


%%ref_done:
    mov byte [rdi + r9], 0
    jmp %%done


%%ref_next:
    inc r8
    jmp %%ref_scan


%%ref_not_found:
    mov byte [%3], 0


%%done:
%endmacro

; HTTP_EXPIRE_DATE offset_sec, out_buf
;   Builds a null-terminated RFC 7231 GMT date string for use in HTTP headers.
;   Takes the current wall-clock time, adds offset_sec seconds, then formats it.
;   Args:
;     %1: offset in seconds to add (immediate or register)
;     %2: output buffer, min 32b
;   Returns:
;     %2 contains a null-terminated string like "Mon, 01 Jan 2000 00:00:00 GMT"
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro HTTP_EXPIRE_DATE 2
    ; clock_gettime(CLOCK_REALTIME, &date_timespec)
    mov rax, 228
    xor rdi, rdi
    mov rsi, date_timespec
    syscall

    ; add offset to tv_sec
    mov rax, [date_timespec]
    add rax, %1
    mov [date_timespec], rax

    ; gmtime_r(&tv_sec, &date_tm_buf)
    mov rdi, date_timespec
    mov rsi, date_tm_buf
    call gmtime_r

    ; strftime(out, 32, fmt, &tm)
    mov rdi, %2
    mov rsi, 32
    mov rdx, http_date_fmt
    mov rcx, date_tm_buf
    call strftime
%endmacro

; GET_HTTP_TIME out_buf
;   Builds a null-terminated RFC 7231 / HTTP/1.0 GMT date string for the current time.
;   Args:
;     %1: output buffer, min 32 bytes
;   Returns:
;     %1 contains a string like "Mon, 01 Jan 2000 00:00:00 GMT"
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro GET_HTTP_TIME 1
    ; clock_gettime(CLOCK_REALTIME, &date_timespec)
    mov rax, 228
    xor rdi, rdi
    mov rsi, date_timespec
    syscall

    ; gmtime_r(&tv_sec, &date_tm_buf)
    mov rdi, date_timespec
    mov rsi, date_tm_buf
    call gmtime_r

    ; strftime(out, 32, fmt, &tm)
    mov rdi, %1
    mov rsi, 32
    mov rdx, http_date_fmt
    mov rcx, date_tm_buf
    call strftime
%endmacro

; HTTP_PARSE_TIME in_buf, out_reg
;   Parses an RFC 7231 HTTP-date string (GMT) into epoch seconds.
;   Expected format: "%a, %d %b %Y %H:%M:%S GMT"
;   Args:
;     %1: input buffer (null-terminated HTTP date string)
;     %2: register to receive epoch time (time_t)
;   Returns:
;     %2 = epoch seconds on success -1 on failure (parse error)
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro HTTP_PARSE_TIME 2
    ; strptime(in, fmt, tm)
    mov rdi, %1
    mov rsi, http_date_fmt
    mov rdx, date_tm_buf

    call strptime

    ; strptime returns 0 on failure
    test rax, rax
    jz %%parse_fail

    ; timegm(&tm)
    mov rdi, date_tm_buf
    call timegm             ; returns time_t in rax

    mov %2, rax
    jmp %%done

%%parse_fail:
    mov %2, -1

%%done:
%endmacro
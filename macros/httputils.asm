; httputils.asm - HTTP/1.0 parsing utilities

extern gmtime_r
extern strftime
extern strptime
extern timegm

section .data
    http_date_fmt   db "%a, %d %b %Y %H:%M:%S GMT", 0  ; RFC 7231 date format
    date_timespec   dq 0, 0                            ; tv_sec, tv_nsec (reused for expire calc)

    hdr_user_agent  db "user-agent", 0
    hdr_referer     db "referer", 0
    hdr_xri         db "x-real-ip", 0
    hdr_ims         db "if-modified-since", 0

section .bss
    date_tm_buf  resb 64  ; struct tm

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

; LOWERCASE_HEADERS buffer, length
;   Lowercases header names in-place, stopping at \r\n\r\n or end of buffer.
;   Only lowercases chars before the ':' on each line (preserves values).
;   Args:
;     %1: buffer address
;     %2: buffer length
;   Clobbers: rax, rsi, r8, r9
%macro LOWERCASE_HEADERS 2
    mov rsi, %1
    xor r8, r8
    xor r9, r9   ; r9 = 1 if we're past the ':' on this line

%%lwc_skip_reqline:
    ; skip the first line to avoid corrupting the request itself
    cmp r8, %2
    jge %%lwc_done

    cmp word [rsi + r8], 0x0a0d
    je %%lwc_start

    inc r8
    jmp %%lwc_skip_reqline

%%lwc_start:
    add r8, 2

%%lwc_loop:
    cmp r8, %2
    jge %%lwc_done

    movzx rax, byte [rsi + r8]

    ; check for end of headers (\r\n\r\n)
    cmp r8, 3
    jl %%lwc_skip_eoh

    cmp dword [rsi + r8 - 3], 0x0a0d0a0d
    je %%lwc_done

%%lwc_skip_eoh:
    ; reset "past colon" flag on newline
    cmp al, 0x0a
    je %%lwc_newline

    cmp al, ':'
    je %%lwc_colon

    ; only lowercase if we haven't hit ':' yet
    test r9, r9
    jnz %%lwc_skip

    cmp al, 'A'
    jl %%lwc_skip
    cmp al, 'Z'
    jg %%lwc_skip
    or al, 0x20         ; to lowercase
    mov [rsi + r8], al

    jmp %%lwc_skip

%%lwc_colon:
    mov r9, 1
    jmp %%lwc_skip

%%lwc_newline:
    xor r9, r9  ; reset for next line

%%lwc_skip:
    inc r8
    jmp %%lwc_loop

%%lwc_done:
%endmacro

; GET_HEADER buffer, length, name, name_len, out_buf, max_len
;   Header scanner. Finds a lowercase header name and copies its value.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: header name string
;     %4: header name length
;     %5: output buffer, zeroed on failure
;     %6: max bytes to copy
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro GET_HEADER 6
    mov rsi, %1
    xor r8, r8

%%fh_scan:
    ; bail if there's not enough buffer left for name + ": " + 1 byte of value
    mov rax, r8
    add rax, %4 + 3
    cmp rax, %2
    jg %%fh_not_found

    ; first-char check before doing the full comparison
    movzx rax, byte [%3]
    cmp byte [rsi + r8], al
    jne %%fh_next

    ; header names must start at the beginning of a line
    cmp r8, 2
    jl %%fh_next

    cmp word [rsi + r8 - 2], 0x0a0d   ; \r\n
    jne %%fh_next

    ; compare the full header name using repe cmpsb
    push rsi
    push rdi
    push rcx

    lea rdi, [rsi + r8]               ; rdi = current position in buffer
    mov rsi, %3                       ; rsi = header name to match
    mov rcx, %4                       ; rcx = header name length
    repe cmpsb

    pop rcx
    pop rdi
    pop rsi

    jne %%fh_next

    cmp word [rsi + r8 + %4], 0x203a  ; ": "
    jne %%fh_next

    ; skip past "name: " to get the value
    add r8, %4 + 2
    xor r9, r9

%%fh_measure:
    ; measure how many bytes the value is before \r, \n, or a control char
    mov rax, r8
    add rax, r9

    cmp rax, %2
    jge %%fh_copy

    movzx rax, byte [rsi + rax]

    cmp al, 0x0d                 ; \r = end of value
    je %%fh_copy

    cmp al, 0x0a                 ; \n = also end
    je %%fh_copy

    cmp al, 0x20                 ; control chars below space = end
    jl %%fh_copy

    inc r9

    cmp r9, %6                   ; don't exceed the output buffer
    jge %%fh_copy

    jmp %%fh_measure

%%fh_copy:
    ; copy the measured value into the output buffer
    lea rdi, [%5]
    lea rax, [rsi + r8]

    APPEND rdi, rax, r9

    mov byte [rdi], 0     ; NUL-terminate
    jmp %%fh_out

%%fh_next:
    inc r8
    jmp %%fh_scan

%%fh_not_found:
    mov byte [%5], 0   ; zero out the buffer so callers don't see stale data

%%fh_out:
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

; PARSE_UA_HEADER buffer, length, out_buf, max_len
;   Scans headers for "user-agent" and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer, zeroed on failure
;     %4: max bytes to copy (should be resb size - 1)
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_UA_HEADER 4
    GET_HEADER %1, %2, hdr_user_agent, 10, %3, %4
%endmacro


; PARSE_REFERER_HEADER buffer, length, out_buf, max_len
;   Scans headers for "referer" and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer, zeroed on failure
;     %4: max bytes to copy (should be resb size - 1)
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_REFERER_HEADER 4
    GET_HEADER %1, %2, hdr_referer, 7, %3, %4
%endmacro


; PARSE_XRI_HEADER buffer, length, out_buf, max_len
;   Scans headers for "x-real-ip" and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer, zeroed on failure
;     %4: max bytes to copy (should be resb size - 1)
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_XRI_HEADER 4
    GET_HEADER %1, %2, hdr_xri, 9, %3, %4
%endmacro


; PARSE_IMS_HEADER buffer, length, out_buf
;   Scans headers for "if-modified-since" and copies the value into out_buf.
;   Args:
;     %1: buffer address
;     %2: buffer length
;     %3: output buffer (min 32 bytes), zeroed on failure
;   Clobbers: rax, rsi, rdi, rcx, r8, r9
%macro PARSE_IMS_HEADER 3
    GET_HEADER %1, %2, hdr_ims, 17, %3, 31
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
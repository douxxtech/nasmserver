; logutils.asm - Logging utilities for NASMServer

extern localtime_r
extern strftime

section .data
    ts_fmt      db "%H:%M:%S ", 0          ; trailing space included
    timespec    dq 0, 0                    ; tv_sec, tv_nsec (struct timespec)

    rs_fmt      db "%d/%b/%Y:%H:%M:%S %z", 0

    str_prefix_info                 db "[INFO] ", 0
    str_prefix_info_len             equ $ - str_prefix_info - 1

    str_prefix_warning              db "[WARNING] ", 0
    str_prefix_warning_len          equ $ - str_prefix_warning - 1

    str_prefix_err                  db "[ERROR] ", 0
    str_prefix_err_len              equ $ - str_prefix_err - 1

    str_prefix_dbg                  db "* ", 0
    str_prefix_dbg_len              equ $ - str_prefix_dbg - 1


section .bss
    tm_buf      resb 64    ; struct tm (libc)
    ts_buf      resb 16    ; "HH:MM:SS \0" + padding
    rs_buf      resb 32    ; "dd/mmm/yyyy:HH:MM:SS +-zzzz \0" + padding

    status_buf  resb 20    ; current ITOA scratch-buffer requirement

    log_buffer  resb 4096  ; buffer for a variety of logs

; PRINT_TIMESTAMP
;   Prints "HH:MM:SS " to stdout via clock_gettime + localtime_r + strftime.
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro PRINT_TIMESTAMP 0

    ; get the current wall-clock time
    ; clock_gettime(clockid, timespec)
    mov rax, 228
    xor rdi, rdi       ; CLOCK_REALTIME
    mov rsi, timespec
    syscall

    ; localtime_r(&tv_sec, &tm_buf)
    mov rdi, timespec
    mov rsi, tm_buf
    call localtime_r

    ; strftime(ts_buf, 16, "%H:%M:%S ", &tm_buf)
    mov rdi, ts_buf
    mov rsi, 16
    mov rdx, ts_fmt
    mov rcx, tm_buf
    call strftime

    ; write the formatted timestamp (9 chars) to stdout
    ; write(fd, buffer, count)
    mov rax, 1
    mov rdi, 1         ; stdout
    mov rsi, ts_buf
    mov rdx, 9
    syscall
%endmacro

; LOG_INFO msg, len
;   Prints: "HH:MM:SS [INFO] <msg>\n"
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_INFO 2
    ; check if we should log or not
    cmp byte [rel str_level], 0  ; log lvl none = skip
    je %%end

%%log:
    PRINT_TIMESTAMP
    PRINT str_prefix_info, str_prefix_info_len
    PRINTN %1, %2

%%end:
%endmacro

; LOG_WARNING msg, len
;   Prints: "HH:MM:SS [WARNING] <msg>\n"
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_WARNING 2
    ; check if we should log or not
    cmp byte [rel str_level], 0  ; log lvl none = skip
    je %%end

%%log:
    PRINT_TIMESTAMP
    PRINT str_prefix_warning, str_prefix_warning_len
    PRINTN %1, %2

%%end:
%endmacro

; LOG_ERR msg, len
;   Prints: "HH:MM:SS [ERROR] <msg>\n" to STDERR
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_ERR 2
    ; check if we should log or not
    cmp byte [rel str_level], 0  ; log lvl none = skip
    je %%end

%%log:
    PRINT_TIMESTAMP
    PRINTF 2, str_prefix_err, str_prefix_err_len
    PRINTF 2, %1, %2
    PRINTF 2, sysutils_newline, 1

%%end:
%endmacro

; LOG_DEBUG msg, len
;   Prints: "HH:MM:SS [ERROR] <msg>\n" to STDERR
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_DEBUG 2
    ; check if we should log or not
    cmp byte [rel str_level], 2  ; log lvl none = skip
    jne %%end

%%log:
    PRINTF 2, str_prefix_dbg, str_prefix_dbg_len

    STRLEN current_pid_str, rcx
    PRINTF 2, current_pid_str, rcx
    PRINTF 2, str_two_dots, str_two_dots_len
    PRINTF 2, str_space, str_space_len
    PRINTF 2, %1, %2
    PRINTF 2, sysutils_newline, 1

%%end:
%endmacro

; LOG_PORT
;   Prints: "HH:MM:SS [INFO] Listening on <bind_addr>:<port>\n"
;   Uses:
;     bind_addr_str  null-terminated string containing the IPv4 address
;     port           word containing the port number (host byte order)
;     log_port_buf   buffer for integer-to-ASCII conversion
;   Clobbers: rax, rbx, rdi, rsi, rdx, rcx, r9
%macro LOG_PORT 0
    ; check if we should log or not
    cmp byte [rel str_level], 0  ; log lvl none = skip
    je %%end

%%log:
    ; this mess prints the port log
    PRINT_TIMESTAMP

    PRINT str_prefix_info, str_prefix_info_len
    PRINT str_listening_on, str_listening_on_len

    STRLEN bind_addr_str, r9
    PRINT bind_addr_str, r9                        ; x.x.x.x 

    PRINT str_two_dots, str_two_dots_len           ; ":"

    ; port int to ascii
    movzx rbx, word [rel port]

    ITOA rbx, log_port_buf, r9
    PRINTN log_port_buf, r9                        ; XXXX

%%end:
%endmacro

; LOG_REQUEST_CLFE
;   Prints a Combined Log Format Extended (CLFE) log line to stdout.
;   Also matches the default Apache HTTP Server log format.
;   Format: <ip> <ident> <auth> [<timestamp>] "<request>" <status> <size> "<referer>" "<user-agent>"
;   Args:
;     %1: file descriptor
;   Reads from:
;     real_ip          null-terminated client IP string
;     username         null-terminated auth username (or empty for "-")
;     request          raw HTTP request buffer (up to 8192 bytes, CR/LF terminated)
;     last_status      word containing the HTTP status code
;     itoa_buf         null-terminated response size string (or empty for "0")
;     referer          null-terminated Referer header value (or empty for "-")
;     user_agent       null-terminated User-Agent header value (or empty for "-")
;   Clobbers: rax, rbx, rcx, rdi, rsi, rdx, r8, r9, r10
%macro LOG_REQUEST_CLFE 1

    ; check if we should log or not
    cmp qword [rel str_file], 1
    jne %%pt1                ; log to file = log

    cmp byte [rel str_level], 0  ; not to file + log lvl none = skip
    je %%end


%%pt1:
    CLB                      ; clear the log buffer before building
    lea r8, [rel log_buffer]     ; r8 = write pointer into log_buffer

    ; pt. 1: ip
    lea r10, [rel real_ip]
    STRLEN r10, rcx
    APPEND r8, r10, rcx
    APPEND r8, str_space, str_space_len

%%pt2:
    ; pt. 2: identity, not supported
    APPEND r8, clfe_missing, clfe_missing_len
    APPEND r8, str_space, str_space_len

%%pt3:
    ; pt. 3: auth
    lea r10, [rel username]
    STRLEN r10, rcx

    cmp rcx, 0                            ; if empty, no auth
    je %%no_auth

    APPEND r8, r10, rcx
    APPEND r8, str_space, str_space_len

    jmp %%pt4

%%no_auth:
    APPEND r8, clfe_missing, clfe_missing_len
    APPEND r8, str_space, str_space_len

%%pt4:
    ; pt. 4: timestamp
    APPEND r8, clfe_start_ts, clfe_start_ts_len

    push r8            ; save write pointer so it doesn't get clobbered

    ; get the current wall-clock time
    ; clock_gettime(clockid, timespec)
    mov rax, 228
    xor rdi, rdi       ; CLOCK_REALTIME
    mov rsi, timespec
    syscall

    ; localtime_r(&tv_sec, &tm_buf)
    mov rdi, timespec
    mov rsi, tm_buf
    call localtime_r

    ; strftime(rs_buf, 32, rs_fmt, &tm_buf)
    mov rdi, rs_buf    ; fixed: write directly to rs_buf
    mov rsi, 32        ; fixed: size matches rs_buf
    mov rdx, rs_fmt
    mov rcx, tm_buf    ; fixed: pass struct tm*, not rs_buf
    call strftime

    pop r8             ; restore write pointer

    STRLEN rs_buf, rcx
    APPEND r8, rs_buf, rcx

    APPEND r8, clfe_end_ts, clfe_end_ts_len
    APPEND r8, str_space, str_space_len

%%pt5:
    APPEND r8, str_quotation_mark, str_quotation_mark_len

    lea r10, [rel request]
    xor r9, r9

%%req_scan:
    cmp r9, 8192
    jge %%req_print

    movzx rax, byte [r10 + r9]

    cmp al, 0x0d                ; \r
    je %%req_print

    cmp al, 0xa                 ; \n
    je %%req_print

    cmp al, 0                   ; \0
    je %%req_print

    inc r9
    jmp %%req_scan

%%req_print:
    APPEND r8, r10, r9

    APPEND r8, str_quotation_mark, str_quotation_mark_len
    APPEND r8, str_space, str_space_len

%%pt6:
    ; pt. 6: status code

    movzx r10, word [rel last_status]

    ITOA r10, status_buf, r9
    APPEND r8, status_buf, r9

    APPEND r8, str_space, str_space_len

%%pt7:
    ; pt. 7: size
    STRLEN itoa_buf, rcx

    cmp rcx, 0
    je %%no_len

    APPEND r8, itoa_buf, rcx
    APPEND r8, str_space, str_space_len

    jmp %%pt8

%%no_len:
    APPEND r8, clfe_nobytes, clfe_nobytes_len
    APPEND r8, str_space, str_space_len

%%pt8:
    ; pt. 8: "referer"
    APPEND r8, str_quotation_mark, str_quotation_mark_len

    STRLEN referer, rcx

    cmp rcx, 0
    je %%no_referer

    APPEND r8, referer, rcx
    APPEND r8, str_quotation_mark, str_quotation_mark_len
    APPEND r8, str_space, str_space_len

    jmp %%pt9

%%no_referer:
    APPEND r8, clfe_missing, clfe_missing_len
    APPEND r8, str_quotation_mark, str_quotation_mark_len
    APPEND r8, str_space, str_space_len

%%pt9:
    ; pt. 9: user agent
    APPEND r8, str_quotation_mark, str_quotation_mark_len

    STRLEN user_agent, rcx

    cmp rcx, 0
    je %%no_ua

    APPEND r8, user_agent, rcx
    APPEND r8, str_quotation_mark, str_quotation_mark_len

    jmp %%done

%%no_ua:
    APPEND r8, clfe_missing, clfe_missing_len
    APPEND r8, str_quotation_mark, str_quotation_mark_len

%%done:
    APPEND r8, sysutils_newline, 1

    ; flush the whole log line in one shot
    lea rsi, [rel log_buffer]
    mov rdx, r8
    sub rdx, rsi                           ; length = write pointer - base
    PRINTF %1, log_buffer, rdx

%%end:
%endmacro

; CLB
;   Clears the log buffer
;   Clobbers: rax, rdi, rcx
%macro CLB 0
    CLEAR_BUFFER log_buffer, 2048
%endmacro
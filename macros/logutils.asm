; logutils.asm - Logging utilities for NASMServer

extern localtime_r
extern strftime

section .data

    ; timestamp
    ts_fmt  db "%H:%M:%S ", 0 ; trailing space included
    ts_buf  times 16 db 0     ; "HH:MM:SS \0" + padding
    timespec dq 0, 0          ; tv_sec, tv_nsec (struct timespec)
    tm_buf  times 64 db 0     ; struct tm (libc)

    ; level prefixes
    log_prefix_info     db "[INFO] ", 0
    log_prefix_info_len equ $ - log_prefix_info - 1

    log_prefix_err      db "[ERROR] ", 0
    log_prefix_err_len  equ $ - log_prefix_err - 1

    ; startup / fatal messages
    log_listening_port      db "Listening on port 80", 0
    log_listening_port_len  equ $ - log_listening_port - 1

    log_fail_socket         db "Failed to open socket", 0
    log_fail_socket_len     equ $ - log_fail_socket - 1

    log_fail_setsockopt     db "Failed to set socket options", 0
    log_fail_setsockopt_len equ $ - log_fail_setsockopt - 1

    log_fail_bind           db "Failed to bind to port", 0
    log_fail_bind_len       equ $ - log_fail_bind - 1

    log_fail_accept         db "Failed to accept connection", 0
    log_fail_accept_len     equ $ - log_fail_accept - 1

    ; request logging

    log_thing           db " - ", 0
    log_thing_len       equ $ - log_thing - 1

    log_request_pre     db "Request: ", 0
    log_request_pre_len equ $ - log_request_pre - 1

    log_arrow           db " -> ", 0
    log_arrow_len       equ $ - log_arrow - 1

    log_status_200      db "200 OK", 0xa, 0
    log_status_200_len  equ $ - log_status_200 - 1

    log_status_400      db "400 Bad Request", 0xa, 0
    log_status_400_len  equ $ - log_status_400 - 1

    log_status_404      db "404 Not Found", 0xa, 0
    log_status_404_len  equ $ - log_status_404 - 1

; macros

; PRINT_TIMESTAMP
;   Prints "HH:MM:SS " to stdout via clock_gettime + localtime_r + strftime.
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro PRINT_TIMESTAMP 0
    ; clock_gettime(CLOCK_REALTIME=0, &timespec)
    mov rax, 228
    xor rdi, rdi
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

    ; write "HH:MM:SS " (9 chars) to stdout
    mov rax, 1
    mov rdi, 1
    mov rsi, ts_buf
    mov rdx, 9
    syscall
%endmacro

; LOG_INFO msg, len
;   Prints: "HH:MM:SS [INFO]  <msg>\n"
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_INFO 2
    PRINT_TIMESTAMP
    PRINT log_prefix_info, log_prefix_info_len
    PRINTN %1, %2
%endmacro

; LOG_ERR msg, len
;   Prints: "HH:MM:SS [ERROR] <msg>\n"
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_ERR 2
    PRINT_TIMESTAMP
    PRINT log_prefix_err, log_prefix_err_len
    PRINTN %1, %2
%endmacro

; LOG_REQUEST path_ptr, status_code
;   Prints: "HH:MM:SS [INFO]  Request: <path> -> <status>\n"
;   Args:
;     %1: pointer to null-terminated path string
;     %2: status code as integer (200, 400, or 404)
;     %3: pointer to the ip string
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_REQUEST 3
    PRINT_TIMESTAMP
    PRINT log_prefix_info, log_prefix_info_len
    PRINT log_request_pre, log_request_pre_len
    STRLEN %3, rcx
    PRINT %3, rcx
    PRINT log_thing, log_thing_len
    STRLEN %1, rcx
    PRINT %1, rcx
    PRINT log_arrow, log_arrow_len
    cmp %2, 404
    je %%s404
    cmp %2, 400
    je %%s400
    PRINT log_status_200, log_status_200_len
    jmp %%done
%%s404:
    PRINT log_status_404, log_status_404_len
    jmp %%done
%%s400:
    PRINT log_status_400, log_status_400_len
%%done:
%endmacro
; logutils.asm - Logging utilities for NASMServer

extern localtime_r
extern strftime

section .data
    ts_fmt      db "%H:%M:%S ", 0          ; trailing space included
    timespec    dq 0, 0                    ; tv_sec, tv_nsec (struct timespec)

    rs_fmt      db "%d/%b/%Y:%H:%M:%S %z", 0

    log_space                       db " ", 0
    log_space_len                   equ $ - log_space - 1

    log_quotation_mark              db 0x22, 0  ; '"'
    log_quotation_mark_len          equ $ - log_quotation_mark - 1

    log_two_dots                    db ":", 0
    log_two_dots_len                equ $ - log_two_dots - 1


    ; log level prefixes

    log_prefix_info                 db "[INFO] ", 0
    log_prefix_info_len             equ $ - log_prefix_info - 1

    log_prefix_warning              db "[WARNING] ", 0
    log_prefix_warning_len          equ $ - log_prefix_warning - 1

    log_prefix_err                  db "[ERROR] ", 0
    log_prefix_err_len              equ $ - log_prefix_err - 1


    ; startup banner
    log_started_nasmserver          db "Started the NASMServer static files HTTP server.", 0xa, 0
    log_started_nasmserver_len      equ $ - log_started_nasmserver - 1


    ; startup checks
    log_startup_ok                  db "Startup checks passed", 0
    log_startup_ok_len              equ $ - log_startup_ok - 1

    log_check_docroot_missing       db "document_root does not exist or is not a directory", 0
    log_check_docroot_missing_len   equ $ - log_check_docroot_missing - 1

    log_check_docroot_perms         db "document_root is not readable/accessible", 0
    log_check_docroot_perms_len     equ $ - log_check_docroot_perms - 1

    log_check_errordoc_missing      db "errordoc file not found (requests will get empty error pages)", 0
    log_check_errordoc_missing_len  equ $ - log_check_errordoc_missing - 1

    log_check_port_privileged       db "Warning: port < 1024 requires root privileges", 0
    log_check_port_privileged_len   equ $ - log_check_port_privileged - 1

    log_log_file_not_opened         db "Failed to open the provided log file (missing permissions?). STDOUT will be used instead.", 0
    log_log_file_not_opened_len     equ $ - log_log_file_not_opened - 1

    ; startup / fatal errors
    log_fail_read_env               db "Failed to read the provided configuration file path", 0
    log_fail_read_env_len           equ $ - log_fail_read_env - 1

    log_fail_build_addr             db "Failed to parse the provided BIND_ADDRES. Make sure to provide a valid IPv4 address.", 0
    log_fail_build_addr_len         equ $ - log_fail_build_addr - 1

    log_fail_socket                 db "Failed to open socket", 0
    log_fail_socket_len             equ $ - log_fail_socket - 1

    log_fail_setsockopt             db "Failed to set socket options", 0
    log_fail_setsockopt_len         equ $ - log_fail_setsockopt - 1

    log_fail_bind                   db "Failed to bind to port", 0
    log_fail_bind_len               equ $ - log_fail_bind - 1

    log_fail_accept                 db "Failed to accept connection", 0
    log_fail_accept_len             equ $ - log_fail_accept - 1

    log_listening_on                db "Listening on ", 0
    log_listening_on_len            equ $ - log_listening_on - 1


    ; request logging
    ; common log format extended
    clfe_missing                    db "-", 0
    clfe_missing_len                equ $ - clfe_missing - 1

    clfe_start_ts                   db "[", 0
    clfe_start_ts_len               equ $ - clfe_start_ts - 1

    clfe_end_ts                     db "]", 0
    clfe_end_ts_len                 equ $ - clfe_end_ts - 1

    clfe_nobytes                    db "0", 0
    clfe_nobytes_len                equ $ - clfe_nobytes - 1

    ; HTTP status messages
    log_status_200                  db "200 OK", 0xa, 0
    log_status_200_len              equ $ - log_status_200 - 1

    log_status_304                  db "304 Not Modified", 0xa, 0
    log_status_304_len              equ $ - log_status_304 - 1

    log_status_400                  db "400 Bad Request", 0xa, 0
    log_status_400_len              equ $ - log_status_400 - 1

    log_status_401                  db "401 Unauthorized", 0xa, 0
    log_status_401_len              equ $ - log_status_401 - 1

    log_status_403                  db "403 Forbidden", 0xa, 0
    log_status_403_len              equ $ - log_status_403 - 1

    log_status_404                  db "404 Not Found", 0xa, 0
    log_status_404_len              equ $ - log_status_404 - 1

    log_status_405                  db "405 Method Not Allowed", 0xa, 0
    log_status_405_len              equ $ - log_status_405 - 1


    ; runtime warnings
    log_too_many_concurrent         db "Rejected request: too many concurrent requests", 0
    log_too_many_concurrent_len     equ $ - log_too_many_concurrent - 1


    ; CLI / arguments / help
    log_arg_not_recognized_p1       db "Argument '", 0
    log_arg_not_recognized_p1_len   equ $ - log_arg_not_recognized_p1 - 1

    log_arg_not_recognized_p2       db "' is not recognized by NASMServer.", 0xa, \
                                       "Run nasmserver -h to see the list of available flags and arguments.", 0
    log_arg_not_recognized_p2_len   equ $ - log_arg_not_recognized_p2 - 1

    log_flag_e_error                db "Missing value after '-e'. Usage: -e <config.env>", 0
    log_flag_e_error_len            equ $ - log_flag_e_error - 1

    log_help_text                   db "Usage: nasmserver [-h] [-e <config.env>]", 0xa, \
                                       "  -h              show this help", 0xa, \
                                       "  -v              show the current version", 0xa, \
                                       "  -e <config>     path to the .env config file", 0xa, 0
    log_help_text_len               equ $ - log_help_text - 1

    log_version                     db "Server version: ", 0
    log_version_len                 equ $ - log_version - 1


section .bss
    tm_buf     resb 64  ; struct tm (libc)
    ts_buf     resb 16  ; "HH:MM:SS \0" + padding
    rs_buf     resb 32  ; "dd/mmm/yyyy:HH:MM:SS +-zzzz \0" + padding

    status_buf resb 20  ; current ITOA scratch-buffer requirement

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
    PRINT_TIMESTAMP
    PRINT log_prefix_info, log_prefix_info_len
    PRINTN %1, %2
%endmacro

; LOG_WARNING msg, len
;   Prints: "HH:MM:SS [WARNING] <msg>\n"
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_WARNING 2
    PRINT_TIMESTAMP
    PRINT log_prefix_warning, log_prefix_warning_len
    PRINTN %1, %2
%endmacro

; LOG_ERR msg, len
;   Prints: "HH:MM:SS [ERROR] <msg>\n" to STDERR
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_ERR 2
    PRINT_TIMESTAMP
    PRINTF 2, log_prefix_err, log_prefix_err_len
    PRINTF 2, %1, %2
    PRINTF 2, sysutils_newline, 1
%endmacro

; LOG_REQUEST_CLFE
;   Prints a Combined Log Format Extended (CLFE) log line to stdout.
;   Also matches the default Apache HTTP Server log format.
;   Format: <ip> <ident> <auth> [<timestamp>] "<request>" <status> <size> "<referer>" "<user-agent>"
;   Args:
;     %1: file descriptor
;   Reads from:
;     client_ip_str    null-terminated client IP string
;     username         null-terminated auth username (or empty for "-")
;     request          raw HTTP request buffer (up to 8192 bytes, CR/LF terminated)
;     last_status      word containing the HTTP status code
;     content_length_b null-terminated response size string (or empty for "0")
;     referer          null-terminated Referer header value (or empty for "-")
;     user_agent       null-terminated User-Agent header value (or empty for "-")
;   Clobbers: rax, rcx, rdi, rsi, rdx, r9, r10
%macro LOG_REQUEST_CLFE 1

%%pt1:
    ; pt. 1: ip
    lea r10, [client_ip_str]
    STRLEN r10, rcx
    PRINTF %1, r10, rcx
    PRINTF %1, log_space, log_space_len

%%pt2:
    ; pt. 2: identity, not supported
    PRINTF %1, clfe_missing, clfe_missing_len
    PRINTF %1, log_space, log_space_len

%%pt3:
    ; pt. 3: auth
    lea r10, [username]
    STRLEN r10, rcx

    cmp rcx, 0                            ; if empty, no auth
    je %%no_auth

    PRINTF %1, r10, rcx
    PRINTF %1, log_space, log_space_len

    jmp %%pt4

%%no_auth:
    PRINTF %1, clfe_missing, clfe_missing_len
    PRINTF %1, log_space, log_space_len

%%pt4:
    ; pt. 4: timestamp
    PRINTF %1, clfe_start_ts, clfe_start_ts_len

    push %1            ;  save %1 (r9) so it doesn't get clobbered

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

    pop %1

    STRLEN rs_buf, rcx
    PRINTF %1, rs_buf, rcx

    PRINTF %1, clfe_end_ts, clfe_end_ts_len
    PRINTF %1, log_space, log_space_len

%%pt5:
    PRINTF %1, log_quotation_mark, log_quotation_mark_len

    lea r10, [request]
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
    PRINTF %1, r10, r9

    PRINTF %1, log_quotation_mark, log_quotation_mark_len
    PRINTF %1, log_space, log_space_len

%%pt6:
    ; pt. 6: status code

    movzx r10, word [last_status]

    ITOA r10, status_buf, r9
    PRINTF %1, status_buf, r9

    PRINTF %1, log_space, log_space_len

%%pt7:
    ; pt. 7: size
    STRLEN content_length_b, rcx

    cmp rcx, 0
    je %%no_len

    PRINTF %1, content_length_b, rcx
    PRINTF %1, log_space, log_space_len

    jmp %%pt8

%%no_len:
    PRINTF %1, clfe_nobytes, clfe_nobytes_len
    PRINTF %1, log_space, log_space_len

%%pt8:
    ; pt. 8: "referer"
    PRINTF %1, log_quotation_mark, log_quotation_mark_len

    STRLEN referer, rcx

    cmp rcx, 0
    je %%no_referer

    PRINTF %1, referer, rcx
    PRINTF %1, log_quotation_mark, log_quotation_mark_len
    PRINTF %1, log_space, log_space_len

    jmp %%pt9

%%no_referer:
    PRINTF %1, clfe_missing, clfe_missing_len
    PRINTF %1, log_quotation_mark, log_quotation_mark_len
    PRINTF %1, log_space, log_space_len

%%pt9:
    ; pt. 9: user agent
    PRINTF %1, log_quotation_mark, log_quotation_mark_len

    STRLEN user_agent, rcx

    cmp rcx, 0
    je %%no_ua

    PRINTF %1, user_agent, rcx
    PRINTF %1, log_quotation_mark, log_quotation_mark_len

    jmp %%done

%%no_ua:
    PRINTF %1, clfe_missing, clfe_missing_len
    PRINTF %1, log_quotation_mark, log_quotation_mark_len

%%done:
    PRINTF %1, sysutils_newline, 1
%endmacro
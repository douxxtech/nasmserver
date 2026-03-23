; logutils.asm - Logging utilities for NASMServer

extern localtime_r
extern strftime

section .data
    ts_fmt      db "%H:%M:%S ", 0  ; trailing space included
    ts_buf      times 16 db 0      ; "HH:MM:SS \0" + padding
    timespec    dq 0, 0            ; tv_sec, tv_nsec (struct timespec)
    tm_buf      times 64 db 0      ; struct tm (libc)


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


    ; startup / fatal errors
    log_fail_read_env               db "Failed to read the provided configuration file path", 0
    log_fail_read_env_len           equ $ - log_fail_read_env - 1

    log_fail_socket                 db "Failed to open socket", 0
    log_fail_socket_len             equ $ - log_fail_socket - 1

    log_fail_setsockopt             db "Failed to set socket options", 0
    log_fail_setsockopt_len         equ $ - log_fail_setsockopt - 1

    log_fail_bind                   db "Failed to bind to port", 0
    log_fail_bind_len               equ $ - log_fail_bind - 1

    log_fail_accept                 db "Failed to accept connection", 0
    log_fail_accept_len             equ $ - log_fail_accept - 1

    log_listening_port              db "Listening on port ", 0
    log_listening_port_len          equ $ - log_listening_port - 1


    ; request logging
    log_request_pre                 db "Request: ", 0
    log_request_pre_len             equ $ - log_request_pre - 1

    log_arrow                       db " -> ", 0
    log_arrow_len                   equ $ - log_arrow - 1

    log_thing                       db " - ", 0
    log_thing_len                   equ $ - log_thing - 1


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


; macros

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
;   Prints: "HH:MM:SS [ERROR] <msg>\n"
;   Args:
;     %1: message buffer
;     %2: message length
;   Clobbers: rax, rdi, rsi, rdx, rcx
%macro LOG_ERR 2
    PRINT_TIMESTAMP
    PRINT log_prefix_err, log_prefix_err_len
    PRINTN %1, %2
%endmacro

; LOG_REQUEST path, status_code, ip_ptr
;   Prints: "HH:MM:SS [INFO] Request: <ip> - <path> -> <status>\n"
;   Args:
;     %1: pointer to null-terminated path string
;     %2: status code as integer (200, 400, 403, 404, or 405)
;     %3: pointer to null-terminated ip string
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

    cmp %2, 405
    je %%s405

    cmp %2, 404
    je %%s404

    cmp %2, 403
    je %%s403

    cmp %2, 401
    je %%s401

    cmp %2, 400
    je %%s400

    cmp %2, 304
    je %%s304

    jmp %%s200

%%s405:
    PRINT log_status_405, log_status_405_len
    jmp %%done

%%s404:
    PRINT log_status_404, log_status_404_len
    jmp %%done

%%s403:
    PRINT log_status_403, log_status_403_len
    jmp %%done

%%s401:
    PRINT log_status_401, log_status_401_len
    jmp %%done

%%s400:
    PRINT log_status_400, log_status_400_len
    jmp %%done

%%s304:
    PRINT log_status_304, log_status_304_len
    jmp %%done

%%s200:
    PRINT log_status_200, log_status_200_len

%%done:
%endmacro
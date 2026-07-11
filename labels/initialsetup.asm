; initialsetup.asm - Loads config into buffers

extern inet_pton  ; to parse the interface

section .data
    env_path              db ".env", 0

section .bss
    ; system
    current_uid        resd 1    ; Storing the current uid to check for root
    current_pid_str    resb 20   ; the current pid, as a string
    use_chroot_str     resb 5    ; Buffer for "true\0"
    use_chroot         resb 1    ; Toggle for chroot-ing
    be_nobody_str      resb 5    ; Buffer for "true\0"
    be_nobody          resb 1    ; Toggle for nobody-ing

    ; env / strings
    env_path_buf       resb 129  ; Path to .env file
    word_str_buf       resb 8    ; Temp buffer for ASCII to Integer conversion
    max_age_str        resb 12   ; Buffer for "4294967295\0"
    serve_dots_str     resb 5    ; Buffer for "true\0"
    use_xri_str        resb 5    ; Buffer for "true\0"

    ; network
    bind_addr_str      resb 16   ; "255.255.255.255\0"
    interface          resd 1
    port               resw 1    ; Port number (host byte order)
    max_requests       resw 1    ; Max simultaneous connections (0-65535)
    max_age            resd 1    ; Cache-Control Max-Age value
    linger_to          resw 1    ; Linger timeout
    use_xri            resb 1    ; Toggle for X-Real-IP

    ; server
    server_name        resb 129  ; Server: header value
    server_w_ver       resb 24   ; "ServerName/1.0" combined string

    ; serve configs
    document_root      resb 129  ; Root directory (no trailing slash)
    index_file         resb 129  ; Default index (e.g., index.html)
    serve_dots         resb 1    ; Toggle serving hidden files

    ; auth
    auth_username      resb 129  ; HTTP 1.0 Basic Auth User
    auth_password      resb 129  ; HTTP 1.0 Basic Auth Pass
    auth_realm         resb 129  ; HTTP 1.0 Basic Auth Realm

    ; logs
    str_level_str      resb 6    ; "debug\0"
    str_level          resb 1    ; 0 = none, 1 = normal, 2 = verbose
    str_file_path      resb 129  ; Path to access/error log
    str_file           resq 1    ; Log file descriptor (64-bit)

    ; errordocs
    errordoc_400       resb 129
    errordoc_401       resb 129
    errordoc_403       resb 129
    errordoc_404       resb 129
    errordoc_405       resb 129

    ; document_root + errordoc_XXX + NULL = 257 bytes
    errordoc_400_path  resb 257
    errordoc_401_path  resb 257
    errordoc_403_path  resb 257
    errordoc_404_path  resb 257
    errordoc_405_path  resb 257

section .text
    global initial_setup

; initial_setup
;   Loads configuration from a .env file (or -e) into BSS buffers.
;   Also populate other buffers with additional info. 
;   Exits with code 1 if -e was given but the file doesn't exist.
;   Exits with code 0 if the help was displayed (-h).
initial_setup:
    call .build_server_name     ; first of all, build the server name with default_name + version

    cmp byte [rel flag_help], 1     ; -h passed
    je .display_help

    cmp byte [rel flag_version], 1  ; -v passed
    je .display_version

    mov r14, [rel flag_env_path]
    test r14, r14
    jz .use_default             ; -e not passed

    FILE_EXISTS r14
    cmp rax, 1
    jne .failed_read_file

    lea rcx, [rel env_path_buf]

.copy_argv1:
    mov al, [r14]
    mov [rcx], al

    inc r14
    inc rcx

    test al, al
    jnz .copy_argv1

    jmp .get_uid

.use_default:
    lea r14, [rel env_path]
    lea rcx, [rel env_path_buf]

.copy_default:
    mov al, [r14]
    mov [rcx], al

    inc r14
    inc rcx

    test al, al
    jnz .copy_default

.get_uid:
    ; getuid()
    mov rax, 102
    syscall
    mov [rel current_uid], eax

.get_pid:
    GET_PID
    mov r10, rax
    ITOA r10, current_pid_str, rcx

    call load_config                   ; from labels/envreload.asm
    mov byte [rel first_load], 0

    ; open the log file
    call .open_logfile

    ; build sockaddr from the now-loaded port/interface
    movzx eax, word [rel port]
    xchg al, ah                        ; htons(), swap bytes for big-endian
    mov word [rel sockaddr + 2], ax

    ; inet_pton(af, src, dst)
    mov rdi, 2                         ; AF_INET (ipv4)
    lea rsi, [rel bind_addr_str]
    lea rdx, [rel interface]
    call inet_pton

    cmp rax, 0
    jle .bad_bind_addr                 ; 0 = invalid format, -1 = unsupported af

    mov eax, [rel interface]
    mov dword [rel sockaddr + 4], eax

    ; build errordoc full paths (document_root + errordoc_*)
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400

    call dbg_startup_infos

    ret                             ; initial_setup return point

.build_server_name:
    lea r14, [rel server_w_ver]
    AAPPEND r14, default_name
    AAPPEND r14, version
    ret  ; .build_server_name return point

.open_logfile:
    cmp byte [rel str_file_path], 0
    je .no_str_file

    OPEN_FILE_A str_file_path

    cmp rax, 0
    jl .no_str_file              ; failed to open / create it

    mov qword [rel str_file], rax

    jmp .str_file_end

.no_str_file:
    mov qword [rel str_file], 1  ; no log file = stdout

.str_file_end:
    ret  ; open_logfile len

.failed_read_file:
    LOG_ERR str_fail_read_env, str_fail_read_env_len
    EXIT 1

.bad_bind_addr:
    LOG_ERR str_fail_build_addr, str_fail_build_addr_len
    EXIT 1

.display_help:
    PRINTN str_help_text, str_help_text_len
    EXIT 0

.display_version:
    PRINT str_version, str_version_len
    STRLEN server_w_ver, rcx
    PRINTN server_w_ver, rcx
    EXIT 0
; initialsetup.asm - Loads config into buffers

extern inet_pton  ; to parse the interface

section .data
    env_path              db ".env", 0

    ; keys & defaults if no .env is provided or found
    key_bindaddr          db "BIND_ADDRESS", 0
    default_bindaddr      db "0.0.0.0", 0

    key_port              db "PORT", 0
    default_port          db "8080", 0

    key_docroot           db "DOCUMENT_ROOT", 0   ; document root, no trailing slash !
    default_docroot       db ".", 0

    key_index             db "INDEX_FILE", 0      ; default file if a directory is fetched (eg '/' becomes internally '/index.txt')
    default_index         db "index.html", 0

    key_maxconns          db "MAX_REQUESTS", 0    ; max concurrent requests (and threads)
    default_maxconns      db "20", 0

    key_name              db "SERVER_NAME", 0     ; server name provided in the response headers
    default_name          db "NASMServer/", 0     ; version will be appended later

    key_authuser          db "AUTH_USER", 0
    default_authuser      db "", 0

    key_authpass          db "AUTH_PASSWORD", 0
    default_authpass      db "", 0

    key_authrealm         db "AUTH_REALM", 0
    default_authrealm     db "None", 0

    key_servedots         db "SERVE_DOTS", 0
    default_servedots     db "false", 0

    key_maxage            db "MAX_AGE", 0
    default_maxage        db "600", 0

    key_logfile           db "LOG_FILE", 0
    default_logfile       db "", 0

    key_use_xri           db "USE_X_REAL_IP", 0   ; if we should use 'X-Real-IP' to display the IP address in the logs
    default_use_xri       db "false", 0

    key_use_chroot        db "USE_CHROOT", 0
    default_use_chroot    db "true", 0

    key_noperms           db "DROP_PRIVILEGES", 0
    default_noperms       db "true", 0

    ; errordocs files, relatively to the document_root (empty = none)
    ; start them with a slash !

    key_errordoc_405      db "ERRORDOC_405", 0
    key_errordoc_404      db "ERRORDOC_404", 0
    key_errordoc_403      db "ERRORDOC_403", 0
    key_errordoc_401      db "ERRORDOC_401", 0
    key_errordoc_400      db "ERRORDOC_400", 0

    default_errordoc_405  db "", 0
    default_errordoc_404  db "", 0
    default_errordoc_403  db "", 0
    default_errordoc_401  db "", 0
    default_errordoc_400  db "", 0

section .bss
    ; system
    current_uid        resd 1    ; Storing the current uid to check for root
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
    log_file_path      resb 129  ; Path to access/error log
    log_file           resq 1    ; Log file descriptor (64-bit)

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

    cmp byte [flag_help], 1     ; -h passed
    je .display_help

    cmp byte [flag_version], 1  ; -v passed
    je .display_version

    mov r14, [flag_env_path]
    test r14, r14
    jz .use_default             ; -e not passed

    FILE_EXISTS r14
    cmp rax, 1
    jne .failed_read_file

    lea rcx, [env_path_buf]

.copy_argv1:
    mov al, [r14]
    mov [rcx], al

    inc r14
    inc rcx

    test al, al
    jnz .copy_argv1

    jmp .load_env

.use_default:
    lea r14, [env_path]
    lea rcx, [env_path_buf]

.copy_default:
    mov al, [r14]
    mov [rcx], al

    inc r14
    inc rcx

    test al, al
    jnz .copy_default

.load_env:
    ; load all config from .env (or fall back to defaults)

    ENV_DEFAULT env_path_buf, key_docroot,      document_root,  129,  default_docroot
    ENV_DEFAULT env_path_buf, key_index,        index_file,     129,  default_index
    ENV_DEFAULT env_path_buf, key_name,         server_name,    129,  server_w_ver
    ENV_DEFAULT env_path_buf, key_authuser,     auth_username,  129,  default_authuser
    ENV_DEFAULT env_path_buf, key_authpass,     auth_password,  129,  default_authpass
    ENV_DEFAULT env_path_buf, key_authrealm,    auth_realm,     129,  default_authrealm

    ENV_DEFAULT env_path_buf, key_errordoc_405, errordoc_405,   129,  default_errordoc_405
    ENV_DEFAULT env_path_buf, key_errordoc_404, errordoc_404,   129,  default_errordoc_404
    ENV_DEFAULT env_path_buf, key_errordoc_403, errordoc_403,   129,  default_errordoc_403
    ENV_DEFAULT env_path_buf, key_errordoc_401, errordoc_401,   129,  default_errordoc_401
    ENV_DEFAULT env_path_buf, key_errordoc_400, errordoc_400,   129,  default_errordoc_400

    ; port: read as ascii, then convert to integer
    ENV_DEFAULT env_path_buf, key_port, word_str_buf, 8, default_port
    ATOI word_str_buf, rax
    mov word [port], ax

    ENV_DEFAULT env_path_buf, key_maxconns, word_str_buf, 8, default_maxconns  ; reuse word_str_buf, we're done with it
    ATOI word_str_buf, rax
    mov word [max_requests], ax

    ENV_DEFAULT env_path_buf, key_maxage, max_age_str, 12, default_maxage
    ATOI max_age_str, rax
    mov dword [max_age], eax

    ENV_DEFAULT env_path_buf, key_servedots, serve_dots_str, 5, default_servedots
    BOOL_FLAG serve_dots_str, serve_dots

    ENV_DEFAULT env_path_buf, key_use_xri, use_xri_str, 5, default_use_xri
    BOOL_FLAG use_xri_str, use_xri

    ENV_DEFAULT env_path_buf, key_use_chroot, use_chroot_str, 5, default_use_chroot
    BOOL_FLAG use_chroot_str, use_chroot

    ENV_DEFAULT env_path_buf, key_noperms, be_nobody_str, 5, default_noperms
    BOOL_FLAG be_nobody_str, be_nobody
    
    ; open the log file
    ENV_DEFAULT env_path_buf, key_logfile, log_file_path, 129, default_logfile
    call .open_logfile

    ENV_DEFAULT env_path_buf, key_bindaddr, bind_addr_str, 16, default_bindaddr

    ; build sockaddr from the now-loaded port/interface
    movzx eax, word [port]
    xchg al, ah                     ; htons(), swap bytes for big-endian
    mov word [sockaddr + 2], ax

    ; inet_pton(af, src, dst)
    mov rdi, 2                      ; AF_INET (ipv4)
    lea rsi, [bind_addr_str]
    lea rdx, [interface]
    call inet_pton

    cmp rax, 0
    jle .bad_bind_addr              ; 0 = invalid format, -1 = unsupported af

    mov eax, [interface]
    mov dword [sockaddr + 4], eax

    ; build errordoc full paths (document_root + errordoc_*)
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400

.check_user:
    ; getuid()
    mov rax, 102

    syscall

    mov [current_uid], eax
    ret                     ; initial_setup return point

.build_server_name:
    lea r14, [server_w_ver]
    AAPPEND r14, default_name
    AAPPEND r14, version
    ret

.open_logfile:
    cmp byte [log_file_path], 0
    je .no_log_file

    OPEN_FILE_A log_file_path

    cmp rax, 0
    jl .no_log_file              ; failed to open / create it

    mov qword [log_file], rax

    ret

.no_log_file:
    mov qword [log_file], 1  ; no log file = stdout
    ret

.failed_read_file:
    LOG_ERR log_fail_read_env, log_fail_read_env_len
    EXIT 1

.bad_bind_addr:
    LOG_ERR log_fail_build_addr, log_fail_build_addr_len
    EXIT 1

.display_help:
    PRINTN log_help_text, log_help_text_len
    EXIT 0

.display_version:
    PRINT log_version, log_version_len
    STRLEN server_w_ver, rcx
    PRINTN server_w_ver, rcx
    EXIT 0
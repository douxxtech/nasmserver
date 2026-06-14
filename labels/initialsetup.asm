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

    key_loglevel          db "LOG_LEVEL", 0
    default_loglevel      db "info", 0

    key_linger_to         db "LINGER_TIMEOUT", 0
    default_linger_to     db "5", 0

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
    mov word [rel port], ax

    ENV_DEFAULT env_path_buf, key_maxconns, word_str_buf, 8, default_maxconns  ; reuse word_str_buf, we're done with it
    ATOI word_str_buf, rax
    mov word [rel max_requests], ax

    ENV_DEFAULT env_path_buf, key_maxage, max_age_str, 12, default_maxage
    ATOI max_age_str, rax
    mov dword [rel max_age], eax

    ENV_DEFAULT env_path_buf, key_linger_to, max_age_str, 12, default_linger_to
    ATOI max_age_str, rax
    mov dword [rel linger_to], eax

    ENV_DEFAULT env_path_buf, key_servedots, serve_dots_str, 5, default_servedots
    BOOL_FLAG serve_dots_str, serve_dots

    ENV_DEFAULT env_path_buf, key_use_xri, use_xri_str, 5, default_use_xri
    BOOL_FLAG use_xri_str, use_xri

    ENV_DEFAULT env_path_buf, key_use_chroot, use_chroot_str, 5, default_use_chroot
    BOOL_FLAG use_chroot_str, use_chroot

    ENV_DEFAULT env_path_buf, key_noperms, be_nobody_str, 5, default_noperms
    BOOL_FLAG be_nobody_str, be_nobody

    ; process the log level
    ENV_DEFAULT env_path_buf, key_loglevel, str_level_str, 6, default_loglevel
    call .parse_str_level
    
    ; open the log file
    ENV_DEFAULT env_path_buf, key_logfile, str_file_path, 129, default_logfile
    call .open_logfile

    ENV_DEFAULT env_path_buf, key_bindaddr, bind_addr_str, 16, default_bindaddr

    ; build sockaddr from the now-loaded port/interface
    movzx eax, word [rel port]
    xchg al, ah                     ; htons(), swap bytes for big-endian
    mov word [rel sockaddr + 2], ax

    ; inet_pton(af, src, dst)
    mov rdi, 2                      ; AF_INET (ipv4)
    lea rsi, [rel bind_addr_str]
    lea rdx, [rel interface]
    call inet_pton

    cmp rax, 0
    jle .bad_bind_addr              ; 0 = invalid format, -1 = unsupported af

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

.parse_str_level:
    lea rax, [rel str_level_str]

    ; "debug"
    cmp dword [rax], 'debu'
    jne .check_none

    cmp byte [rax+4], 'g'
    jne .check_none

    mov byte [rel str_level], 2

    jmp .str_level_end

.check_none:
    ; "none"
    cmp dword [rax], 'none'
    jne .check_info

    mov byte [rel str_level], 0
    
    jmp .str_level_end

.check_info:
    ; "info" or anything unrecognized = 0
    mov byte [rel str_level], 1
    ret

.str_level_end:
    ret  ; .parse_str_level return point

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
section .data
    env_path              db ".env", 0

    ; keys & defaults if no .env is provided or found
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

    key_servedots         db "SERVE_DOTS", 0
    default_servedots     db "false", 0

    key_maxage            db "MAX_AGE", 0
    default_maxage        db "600", 0

    key_logfile           db "LOG_FILE", 0
    default_logfile       db "", 0

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
    ; config (loaded from .env at startup)
    ; all custom paths are 128 chars max for consistency (129 for the null byte)

    env_path_buf       resb 129
    word_str_buf       resb 8    ; ascii port/max requests from .env before ATOI
    port               resw 1    ; port number (host byte order)
    interface          resd 1    ; 0 = 0.0.0.0
    max_age_str        resb 12   ; enough for "4294967295\0" (max value of resd 1)
    max_age            resd 1
    max_requests       resw 1    ; max simultaneous connections (max 65535)
    document_root      resb 129  ; document root, no trailing slash !
    index_file         resb 129  ; default index file
    server_w_ver       resb 24   ; The default server with the version (24 chars should be enough)
    server_name        resb 129  ; Server: header value
    auth_username      resb 129  ; for HTTP 1.0 authentication
    auth_password      resb 129
    serve_dots_str     resb 5    ; "true\0"
    serve_dots         resb 1
    errordoc_405       resb 129  ; relative to document_root, start with /
    errordoc_404       resb 129
    errordoc_403       resb 129
    errordoc_400       resb 129
    errordoc_401       resb 129

    ; error doc paths (built at startup from document_root + errordoc_* + NUL)
    errordoc_405_path  resb 257
    errordoc_404_path  resb 257
    errordoc_403_path  resb 257
    errordoc_401_path  resb 257
    errordoc_400_path  resb 257

    log_file_path      resb 129

section .text
    global initial_setup

; initial_setup
;   Loads configuration from a .env file (or -e) into BSS buffers.
;   Populates: port, max_requests, document_root, index_file, server_name,
;              errordoc_* paths, and sockaddr.
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
    ENV_DEFAULT env_path_buf, key_logfile,      log_file_path,  129,   default_logfile

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
    call .is_servedot_true
    

    ; build sockaddr from the now-loaded port/interface
    movzx eax, word [port]
    xchg al, ah                     ; htons(), swap bytes for big-endian
    mov word [sockaddr + 2], ax

    mov eax, [interface]
    mov dword [sockaddr + 4], eax  

    ; build errordoc full paths (document_root + errordoc_*)
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400

    ret

.build_server_name:
    lea r14, [server_w_ver]
    AAPPEND r14, default_name
    AAPPEND r14, version
    ret

.is_servedot_true:
    cmp dword [serve_dots_str], 0x65757274  ; "true"
    je .set_servedot_true

    ret

.set_servedot_true:
    mov byte [serve_dots], 1
    ret

.failed_read_file:
    LOG_ERR log_fail_read_env, log_fail_read_env_len
    EXIT 1

.display_help:
    PRINTN log_help_text, log_help_text_len
    EXIT 0

.display_version:
    PRINT log_version, log_version_len
    STRLEN server_w_ver, rcx
    PRINTN server_w_ver, rcx
    EXIT 0
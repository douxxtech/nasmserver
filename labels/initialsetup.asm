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

    ; errordocs files, relatively to the document_root (empty = none)
    ; start them with a slash !

    key_errordoc_405      db "ERRORDOC_405", 0
    key_errordoc_404      db "ERRORDOC_404", 0
    key_errordoc_403      db "ERRORDOC_403", 0
    key_errordoc_400      db "ERRORDOC_400", 0

    default_errordoc_405  db "", 0
    default_errordoc_404  db "", 0
    default_errordoc_403  db "", 0
    default_errordoc_400  db "", 0

section .bss
    ; config (loaded from .env at startup)
    ; all custom paths are 128 chars max for consistency

    env_path_buf       resb 128
    port_str_buf       resb 8    ; ascii port from .env before ATOI
    port               resw 1    ; port number (host byte order)
    interface          resd 1    ; 0 = 0.0.0.0
    max_conns          resb 1    ; max simultaneous connections (max 255)
    document_root      resb 128  ; document root, no trailing slash !
    index_file         resb 128  ; default index file
    server_w_ver       resb 24   ; The default server with the version (24 chars should be enough)
    server_name        resb 128  ; Server: header value
    auth_username      resb 128  ; for HTTP 1.0 authentication
    auth_password      resb 128
    errordoc_405       resb 128  ; relative to document_root, start with /
    errordoc_404       resb 128
    errordoc_403       resb 128
    errordoc_400       resb 128

    ; error doc paths (built at startup from document_root + errordoc_*)
    errordoc_400_path  resb 256
    errordoc_403_path  resb 256
    errordoc_404_path  resb 256
    errordoc_405_path  resb 256

section .text
    global initial_setup

; initial_setup
;   Loads configuration from a .env file (or -e) into BSS buffers.
;   Populates: port, max_conns, document_root, index_file, server_name,
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

    ENV_DEFAULT env_path_buf, key_docroot,      document_root,  128,  default_docroot
    ENV_DEFAULT env_path_buf, key_index,        index_file,     128,  default_index
    ENV_DEFAULT env_path_buf, key_name,         server_name,    128,  server_w_ver
    ENV_DEFAULT env_path_buf, key_authuser,     auth_username,  128,  default_authuser
    ENV_DEFAULT env_path_buf, key_authpass,     auth_password,  128,  default_authpass

    ENV_DEFAULT env_path_buf, key_errordoc_405, errordoc_405,   128,  default_errordoc_405
    ENV_DEFAULT env_path_buf, key_errordoc_404, errordoc_404,   128,  default_errordoc_404
    ENV_DEFAULT env_path_buf, key_errordoc_403, errordoc_403,   128,  default_errordoc_403
    ENV_DEFAULT env_path_buf, key_errordoc_400, errordoc_400,   128,  default_errordoc_400

    ; port: read as ascii, then convert to integer
    ENV_DEFAULT env_path_buf, key_port, port_str_buf, 8, default_port
    ATOI port_str_buf, rax
    mov word [port], ax

    ; max_conns: same deal, byte is enough (max 255)
    ENV_DEFAULT env_path_buf, key_maxconns, port_str_buf, 8, default_maxconns  ; reuse port_str_buf, we're done with it
    ATOI port_str_buf, rax
    mov byte [max_conns], al

    ; build sockaddr from the now-loaded port/interface
    movzx eax, word [port]
    xchg al, ah                    ; htons(), swap bytes for big-endian
    mov word [sockaddr + 2], ax

    mov eax, [interface]
    mov dword [sockaddr + 4], eax  

    ; build errordoc full paths (document_root + errordoc_*)
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_400_path, document_root, errordoc_400

    ret

.build_server_name:
    lea r14, [server_w_ver]
    AAPPEND r14, default_name
    AAPPEND r14, version
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
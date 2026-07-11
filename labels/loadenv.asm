; loadenv.asm - Loads config from .env, on boot and on reloads

section .data
    first_load            db 1  ; 1 = boot, 0 = subsequent reloads

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
    ; snapshots of boot-only settings, used to detect drift on reload
    old_document_root  resb 129
    old_bind_addr_str  resb 16
    old_port           resw 1
    old_str_file_path  resb 129
    old_use_chroot     resb 1
    old_be_nobody      resb 1

section .text
    global load_config

; load_config
;   Loads config from .env (or defaults) into BSS buffers.
;   On first_load: loads everything, same behavior as the old initial_setup.load_env.
;   On reloads: loads reloadable settings, and warns + restores the old
;   value for anything that would require a restart to take effect (docroot,
;   bind address, port, log file path, chroot/nobody toggles).
;   Expects: env_path_buf to already be set (initial_setup does this once at boot).
;   Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10
load_config:
    cmp byte [rel first_load], 1
    jne .snapshot_boot_only

    jmp .load_body                ; first boot: load everything, nothing to compare against yet

.snapshot_boot_only:
    ; save current values of boot-only settings so we can detect drift after reload

    lea rsi, [rel document_root]
    lea rdi, [rel old_document_root]
    call .copy_str

    lea rsi, [rel bind_addr_str]
    lea rdi, [rel old_bind_addr_str]
    call .copy_str

    mov ax, [rel port]
    mov [rel old_port], ax

    lea rsi, [rel str_file_path]
    lea rdi, [rel old_str_file_path]
    call .copy_str

    mov al, [rel use_chroot]
    mov [rel old_use_chroot], al

    mov al, [rel be_nobody]
    mov [rel old_be_nobody], al

.load_body:
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

    ENV_DEFAULT env_path_buf, key_logfile, str_file_path, 129, default_logfile

    ENV_DEFAULT env_path_buf, key_bindaddr, bind_addr_str, 16, default_bindaddr

    cmp byte [rel first_load], 1
    jne .check_drift

    ret  ; load_config return point for first load

.check_drift:
    ; warn (and restore the old value) for anything that changed but can't be hot-reloaded
 
    STREQ document_root, old_document_root, rcx
    cmp rcx, 1
    je .drift_docroot_ok
 
    lea rsi, [rel key_docroot]
    call .warn_boot_only
 
    lea rsi, [rel old_document_root]
    lea rdi, [rel document_root]
    call .copy_str
 
.drift_docroot_ok:
    STREQ bind_addr_str, old_bind_addr_str, rcx
    cmp rcx, 1
    je .drift_bindaddr_ok
 
    lea rsi, [rel key_bindaddr]
    call .warn_boot_only
 
    lea rsi, [rel old_bind_addr_str]
    lea rdi, [rel bind_addr_str]
    call .copy_str
 
.drift_bindaddr_ok:
    mov ax, [rel port]
    cmp ax, [rel old_port]
    je .drift_port_ok
 
    lea rsi, [rel key_port]
    call .warn_boot_only
 
    mov ax, [rel old_port]
    mov [rel port], ax
 
.drift_port_ok:
    STREQ str_file_path, old_str_file_path, rcx
    cmp rcx, 1
    je .drift_logfile_ok
 
    lea rsi, [rel key_logfile]
    call .warn_boot_only
 
    lea rsi, [rel old_str_file_path]
    lea rdi, [rel str_file_path]
    call .copy_str
 
.drift_logfile_ok:
    mov al, [rel use_chroot]
    cmp al, [rel old_use_chroot]
    je .drift_chroot_ok
 
    lea rsi, [rel key_use_chroot]
    call .warn_boot_only
 
    mov al, [rel old_use_chroot]
    mov [rel use_chroot], al
 
.drift_chroot_ok:
    mov al, [rel be_nobody]
    cmp al, [rel old_be_nobody]
    je .drift_nobody_ok
 
    lea rsi, [rel key_noperms]
    call .warn_boot_only
 
    mov al, [rel old_be_nobody]
    mov [rel be_nobody], al
 
.drift_nobody_ok:
    ; rebuild errordoc full paths (document_root + errordoc_*), in case either changed
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400
 
    LOG_INFO str_reload_done, str_reload_done_len
 
    ret  ; load_config return point for reloads

.copy_str:
    ; copies a null-terminated string from rsi to rdi
    ; Args:
    ;   rsi: source
    ;   rdi: dest
    ; Clobbers: al, rsi, rdi
    mov al, [rsi]
    mov [rdi], al

    inc rsi
    inc rdi

    test al, al
    jnz .copy_str

    ret  ; .copy_str return point

.warn_boot_only:
    ; Logs: "Reload: <rsi> changed but requires a restart, ignoring"
    mov r9, rsi                ; AAPPEND clobbers rsi

    CLB
    lea r8, [rel log_buffer]

    AAPPEND r8, str_reload_p1
    AAPPEND r8, rsi
    AAPPEND r8, str_reload_p2

    lea rcx, [rel log_buffer]
    sub r8, rcx
    mov rbx, r8

    LOG_WARNING log_buffer, rbx

    ret  ; .warn_boot_only return point

; log level parsing
.parse_str_level:
    lea rax, [rel str_level_str]

    ; "debug"
    cmp dword [rax], 'debu'
    jne .check_none

    cmp byte [rax+4], 'g'
    jne .check_none

    mov byte [rel str_level], 2

    ret

.check_none:
    ; "none"
    cmp dword [rax], 'none'
    jne .check_info

    mov byte [rel str_level], 0

    ret

.check_info:
    ; "info" or anything unrecognized = 0
    mov byte [rel str_level], 1
    ret  ; .parse_str_level return point
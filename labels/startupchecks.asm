section .text
    global startup_checks

; startup_checks
;   Validates server configuration before entering the accept loop.
;   Checks: document_root existence + permissions, errordoc paths, port range.
;   Exits with code 1 on fatal errors, warns on non-fatal ones.
;   Expects: document_root, errordoc_*_path, port to be defined in the caller.
startup_checks:
    push rbp
    mov rbp, rsp

.check_docroot:
    ; document_root: must exist and be a directory
    lea rdi, [document_root]
    FILE_EXISTS rdi

    cmp rax, 2
    je .check_docroot_perms

    LOG_ERR log_check_docroot_missing, log_check_docroot_missing_len
    EXIT 1

.check_docroot_perms:

    ; check that document_root is readable and executable by the current process
    ; access(path, mode)
    mov rax, 21
    lea rdi, [document_root]
    mov rsi, 5                ; R_OK | X_OK
    syscall

    cmp rax, 0
    je .check_errordocs

    LOG_ERR log_check_docroot_perms, log_check_docroot_perms_len
    EXIT 1

.check_errordocs:
    ; non-fatal: server still starts without errordocs

    lea rdi, [errordoc_400_path]

    cmp byte [rdi], 0             ; BUILDPATH leaves it empty if errordoc_400 was empty
    je .check_errordoc_401

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_401

    LOG_WARNING log_check_errordoc_missing, log_check_errordoc_missing_len

.check_errordoc_401:
    lea rdi, [errordoc_401_path]

    cmp byte [rdi], 0
    je .check_errordoc_403

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_403

    LOG_WARNING log_check_errordoc_missing, log_check_errordoc_missing_len

.check_errordoc_403:
    lea rdi, [errordoc_403_path]

    cmp byte [rdi], 0
    je .check_errordoc_404

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_404

    LOG_WARNING log_check_errordoc_missing, log_check_errordoc_missing_len

.check_errordoc_404:
    lea rdi, [errordoc_404_path]

    cmp byte [rdi], 0
    je .check_errordoc_405

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_405

    LOG_WARNING log_check_errordoc_missing, log_check_errordoc_missing_len

.check_errordoc_405:
    lea rdi, [errordoc_405_path]

    cmp byte [rdi], 0
    je .check_port

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_port

    LOG_WARNING log_check_errordoc_missing, log_check_errordoc_missing_len

.check_port:
    mov rax, [current_uid]
    cmp rax, 0
    je .check_logfile

    movzx rax, word [port]
    cmp rax, 1024
    jge .check_logfile

    LOG_WARNING log_check_port_privileged, log_check_port_privileged_len

.check_logfile:
    cmp byte [log_file_path], 0
    je .checks_done         ; no file path provided, just skep

    cmp qword [log_file], 1
    jne .checks_done        ; if != 1, its ok

    ; if its 1, it means that we failed to open the file
    LOG_WARNING log_log_file_not_opened, log_log_file_not_opened_len 

.checks_done:
    LOG_INFO log_startup_ok, log_startup_ok_len

    pop rbp
    ret
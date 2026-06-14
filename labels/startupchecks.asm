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
    lea rdi, [rel document_root]
    FILE_EXISTS rdi

    cmp rax, 2
    je .check_docroot_perms

    LOG_ERR str_check_docroot_missing, str_check_docroot_missing_len
    EXIT 1

.check_docroot_perms:

    ; check that document_root is readable and executable by the current process
    ; access(path, mode)
    mov rax, 21
    lea rdi, [rel document_root]
    mov rsi, 5                ; R_OK | X_OK
    syscall

    cmp rax, 0
    je .check_errordocs

    LOG_ERR str_check_docroot_perms, str_check_docroot_perms_len
    EXIT 1

.check_errordocs:
    ; non-fatal: server still starts without errordocs

    lea rdi, [rel errordoc_400_path]

    cmp byte [rdi], 0             ; BUILDPATH leaves it empty if errordoc_400 was empty
    je .check_errordoc_401

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_401

    LOG_WARNING str_check_errordoc_missing, str_check_errordoc_missing_len

.check_errordoc_401:
    lea rdi, [rel errordoc_401_path]

    cmp byte [rdi], 0
    je .check_errordoc_403

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_403

    LOG_WARNING str_check_errordoc_missing, str_check_errordoc_missing_len

.check_errordoc_403:
    lea rdi, [rel errordoc_403_path]

    cmp byte [rdi], 0
    je .check_errordoc_404

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_404

    LOG_WARNING str_check_errordoc_missing, str_check_errordoc_missing_len

.check_errordoc_404:
    lea rdi, [rel errordoc_404_path]

    cmp byte [rdi], 0
    je .check_errordoc_405

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_errordoc_405

    LOG_WARNING str_check_errordoc_missing, str_check_errordoc_missing_len

.check_errordoc_405:
    lea rdi, [rel errordoc_405_path]

    cmp byte [rdi], 0
    je .check_logfile

    FILE_EXISTS rdi

    cmp rax, 1
    je .check_logfile

    LOG_WARNING str_check_errordoc_missing, str_check_errordoc_missing_len

.check_logfile:
    cmp byte [rel str_file_path], 0
    je .check_port         ; no file path provided, just skep

    cmp qword [rel str_file], 1
    jne .check_port        ; if != 1, its ok

    ; if its 1, it means that we failed to open the file
    LOG_WARNING str_log_file_not_opened, str_log_file_not_opened_len 

.check_port:
    mov eax, [rel current_uid]
    cmp eax, 0
    je .check_chroot

    movzx rax, word [rel port]
    cmp rax, 1024
    jge .check_chroot

    LOG_WARNING str_check_port_privileged, str_check_port_privileged_len

.check_chroot:
    cmp byte [rel use_chroot], 1
    jne .check_nobody

    mov eax, [rel current_uid]
    cmp eax, 0
    je .check_nobody

    ; if not root, we won't be able to chroot
    LOG_WARNING str_chroot_noroot, str_chroot_noroot_len

.check_nobody:
    cmp byte [rel be_nobody], 1
    jne .checks_done

    mov eax, [rel current_uid]
    cmp eax, 0
    je .checks_done

    ; if not root, we won't be able to set uid to nobody
    LOG_WARNING str_nobody_noroot, str_nobody_noroot_len

.checks_done:
    LOG_INFO str_startup_ok, str_startup_ok_len

    pop rbp
    ret
; debug.asm - Debug logs labels, and some warnings too

section .text
    global dbg_new_child
    global dbg_child_exit
    global dbg_path_resolved
    global dbg_dotfile_blocked
    global dbg_status_code
    global dbg_bytes_sent
    global dbg_process_reaped
    global dbg_chroot_success
    global warn_chroot_fail
    global dbg_sighandler_success
    global warn_sighandler_fail

dbg_new_child:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    GET_PID
    mov r10, rax
    ITOA r10, current_pid_str, rcx

    lea r9, [log_buffer]
    AAPPEND r9, log_child_created_p1
    AAPPEND r9, current_pid_str
    AAPPEND r9, log_child_created_p2
    AAPPEND r9, client_ip_str
    mov byte [r9], 0

    lea rcx, [log_buffer]
    sub r9, rcx                       ; r9 = length of what was written

    LOG_DEBUG log_buffer, r9

    ret                               ; dbg_new_child return point

dbg_child_exit:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    lea r9, [log_buffer]
    AAPPEND r9, log_child_exit_p1
    AAPPEND r9, current_pid_str
    AAPPEND r9, log_child_exit_p2
    mov byte [r9], 0

    lea rcx, [log_buffer]
    sub r9, rcx                       ; r9 = length of what was written

    LOG_DEBUG log_buffer, r9

    ret                               ; dbg_child_exit return point

dbg_path_resolved:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    lea r9, [log_buffer]
    AAPPEND r9, log_path_resolved

    lea rdi, [path]
    STRLEN rdi, rcx
    APPEND r9, rdi, rcx

    lea rcx, [log_buffer]
    sub r9, rcx
    LOG_DEBUG log_buffer, r9

    ret                            ; dbg_path_resolved return point

dbg_dotfile_blocked:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    lea r9, [log_buffer]
    AAPPEND r9, log_dotfile_blocked

    lea rdi, [path]
    STRLEN rdi, rcx
    APPEND r9, rdi, rcx

    lea rcx, [log_buffer]
    sub r9, rcx
    LOG_DEBUG log_buffer, r9

    ret                              ; dbg_dotfile_blocked return point

dbg_status_code:
    cmp byte [log_level], 2
    jne dbg_skip

    mov r10, rdi
    push rdi                          ; we need to save rdi since .write_header needs it

    ITOA r10, itoa_buf, rcx

    CLB

    lea r9, [log_buffer]
    AAPPEND r9, log_replying_with_code
    AAPPEND r9, itoa_buf

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_DEBUG log_buffer, r9

    pop rdi
    ret                               ; dbg_status_code return point

dbg_bytes_sent:
    cmp byte [log_level], 2
    jne dbg_skip

    mov r10, rax
    ITOA r10, itoa_buf, rcx

    CLB

    lea r9, [log_buffer]

    AAPPEND r9, log_sent_bytes_p1
    AAPPEND r9, itoa_buf
    AAPPEND r9, log_sent_bytes_p2

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_DEBUG log_buffer, r9

    ret                            ; dbg_bytes_sent return point

dbg_process_reaped:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    movzx r10, word [process_count]
    ITOA r10, itoa_buf, rcx

    lea r9, [log_buffer]

    AAPPEND r9, log_process_reaped
    AAPPEND r9, itoa_buf

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_DEBUG log_buffer, r9

    ret                              ; dbg_process_reaped return point

dbg_chroot_success:
    cmp byte [log_level], 2
    jne dbg_skip

    CLB

    lea r9, [log_buffer]

    AAPPEND r9, log_chroot_succeeded
    AAPPEND r9, document_root

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_DEBUG log_buffer, r9

    ret                                ; warn_chroot_fail return point

warn_chroot_fail:                     ; yea thats a warning but meh
    cmp byte [log_level], 0
    je dbg_skip

    CLB

    lea r9, [log_buffer]

    AAPPEND r9, log_chroot_failed_p1
    AAPPEND r9, document_root
    AAPPEND r9, log_chroot_failed_p2

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_WARNING log_buffer, r9

    ret                               ; warn_chroot_fail return point

dbg_sighandler_success:
    cmp byte [log_level], 0
    je dbg_skip

    mov r10, rax             ; rax content: 17 = sigchld, 15 = sigterm, 2 = sigint

    CLB

    lea r9, [log_buffer]

    AAPPEND r9, log_success_sighandler_p1

    cmp r10, 17
    je .sigchld

    cmp r10, 15
    je .sigterm

    cmp r10, 2
    je .sigint

    je dbg_skip              ; if its something unexpected, just skip

.sigchld:
    AAPPEND r9, log_sighanlder_sigchld
    jmp .end

.sigterm:
    AAPPEND r9, log_sighanlder_sigterm
    jmp .end

.sigint:
    AAPPEND r9, log_sighanlder_sigint
    jmp .end

.end:
    AAPPEND r9, log_success_sighandler_p2

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_DEBUG log_buffer, r9

    ret                                    ; dbg_sighandler_success return point


warn_sighandler_fail:
    cmp byte [log_level], 0
    je dbg_skip

    mov r10, rax             ; rax content: 17 = sigchld, 15 = sigterm, 2 = sigint

    CLB

    lea r9, [log_buffer]

    AAPPEND r9, log_fail_sighandler_p1

    cmp r10, 17
    je .sigchld

    cmp r10, 15
    je .sigterm

    cmp r10, 2
    je .sigint

    je dbg_skip              ; if its something unexpected, just skip

.sigchld:
    AAPPEND r9, log_sighanlder_sigchld
    jmp .end

.sigterm:
    AAPPEND r9, log_sighanlder_sigterm
    jmp .end

.sigint:
    AAPPEND r9, log_sighanlder_sigint
    jmp .end

.end:
    AAPPEND r9, log_fail_sighandler_p2

    lea rcx, [log_buffer]
    sub r9, rcx

    LOG_WARNING log_buffer, r9

    ret                                    ; warn_sighandler_fail return point

dbg_skip:
    ret  ; skip point if debug mode isn't enabled
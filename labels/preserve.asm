; preserve.asm - Prepares the server environment

section .bss
    sigaction  resb 152  ; sigaction struct


section .text
    global pre_serve

; pre_serve
;   Prepares the server environment before entering the accept loop.
;   - Creates a socket and binds a port to it
;   - If running as root, chroots into document_root and resets it to ".".
;   - If running as root, sets its uid to nobody
;   - Registers the signal handlers
pre_serve:
    call .create_socket
    call .bind_port

    call .chroot
    call .im_nobody

    call .sigchld_setup
    call .sigterm_setup
    call .sigint_setup

    ret           ; pre_serve return point

.create_socket:
    ; socket(domain, type, protocol)
    mov rax, 41
    mov rdi, 2            ; ipv4
    mov rsi, 1            ; stream
    mov rdx, 0            ; tcp
    syscall

    cmp rax, 0
    jl .fail_socket

    mov r15, rax          ; r15 will hold the socket fd

    ; allow reuse of the address so we can restart without waiting for TIME_WAIT
    ; setsockopt(fd, level, optname, optval, optlen)
    mov rax, 54
    mov rdi, r15
    mov rsi, 1            ; SOL_SOCKET
    mov rdx, 2            ; SO_REUSEADDR
    mov r10, sockopt
    mov r8,  4
    syscall

    cmp rax, 0
    jne .fail_setsockopt

    ret                   ; return point for create_socket

.bind_port:
    ; bind the socket to the configured port and interface
    ; bind(fd, sockaddr, addrlen)
    mov rax, 49
    mov rdi, r15
    mov rsi, sockaddr
    mov rdx, 16
    syscall

    cmp rax, 0
    jl .fail_bind

    ret               ; return point for bind_port

.chroot:
    ; chroot into the document_root
    mov eax, [current_uid]
    cmp eax, 0
    jne .chroot_end

    cmp byte [use_chroot], 1
    jne .chroot_end

.do_chroot:

    ; chdir first so that chroot(".") jails us inside document_root
    ; chdir(dir)
    mov rax, 80
    lea rdi, document_root
    syscall

    ; chroot(filename)
    mov rax, 161
    lea rdi, default_docroot  ; "."
    syscall

    cmp rax, 0
    jl .chroot_fail

    call dbg_chroot_success

    ; set document_root to default_docroot (".")
    mov ax, [default_docroot]
    mov [document_root], ax

    ; rebuild errordoc paths now that we're inside the jail
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400

    LOG_DEBUG log_errordoc_paths_rebuilt, log_errordoc_paths_rebuilt_len

    jmp .chroot_end

.chroot_fail:
    call warn_chroot_fail

.chroot_end:
    ret  ; .do_chroot return point

.im_nobody:
    ; sets current user to "nobody" for minimal privileges (if root)
    mov eax, [current_uid]
    cmp eax, 0
    jne .nobody_end

    cmp byte [be_nobody], 1
    jne .nobody_end

    ; setuid(uid)
    mov rax, 105
    mov rdi, 65534
    syscall

    cmp rax, 0
    jl .nobody_fail

    mov dword [current_uid], 65534

    LOG_DEBUG log_nobody_succeeded, log_nobody_succeeded_len
    jmp .nobody_end

.nobody_fail:
    LOG_WARNING log_nobody_failed, log_nobody_failed_len

.nobody_end:
    ret  ; .im_nobody return point

.sig_restorer:
    ; shared restorer trampoline for all signal handlers
    ; the kernel wants SA_RESTORER to be set and sa_restorer to point here

    ; rt_sigreturn()
    mov rax, 15  ; rt_sigreturn
    syscall      ; return point for .sig_restorer

.sigchld_setup:
    ; setups the SIGCHLD handler (child exits)

    ; 0 the struct
    lea rdi, [sigaction]
    mov rcx, 152
    xor al, al
    rep stosb

    lea rax, [.sigchld_handler]
    mov [sigaction], rax                    ; sa_handler

    mov qword [sigaction + 8], 0x14000000   ; sa_flags SA_RESTART | SA_RESTORER

    lea rax, [.sig_restorer]
    mov [sigaction + 16], rax               ; sa_restorer

    ; rt_sigaction(signum, newact, oldact)
    mov rax, 13
    mov rdi, 17           ; SIGCHLD
    lea rsi, [sigaction]
    xor rdx, rdx
    mov r10, 8            ; "sigsetsize"
    syscall

    mov rdi, rax
    mov rax, 17           ; for warn / debug logs

    cmp rdi, 0
    jl .sigchld_fail

    call dbg_sighandler_success

    jmp .sigchld_end

.sigchld_fail:
    call warn_sighandler_fail

.sigchld_end:
    ret  ; .sigchld_setup return point

.sigchld_handler:
    ; reap zombie processes (same as _start.reap_loop)

    ; wait4(pid, status, options, usage)
    mov rax, 61
    mov rdi, -1      ; any child
    xor rsi, rsi
    mov rdx, 1       ; WNOHANG
    xor r10, r10
    syscall

    cmp rax, 0
    jle .sigchld_ok  ; no child reaped, stop

    dec word [process_count]

    call dbg_process_reaped
    jmp .sigchld_handler

.sigchld_ok:
    ret  ; return point for .sigchld_handler (restorer handles rt_sigreturn)

.sigterm_setup:
    ; setups the SIGTERM handler

    ; 0 the struct
    lea rdi, [sigaction]
    mov rcx, 152
    xor al, al
    rep stosb

    lea rax, [.sigterm_handler]
    mov [sigaction], rax                   ; sa_handler

    mov qword [sigaction + 8], 0x04000000  ; sa_flag SA_RESTORER

    lea rax, [.sig_restorer]
    mov [sigaction + 16], rax              ; sa_restorer

    ; rt_sigaction(signum, newact, oldact)
    mov rax, 13
    mov rdi, 15           ; SIGTERM
    lea rsi, [sigaction]
    xor rdx, rdx
    mov r10, 8            ; "sigsetsize"
    syscall

    mov rdi, rax
    mov rax, 15           ; for warn / debug logs

    cmp rdi, 0
    jl .sigterm_fail

    call dbg_sighandler_success

    jmp .sigterm_end

.sigterm_fail:
    call warn_sighandler_fail

.sigterm_end:
    ret  ; return point for .sigterm_setup

.sigterm_handler:
    mov byte [shutdown], 1
    ret  ; return point for .sigterm_handler

.sigint_setup:
    ; setups the SIGINT handler

    ; 0 the struct
    lea rdi, [sigaction]
    mov rcx, 152
    xor al, al
    rep stosb

    lea rax, [.sigint_handler]
    mov [sigaction], rax                   ; sa_handler

    mov qword [sigaction + 8], 0x04000000  ; sa_flag SA_RESTORER

    lea rax, [.sig_restorer]
    mov [sigaction + 16], rax              ; sa_restorer

    ; rt_sigaction(signum, newact, oldact)
    mov rax, 13
    mov rdi, 2            ; SIGINT
    lea rsi, [sigaction]
    xor rdx, rdx
    mov r10, 8            ; "sigsetsize"
    syscall

    mov rdi, rax
    mov rax, 2            ; for warn / debug logs

    cmp rdi, 0
    jl .sigint_fail

    call dbg_sighandler_success

    jmp .sigint_end

.sigint_fail:
    call warn_sighandler_fail

.sigint_end:
    ret  ; return point for .sigint_setup

.sigint_handler:
    mov byte [shutdown], 1
    ret  ; return point for .sigint_handler

.fail_socket:
    LOG_ERR log_fail_socket, log_fail_socket_len
    mov rdi, rax
    EXIT rdi

.fail_setsockopt:
    LOG_ERR log_fail_setsockopt, log_fail_setsockopt_len
    mov rdi, rax
    EXIT rdi

.fail_bind:
    LOG_ERR log_fail_bind, log_fail_bind_len
    mov rdi, rax
    EXIT rdi
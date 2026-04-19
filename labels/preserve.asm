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

    ; set the docroot to '' (/)
    mov word [document_root], 0x00  ; "\0" (reset before chroot since we're already inside)

    ; chroot(filename)
    mov rax, 161
    lea rdi, default_docroot  ; (".")
    syscall

    cmp rax, 0
    jl .chroot_fail

    ; rebuild errordoc paths now that we're inside the jail
    
    BUILDPATH errordoc_405_path, default_docroot, errordoc_405  ; again, default_docroot is just "."
    BUILDPATH errordoc_404_path, default_docroot, errordoc_404
    BUILDPATH errordoc_403_path, default_docroot, errordoc_403
    BUILDPATH errordoc_401_path, default_docroot, errordoc_401
    BUILDPATH errordoc_400_path, default_docroot, errordoc_400

    jmp .chroot_end

.chroot_fail:
    ; for now do nothing
    ; we'll log in verbose when the feature will be there
    EXIT 69

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
    jmp .nobody_end

.nobody_fail:
    ; for now do nothing
    ; we'll log in verbose when the feature will be there

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

    cmp rax, 0
    jl .sigchld_fail

    jmp .sigchld_end

.sigchld_fail:
    ; for now do nothing
    ; we'll log in verbose when the feature will be there

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

    cmp rax, 0
    jl .sigterm_fail

    jmp .sigterm_end

.sigterm_fail:
    ; for now do nothing
    ; we'll log in verbose when the feature will be there

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

    cmp rax, 0
    jl .sigint_fail

    jmp .sigint_end

.sigint_fail:
    ; for now do nothing
    ; we'll log in verbose when the feature will be there

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
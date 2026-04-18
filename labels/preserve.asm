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

    ; set the docroot to '.' (/)
    mov word [document_root], 0x002e  ; ".\0" (reset before chroot since we're already inside)

    ; chroot(filename)
    mov rax, 161
    lea rdi, document_root
    syscall

    cmp rax, 0
    jl .chroot_fail

    ; rebuild errordoc paths now that we're inside the jail
    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_401_path, document_root, errordoc_401
    BUILDPATH errordoc_400_path, document_root, errordoc_400

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

.sigchld_setup:
    ; setups the SIGCHLD handler (child exits)

    ; 0 the reg
    lea rdi, [sigaction]
    mov rcx, 152
    xor al, al
    rep stosb

    ; point it the the label
    mov qword [sigaction + 8], 0x4000000 | 0x10000000  ; SA_RESTORER | SA_RESTART (claude)

    lea rax, [.sigchld_handler]
    mov [sigaction + 16], rax

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
    ; rt_sigreturn()
    mov rax, 15
    syscall      ; return point for .sigchld_handler

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

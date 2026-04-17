; preserve.asm - Prepares the server environment

section .text
    global pre_serve

; pre_serve
;   Prepares the server environment before entering the accept loop.
;   - Creates a socket and binds a port to it
;   - If running as root, chroots into document_root and resets it to ".".
;   - If running as root, sets its uid to nobody
pre_serve:
    call .create_socket

    call .bind_port

    call .chroot

    call .im_nobody

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

.do_chroot:
    ; chroot(filename)
    mov rax, 161
    mov rdi, document_root
    syscall

    cmp rax, 0
    jl .chroot_fail

    mov word [document_root], 0x002e  ; ".\0"
    jmp .chroot_end

.chroot_fail:
    ; for the moment do nothing
    ; we'll log in verbose when the feature will be there

.chroot_end:
    ret

.im_nobody:
    ; sets current user to "nobody" for minimal privileges (if root)
    mov eax, [current_uid]
    cmp eax, 0
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
    ; for the moment do nothing
    ; we'll log in verbose when the feature will be there

.nobody_end:
    ret  ; .im_nobody return point


.fail_socket:
    LOG_ERR log_fail_socket, log_fail_socket_len
    EXIT rax

.fail_setsockopt:
    LOG_ERR log_fail_setsockopt, log_fail_setsockopt_len
    EXIT rax

.fail_bind:
    LOG_ERR log_fail_bind, log_fail_bind_len
    EXIT rax

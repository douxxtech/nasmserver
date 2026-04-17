section .text
    global pre_serve

; pre_serve
;   Prepares the server environment before entering the accept loop.
;   - If running as root, chroots into document_root and resets it to ".".
pre_serve:
pre_serve:
    mov eax, [current_uid]
    cmp eax, 0
    jne .skip_chroot

.do_chroot:
    ; chroot(filename)
    mov rax, 161
    mov rdi, document_root

    syscall

    cmp rax, 0
    jl .chroot_fail

    mov word [document_root], 0x002e  ; ".\0"

.chroot_fail:
    ; for the moment do nothing
    ; we'll log in verbose when the feature will be there

.skip_chroot:
    ret
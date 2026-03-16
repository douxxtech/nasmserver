; flagparser.asm - CLI flag parsing for NASMServer
;   Call parse_flags before initial_setup.
;   Reads argv, sets flag_* bytes in .bss.

section .data
    flag_str_h   db "-h", 0
    flag_str_e   db "-e", 0

section .bss
    flag_env_path  resq 1  ; pointer to env path string, or 0 if not set
    flag_help      resb 1  ; 1 if -h was passed


section .text
    global parse_flags

; parse_flags
;   Walks argv[1..argc-1], sets flag bytes, removes recognized flags from argv.
;   Expects: r15 = argc
;   Clobbers: rax, rbx, rcx, rsi, rdi
parse_flags:
    push rbp
    mov rbp, rsp

    mov qword [flag_env_path], 0  ; default: not set

    cmp r15, 1
    je .done

    mov rcx, 1                    ; current argv index

.next_arg:
    cmp rcx, r15
    jge .done

    mov rsi, [rbp + 8 + 8 + rcx * 8]  ; argv[rcx]  (rbp + saved rbp + saved ret addr)

    ; check -h
    lea rdi, [flag_str_h]
    call .streq

    cmp rax, 1
    je .is_h

    ; check -e
    lea rdi, [flag_str_e]
    call .streq

    cmp rax, 1
    je .is_e

    ; not a recognized flag, skip
    inc rcx
    jmp .next_arg

.is_h:
    mov byte [flag_help], 1
    call .remove_arg

    dec r15
    jmp .next_arg

.is_e:
    ; next arg is the env path
    mov rax, rcx
    inc rax
    cmp rax, r15
    jge .done                         ; -e with no value, ignore

    mov rax, [rbp + 8 + 8 + rax * 8]  ; argv[rcx+1]
    mov [flag_env_path], rax

    ; remove -e from argv
    call .remove_arg
    dec r15

    ; remove the path
    call .remove_arg
    dec r15

    jmp .next_arg

; .remove_arg
;   Removes argv[rcx] by shifting argv[rcx+1..argc-1] left by one slot.
;   Expects: rcx = index to remove, r15 = current argc
;   Clobbers: rdx, rbx, rax
.remove_arg:
    mov rdx, rcx

.shift_loop:
    mov rax, rdx
    inc rax
    cmp rax, r15
    jge .shift_done

    mov rbx, [rbp + 8 + 8 + rax * 8]
    mov [rbp + 8 + 8 + rdx * 8], rbx

    inc rdx
    jmp .shift_loop

.shift_done:
    ret

; .streq
;   Compares null-terminated strings at rsi and rdi.
;   Returns rax = 1 if equal, 0 otherwise.
;   Clobbers: rax, rbx
.streq:
    mov al, [rsi]
    mov bl, [rdi]

    cmp al, bl
    jne .streq_not_equal

    test al, al
    jz .streq_equal

    inc rsi
    inc rdi
    jmp .streq

.streq_equal:
    mov rax, 1
    ret

.streq_not_equal:
    xor rax, rax
    ret

.done:
    pop rbp
    ret
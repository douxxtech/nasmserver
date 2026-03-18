; flagparser.asm - CLI flag parsing for NASMServer
;   Call parse_flags before initial_setup.
;   Reads argv, sets flag_* bytes in .bss.

section .data
    flag_str_h   db "-h", 0
    flag_str_e   db "-e", 0
    flag_str_v   db "-v", 0

section .bss
    flag_env_path  resq 1  ; pointer to env path string, or 0 if not set
    flag_help      resb 1  ; 1 if -h was passed
    flag_version   resb 1  ; 1 if -v was passed


section .text
    global parse_flags

; parse_flags
;   Walks argv[1..argc-1], sets flag bytes, removes recognized flags from argv.
;   Expects: r15 = argc
;   Clobbers: rax, rbx, rcx, rsi, rdi
parse_flags:
    mov rbp, rsp

    mov qword [flag_env_path], 0  ; default: not set
    mov byte [flag_help], 0
    mov byte [flag_version], 0

    cmp r15, 1                    ; argc = 1: no args passed
    je .done

    mov rcx, 1                    ; current argv index

.next_arg:
    ; rbp + 16 + rcx * 8  =>  argv[rcx]
    ; (rbp = rsp at entry, +16 skips argc and argv[0])

    cmp rcx, r15
    jge .done


    ; check -h
    mov rsi, [rbp + 16 + rcx * 8]
    STREQ rsi, flag_str_h, rax

    cmp rax, 1
    je .is_h

    ; check -e
    mov rsi, [rbp + 16 + rcx * 8]
    STREQ rsi, flag_str_e, rax

    cmp rax, 1
    je .is_e

    ; check -v
    mov rsi, [rbp + 16 + rcx * 8]
    STREQ rsi, flag_str_v, rax

    cmp rax, 1
    je .is_v

    ; not a recognized flag, skip
    mov rsi, [rbp + 16 + rcx * 8]
    jmp .arg_not_recognized

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
    jge .error_e                      ; -e with no value, ignore

    mov rax, [rbp + 8 + 8 + rax * 8]  ; argv[rcx+1]
    mov [flag_env_path], rax

    ; remove -e from argv
    call .remove_arg
    dec r15

    ; remove the path
    call .remove_arg
    dec r15

    jmp .next_arg

.is_v:
    mov byte [flag_version], 1
    call .remove_arg

    dec r15
    jmp .next_arg

.error_e:
    PRINTN log_flag_e_error, log_flag_e_error_len
    EXIT 1


.remove_arg:
    ; Removes argv[rcx] by shifting argv[rcx+1..argc-1] left by one slot
    ; Expects: rcx = index to remove, r15 = current argc
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

.arg_not_recognized:
    PRINT log_arg_not_recognized_p1, log_arg_not_recognized_p1_len

    STRLEN rsi, rcx
    PRINT rsi, rcx

    PRINTN log_arg_not_recognized_p2, log_arg_not_recognized_p2_len
    EXIT 1

.done:
    ret
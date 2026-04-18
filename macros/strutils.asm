; strutils.asm - String utility macros for x86_64 Linux

; STRLEN string_ptr, out_reg
;   Calculates the length of a null-terminated string.
;   Args:
;     %1: pointer to string
;     %2: register to store length
;   Clobbers: rax, rbx
%macro STRLEN 2
    push rax
    push rbx

    mov %2, 0
%%loop:
    mov bl, [%1 + %2]
    cmp bl, 0
    je %%done
    inc %2
    jmp %%loop

%%done:
    pop rbx
    pop rax
%endmacro

; STRCUT buf, char
;   Truncates a null-terminated string at the first occurrence of char.
;   If char is not found, the string is left untouched.
;   Args:
;     %1: pointer to the null-terminated buffer
;     %2: byte value to cut at (e.g. '!', 0xa)
;   Clobbers: rax, rbx
%macro STRCUT 2
    push rax
    push rbx

    lea rax, [%1]      ; rax = walking pointer

%%loop:
    mov bl, [rax]      ; load current byte

    cmp bl, 0
    je %%done          ; hit NUL, char not found

    cmp bl, %2
    je %%cut           ; found the target char

    inc rax            ; advance pointer
    jmp %%loop

%%cut:
    mov byte [rax], 0  ; overwrite char with NUL, truncating here

%%done:
    pop rbx
    pop rax
%endmacro

; STREQ a, b, out_reg
;   Compares two null-terminated strings.
;   Args:
;     %1: pointer to string a
;     %2: pointer to string b
;     %3: register to store result (1 if equal, 0 otherwise)
;   Clobbers: rax, rbx, rsi, rdi
%macro STREQ 3
    push rsi
    push rdi

    lea rsi, [%1]
    lea rdi, [%2]

%%loop:
    mov al, [rsi]
    mov bl, [rdi]

    cmp al, bl
    jne %%not_equal

    test al, al
    jz %%equal

    inc rsi
    inc rdi
    jmp %%loop

%%equal:
    mov %3, 1
    jmp %%done

%%not_equal:
    xor %3, %3

%%done:
    pop rdi
    pop rsi
%endmacro

; STRSPLIT src, split_char, out_a, out_b, found_reg
;   Splits a null-terminated string at the first occurrence of split_char.
;   Copies everything before split_char into out_a, everything after into out_b.
;   If split_char is not found, out_a gets the full string and out_b is empty.
;   Args:
;     %1: pointer to source string (null-terminated)
;     %2: byte value to split on (e.g. ':')
;     %3: output buffer for the left part
;     %4: output buffer for the right part
;     %5: register to store result (1 if split_char was found, 0 otherwise)
;   Clobbers: rax, rbx, rsi, rdi
%macro STRSPLIT 5
    push rsi
    push rdi

    lea rsi, [%1]  ; rsi = read pointer
    lea rdi, [%3]  ; rdi = write pointer (left buffer)
    xor %5, %5     ; assume not found

%%copy_left:
    mov al, [rsi]

    test al, al
    jz %%null_term_right  ; hit NUL without finding split_char

    cmp al, %2
    je %%found            ; found the split char

    mov [rdi], al         ; copy byte into out_a
    inc rsi
    inc rdi

    jmp %%copy_left

%%found:
    mov %5, 1
    inc rsi            ; skip the split char

    mov byte [rdi], 0  ; null-terminate out_a
    lea rdi, [%4]      ; switch to right buffer

%%copy_right:
    mov al, [rsi]
    mov [rdi], al     ; copy byte (including final NUL)

    inc rsi
    inc rdi
    
    test al, al
    jnz %%copy_right  ; loop until NUL is copied
    jmp %%done

%%null_term_right:
    mov byte [rdi], 0  ; null-terminate out_a
    lea rdi, [%4]
    mov byte [rdi], 0  ; out_b is empty

%%done:
    pop rdi
    pop rsi
%endmacro

; BOOL_FLAG str_buf, flag_buf
;   Sets flag_buf to 1 if str_buf contains "true", leaves it untouched otherwise.
;   Args:
;     %1: buffer containing the string to check (e.g. serve_dots_str)
;     %2: byte flag to set (e.g. serve_dots)
;   Clobbers: nothing
%macro BOOL_FLAG 2
    cmp dword [%1], 0x65757274  ; "true"
    jne %%done

    mov byte [%2], 1

%%done:
%endmacro

; CLEAR_BUFFER dest, length
;   Fills `length` bytes at dest with 0.
;   Args:
;     %1: destination buffer address
;     %2: number of bytes to clear
;   Notes:
;     Uses rep stosb for efficiency.
;   Clobbers: rax, rdi, rcx
%macro CLEAR_BUFFER 2
    mov rdi, %1
    mov rcx, %2
    xor eax, eax
    rep stosb
%endmacro

; APPEND dest, src, length
;   Copies `length` bytes from src into dest, advancing dest.
;   Args:
;     %1: destination pointer (incremented in place)
;     %2: source buffer address
;     %3: number of bytes to copy
;   Notes:
;     Does not null-terminate the destination.
;   Clobbers: rax, rsi, rcx
%macro APPEND 3
    mov rsi, %2
    mov rcx, %3

%%loop:
    cmp rcx, 0
    je %%done

    mov al, [rsi]
    mov [%1], al

    inc rsi
    inc %1

    dec rcx
    jmp %%loop

%%done:
%endmacro

; AAPPEND dest, src
;   Appends a null-terminated string to dest, advancing dest.
;   Args:
;     %1: destination pointer (incremented in place)
;     %2: source string (null-terminated)
;   Notes:
;     Does not null-terminate the destination.
;   Clobbers: rax, rbx, rsi, rcx
%macro AAPPEND 2
    STRLEN %2, rcx  ; length -> rcx
    mov rsi, %2

%%loop:
    cmp rcx, 0
    je %%done

    mov al, [rsi]
    mov [%1], al

    inc rsi
    inc %1

    dec rcx
    jmp %%loop

%%done:
%endmacro

; BUILDPATH dest, base, suffix
;   Concatenates base and suffix into dest (null-terminated result).
;   If the base OR suffix string is empty, it'll leave the buffer untouched.
;   Args:
;     %1: destination buffer
;     %2: base string (null-terminated)
;     %3: suffix string (null-terminated)
;   Clobbers: whatever AAPPEND clobbers (rax, rbx, rsi, rcx)
%macro BUILDPATH 3

    ; if either part is empty, leave dest empty and bail
    cmp byte [%2], 0
    je %%done
    cmp byte [%3], 0
    je %%done

    lea r8, [%1]
    AAPPEND r8, %2
    AAPPEND r8, %3
    mov byte [r8], 0  ; null-terminate

%%done:
%endmacro

; PATH_HAS_DOT path, out_reg
;   Checks if any component of a path starts with a dot, ignoring '.' and '..'
;   Args:
;     %1: pointer to null-terminated path string
;     %2: register to store result (1 if a dot entry was found, 0 otherwise)
;   Clobbers: rax, rsi
%macro PATH_HAS_DOT 2
    ; /hi/.dir/hello.txt -> 1 (dotdir in the middle)
    ; /hello/.dotfile    -> 1 (dotfile at the end)
    ; ./hi/index.html    -> 0 (leading ./ is ignored)
    ; /hi/../hello.txt   -> 0 (.. is ignored)

    lea rsi, [%1]
    xor %2, %2     ; assume good

%%next:
    mov al, [rsi]
    test al, al
    jz %%done            ; end, nothing flagged

    cmp al, '/'
    jne %%advance        ; not a slash, continue

    inc rsi              ; skip the '/'
    cmp byte [rsi], '.'  ; does the part start with a dot?
    jne %%next

    ; starts with '.', now check if it's just '.' or '..'
    mov al, [rsi + 1]
    cmp al, '/'
    je %%next          ; skip './'

    cmp al, 0
    je %%next          ; it's '.' at end of path, skip

    cmp al, '.'
    jne %%flagged       ; second char isn't a dot = flagged

    mov al, [rsi + 2]
    cmp al, '/'
    je %%next           ; skip'../'

    cmp al, 0
    je %%next

%%flagged:
    mov %2, 1
    jmp %%done

%%advance:
    inc rsi
    jmp %%next

%%done:
%endmacro

; B64_DECODE src, dst, out_len_reg
;   Decodes a null-terminated base64 string into a buffer.
;   Args:
;     %1: pointer to the base64 source string (null-terminated)
;     %2: pointer to the destination buffer
;     %3: register to store the number of decoded bytes
;   Notes:
;     Output is null-terminated.
;     Invalid characters (including '=') are treated as end.
;   Clobbers: rax, rbx, rcx, rdx, rsi, rdi
%macro B64_DECODE 3
    lea rsi, [%1] ; rsi = read pointer (src)
    lea rdi, [%2] ; rdi = write pointer (dst)
    xor %3, %3    ; output byte count = 0

%%loop:
    ; load 4 base64 chars, bail if we hit NUL or '=' early
    movzx rax, byte [rsi]

    test al, al
    jz %%done

    B64_CHAR_VAL al
    cmp al, 0xff
    je %%done

    ; shl = shift left
    shl rax, 18                ; char 0 -> bits [23:18]  

    movzx rbx, byte [rsi + 1]  ;

    test bl, bl
    jz %%done

    B64_CHAR_VAL bl
    cmp bl, 0xff
    je %%done
    shl rbx, 12                ; char 1 -> bits [17:12]
    or rax, rbx

    movzx rbx, byte [rsi + 2]

    test bl, bl
    jz %%flush2                ; 2 chars = 1 output byte

    cmp bl, '='
    je %%flush2

    B64_CHAR_VAL bl

    cmp bl, 0xff
    je %%flush2

    shl rbx, 6                 ; char 2 -> bits [11:6]
    or rax, rbx

    movzx rbx, byte [rsi + 3]

    test bl, bl
    jz %%flush3                ; 3 chars = 2 output bytes

    cmp bl, '='
    je %%flush3

    B64_CHAR_VAL bl

    cmp bl, 0xff
    je %%flush3

    or rax, rbx                ; char 3 -> bits [5:0]

    ; write all 3 decoded bytes
    mov rcx, rax
    shr rcx, 16
    mov [rdi], cl
    inc rdi

    mov rcx, rax
    shr rcx, 8
    and cl, 0xff
    mov [rdi], cl
    inc rdi

    mov rcx, rax
    and cl, 0xff
    mov [rdi], cl
    inc rdi

    add %3, 3
    add rsi, 4
    jmp %%loop

%%flush2:
    ; only 2 base64 chars = 1 byte
    shr rax, 16
    mov [rdi], al
    inc rdi
    inc %3
    jmp %%done

%%flush3:
    ; only 3 base64 chars = 2 bytes
    mov rcx, rax
    shr rcx, 16
    mov [rdi], cl
    inc rdi

    mov rcx, rax
    shr rcx, 8
    and cl, 0xff
    mov [rdi], cl
    inc rdi

    add %3, 2

%%done:
    mov byte [rdi], 0  ; null-terminate
%endmacro

; B64_CHAR_VAL reg
;   Converts a single base64 ASCII character to its 6-bit value in-place.
;   Returns 0xff in reg if the character is invalid.
;   Args:
;     %1: byte register (al, bl, etc.)
;   The register is modified in place
;   Clobbers: nothing else
%macro B64_CHAR_VAL 1
    ; https://base64.guru/learn/base64-algorithm/decode
    ; https://base64.guru/learn/base64-characters

    cmp %1, 'A'
    jl %%try_lower

    cmp %1, 'Z'
    jg %%try_lower

    sub %1, 'A'     ; A-Z -> 0-25
    jmp %%done

%%try_lower:
    cmp %1, 'a'
    jl %%try_digit

    cmp %1, 'z'
    jg %%try_digit

    sub %1, 'a' - 26  ; a-z -> 26-51
    jmp %%done

%%try_digit:
    cmp %1, '0'
    jl %%try_plus

    cmp %1, '9'
    jg %%try_plus

    sub %1, '0' - 52  ; 0-9 -> 52-61
    jmp %%done

%%try_plus:
    cmp %1, '+'
    je %%is_plus

    cmp %1, '/'
    je %%is_slash

    mov %1, 0xff   ; invalid
    jmp %%done

%%is_plus:
    mov %1, 62
    jmp %%done

%%is_slash:
    mov %1, 63

%%done:
%endmacro

; ITOA num_reg, buf_ptr, out_len_reg
;   Converts an unsigned 64-bit integer to decimal ASCII.
;   Args:
;     %1: register containing the number
;     %2: pointer to a buffer of at least 20 bytes
;     %3: register to store resulting string length
;   Clobbers: rax, rbx, rcx, rdx, rdi, rsi
%macro ITOA 3
    mov rax, %1
    lea rdi, [%2 + 19]

    mov byte [rdi], 0
    xor %3, %3

%%loop:
    xor rdx, rdx

    mov rcx, 10
    div rcx

    add dl, '0'
    dec rdi

    mov [rdi], dl
    inc %3

    test rax, rax
    jnz %%loop

    lea rsi, [rdi]
    lea rdi, [%2]
    mov rcx, %3

    rep movsb
%endmacro

; ATOI buf_ptr, out_reg
;   Converts a null-terminated decimal ASCII string to an unsigned 64-bit integer.
;   Args:
;     %1: pointer to the string buffer
;     %2: register to store the resulting integer
;   Clobbers: rax, rbx, rsi
%macro ATOI 2
    xor %2, %2
    lea rsi, [%1]

%%loop:
    movzx rbx, byte [rsi]

    cmp bl, 0
    je %%done

    imul %2, %2, 10
    sub bl, '0'
    add %2, rbx

    inc rsi
    jmp %%loop

%%done:
%endmacro
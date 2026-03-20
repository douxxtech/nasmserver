; fileutils.asm - File operation macros for x86_64 Linux

extern gmtime_r
extern strftime

section .bss
    stat  resb 144  ; struct stat is 144 bytes on x86_64 linux (for content length)

; FILE_EXISTS path
;   Checks whether a path exists and what it is.
;   Args:
;     %1: null-terminated path
;   Returns:
;     rax = 1  if exists and is a regular file
;     rax = 2  if exists and is a directory
;     rax = 3  if exists but is not readable
;     rax = 0  if does not exist
;   Clobbers: rax, rdi, rsi
%macro FILE_EXISTS 1
    push rdi
    push rsi

    ; get file metadata to check existence and type
    ; stat(path, statbuf)
    mov rax, 4
    mov rdi, %1
    lea rsi, [stat]
    syscall

    cmp rax, 0
    jl %%not_found        ; stat failed = doesn't exist

    ; check st_mode at offset 24, mask the file type bits
    mov rax, [stat + 24]
    and rax, 0xF000

    cmp rax, 0x8000       ; S_IFREG
    je %%is_file

    cmp rax, 0x4000       ; S_IFDIR
    je %%is_dir

    ; exists but some other obscure type, just continue

%%is_file:

    ; check read permission on the file
    ; access(path, mode)
    mov rax, 21         ; sys_access
    mov rdi, %1
    mov rsi, 4          ; R_OK
    syscall

    cmp rax, 0
    jne %%not_readable

    mov rax, 1          ; exists, is a file, is readable
    jmp %%done

%%is_dir:
    mov rax, 2          ; exists, is a directory
    jmp %%done

%%not_readable:
    mov rax, 3          ; exists but not readable
    jmp %%done

%%not_found:
    mov rax, 0          ; does not exist

%%done:
    pop rsi
    pop rdi
%endmacro

; FILE_LAST_MODIFIED path, out_buf
;   Gets the last-modified time of a file as a null-terminated RFC 7231 date string.
;   Args:
;     %1: null-terminated path
;     %2: output buffer, min 32b
;   Returns:
;     rax = 1 on success, 0 on error
;   Clobbers: rax, rdi, rsi
%macro FILE_LAST_MODIFIED 2
    push rdi
    push rsi

    ; stat(path, statbuf)
    mov rax, 4
    mov rdi, %1
    lea rsi, [stat]
    syscall

    cmp rax, 0
    jl %%fail

    ; some buffers are taken from httputils.asm, should clean that up one day
    mov rax, [stat + 88]      ; st_mtime is at offset 88 in struct stat
    mov [date_timespec], rax

    ; gmtime_r(&tv_sec, &date_tm_buf)
    mov rdi, date_timespec
    mov rsi, date_tm_buf
    call gmtime_r

    ; strftime(out, 32, fmt, &tm)
    mov rdi, %2
    mov rsi, 32
    mov rdx, http_date_fmt
    mov rcx, date_tm_buf
    call strftime

    mov rax, 1
    jmp %%done

%%fail:
    mov rax, 0

%%done:
    pop rsi
    pop rdi
%endmacro

; FILE_SIZE path, out_reg
;   Gets the size of a file in bytes.
;   Args:
;     %1: null-terminated path
;     %2: register to store the size (-1 on error)
;   Clobbers: rax, rdi, rsi
%macro FILE_SIZE 2
    push rdi
    push rsi

    ; get file metadata to read st_size
    ; stat(path, statbuf)
    mov rax, 4
    mov rdi, %1
    lea rsi, [stat]
    syscall

    cmp rax, 0
    jl %%fail

    mov %2, [stat + 48]  ; st_size is at offset 48 in struct stat
    jmp %%done

%%fail:
    mov %2, -1

%%done:
    pop rsi
    pop rdi
%endmacro

; READ_FILE fd, buffer, length
;   Reads up to `length` bytes from a file descriptor into a buffer.
;   Args:
;     %1: file descriptor
;     %2: buffer address
;     %3: buffer size
;   Returns:
;     rax = bytes read, or negative errno on error
;   Clobbers: rax, rdi, rsi, rdx
%macro READ_FILE 3

    ; read(fd, buffer, count)
    mov rax, 0   ; sys_read
    mov rdi, %1
    mov rsi, %2
    mov rdx, %3
    syscall
%endmacro

; OPEN_FILE path
;   Opens a file for reading.
;   Args:
;     %1: null-terminated path
;   Returns:
;     rax = file descriptor, or negative errno on error
;   Clobbers: rax, rdi, rsi, rdx
%macro OPEN_FILE 1

    ; open(path, flags, mode)
    mov rax, 2   ; sys_open
    mov rdi, %1
    mov rsi, 0   ; O_RDONLY
    mov rdx, 0
    syscall
%endmacro
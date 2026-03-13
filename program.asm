%include "./macros/sysutils.asm"
%include "./macros/fileutils.asm"
%include "./macros/httputils.asm"
%include "./macros/logutils.asm"

extern inet_ntop ; to process the client IP address

; program.asm - HTTP/1.0 server entry point
section .data

    ; things you might want to configure

    ; socket setup
    sockaddr:
        dw 2            ; AF_INET (ipv4)
        dw 0x5000       ; port 80 big-endian
        dd 0            ; 0.0.0.0 = listen on all interfaces
        dq 0            ; padding

    index_file    db "index.txt", 0                  ; default file if a directory is fetched (eg / becomes internally /index.txt)   
    max_conns     equ 5                              ; max connections to queue before starting to reject them
    http_server   db "Server: NASMServer/1.0", 0     ; the server name

    ; end of the things might want to configure

    sockopt         dd 1    ; value for SO_REUSEADDR
    client_addr_len dd 16

    ; HTTP constants
    crlf            db 0xd, 0xa, 0

    response_200     db "HTTP/1.0 200 OK", 0
    response_404     db "HTTP/1.0 404 Not Found", 0
    response_400     db "HTTP/1.0 400 Bad Request", 0

    content_type     db "Content-Type: text/plain", 0
    connection_close db "Connection: close", 0

section .bss
    request       resb 1024
    response      resb 1024
    client_addr   resb 16
    path          resb 256  ; should be enough for now
    last_status   resw 1    ; for logs
    client_ip_str resb 16   ; "255.255.255.255\0"

section .text
    global _start


; register usage (persistent across the loop):
;   r15 = server socket fd
;   r14 = client socket fd (per request)
;   r13 = response buffer start (anchor)
;   r12 = response buffer write position
;   r11 = file fd (when serving a file)
_start:

    ; socket(domain, type, protocol)
    mov rax, 41
    mov rdi, 2      ; ipv4
    mov rsi, 1      ; stream
    mov rdx, 0      ; tcp
    syscall

    cmp rax, 0
    jl .fail_socket

    mov r15, rax    ; r15 will hold the socket fd

    ; setsockopt(fd, SOL_SOCKET=1, SO_REUSEADDR=2, &opt, 4)
    mov rax, 54
    mov rdi, r15
    mov rsi, 1      ; SOL_SOCKET
    mov rdx, 2      ; SO_REUSEADDR
    mov r10, sockopt
    mov r8,  4
    syscall

    cmp rax, 0
    jne .fail_setsockopt

    ; bind(fd, sockaddr, addrlen)
    mov rax, 49
    mov rdi, r15
    mov rsi, sockaddr
    mov rdx, 16
    syscall

    cmp rax, 0
    jl .fail_bind

    ; listen(fd, backlog)
    mov rax, 50
    mov rdi, r15
    mov rsi, max_conns
    syscall

    LOG_INFO log_listening_port, log_listening_port_len

.wait: ; from here, we're NOT stopping the program anymore
    ; accept(fd, sockaddr, addrlen) -> rax client fd (to use to write the resp)
    ; blocks until a connection arrives
    mov rax, 43
    mov rdi, r15
    mov rsi, client_addr
    mov rdx, client_addr_len
    syscall

    cmp rax, 0
    jl .fail_accept

    mov r14, rax    ; r14 will contain the client file descriptor

    movzx eax, byte [client_addr + 4]   ; first octet
    movzx ebx, byte [client_addr + 5]   ; second
    movzx ecx, byte [client_addr + 6]   ; third
    movzx edx, byte [client_addr + 7]   ; fourth

    ; rdi = AF_INET (2)
    ; rsi = pointer to sin_addr (client_addr + 4)
    ; rdx = output buffer
    ; rcx = buffer size (16)
    mov     edi, 2
    lea     rsi, [client_addr + 4]
    lea     rdx, [client_ip_str]
    mov     ecx, 16
    call    inet_ntop

.handle_request:
    READ_FILE r14, request, 1024

    IS_HTTP_REQUEST request, 1024

    cmp rax, 1
    jne .bad_request

    ; prepend '.' so it becomes a relative path
    mov rdi, path
    mov byte [rdi], '.'

    lea rdi, [path + 1]

    PARSE_HTTP_PATH request, 1024, rdi, rcx
    mov byte [path + rcx + 1], 0    ; nul terminate the path

    ; if ends with '/', append "index.txt"
    cmp byte [path + rcx], '/'
    jne .check_exists

    ; copy index_file into path after the trailing slash
    lea rsi, [index_file]
    lea rdi, [path + rcx + 1]


.add_index:
    mov al, [rsi]
    mov [rdi], al

    inc rsi
    inc rdi

    test al, al
    jnz .add_index

.check_exists:
    lea rdi, [path]

    FILE_EXISTS rdi

    cmp rax, 0
    je .not_found

.send_response:
    lea r13, [response]     ; anchor, won't move
    lea r12, [response]     ; write cursor

    mov rdi, 200
    call .write_header

    ; send the header first
    sub r12, r13
    PRINTF r14, r13, r12

    ; open the file
    lea rdi, [path]
    OPEN_FILE rdi

    cmp rax, 0
    jl .end             ; shouldn't happen cuz FILE_EXISTS passed, but just in case
    mov r11, rax        ; r11 = file fd

    ; sendfile(out_fd, in_fd, offset=NULL, count=big)
    mov rax, 40
    mov rdi, r14        ; client socket
    mov rsi, r11        ; file fd
    xor rdx, rdx        ; offset = NULL (start from beginning)
    mov r10, 0x7fffffff ; send as much as possible
    syscall

    ; close the file fd
    mov rax, 3
    mov rdi, r11
    syscall

    mov word [last_status], 200
    jmp .end

.bad_request:
    lea r13, [response]
    lea r12, [response]

    mov rdi, 400
    call .write_header

    sub r12, r13

    mov word [last_status], 400
    jmp .send

.not_found: 
    lea r13, [response]
    lea r12, [response]

    mov rdi, 404
    call .write_header

    sub r12, r13

    mov word [last_status], 404
    jmp .send

.write_header:
    ; rdi: status code (200, 400, or 404)
    ; appends the HTTP header to the 'response' buffer
    cmp rdi, 404
    je .write_404

    cmp rdi, 400
    je .write_400

    jmp .write_200

.write_404:
    AAPPEND r12, response_404
    AAPPEND r12, crlf
    jmp .write_common_headers

.write_400:
    AAPPEND r12, response_400
    AAPPEND r12, crlf
    jmp .write_common_headers

.write_200:
    AAPPEND r12, response_200
    AAPPEND r12, crlf

.write_common_headers:
    AAPPEND r12, http_server
    AAPPEND r12, crlf
    AAPPEND r12, content_type
    AAPPEND r12, crlf
    AAPPEND r12, connection_close
    AAPPEND r12, crlf
    AAPPEND r12, crlf   ; blank line = end of headers
    ret

.clear_buffers:
    xor eax, eax

    mov rdi, request
    mov rcx, 1024
    rep stosb

    mov rdi, response
    mov rcx, 1024
    rep stosb

    mov rdi, path
    mov rcx, 256
    rep stosb

    ret

.send:
    PRINTF r14, r13, r12

.end:
    ; shutdown(fd, SHUT_WR=1)
    mov rax, 48
    mov rdi, r14
    mov rsi, 1      ; SHUT_WR
    syscall

    ; drain remaining input so TCP can close cleanly
.__drain:
    mov rax, 0
    mov rdi, r14
    lea rsi, [request]
    mov rdx, 16
    syscall

    cmp rax, 0
    jg .__drain     ; keep reading until eof / err

    ; close(fd)
    mov rax, 3
    mov rdi, r14
    syscall

    movzx r12, word [last_status] ; Move byte to word with zero-extension
    lea r13, [client_ip_str] ; using r12 and r13 to not get it clobbered, shouldnt be a problem since they will be replaced next iteration
    LOG_REQUEST path, r12, r13 

    call .clear_buffers
    jmp .wait

.fail_socket:
    LOG_ERR log_fail_socket, log_fail_socket_len
    EXIT rax

.fail_setsockopt:
    LOG_ERR log_fail_setsockopt, log_fail_setsockopt_len
    EXIT rax

.fail_bind:
    LOG_ERR log_fail_bind, log_fail_bind_len
    EXIT rax

.fail_accept:
    LOG_ERR log_fail_accept, log_fail_accept_len
    jmp .wait ; non-fatal, try again
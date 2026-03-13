%include "sysutils.asm"
%include "fileutils.asm"
%include "httputils.asm"

section .data
    sockaddr:
        dw 2 ; AF_INET (ipv4)
        dw 0x5000 ; port 80 big-endian
        dd 0 ; 0.0.0.0 = listen on all interfaces
        dq 0 ; padding

    max_conns equ 5
    resp_text db "temporary text, read from a file later", 0

    sockopt dd 1
    client_addr_len dd 16

    crlf db 0xd, 0xa, 0

    response_200 db "HTTP/1.0 200 OK", 0
    response_404 db "HTTP/1.0 404 NOT FOUND", 0
    response_400 db "HTTP/1.0 400 BAD REQUEST", 0

    http_server db "Server: NASMServer/1.0", 0
    content_type db "Content-Type: text/text", 0
    connection_close db "Connection: close", 0

    ; logs ===================

    log_listening_port db "Listening requests on port 80", 0
    log_listening_port_len equ $ - log_listening_port - 1

    log_handling_request db "Handling a request...", 0
    log_handling_request_len equ $ - log_handling_request - 1

    log_responded_request db "Responded to request", 0
    log_responded_request_len equ $ - log_responded_request - 1

    log_fail_socket db "Failed to open a socket", 0
	log_fail_socket_len equ $ - log_fail_socket - 1

    log_fail_setsockopt db "Failed to set socket options", 0
	log_fail_setsockopt_len equ $ - log_fail_setsockopt - 1

    log_fail_bind db "Failed to bind to port", 0
	log_fail_bind_len equ $ - log_fail_bind - 1

    log_fail_accept db "Failed to to accept a request", 0
	log_fail_accept_len equ $ - log_fail_accept - 1

section .bss
    request resb 1024
    response resb 1024
    client_addr resb 16
    path resb 256 ; should be enough for now

section .text
    global _start

_start:

    ; socket(domain, type, protocol)

	mov rax, 41
	mov rdi, 2 ; ipv4
	mov rsi, 1 ; stream
	mov rdx, 0 ; tcp

	syscall

	cmp rax, 0
	jl .fail_socket ; if -errno

    mov r15, rax ; r15 will hold the socket fd

    ; setsockopt(fd, SOL_SOCKET=1, SO_REUSEADDR=2, &opt, 4)
    mov rax, 54
    mov rdi, r15 ; socket fd
    mov rsi, 1 ; SOL_SOCKET
    mov rdx, 2 ; SO_REUSEADDR
    mov r10, sockopt ; pointer to value (use lea)
    mov r8, 4 ; size of opt

    syscall

    cmp rax, 0
    jne .fail_setsockopt  ; treat any non-zero as error

    cmp rax, 0
	jl .fail_socket ; if -errno

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

    PRINTN log_listening_port, log_listening_port_len


.wait: ; from here, we're NOT stopping the program anymore
    ; accept(fd, sockaddr, addrlen) -> rax client fd (to use to write the resp)
    ; blocks until a con
    mov rax, 43
    mov rdi, r15
    mov rsi, client_addr
    mov rdx, client_addr_len

    syscall

    cmp rax, 0
    jl .fail_accept

    mov r14, rax ; r14 will contain the client file descriptor

    PRINTN log_handling_request, log_handling_request_len

.handle_request:
    READ_FILE r14, request, 1024

    IS_HTTP_REQUEST request, 1024

    cmp rax, 1
    jne .bad_request

    mov rdi, path
    mov byte [rdi], '.' ; becomes a relative path

    lea rdi, [path + 1]

    PARSE_HTTP_PATH request, 1024, rdi, rcx
    mov byte [path + rcx + 1], 0 ; nul term the path


    ; if ends with '/', add index.txt, so it becomes /index.txt
    cmp byte [path + rcx], '/' 
    jne .check_exists

    mov dword [path + rcx + 1], 'inde'
    mov dword [path + rcx + 5], 'x.tx'
    mov byte  [path + rcx + 9], 't'
    mov byte  [path + rcx + 10], 0


.check_exists:
    PRINTN path, 16
    lea rdi, [path]

    FILE_EXISTS rdi

    cmp rax, 0
    je .not_found

.send_response:
    lea r13, [response]
    lea r12, [response]

    mov rdi, 200
    call .write_header

    ;AAPPEND r12, resp_text

    ; send the header first
    sub r12, r13
    PRINTF r14, r13, r12


    ; open the file
    lea rdi, [path]

    OPEN_FILE rdi

    cmp rax, 0
    jl .end ; shouldn't happen cuz FILE_EXISTS passed, but just in case
    mov r11, rax ; r11 = file fd

    ; sendfile(out_fd, in_fd, offset=NULL, count=big)
    mov rax, 40
    mov rdi, r14 ; client socket
    mov rsi, r11 ; file fd
    xor rdx, rdx ; offset = NULL (start from beginning)
    mov r10, 0x7fffffff ; send as much as possible
    
    syscall

    ; close the file fd
    mov rax, 3
    mov rdi, r11
    syscall

    jmp .end

.bad_request:
    lea r13, [response] ; start of the buffer, wont move
    lea r12, [response] ; current write pos

    mov rdi, 400
    call .write_header

    sub r12, r13

    jmp .send

.not_found:
    lea r13, [response] ; start of the buffer, wont move
    lea r12, [response] ; current write pos

    mov rdi, 404
    call .write_header

    sub r12, r13

    jmp .send

.write_header:
    ; rdi: status code (default 200). only supports 404, 400 and 200
    ; appends the HTTP header to the 'response' buffer

    cmp rdi, 404
    je .write_404

    cmp rdi, 400
    je .write_400

    jmp .write_200

.write_404:
    AAPPEND r12, response_404
    AAPPEND r12, crlf

    jmp .write_server_contenttype

.write_400:
    AAPPEND r12, response_400
    AAPPEND r12, crlf

    jmp .write_server_contenttype

.write_200:
    AAPPEND r12, response_200
    AAPPEND r12, crlf

.write_server_contenttype:
    AAPPEND r12, http_server
    AAPPEND r12, crlf
    AAPPEND r12, content_type
    AAPPEND r12, crlf
    AAPPEND r12, connection_close
    AAPPEND r12, crlf
    AAPPEND r12, crlf
    ret

.clear_buffers:
    ; clear request
    xor eax, eax
    mov rdi, request
    mov rcx, 1024
    rep stosb

    ; clear response
    mov rdi, response
    mov rcx, 1024
    rep stosb

    ; clear path
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
    mov rsi, 1 ; SHUT_WR
    syscall

    ; Drain remaining input so TCP can close cleanly
.__drain:
    mov rax, 0
    mov rdi, r14
    lea rsi, [request]
    mov rdx, 16
    syscall

    cmp rax, 0
    jg .__drain ; keep reading until eof / err

    ; close(fd)
    mov rax, 3
    mov rdi, r14
    syscall

    PRINTN log_responded_request, log_responded_request_len

    call .clear_buffers

    jmp .wait

.fail_socket:
	PRINTN log_fail_socket, log_fail_socket_len
	EXIT rax

.fail_setsockopt:
    PRINTN log_fail_setsockopt, log_fail_setsockopt_len
	EXIT rax

.fail_bind:
	PRINTN log_fail_bind, log_fail_bind_len
	EXIT rax

.fail_accept:
 	PRINTN log_fail_accept, log_fail_accept_len
    jmp .wait

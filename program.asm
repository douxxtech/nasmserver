%include "./macros/sysutils.asm"
%include "./macros/fileutils.asm"
%include "./macros/httputils.asm"
%include "./macros/logutils.asm"
%include "./macros/whatmimeisthat.asm"

extern inet_ntop ; to process the client IP address

; program.asm - HTTP/1.0 server entry point
section .data

    ; things you might want to configure

    ; socket setup
    sockaddr:
        dw 2                              ; AF_INET (ipv4)
        dw 0x5000                         ; port 80 big-endian
        dd 0                              ; 0.0.0.0 = listen on all interfaces
        dq 0                              ; padding

    ; server conf
    document_root  db "/var/www/html", 0                  ; document root, no trailing slash !
    index_file     db "index.html", 0      ; default file if a directory is fetched (eg / becomes internally /index.txt)
    max_conns      equ 20                  ; max simultaneous connections / threads (max is 255)
    server_name    db "NASMServer/1.0", 0  ; the server name

    ; errordocs files, relatively to the document_root (leave empty for none)
    ; start them with a slash !
    errordoc_405  db "/errordocs/405.html", 0
    errordoc_404  db "/errordocs/404.html", 0
    errordoc_403  db "/errordocs/403.html", 0
    errordoc_400  db "/errordocs/400.html", 0

    ; end of the things might want to configure

    sockopt         dd 1    ; value for SO_REUSEADDR
    client_addr_len dd 16

    ; HTTP constants
    crlf                    db 0xd, 0xa, 0

    response_405            db "HTTP/1.0 405 Method Not Allowed", 0
    response_404            db "HTTP/1.0 404 Not Found", 0
    response_403            db "HTTP/1.0 403 Forbidden", 0
    response_400            db "HTTP/1.0 400 Bad Request", 0
    response_200            db "HTTP/1.0 200 OK", 0

    server_header           db "Server: ", 0
    content_length_header   db "Content-Length: ", 0
    connection_close_header db "Connection: close", 0

section .bss
    request             resb 1024
    response            resb 1024
    client_addr         resb 16
    path                resb 256  ; should be enough for now
    last_status         resw 1    ; for logs
    client_ip_str       resb 16   ; "255.255.255.255\0"
    content_length_b    resb 20
    process_count       resb 1    ; current processes count
    file_to_serve       resq 1    ; pointer to path to serve, or 0 for none
    errordoc_405_path   resb 256
    errordoc_404_path   resb 256
    errordoc_403_path   resb 256
    errordoc_400_path   resb 256

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

    BUILDPATH errordoc_405_path, document_root, errordoc_405
    BUILDPATH errordoc_404_path, document_root, errordoc_404
    BUILDPATH errordoc_403_path, document_root, errordoc_403
    BUILDPATH errordoc_400_path, document_root, errordoc_400


.wait:  ; from here, we're NOT stopping the program anymore
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

.wait_for_slot:
    movzx rax, byte [process_count]
    cmp rax, max_conns
    jl .do_fork

    ; try reaping first in case some just finished
    call .reap_loop

    movzx rax, byte [process_count]
    cmp rax, max_conns
    jl .do_fork

    ; still full so just close the conn
    mov rax, 3
    mov rdi, r14

    syscall

    LOG_WARNING log_too_many_concurrent, log_too_many_concurrent_len

    jmp .wait

.do_fork:
    ; save client_addr to stack before forking to avoid race conds
    push qword [client_addr + 8]
    push qword [client_addr]

    ; fork()
    mov rax, 57
    syscall

    cmp rax, 0
    jl .fail_accept
    jg .close_client ; small issue, that works, but only calls on each new request. so there are zomb processes until next request.

    ; we're now in the child process
    ; child: close the server listening socket
    mov rax, 3
    mov rdi, r15
    syscall

    movzx eax, byte [rsp + 4]   ; first octet
    movzx ebx, byte [rsp + 5]   ; second
    movzx ecx, byte [rsp + 6]   ; third
    movzx edx, byte [rsp + 7]   ; fourth

    ; rdi = AF_INET (2)
    ; rsi = pointer to sin_addr (client_addr + 4)
    ; rdx = output buffer
    ; rcx = buffer size (16)
    mov     edi, 2
    lea     rsi, [rsp + 4]
    lea     rdx, [client_ip_str]
    mov     ecx, 16
    call    inet_ntop

.handle_request:
    READ_FILE r14, request, 1024

    IS_HTTP_REQUEST request, 1024

    cmp rax, 1
    je .get

    cmp rax, -405
    je .method_not_allowed

    cmp rax, -400
    je .bad_request

    jmp .forbidden          ; in case i add a new code and forgot to implement it here

.get:
    ; prepend document_root so the path is relative to it
    lea rsi, [document_root]
    lea rdi, [path]

.copy_docroot:
    mov al, [rsi]

    test al, al
    jz .copy_docroot_done

    mov [rdi], al
    inc rsi
    inc rdi

    jmp .copy_docroot

.copy_docroot_done:
    lea rax, [path]
    sub rdi, rax                             ; rdi = docroot length
    mov rbx, rdi                             ; rbx = docroot length for offsetting

    lea rdi, [path + rbx]
    PARSE_HTTP_PATH request, 1024, rdi, rcx  
    cmp rcx, 0
    jle .forbidden

    add rcx, rbx                             ; full length = docroot + http path

    mov byte [path + rcx + 1], 0

    cmp byte [path + rcx], '/'
    jne .check_exists

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

    cmp rax, 0     ; does not exist
    je .not_found

    cmp rax, 1     ; exists and is a readable file
    je .ok

    cmp rax, 2     ; is a dir
    je .add_slash

    ; 3 = exists but we can't read it
    ; but we're just not checking it to fallback to forbidden
    jmp .forbidden

.add_slash:
    lea rdi, [path]

.find_path_end:
    cmp byte [rdi], 0
    je .add_slash_2

    inc rdi
    jmp .find_path_end

.add_slash_2:
    mov byte [rdi], '/'

    inc rdi                ; rdi now points past the slash (= where index_file goes)
    lea rsi, [index_file]
    
    jmp .add_index

.ok:
    lea r13, [response]
    lea r12, [response]
    lea r10, [path]
    mov [file_to_serve], r10

    mov rdi, 200
    call .write_header

    sub r12, r13

    mov word [last_status], 200
    jmp .send

.method_not_allowed:
    lea r13, [response]
    lea r12, [response]
    mov qword [file_to_serve], errordoc_405_path

    mov rdi, 405
    call .write_header

    sub r12, r13

    mov word [last_status], 405
    jmp .send

.not_found:
    lea r13, [response]
    lea r12, [response]
    mov qword [file_to_serve], errordoc_404_path


    mov rdi, 404
    call .write_header

    sub r12, r13

    mov word [last_status], 404
    jmp .send

.forbidden:
    lea r13, [response]
    lea r12, [response]
    mov qword [file_to_serve], errordoc_403_path

    mov rdi, 403
    call .write_header

    sub r12, r13

    mov word [last_status], 403
    jmp .send

.bad_request:
    lea r13, [response]
    lea r12, [response]
    mov qword [file_to_serve], errordoc_400_path

    mov rdi, 400
    call .write_header

    sub r12, r13

    mov word [last_status], 400
    jmp .send

.write_header:
    ; rdi: status code (200, 400, 403, 404 or 405)
    ; appends the HTTP header to the 'response' buffer

    cmp rdi, 405
    je .write_405

    cmp rdi, 404
    je .write_404

    cmp rdi, 403
    je .write_403

    cmp rdi, 400
    je .write_400

    jmp .write_200

.write_405:
    AAPPEND r12, response_405
    AAPPEND r12, crlf
    jmp .header_server

.write_404:
    AAPPEND r12, response_404
    AAPPEND r12, crlf
    jmp .header_server

.write_403:
    AAPPEND r12, response_403
    AAPPEND r12, crlf
    jmp .header_server

.write_400:
    AAPPEND r12, response_400
    AAPPEND r12, crlf
    jmp .header_server

.write_200:
    AAPPEND r12, response_200
    AAPPEND r12, crlf

.header_server:
    AAPPEND r12, server_header
    AAPPEND r12, server_name
    AAPPEND r12, crlf

.header_content_type:
    ; content type detection
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_content_length

    GET_MIME_TYPE rdi, rbx ; content type will be in rsi

    mov rdi, rbx ; aappend doesn't clobbers rdi
    AAPPEND r12, rdi

    AAPPEND r12, crlf

.header_content_length:
    ; very similar to the previous one
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_conn_close

    FILE_SIZE rdi, rbx

    cmp rbx, 0   ; rbx < 0 means that it failed, skipping header
    jl .header_conn_close

    ITOA rbx, content_length_b, rcx

    AAPPEND r12, content_length_header
    AAPPEND r12, content_length_b
    AAPPEND r12, crlf


.header_conn_close:
    AAPPEND r12, connection_close_header
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
    PRINTF r14, r13, r12    ; send the headers first

    ; serve the file if one was set
    mov r10, [file_to_serve]  
    test r10, r10
    jz .end

    FILE_EXISTS r10
    cmp rax, 1
    jne .end                   ; file doesn't exist, just send headers

    ; open the file
    mov rdi, r10
    OPEN_FILE rdi

    cmp rax, 0
    jl .end                   ; shouldn't happen cuz FILE_EXISTS passed, but just in case
    mov r11, rax              ; r11 = file fd

    ; sendfile(out_fd, in_fd, offset=NULL, count=big)
    mov rax, 40
    mov rdi, r14              ; client socket
    mov rsi, r11              ; file fd
    xor rdx, rdx              ; offset = NULL (start from beginning)
    mov r10, 0x7fffffff       ; send as much as possible
    syscall

    ; close the file fd
    mov rax, 3
    mov rdi, r11
    syscall

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

    add rsp, 16
    EXIT 0 ; child exits

.close_client:
    add rsp, 16

    mov rax, 3
    mov rdi, r14
    syscall

    inc byte [process_count]

    call .reap_loop
    jmp .wait

.reap_loop:
    ; reap zombie processes

    ; wait4(pid, status, opt)
    mov rax, 61
    mov rdi, -1
    xor rsi, rsi
    mov rdx, 1      ; WNOHANG
    xor r10, r10
    syscall

    cmp rax, 0
    jle .reap_done ; no child reaped, stop

    dec byte [process_count]
    jmp .reap_loop

.reap_done:
    ret
    

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
    jmp .wait ; child exits
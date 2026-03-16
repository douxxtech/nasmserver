; program.asm - HTTP/1.0 server entry point

%include "./macros/sysutils.asm"
%include "./macros/fileutils.asm"
%include "./macros/httputils.asm"
%include "./macros/logutils.asm"
%include "./macros/whatmimeisthat.asm"
%include "./macros/envutils.asm"

%include "./labels/flagparser.asm"
%include "./labels/initialsetup.asm"
%include "./labels/startupchecks.asm"

extern inet_ntop ; to process the client IP address

section .data

    ; socket setup
    sockaddr:
        dw 2       ; AF_INET (ipv4)
        dw 0x5000  ; port 80 big-endian (edited at runtime)
        dd 0       ; 0.0.0.0 = listen on all interfaces
        dq 0       ; padding

    sockopt                  dd 1   ; value for SO_REUSEADDR
    client_addr_len          dd 16  ; data directive for accept() (at .wait)

    ; HTTP constants
    crlf                     db 0xd, 0xa, 0

    response_405             db "HTTP/1.0 405 Method Not Allowed", 0
    response_404             db "HTTP/1.0 404 Not Found", 0
    response_403             db "HTTP/1.0 403 Forbidden", 0
    response_400             db "HTTP/1.0 400 Bad Request", 0
    response_200             db "HTTP/1.0 200 OK", 0

    server_header            db "Server: ", 0
    content_length_header    db "Content-Length: ", 0
    connection_close_header  db "Connection: close", 0

section .bss
    ; network
    client_addr       resb 16
    client_ip_str     resb 16    ; "255.255.255.255\0"

    ; request / response
    request           resb 1024
    response          resb 1024

    ; path handling
    path              resb 256
    file_to_serve     resq 1     ; pointer to path to serve, or 0 for none

    ; misc
    last_status       resw 1     ; for logs
    content_length_b  resb 20
    process_count     resb 1     ; current processes count
    log_port_buf      resb 8     ; "65535\n\0" worst case

section .text
    global _start


; register usage, after startup (persistent across the request handling):
;   r15 = server socket fd
;   r14 = client socket fd (per request)
;   r13 = response buffer start (anchor) / client IP str (at .end, for logging)
;   r12 = response buffer write position / last status code (at .end, for logging)
;   r11 = file fd (when serving a file)

_start:
    PRINTN log_started_nasmserver, log_started_nasmserver_len

    mov r15, [rsp]       ; argc
    call parse_flags     ; sets flag_* bytes, strips flags, etc. From labels/flagparser.asm

    call initial_setup   ; from labels/initialsetup.asm

    call startup_checks  ; from labels/startupchecks.asm

.start_server:

    ; create the server TCP socket
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
    jne .fail_setsockopt  ;


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

    ; start listening for incoming connections
    ; listen(fd, backlog)
    mov rax, 50
    mov rdi, r15
    movzx rsi, byte [max_conns]
    syscall

    ; this mess prints the port log
    PRINT_TIMESTAMP

    PRINT log_prefix_info, log_prefix_info_len
    PRINT log_listening_port, log_listening_port_len

    ; port int to ascii
    movzx rbx, word [port]

    ITOA rbx, log_port_buf, r9
    PRINTN log_port_buf, r9


.wait:  
    ; from here, we're NOT stopping the program anymore

    ; block until a new connection arrives, then store the client fd in r14
    ; accept(fd, sockaddr, addrlen)
    mov rax, 43
    mov rdi, r15
    mov rsi, client_addr
    mov rdx, client_addr_len
    syscall

    cmp rax, 0
    jl .fail_accept

    mov r14, rax              ; r14 will contain the client file descriptor

.wait_for_slot:
    movzx rax, byte [process_count]
    cmp al, [max_conns]
    jl .do_fork

    ; try reaping first in case some just finished
    call .reap_loop

    movzx rax, byte [process_count]
    cmp al, [max_conns]
    jl .do_fork

    ; still full, drop the connection and warn

    ; close the file
    ; close(fd)
    mov rax, 3
    mov rdi, r14
    syscall

    LOG_WARNING log_too_many_concurrent, log_too_many_concurrent_len

    jmp .wait

.do_fork:
    ; save client_addr to stack before forking to avoid race conds
    push qword [client_addr + 8]
    push qword [client_addr]

    ; spawn a child process to handle this request
    ; fork()
    mov rax, 57
    syscall

    cmp rax, 0
    jl .fail_accept

    ; small issue: .close_client only gets called on each new request,
    ; so zombie processes linger until the next connection comes in
    jg .close_client

    ; we're now in the child process

    ; child doesn't need the server listening socket
    ; close(fd)
    mov rax, 3
    mov rdi, r15
    syscall

    movzx eax, byte [rsp + 4]     ; first octet
    movzx ebx, byte [rsp + 5]     ; second
    movzx ecx, byte [rsp + 6]     ; third
    movzx edx, byte [rsp + 7]     ; fourth

    ; convert the binary client address to a printable string
    ; inet_ntop(af, src, dst, size)
    mov edi, 2                ; AF_INET
    lea rsi, [rsp + 4]        ; pointer to sin_addr (client_addr + 4)
    lea rdx, [client_ip_str]  ; output buffer
    mov ecx, 16               ; buffer size
    
    call inet_ntop

.handle_request:
    READ_FILE r14, request, 1024

    IS_HTTP_REQUEST request, 1024

    cmp rax, 1
    je .get

    cmp rax, -405
    je .method_not_allowed

    cmp rax, -400
    je .bad_request

    jmp .forbidden                 ; in case i add a new code and forgot to implement it here

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
    sub rdi, rax                                  ; rdi = docroot length
    mov rbx, rdi                                  ; rbx = docroot length for offsetting

    cmp rbx, 255
    jge .forbidden                                ; if docroot alone is >= 255, there's no room for any path

    mov r10, 255
    sub r10, rbx                                  ; rcx = 255 - docroot_len = remaining space

    lea rdi, [path + rbx]
    PARSE_HTTP_PATH request, 1024, rdi, rax, r10  ; parse path into [path + docroot_len]

    cmp rax, 0
    jle .forbidden

    add rax, rbx                                  ; full length = docroot + http path

    mov byte [path + rax + 1], 0

    STRCUT path, '?'                              ; remove the ?query=string, we won't process it as a static site

    cmp byte [path + rax], '/'
    jne .check_exists

.add_index:
    mov al, [rsi]
    mov [rdi], al

    inc rsi
    inc rdi

    test al, al
    jnz .add_index

.check_exists:

    ; check if the file exists before continuing
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

    GET_MIME_TYPE rdi, rbx     ; content type will be in rsi

    mov rdi, rbx               ; aappend doesn't clobbers rdi
    AAPPEND r12, rdi

    AAPPEND r12, crlf

.header_content_length:
    ; very similar to the previous one
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_conn_close

    FILE_SIZE rdi, rbx

    cmp rbx, 0                          ; rbx < 0 means that it failed, skipping header
    jl .header_conn_close

    ITOA rbx, content_length_b, rcx

    AAPPEND r12, content_length_header
    AAPPEND r12, content_length_b
    AAPPEND r12, crlf

.header_conn_close:
    AAPPEND r12, connection_close_header
    AAPPEND r12, crlf
    AAPPEND r12, crlf                     ; blank line = end of headers
    ret

.send:
    PRINTF r14, r13, r12      ; send the headers first

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
    jl .end                    ; shouldn't happen cuz FILE_EXISTS passed, but just in case
    mov r11, rax               ; r11 = file fd

    ; stream the file directly from the fd to the client socket
    ; sendfile(out_fd, in_fd, offset, count)
    mov rax, 40
    mov rdi, r14               ; client socket
    mov rsi, r11               ; file fd
    xor rdx, rdx               ; offset = NULL (start from beginning)
    mov r10, 0x7fffffff        ; send as much as possible
    syscall

    ; close(fd)
    mov rax, 3
    mov rdi, r11
    syscall

.end:

    ; signal we're done writing so the client knows the response is complete
    ; shutdown(fd, how)
    mov rax, 48
    mov rdi, r14
    mov rsi, 1      ; SHUT_WR
    syscall

    ; drain remaining input so TCP can close cleanly
.__drain:

    ; read(fd, buffer, count)
    mov rax, 0
    mov rdi, r14
    lea rsi, [request]
    mov rdx, 16
    syscall

    cmp rax, 0
    jg .__drain                    ; keep reading until eof / err

    ; close(fd)
    mov rax, 3
    mov rdi, r14
    syscall

    movzx r12, word [last_status]  ; reuse r12/r13 for log, replaced next iteration
    lea r13, [client_ip_str]
    LOG_REQUEST path, r12, r13

    add rsp, 16
    EXIT 0 ; child exits

.close_client:
    add rsp, 16

    ; close the client fd in the parent, the child owns it now
    ; close(fd)
    mov rax, 3
    mov rdi, r14
    syscall

    inc byte [process_count]

    call .reap_loop
    jmp .wait

.reap_loop:

    ; reap zombie processes
    ; wait4(pid, status, options, usage)
    mov rax, 61
    mov rdi, -1     ; any child
    xor rsi, rsi
    mov rdx, 1      ; WNOHANG
    xor r10, r10
    syscall

    cmp rax, 0
    jle .reap_done  ; no child reaped, stop

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
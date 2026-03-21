; program.asm - HTTP/1.0 server entry point

%include "./macros/envutils.asm"
%include "./macros/fileutils.asm"
%include "./macros/httputils.asm"
%include "./macros/logutils.asm"
%include "./macros/strutils.asm"
%include "./macros/sysutils.asm"
%include "./macros/whatmimeisthat.asm"

%include "./labels/flagparser.asm"
%include "./labels/initialsetup.asm"
%include "./labels/startupchecks.asm"

extern inet_ntop ; to process the client IP address

section .data

    version db "1.6", 0

    ; socket setup
    sockaddr:
        dw 2       ; AF_INET (ipv4)
        dw 0x1F90  ; port 8080 big-endian (edited at runtime)
        dd 0       ; 0.0.0.0 = listen on all interfaces
        dq 0       ; padding

    sockopt                  dd 1   ; value for SO_REUSEADDR
    client_addr_len          dd 16  ; data directive for accept() (at .wait)

    ; HTTP constants
    crlf                     db 0xd, 0xa, 0

    response_405             db "HTTP/1.0 405 Method Not Allowed", 0
    response_404             db "HTTP/1.0 404 Not Found", 0
    response_403             db "HTTP/1.0 403 Forbidden", 0
    response_401             db "HTTP/1.0 401 Unauthorized", 0
    response_400             db "HTTP/1.0 400 Bad Request", 0
    response_200             db "HTTP/1.0 200 OK", 0

    allow_header             db "Allow: GET, HEAD", 0
    www_authenticate_header  db "WWW-Authenticate: Basic realm=", 0x22, "None", 0x22, 0  ; 0x22 is "
    date_header              db "Date: ", 0
    server_header            db "Server: ", 0
    pragma_header            db "Pragma: no-cache", 0
    last_modified_header     db "Last-Modified: ", 0
    expires_header           db "Expires: ", 0
    content_type_header      db "Content-Type: ", 0
    content_encoding_header  db "Content-Encoding: identity", 0  ; identity = not changed
    content_length_header    db "Content-Length: ", 0
    accept_ranges_header     db "Accept-Ranges: none", 0         ; We don't support ranging
    connection_close_header  db "Connection: close", 0           ; We don't support keep alive


section .bss
    ; network
    client_addr       resb 16
    client_ip_str     resb 16    ; "255.255.255.255\0"

    ; request / response
    request           resb 8192  ; requests can get big
    response          resb 512   ; 512 should be enough for headers

    ; path handling
    path              resb 768   ; docroot + url + index
    file_to_serve     resq 1     ; pointer to path to serve, or 0 for none

    ; authentication
    auth              resb 258   ; 128 (user) + 1 (:) + 128 (pwd) + null term (1)
    username          resb 129
    password          resb 129

    ; misc
    last_status       resw 1     ; for logs
    content_length_b  resb 20
    process_count     resw 1     ; current processes count
    log_port_buf      resb 8     ; "65535\n\0" worst case
    header_time       resb 32    ; "Mon, 01 Jan 2000 00:00:00 GMT\0" + padding
    request_type      resb 1     ; GET = 0, HEAD = 1

section .text
    global _start


; consistent register usage, after startup (persistent across the request handling):
;   r15 = server socket fd
;   r14 = client socket fd (per request)
;   r13 = response buffer start (anchor) / client IP str (at .end, for logging)
;   r12 = response buffer write position / last status code (at .end, for logging)
;   r11 = file fd (when serving a file)

_start:
    mov r15, [rsp]       ; argc
    call parse_flags     ; sets flag_* bytes, strips flags, etc. From labels/flagparser.asm

    call initial_setup   ; from labels/initialsetup.asm

    call startup_checks  ; from labels/startupchecks.asm

    LF
    PRINTN log_started_nasmserver, log_started_nasmserver_len

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
    movzx rsi, byte [max_requests]
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
    movzx rax, word [process_count]
    cmp ax, [max_requests]
    jb .do_fork

    ; try reaping first in case some just finished
    call .reap_loop

    movzx rax, word [process_count]
    cmp ax, [max_requests]
    jb .do_fork

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
    READ_FILE r14, request, 8192

    IS_HTTP_REQUEST request, 8192



    cmp rax, -405
    je .method_not_allowed

    cmp rax, -400
    je .bad_request

    cmp rax, -200
    je .head

    cmp rax, 200
    je .get

    jmp .forbidden                 ; in case i add a new code and forgot to implement it here

.get:
    mov byte [request_type], 0
    jmp .auth_check

.head:
    mov byte [request_type], 1

.auth_check:
    ; if no auth is configured, go to auth_ok (no auth setuped)
    cmp byte [auth_username], 0
    je .auth_ok

    PARSE_AUTH_HEADER request, 8192, auth, 264
    STRLEN auth, rcx

    ; if nothing was decoded (no header sent), demand credentials
    cmp rcx, 0
    je .unauthorized

    STRSPLIT auth, ':', username, password, rcx  ; using rcx since rax gets clobbered

    cmp rcx, 0                                   ; 0 = no ':', so bad creds format
    je .unauthorized

    ; check if they're the correct ones

    STREQ username, auth_username, rcx

    cmp rcx, 0                                  ; 0 = not equal
    je .unauthorized


    STREQ password, auth_password, rcx

    cmp rcx, 0
    je .unauthorized

    ; both passed = auth passed

.auth_ok:
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

    mov r10, 767
    sub r10, rbx                                  ; rcx = 255 - docroot_len = remaining space

    lea rdi, [path + rbx]
    PARSE_HTTP_PATH request, 8192, rdi, rax, r10  ; parse path into [path + docroot_len]

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

.unauthorized:
    lea r13, [response]
    lea r12, [response]
    mov qword [file_to_serve], errordoc_401_path

    mov rdi, 401
    call .write_header

    sub r12, r13

    mov word [last_status], 401
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

    cmp rdi, 401
    je .write_401

    cmp rdi, 400
    je .write_400

    jmp .write_200

.write_405:
    AAPPEND r12, response_405
    AAPPEND r12, crlf
    AAPPEND r12, allow_header
    AAPPEND r12, crlf
    jmp .header_date

.write_404:
    AAPPEND r12, response_404
    AAPPEND r12, crlf
    jmp .header_date

.write_403:
    AAPPEND r12, response_403
    AAPPEND r12, crlf
    jmp .header_date

.write_401:
    AAPPEND r12, response_401
    AAPPEND r12, crlf
    AAPPEND r12, www_authenticate_header
    AAPPEND r12, crlf
    jmp .header_date

.write_400:
    AAPPEND r12, response_400
    AAPPEND r12, crlf
    jmp .header_date

.write_200:
    AAPPEND r12, response_200
    AAPPEND r12, crlf

.header_date:
    GET_HTTP_TIME header_time

    AAPPEND r12, date_header
    AAPPEND r12, header_time
    AAPPEND r12, crlf

.header_server:
    AAPPEND r12, server_header
    AAPPEND r12, server_name
    AAPPEND r12, crlf

.header_pragma:
    cmp dword [max_age], 0     ; if maxage is < 0, we don't send the pragma: no-cache header
    ja .header_last_modified   ; jump above (jg unsigned)

    AAPPEND r12, pragma_header
    AAPPEND r12, crlf

.header_last_modified:
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_expires

    AAPPEND r12, last_modified_header

    FILE_LAST_MODIFIED rdi, header_time

    AAPPEND r12, header_time
    AAPPEND r12, crlf

.header_expires:
    mov r8d, dword [max_age]
    HTTP_EXPIRE_DATE r8, header_time

    AAPPEND r12, expires_header
    AAPPEND r12, header_time
    AAPPEND r12, crlf

.header_content_type:
    ; content type detection
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_content_encoding

    AAPPEND r12, content_type_header

    GET_MIME_TYPE rdi, rbx     ; content type will be in rsi

    mov rdi, rbx               ; aappend doesn't clobbers rdi
    
    AAPPEND r12, rdi
    AAPPEND r12, crlf

.header_content_encoding:
    ; content type detection
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .header_content_length

    AAPPEND r12, content_encoding_header
    AAPPEND r12, crlf


.header_content_length:
    ; very similar to the previous one
    mov rdi, [file_to_serve]

    cmp byte [rdi], 0
    je .accept_ranges_header

    FILE_SIZE rdi, rbx

    cmp rbx, 0                          ; rbx < 0 means that it failed, skipping header
    jl .accept_ranges_header

    ITOA rbx, content_length_b, rcx

    AAPPEND r12, content_length_header
    AAPPEND r12, content_length_b
    AAPPEND r12, crlf

.accept_ranges_header:
    AAPPEND r12, accept_ranges_header
    AAPPEND r12, crlf

.header_conn_close:
    AAPPEND r12, connection_close_header
    AAPPEND r12, crlf

.header_end:
    AAPPEND r12, crlf                     ; blank line = end of headers
    ret

.send:
    PRINTF r14, r13, r12      ; send the headers first

    ; directly end if it's a HEAD request
    cmp byte [request_type], 1
    je .end

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
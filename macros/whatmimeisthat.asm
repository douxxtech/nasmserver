; what mime is that?.asm - MIME type detection for NASMServer

section .data

    ; MIME type content-type strings. Taken from https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types
    mime_type_html      db "text/html", 0
    mime_type_css       db "text/css", 0
    mime_type_js        db "text/javascript", 0
    mime_type_json      db "application/json", 0
    mime_type_xml       db "application/xml", 0
    mime_type_csv       db "text/csv", 0
    mime_type_md        db "text/markdown", 0
    mime_type_manifest  db "application/manifest+json", 0
    mime_type_plain     db "text/plain", 0
    mime_type_png       db "image/png", 0
    mime_type_jpg       db "image/jpeg", 0
    mime_type_gif       db "image/gif", 0
    mime_type_ico       db "image/vnd.microsoft.icon", 0
    mime_type_svg       db "image/svg+xml", 0
    mime_type_webp      db "image/webp", 0
    mime_type_avif      db "image/avif", 0
    mime_type_bmp       db "image/bmp", 0
    mime_type_tiff      db "image/tiff", 0
    mime_type_apng      db "image/apng", 0
    mime_type_mp3       db "audio/mpeg", 0
    mime_type_weba      db "audio/webm", 0
    mime_type_wav       db "audio/wav", 0
    mime_type_ogg       db "audio/ogg", 0
    mime_type_aac       db "audio/aac", 0
    mime_type_opus      db "audio/ogg", 0
    mime_type_midi      db "audio/midi", 0
    mime_type_mp4       db "video/mp4", 0
    mime_type_webm      db "video/webm", 0
    mime_type_mpeg      db "video/mpeg", 0
    mime_type_ogv       db "video/ogg", 0
    mime_type_avi       db "video/x-msvideo", 0
    mime_type_3gp       db "video/3gpp", 0
    mime_type_woff      db "font/woff", 0
    mime_type_woff2     db "font/woff2", 0
    mime_type_ttf       db "font/ttf", 0
    mime_type_otf       db "font/otf", 0
    mime_type_zip       db "application/zip", 0
    mime_type_gz        db "application/gzip", 0
    mime_type_tar       db "application/x-tar", 0
    mime_type_epub      db "application/epub+zip", 0
    mime_type_pdf       db "application/pdf", 0
    mime_type_wasm      db "application/wasm", 0
    mime_type_octet     db "application/octet-stream", 0
    mime_type_abw       db "application/x-abiword", 0
    mime_type_arc       db "application/x-freearc", 0
    mime_type_azw       db "application/vnd.amazon.ebook", 0
    mime_type_bin       db "application/octet-stream", 0
    mime_type_bz        db "application/x-bzip", 0
    mime_type_bz2       db "application/x-bzip2", 0
    mime_type_cda       db "application/x-cdf", 0
    mime_type_csh       db "application/x-csh", 0
    mime_type_doc       db "application/msword", 0
    mime_type_docx      db "application/vnd.openxmlformats-officedocument.wordprocessingml.document", 0
    mime_type_eot       db "application/vnd.ms-fontobject", 0
    mime_type_ics       db "text/calendar", 0
    mime_type_jar       db "application/java-archive", 0
    mime_type_jsonld    db "application/ld+json", 0
    mime_type_mjs       db "text/javascript", 0
    mime_type_mpkg      db "application/vnd.apple.installer+xml", 0
    mime_type_odp       db "application/vnd.oasis.opendocument.presentation", 0
    mime_type_ods       db "application/vnd.oasis.opendocument.spreadsheet", 0
    mime_type_odt       db "application/vnd.oasis.opendocument.text", 0
    mime_type_oga       db "audio/ogg", 0
    mime_type_ogx       db "application/ogg", 0
    mime_type_php       db "application/x-httpd-php", 0
    mime_type_ppt       db "application/vnd.ms-powerpoint", 0
    mime_type_pptx      db "application/vnd.openxmlformats-officedocument.presentationml.presentation", 0
    mime_type_rar       db "application/vnd.rar", 0
    mime_type_rtf       db "application/rtf", 0
    mime_type_sh        db "application/x-sh", 0
    mime_type_ts        db "video/mp2t", 0
    mime_type_vsd       db "application/vnd.visio", 0
    mime_type_xhtml     db "application/xhtml+xml", 0
    mime_type_xls       db "application/vnd.ms-excel", 0
    mime_type_xlsx      db "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 0
    mime_type_xul       db "application/vnd.mozilla.xul+xml", 0
    mime_type_7z        db "application/x-7z-compressed", 0

    mime_ext_html      db "html", 0
    mime_ext_htm       db "htm", 0
    mime_ext_css       db "css", 0
    mime_ext_js        db "js", 0
    mime_ext_json      db "json", 0
    mime_ext_xml       db "xml", 0
    mime_ext_csv       db "csv", 0
    mime_ext_md        db "md", 0
    mime_ext_manifest  db "webmanifest", 0
    mime_ext_txt       db "txt", 0
    mime_ext_png       db "png", 0
    mime_ext_jpg       db "jpg", 0
    mime_ext_jpeg      db "jpeg", 0
    mime_ext_gif       db "gif", 0
    mime_ext_ico       db "ico", 0
    mime_ext_svg       db "svg", 0
    mime_ext_webp      db "webp", 0
    mime_ext_avif      db "avif", 0
    mime_ext_bmp       db "bmp", 0
    mime_ext_tiff      db "tiff", 0
    mime_ext_tif       db "tif", 0
    mime_ext_apng      db "apng", 0
    mime_ext_mp3       db "mp3", 0
    mime_ext_weba      db "weba", 0
    mime_ext_wav       db "wav", 0
    mime_ext_oga       db "oga", 0
    mime_ext_aac       db "aac", 0
    mime_ext_opus      db "opus", 0
    mime_ext_mid       db "mid", 0
    mime_ext_midi      db "midi", 0
    mime_ext_mp4       db "mp4", 0
    mime_ext_webm      db "webm", 0
    mime_ext_mpeg      db "mpeg", 0
    mime_ext_ogv       db "ogv", 0
    mime_ext_avi       db "avi", 0
    mime_ext_3gp       db "3gp", 0
    mime_ext_woff      db "woff", 0
    mime_ext_woff2     db "woff2", 0
    mime_ext_ttf       db "ttf", 0
    mime_ext_otf       db "otf", 0
    mime_ext_zip       db "zip", 0
    mime_ext_gz        db "gz", 0
    mime_ext_tar       db "tar", 0
    mime_ext_epub      db "epub", 0
    mime_ext_pdf       db "pdf", 0
    mime_ext_wasm      db "wasm", 0
    mime_ext_abw       db "abw", 0
    mime_ext_arc       db "arc", 0
    mime_ext_azw       db "azw", 0
    mime_ext_bin       db "bin", 0
    mime_ext_bz        db "bz", 0
    mime_ext_bz2       db "bz2", 0
    mime_ext_cda       db "cda", 0
    mime_ext_csh       db "csh", 0
    mime_ext_doc       db "doc", 0
    mime_ext_docx      db "docx", 0
    mime_ext_eot       db "eot", 0
    mime_ext_ics       db "ics", 0
    mime_ext_jar       db "jar", 0
    mime_ext_jsonld    db "jsonld", 0
    mime_ext_mjs       db "mjs", 0
    mime_ext_mpkg      db "mpkg", 0
    mime_ext_odp       db "odp", 0
    mime_ext_ods       db "ods", 0
    mime_ext_odt       db "odt", 0
    mime_ext_ogx       db "ogx", 0
    mime_ext_php       db "php", 0
    mime_ext_ppt       db "ppt", 0
    mime_ext_pptx      db "pptx", 0
    mime_ext_rar       db "rar", 0
    mime_ext_rtf       db "rtf", 0
    mime_ext_sh        db "sh", 0
    mime_ext_ts        db "ts", 0
    mime_ext_vsd       db "vsd", 0
    mime_ext_xhtml     db "xhtml", 0
    mime_ext_xls       db "xls", 0
    mime_ext_xlsx      db "xlsx", 0
    mime_ext_xul       db "xul", 0
    mime_ext_7z        db "7z", 0

    ; lookup table
    mime_table:
        dq mime_ext_html,      mime_type_html
        dq mime_ext_htm,       mime_type_html
        dq mime_ext_css,       mime_type_css
        dq mime_ext_js,        mime_type_js
        dq mime_ext_json,      mime_type_json
        dq mime_ext_xml,       mime_type_xml
        dq mime_ext_csv,       mime_type_csv
        dq mime_ext_md,        mime_type_md
        dq mime_ext_manifest,  mime_type_manifest
        dq mime_ext_txt,       mime_type_plain
        dq mime_ext_png,       mime_type_png
        dq mime_ext_jpg,       mime_type_jpg
        dq mime_ext_jpeg,      mime_type_jpg
        dq mime_ext_gif,       mime_type_gif
        dq mime_ext_ico,       mime_type_ico
        dq mime_ext_svg,       mime_type_svg
        dq mime_ext_webp,      mime_type_webp
        dq mime_ext_avif,      mime_type_avif
        dq mime_ext_bmp,       mime_type_bmp
        dq mime_ext_tiff,      mime_type_tiff
        dq mime_ext_tif,       mime_type_tiff
        dq mime_ext_apng,      mime_type_apng
        dq mime_ext_mp3,       mime_type_mp3
        dq mime_ext_weba,      mime_type_weba
        dq mime_ext_wav,       mime_type_wav
        dq mime_ext_oga,       mime_type_ogg
        dq mime_ext_aac,       mime_type_aac
        dq mime_ext_opus,      mime_type_opus
        dq mime_ext_mid,       mime_type_midi
        dq mime_ext_midi,      mime_type_midi
        dq mime_ext_mp4,       mime_type_mp4
        dq mime_ext_webm,      mime_type_webm
        dq mime_ext_mpeg,      mime_type_mpeg
        dq mime_ext_ogv,       mime_type_ogv
        dq mime_ext_avi,       mime_type_avi
        dq mime_ext_3gp,       mime_type_3gp
        dq mime_ext_woff,      mime_type_woff
        dq mime_ext_woff2,     mime_type_woff2
        dq mime_ext_ttf,       mime_type_ttf
        dq mime_ext_otf,       mime_type_otf
        dq mime_ext_zip,       mime_type_zip
        dq mime_ext_gz,        mime_type_gz
        dq mime_ext_tar,       mime_type_tar
        dq mime_ext_epub,      mime_type_epub
        dq mime_ext_pdf,       mime_type_pdf
        dq mime_ext_wasm,      mime_type_wasm
        dq mime_ext_abw,       mime_type_abw
        dq mime_ext_arc,       mime_type_arc
        dq mime_ext_azw,       mime_type_azw
        dq mime_ext_bin,       mime_type_bin
        dq mime_ext_bz,        mime_type_bz
        dq mime_ext_bz2,       mime_type_bz2
        dq mime_ext_cda,       mime_type_cda
        dq mime_ext_csh,       mime_type_csh
        dq mime_ext_doc,       mime_type_doc
        dq mime_ext_docx,      mime_type_docx
        dq mime_ext_eot,       mime_type_eot
        dq mime_ext_ics,       mime_type_ics
        dq mime_ext_jar,       mime_type_jar
        dq mime_ext_jsonld,    mime_type_jsonld
        dq mime_ext_mjs,       mime_type_mjs
        dq mime_ext_mpkg,      mime_type_mpkg
        dq mime_ext_odp,       mime_type_odp
        dq mime_ext_ods,       mime_type_ods
        dq mime_ext_odt,       mime_type_odt
        dq mime_ext_ogx,       mime_type_ogx
        dq mime_ext_php,       mime_type_php
        dq mime_ext_ppt,       mime_type_ppt
        dq mime_ext_pptx,      mime_type_pptx
        dq mime_ext_rar,       mime_type_rar
        dq mime_ext_rtf,       mime_type_rtf
        dq mime_ext_sh,        mime_type_sh
        dq mime_ext_ts,        mime_type_ts
        dq mime_ext_vsd,       mime_type_vsd
        dq mime_ext_xhtml,     mime_type_xhtml
        dq mime_ext_xls,       mime_type_xls
        dq mime_ext_xlsx,      mime_type_xlsx
        dq mime_ext_xul,       mime_type_xul
        dq mime_ext_7z,        mime_type_7z
        dq 0, 0                ; sentinel

    mime_dot_char  db '.', 0


section .text

; GET_MIME_TYPE path_ptr, out_reg
;   Looks up the MIME Content-Type string for the file at path_ptr.
;   Args:
;     %1: pointer to null-terminated path string (e.g. "./index.txt")
;     %2: register to store the result pointer (points to "..." string)
;   Returns:
;     %2 = pointer to the matching content-type string,
;          or mime_type_octet if extension is unknown/missing
;   Clobbers: rax, rdi, rsi, rcx, rdx
%macro GET_MIME_TYPE 2
    push rdi
    push rsi
    push rcx
    push rdx

    mov  rsi, %1        ; rsi = current scan ptr

%%find_end:             ; go to end of string
    cmp  byte [rsi], 0  ; NUL
    je   %%scan_back
    inc  rsi
    jmp  %%find_end

%%scan_back:             ; walk backwards looking for '.'
    cmp  rsi, %1         ; gone past the start?
    jbe  %%unknown
    dec  rsi
    cmp  byte [rsi], '.'
    jne  %%scan_back

    lea  rax, [rsi + 1]  ; rax = ptr to extension (skip the dot)

    ; go to the mime_table looking for a match
    lea  rsi, [mime_table]

%%loop:
    mov  rcx, [rsi]     ; ext_ptr
    test rcx, rcx
    jz   %%unknown      ; hit sentinel

    ; strcmp(rax, rcx): compare extension against table entry
    push rax
    push rsi

%%cmp:
    mov  dl,  [rax]
    mov  dh,  [rcx]

    cmp  dl,  dh
    jne  %%next_entry   ; mismatch, try next

    test dl,  dl
    jz   %%match        ; both null = full match

    inc  rax
    inc  rcx

    jmp  %%cmp

%%next_entry:
    pop  rsi
    pop  rax
    add  rsi, 16        ; advance by one table entry (2x 8-byte pointers)
    jmp  %%loop

%%match:
    pop  rsi
    pop  rax
    mov  %2, [rsi + 8]  ; load the mime_ptr (second qword of the pair)
    jmp  %%done

%%unknown:
    lea  %2, [mime_type_octet]

%%done:
    pop rdx
    pop rcx
    pop rsi
    pop rdi
%endmacro
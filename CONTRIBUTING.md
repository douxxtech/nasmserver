# Contribution Guidelines

Thanks for your interest in contributing to this project.

NASM can already be tricky to work with, so these guidelines exist to keep the codebase readable and save everyone a headache.

## 1. Comments

Good comments are what make assembly code understandable. Please don't skip them.

### 1.1 Block Comments

Block comments are standalone: they don't share a line with any code.  
Keep them at the same indentation level as the code they describe.

**Example:**
```assembly
.check_exists:

    ; check if the file exists before continuing
    FILE_EXISTS rdi
```

### 1.2 Inline Comments

Inline comments share a line with code. They must follow these rules:

- All inline comments in a section should start on the **same column**
- That column is defined as: `[longest line in section] + 3`
- If the longest line is unusually long, use the **second longest** as the reference instead
- The reference column can differ between sections

**Example:**
```assembly
.copy_docroot_done:
    lea rax, [path]
    sub rdi, rax                             ; rdi = docroot length
    mov rbx, rdi                             ; rbx = docroot length for offsetting

    lea rdi, [path + rbx]
    PARSE_HTTP_PATH request, 1024, rdi, rcx  ; <- longest + 3
    cmp rcx, 0
    jle .forbidden

    add rcx, rbx                             ; full length = docroot + http path

    mov byte [path + rcx + 1], 0

    cmp byte [path + rcx], '/'
    jne .check_exists
```


### 1.3 Syscall Comments

Every syscall **must** have a block comment above it with two parts:
1. A plain-English description of what it does
2. The function signature it maps to

**Example:**
```assembly
; Write \n to stdout

; write(fd, buffer, buffer len)
mov rax 1         ; write
mov rdi, 1        ; stdout
mov rsi, newline
mov rdx, 1        ; 1 char

syscall
```

## 2. Macros

Macros are the primary abstraction unit in this codebase. Use them over duplicated inline code.

Every macro must have a header comment documenting its signature:

```assembly
; MACRO_NAME arg1, arg2
;   Brief description of what it does.
;   Args:
;     %1: what arg1 is
;     %2: what arg2 is
;   Returns:
;     rax = what it returns (if anything)
;   Clobbers: rax, rdi, rsi, ...
```

Always document clobbered registers. If a macro saves and restores registers, still list them.

## 3. Naming Conventions

**Labels** use `snake_case`. Local labels (scoped to a function) are prefixed with a dot:

```assembly
.check_exists:
.copy_docroot_done:
```

Macro-local labels use the `%%` prefix to avoid collisions at expansion time:

```assembly
%%loop:
%%done:
```

**Data labels** are `snake_case`. Constants defined with `equ` follow the same pattern and are placed immediately after the string they measure:

```assembly
log_fail_bind      db "Failed to bind to port", 0
log_fail_bind_len  equ $ - log_fail_bind - 1
```

**Macro names** are `SCREAMING_SNAKE_CASE`.


## 4. File Structure

Each file is scoped to one responsibility (e.g. `fileutils.asm`, `logutils.asm`). Files follow this layout order: `section .data` -> `section .bss` -> `section .text`.

Macros live in `macros/`. Labels (callable procedures using `call`) live in `labels/`. Everything is included from `program.asm`. Nothing should be included from within another utility file.

## 5. Alignment

Repeating structures should be visually aligned by column when they appear in groups.
The same rule as inline comments applies: align to the longest entry + a few spaces.  
We recommend two spaces after the longest element as padding.

This applies to (non-exhaustive):

**definitions:**
```assembly
log_fail_bind      db "Failed to bind to port", 0
log_fail_bind_len  equ $ - log_fail_bind - 1
```

**`.bss` reservations:**
```assembly
port           resw 1    ; port number (host byte order)
max_conns      resb 1    ; max simultaneous connections (max 255)
document_root  resb 256  ; document root, no trailing slash
```

**Macro calls with many arguments:**
```assembly
ENV_DEFAULT env_path_buf, key_docroot, document_root, 256, default_docroot
ENV_DEFAULT env_path_buf, key_index,   index_file,    64,  default_index
ENV_DEFAULT env_path_buf, key_name,    server_name,   64,  default_name
```

**Lookup tables:**
```assembly
dq mime_ext_html,  mime_type_html
dq mime_ext_htm,   mime_type_html
dq mime_ext_css,   mime_type_css
```

## 6. Commits
For the moment, no mandatory commit structure is required. Simply describe what you changed as clearly as you can, and prefer one commit per file.  
Garbage commits (e.g. `sadasf`) **won't** be merged.
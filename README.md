# NASMServer

A HTTP/1.0 static file server written in [NetWide Assembler](https://nasm.us/), by [Douxx](https://douxx.tech).  
Read the [blog article](https://aka.dbo.one/nasmserver)!

> [!CAUTION]
> **Educational project**: This server likely has more security flaws than there are stars in the universe. It is **not recommended for production use**. Use it to learn, experiment, or have fun.

## How it started

I started learning NASM on a Monday afternoon, because I was bored in my NoSQL class. After a few self-made exercises (parsing args, string processing, etc.), I built a small HTTP client tool, imagine curl, but without the cool stuff. Then during my blockchain class, I started developing this server. The source grew from there.

## What it supports

- HTTP/1.0 `GET` and `HEAD` requests
- Static file serving with automatic MIME type detection (70+ types)
- Basic Authentication (`Authorization: Basic`)
- Custom error pages per status code (`400`, `401`, `403`, `404`, `405`)
- Configurable `Cache-Control` via `Max-Age` / `Expires` headers
- `Last-Modified` header based on file mtime
- Dotfile/dotfolder serving control
- Concurrent request handling via `fork()`
- Configurable `Server:` header
- Per-request logging with timestamps and client IPs
- Apache-HTTP-Server-like [combined-format](https://en.wikipedia.org/wiki/Common_Log_Format) logging
- Persistent request logging to file

## What it does NOT support

- HTTP/1.1 (keep-alive, chunked transfer, etc.). Responses are always `HTTP/1.0`
- HTTPS / TLS, use a reverse proxy (nginx, Caddy) or a Cloudflare tunnel in front
- Dynamic content: no CGI, no scripting, purely static
- CRLF line endings in `.env` files: use LF only
- Range requests (`Range: bytes=...`)
- Directory listing, directories without an index file return `403`
- Query string processing, `?foo=bar` is stripped and ignored since it's a static file host

## Usage (from a release)

Each release ships prebuilt bundles for different architectures. The bundles contain everything you need to run NASMServer, including the entry script `nasmserver`, an example config file `env.example`, and a default web directory `www/`.

```bash
# 1. Download and extract the release
wget https://github.com/douxxtech/nasmserver/releases/latest/download/nasmserver-linux-x64.zip
unzip nasmserver-linux-x64.zip -d nasmserver

# 2. Enter the directory
cd nasmserver

# 3. Read the instructions
cat instructions.txt

# 4. Copy the example config (optional)
cp env.example .env

# 5. Run it (defaults to port 8080, document root: ./www or current directory)
./nasmserver

# Pass a custom config file
./nasmserver -e /path/to/config.env

# See all supported flags
./nasmserver -h
```

> Ports below 1024 require root or `CAP_NET_BIND_SERVICE`. Either run with `sudo`, or set `PORT` to something above 1024 in your `.env`.

### CLI flags

| Flag | Description |
|---|---|
| `-h` | Show help and exit |
| `-v` | Show version and exit |
| `-e <path>` | Path to the `.env` config file to load |


## Install (from a release)

Each bundle includes an install script that sets up NASMServer system-wide. It can also be used to update an existing install without overwriting your config.

```bash
# Once inside the extracted bundle (see above)
./install
```

## Build from source

**Requirements:** `nasm` `binutils` `patchelf`

```bash
# Build the x86_64 binary only
bash buildasm.sh program.asm
# Output binary: ./program

# Build a full release bundle
bash .github/scripts/build-bundle.sh <x64|aarch64>
# Outputs: bundle-<arch>/ and nasmserver-linux-<arch>.zip
```

The entry point is `program.asm`. Macros and utilities live in `macros/`, labels in `labels/`.

## Configuration

Copy `env.example` to `.env` and edit as needed. All keys are optional and defaults apply if a key is missing or the file is not found.

| Key | Default | Description |
|---|---|---|
| `BIND_ADDRESS` | `0.0.0.0` | IPv4 address to bind to |
| `PORT` | `8080` | Port to listen on |
| `DOCUMENT_ROOT` | `.` | Document root directory, no trailing slash |
| `INDEX_FILE` | `index.html` | File served when a directory is requested |
| `LOG_FILE` | *(empty)* | File to write request logs instead of STDOUT |
| `LOG_LEVEL` | `info` | Log verbosity level |
| `MAX_AGE` | `600` | Cache expiry offset in seconds for the `Expires:` header. Sets `Pragma: no-cache` if `0` |
| `AUTH_USER` | *(empty)* | Username for Basic Authentication. Authentication is only enabled when this is set |
| `AUTH_PASSWORD` | *(empty)* | Password for Basic Authentication. |
| `AUTH_REALM` | `None` | Realm for Basic Authentication. |
| `SERVE_DOTS` | `false` | Whether `.dotfiles` and `.dotfolders/` should be served |
| `MAX_REQUESTS` | `20` | Max simultaneous connections (1–65535) |
| `SERVER_NAME` | `NASMServer/ver` | Value for the `Server:` response header |
| `USE_X_REAL_IP` | `false` | Use the `X-Real-IP` header for logging instead of the remote socket address |
| `ERRORDOC_400` | *(empty)* | Error page path, relative to `DOCUMENT_ROOT`, must start with `/` |
| `ERRORDOC_401` | *(empty)* | Same, for 401 |
| `ERRORDOC_403` | *(empty)* | Same, for 403 |
| `ERRORDOC_404` | *(empty)* | Same, for 404 |
| `ERRORDOC_405` | *(empty)* | Same, for 405 |
| `USE_CHROOT` | `true` | Chroot into `DOCUMENT_ROOT` at startup for filesystem isolation. Only applies when running as root |
| `DROP_PRIVILEGES` | `true` | Drop to `nobody` (uid 65534) after startup. Only applies when running as root |

If an `ERRORDOC_*` is left empty, the server sends headers only with no body for that error. Nonexistent errordoc files produce a startup warning but are not fatal.

## Dev notes

- The server uses `fork()` per connection, so no threads, no event loop. Each child handles exactly one request, then exits.
- Zombie reaping happens at the top of the `accept()` loop, so zombies linger until the next incoming connection.
- Concurrent connections are capped by `MAX_REQUESTS`. If the limit is hit, the connection is dropped and a warning is logged.
- The request buffer is 8 KB. Requests larger than that are truncated.
- Path traversal (`..`) is blocked in the path parser. Dotfile access is blocked by default unless `SERVE_DOTS=true`.
- Startup checks validate `DOCUMENT_ROOT` existence and permissions, and warn on missing errordoc files. A bad `DOCUMENT_ROOT` is fatal.
- No CRLF support in `.env` files, be sure to use LF line endings only.

## Notes

- HTTP/1.0 only, no TLS (HTTPS can be handled upstream via a reverse proxy or Cloudflare tunnel)
- Bugs, errors, or issues? Open an [issue](https://github.com/douxxtech/nasmserver/issues/new/)

See `LICENSE` for usage terms.
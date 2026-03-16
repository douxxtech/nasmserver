# NASMServer

An HTTP/1.0 server written in [NetWide Assembler](https://nasm.us/), by [Douxx](https://douxx.tech).  
Read the [blog article](https://aka.dbo.one/nasmserver)!

> [!CAUTION] 
> **Educational project**: This server likely has more security flaws than there are stars in the universe. It is **not recommended for production use**. Use it to learn, experiment, or have fun.

## How it started

I started learning NASM on a Monday afternoon, because I was bored in my NoSQL class. After a few self-made exercises (parsing args, string processing, etc.), I built a small HTTP client tool, imagine curl, but without the cool stuff. Then during my blockchain class, I started developing this server. The source grew from there.

## Install (from a release)

Each release ships a prebuilt `nasmserver` binary, a `www.zip` containing the default web directory structure and a `env.example` containing the default configuration.

```bash
# 1. Download and extract the release files
unzip www.zip

# 2. Make the binary executable
chmod +x nasmserver

# 3. Copy your .env (optional, see Configuration)
cp env.example .env

# 4. Run it (defaults to port 80, document root: ./www)
./nasmserver

# Or pass a custom config file as argv[1]
./nasmserver /path/to/config.env
```

> Ports below 1024 (including the default port 80) require root or `CAP_NET_BIND_SERVICE`. Either run with `sudo`, or set `PORT` to something above 1024 in your `.env`.


## Build from source

**Requirements:** `nasm` `binutils`

```bash
bash buildasm.sh program.asm
```

Expected output:

```
Built executable: program
```

The entry file is `program.asm`. Macros and utilities live in `macros/`, labels in `labels/`.

## Configuration

Copy `env.example` to `.env` and edit as needed. All keys are optional, and defaults are used if a key is missing or the file is not found.

| Key | Default | Description |
|---|---|---|
| `PORT` | `80` | Port to listen on |
| `DOCUMENT_ROOT` | `.` | Document root directory, no trailing slash |
| `INDEX_FILE` | `index.html` | File served when a directory is requested |
| `MAX_REQUESTS` | `20` | Max simultaneous connections (1–255) |
| `SERVER_NAME` | `NASMServer/ver` | Value for the `Server:` response header |
| `ERRORDOC_400` | *(empty)* | Error page path, relative to `DOCUMENT_ROOT`, must start with `/` |
| `ERRORDOC_403` | *(empty)* | Same, for 403 |
| `ERRORDOC_404` | *(empty)* | Same, for 404 |
| `ERRORDOC_405` | *(empty)* | Same, for 405 |

If an `ERRORDOC_*` is left empty, the server sends headers only with no body for that error. Inexistent errordoc files produce a startup warning but are not fatal.

## Notes

- HTTP/1.0 only, no TLS (HTTPS can be handled upstream via a reverse proxy or Cloudflare tunnel)
- No CRLF support in `.env` files, so use LF line endings
- Bugs, errors, or issues? Open an [issue](https://github.com/douxxtech/nasmserver/issues/new/)

See `LICENSE` for usage terms.
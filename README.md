# NASMServer

An HTTP/1.0 server written in [NetWide Assembler](https://nasm.us/), by [Douxx](https://douxx.tech).  
Read the [blog article](https://aka.dbo.one/nasmserver)!

> [!CAUTION] 
> **Educational project**: This server likely has more security flaws than there are stars in the universe. It is **not recommended for production use**. Use it to learn, experiment, or have fun.

## How it started

I started learning NASM on a Monday afternoon, because I was bored in my NoSQL class. After a few self-made exercises (parsing args, string processing, etc.), I built a small HTTP client tool, imagine curl, but without the cool stuff. Then during my blockchain class, I started developing this server. The source grew from there.

## Usage (from a release)

Each release ships prebuilt bundles for different architectures. The bundles contain everything you need to run NASMServer. This includes the entry script `nasmserver`, an example configuration file `env.example`, and a default web directory `www/`.

```bash
# 1. Download and extract the release files
wget https://github.com/douxxtech/nasmserver/releases/latest/download/nasmserver-linux-x64.zip
unzip nasmserver-linux-x64.zip -d nasmserver

# 2. Go in the extracted directory
cd nasmserver

# 3. Read the provided instructions.txt
cat instructions.txt

# 4. Copy your .env (optional, see Configuration)
cp env.example .env

# 5. Run it (defaults to port 8080, document root: ./www)
./nasmserver

# Or pass a custom config file as -e
./nasmserver -e /path/to/config.env

# See all the supported flags
./nasmserver -h
```

> Ports below 1024 (including the default port 8080) require root or `CAP_NET_BIND_SERVICE`. Either run with `sudo`, or set `PORT` to something above 1024 in your `.env`.


## Install (from a release)
Each bundle comes with an install script, that installs NASMServer on your operating system. It can also be used to update the current installation without overriding configs.

```bash
# once in the extracted bundle (see previous section)
./install
```

## Build from source

**Requirements:** `nasm` `binutils` `patchelf`

```bash
# to only build the x86_64 NASMServer binary
bash buildasm.sh program.asm
# output binary will be 'program'


# to build a specific bundle
bash .github/scripts/build-bindle.sh <x64|aarch64>
# this script outputs bundle-<arch>/ and nasmserver-linux-<arch>.zip
```

The entry file is `program.asm`. Macros and utilities live in `macros/`, labels in `labels/`.

## Configuration

Copy `env.example` to `.env` and edit as needed. All keys are optional, and defaults are used if a key is missing or the file is not found.

| Key | Default | Description |
|---|---|---|
| `PORT` | `8080` | Port to listen on |
| `DOCUMENT_ROOT` | `.` | Document root directory, no trailing slash |
| `INDEX_FILE` | `index.html` | File served when a directory is requested |
| `MAX_AGE` | `600` | Cache expiry offset in seconds for the `Expires:` header |
| `AUTH_USER` | *(empty)* | Username for Basic Authentication. If set, authentication is enabled |
| `AUTH_PASSWORD` | *(empty)* | Password for Basic Authentication. Only used if `AUTH_USER` is set |
| `MAX_REQUESTS` | `20` | Max simultaneous connections (1–255) |
| `SERVER_NAME` | `NASMServer/ver` | Value for the `Server:` response header |
| `ERRORDOC_400` | *(empty)* | Error page path, relative to `DOCUMENT_ROOT`, must start with `/` |
| `ERRORDOC_401` | *(empty)* | Same, for 401 |
| `ERRORDOC_403` | *(empty)* | Same, for 403 |
| `ERRORDOC_404` | *(empty)* | Same, for 404 |
| `ERRORDOC_405` | *(empty)* | Same, for 405 |

If an `ERRORDOC_*` is left empty, the server sends headers only with no body for that error. Inexistent errordoc files produce a startup warning but are not fatal.

## Notes

- HTTP/1.0 only, no TLS (HTTPS can be handled upstream via a reverse proxy or Cloudflare tunnel)
- No CRLF support in `.env` files, so use LF line endings
- Bugs, errors, or issues? Open an [issue](https://github.com/douxxtech/nasmserver/issues/new/)

See `LICENSE` for usage terms.
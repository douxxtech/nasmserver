# Running NASMServer with Docker

Docker is the easiest way to run [NASMServer](https://github.com/douxxtech/nasmserver) without building from source or managing dependencies.

## Quick start

```bash
docker run -p 8080:8080 douxxtech/nasmserver:latest
```

The server will be available at `http://localhost:8080`.

## Serving your own files

Mount a local directory as the web root:

```bash
docker run -p 8080:8080 -v /path/to/your/files:/var/www/html douxxtech/nasmserver:latest
```

## Custom configuration

Mount a custom `.env` config file and pass it with `-e`:

```bash
docker run -p 8080:8080 \
  -v /path/to/your/files:/var/www/html \
  -v /path/to/your/.env:/config.env \
  douxxtech/nasmserver:latest -e /config.env
```

See the [configuration section in the README](https://github.com/douxxtech/nasmserver/blob/main/README.md#configuration) for all available options.

> [!NOTE]
> `DOCUMENT_ROOT` is pre-set to `/var/www/html` in the Docker image. You don't need to set it in your config unless you're mounting files elsewhere.

## Specific versions

```bash
docker run -p 8080:8080 douxxtech/nasmserver:v1.14
```
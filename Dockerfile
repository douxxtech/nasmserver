FROM debian:trixie AS build-env
WORKDIR /build

COPY . .

# Install build dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    libc6 build-essential nasm patchelf zip git

# Build the x64 bundle
RUN bash .github/scripts/build-bundle.sh x64

# Create the config before installing so the install script doesn't override it
RUN mkdir -p /opt/nasmserver
RUN sed -e 's|DOCUMENT_ROOT=./www|DOCUMENT_ROOT=/var/www/html|' \
    ./.env.example > "/opt/nasmserver/config.cfg"

RUN cd bundle-x64 && ./install

# Use a slim image to keep the final image size minimal
FROM debian:trixie-slim
WORKDIR /opt/nasmserver

# Only copy the installed server files from the build stage
COPY --from=build-env /opt/nasmserver /opt/nasmserver
COPY --from=build-env /var/www/nasmserver /var/www/html

ENV PATH="/opt/nasmserver:$PATH"

EXPOSE 8080

ENTRYPOINT ["nasmserver"]
CMD []
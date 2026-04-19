#!/bin/bash
set -e

ARCH="$1"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <x64|aarch64>"
    exit 1
fi

BUNDLE_DIR="bundle-$ARCH"
mkdir -p "$BUNDLE_DIR/libs"

# build the program
chmod +x buildasm.sh
./buildasm.sh program.asm

# move the bin to the bundle
cp program "$BUNDLE_DIR/nasmserver-bin"

# move the base things
cp .env.example "$BUNDLE_DIR/.env.example"
cp -r www "$BUNDLE_DIR/www"
cp .github/bundle-files/"$ARCH"/* "$BUNDLE_DIR/"

if [ "$ARCH" = "x64" ]; then
    # move the libs
    cp /lib/x86_64-linux-gnu/libc.so.6 "$BUNDLE_DIR/libs/"
    cp /lib64/ld-linux-x86-64.so.2 "$BUNDLE_DIR/libs/"

    # patch the binary to use the provided libs
    patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath '$ORIGIN/libs' "$BUNDLE_DIR/nasmserver-bin"

elif [ "$ARCH" = "aarch64" ]; then
    # fetch the aarch64 build of qemu-x86_64-static
    curl -L "https://github.com/multiarch/qemu-user-static/releases/latest/download/qemu-x86_64-static.tar.gz" | tar xz

    # move the binaries to the bundle
    cp qemu-x86_64-static "$BUNDLE_DIR/"

    # move the libs
    mkdir -p "$BUNDLE_DIR/libs/lib/x86_64-linux-gnu"
    mkdir -p "$BUNDLE_DIR/libs/lib64"
    cp /lib/x86_64-linux-gnu/libc.so.6 "$BUNDLE_DIR/libs/lib/x86_64-linux-gnu/"
    cp /lib64/ld-linux-x86-64.so.2 "$BUNDLE_DIR/libs/lib64/"

    # patch the binary to use the provided libs
    patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath /lib/x86_64-linux-gnu "$BUNDLE_DIR/nasmserver-bin"

    # remove qemu from the working dir
    rm qemu-x86_64-static

else
    echo "Error: unknown arch '$ARCH'"
    exit 1
fi

# make scripts executable
chmod +x "$BUNDLE_DIR/nasmserver"
chmod +x "$BUNDLE_DIR/install"

cd "$BUNDLE_DIR" && zip -r "../nasmserver-linux-$ARCH.zip" .
echo "Bundle created: nasmserver-linux-$ARCH.zip"
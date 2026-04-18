#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: $0 <file.asm>"
  exit 1
fi

file="$1"
base="${file%.asm}"

nasm -f elf64 -o "$base.o" "$file"

ld -dynamic-linker /lib64/ld-linux-x86-64.so.2 -lc "$base.o" -o "$base"

strip --strip-unneeded "$base"

rm "$base.o"
echo "Built executable: $base"

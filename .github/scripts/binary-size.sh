#!/bin/bash

set -e

echo ">> Building program..."
bash buildasm.sh program.asm > /dev/null 2>&1

SIZE=$(stat -c%s program)
HUMAN=$(du -h program | cut -f1)

echo ""
echo "Binary ('program') size: $HUMAN ($SIZE bytes)"
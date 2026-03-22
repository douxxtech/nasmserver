#!/bin/bash

# Counts how much syscalls the server does to start + handle one GET request
# Usage: bash syscall-profile.sh [path]

set -e

REQUEST_PATH="${1:-/}"
PORT=18323
STRACE_OUT="/tmp/nasmserver-strace-$$.txt"

cleanup() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
    rm -f syscall-profile.cfg "$STRACE_OUT"
}
trap cleanup EXIT

echo ">> Building program..."
bash buildasm.sh program.asm > /dev/null 2>&1

cat > syscall-profile.cfg <<EOF
PORT=$PORT
DOCUMENT_ROOT=./www
EOF

echo ">> Starting server..."
strace -f -e trace=all -T -o "$STRACE_OUT" ./program -e syscall-profile.cfg > /dev/null 2>&1 &
PID=$!
sleep 1

curl -s --max-time 5 "http://127.0.0.1:$PORT$REQUEST_PATH" > /dev/null
sleep 0.5

kill "$PID" 2>/dev/null || true
PID=""
sleep 0.2

LINES=$(grep -vE '<unfinished|resumed|---|\+\+\+|signal' "$STRACE_OUT" || true)
TOTAL=$(echo "$LINES" | grep -cE '[a-z_]+\(' || true)

# each strace line looks like: "PID syscall_name(...) = ret <time>"
# extract "time name" pairs, then sort by time
TIME_NAME=$(echo "$LINES" | awk 'match($0, /<([0-9.]+)>$/) {time=substr($0,RSTART+1,RLENGTH-2); name=$2; sub(/\(.*/, "", name); print time, name}' | sort -n || true)  # (yea I didn't make this awk)

FASTEST=$(echo "$TIME_NAME" | head -1 || true)
SLOWEST=$(echo "$TIME_NAME" | tail -1 || true)

echo ""
echo "START + GET $REQUEST_PATH: $TOTAL syscalls"
echo "Fastest: $(echo $FASTEST | awk '{print $1}')s ($(echo $FASTEST | awk '{print $2}'))"
echo "Slowest: $(echo $SLOWEST | awk '{print $1}')s ($(echo $SLOWEST | awk '{print $2}'))"

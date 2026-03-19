#!/bin/bash
set -e

BINARY="./program"
CFG="benchmark.cfg"
PID=""
CORES=$(nproc)
MAX_LEVELS="${1:-3}"

cleanup() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
    rm -f "$BINARY" "$CFG"
}
trap cleanup EXIT

# build the program
echo ">> Building program..."
if ! (bash buildasm.sh program.asm > /dev/null 2>&1 && [ -f program ]); then
    fail "Build failed"
    exit 1
fi


# config
cat > "$CFG" <<EOF
DOCUMENT_ROOT=./www
MAX_REQUESTS=65565
EOF

# start server
echo ">> Starting server..."
"$BINARY" -e "$CFG" >/dev/null 2>&1 &
PID=$!

# watch for unexpected exit
watch_server() {
    wait "$PID" 2>/dev/null
    [ -n "$PID" ] && echo "[!] server exited unexpectedly, aborting." >&2 && exit 1
}
watch_server &
WATCH_PID=$!

sleep 1

# collect server-side stats around a wrk run
run_bench() {
    local level=$1 conns=$2 duration=$3 outfile=$4
    local threads=$CORES

    echo ">> Level $level: ${threads}t / ${conns}c / ${duration}s..."

    # server-side: snapshot before
    local cpu_before mem_before fd_before
    cpu_before=$(ps -p "$PID" -o %cpu= 2>/dev/null | xargs)
    mem_before=$(ps -p "$PID" -o rss=  2>/dev/null | xargs)
    fd_before=$(ls /proc/"$PID"/fd 2>/dev/null | wc -l)
    threads_before=$(ls /proc/"$PID"/task 2>/dev/null | wc -l)

    # run wrk
    local wrk_out
    wrk_out=$(wrk -t"$threads" -c"$conns" -d"${duration}s" http://127.0.0.1:8080/ 2>&1)

    # server-side: snapshot after
    local cpu_after mem_after fd_after
    cpu_after=$(ps -p "$PID" -o %cpu= 2>/dev/null | xargs)
    mem_after=$(ps -p "$PID" -o rss=  2>/dev/null | xargs)
    fd_after=$(ls /proc/"$PID"/fd 2>/dev/null | wc -l)
    threads_after=$(ls /proc/"$PID"/task 2>/dev/null | wc -l)

    {
        echo "threads: $threads (auto), conns: $conns, duration: ${duration}s"
        echo ""
        echo "[server]"
        echo "cpu before/after:  ${cpu_before}% / ${cpu_after}%"
        echo "mem before/after:  ${mem_before}kB / ${mem_after}kB"
        echo "open fds before/after: ${fd_before} / ${fd_after}"
        echo "threads before/after:  ${threads_before} / ${threads_after}"
        echo ""
        echo "[wrk]"
        echo "$wrk_out"
    } > "$outfile"
}

[ "$MAX_LEVELS" -ge 1 ] && run_bench 1 50 20 bm1.txt
[ "$MAX_LEVELS" -ge 2 ] && run_bench 2 200 30 bm2.txt
[ "$MAX_LEVELS" -ge 3 ] && run_bench 3 500 45 bm3.txt

# stop server
kill "$WATCH_PID" 2>/dev/null || true
kill "$PID" 2>/dev/null || true
PID=""
wait 2>/dev/null || true

# print results
echo ""
echo "================================"
echo "  Benchmark results"
echo "================================"
for i in $(seq 1 "$MAX_LEVELS"); do
    echo ""
    echo "-- Level $i --"
    cat "bm${i}.txt"
done
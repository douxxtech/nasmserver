#!/bin/bash
# This file tests the program, returns 0 on correct behavior, 1 on failure.

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; echo ""; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; echo ""; FAIL=$((FAIL + 1)); }

cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    rm -f test-env.cfg
    rm -rf pppIMD
    rm -f program
}
trap cleanup EXIT

# build the program
echo ">> Building program..."
if bash buildasm.sh program.asm > /dev/null 2>&1 && [ -f program ]; then
    pass "Build succeeded"

else
    fail "Build failed"
    exit 1
fi

# setup files
cat > test-env.cfg <<EOF
DOCUMENT_ROOT=./pppIMD
INDEX_FILE=hello.txt
PORT=80
EOF

mkdir -p pppIMD
echo "Hii :3" > pppIMD/hello.txt

# test 2
echo ">> Running on port 80 (should fail)..."
./program -e test-env.cfg > /dev/null 2>&1

if [ $? -ne 0 ]; then
    pass "Correctly exited with error on port 80"
else
    fail "Expected failure on port 80, but it succeeded"
fi

# switch to port 8080
sed -i 's/PORT=80/PORT=8080/' test-env.cfg

# test 3
echo ">> Running on port 8080..."
./program -e test-env.cfg > /dev/null 2>&1 &
SERVER_PID=$!
sleep 1

if kill -0 "$SERVER_PID" 2>/dev/null; then
    pass "Server is running on port 8080"
else
    fail "Server exited unexpectedly on port 8080"
    exit 1
fi

# test 4
echo ">> Curling localhost:8080..."
RESPONSE=$(curl -s localhost:8080)
if echo "$RESPONSE" | grep -q "Hii :3"; then
    pass "curl returned expected content"
else
    fail "curl response did not contain expected content (got: $RESPONSE)"
fi

# Setup Auth in config
echo "AUTH_USER=admin" >> test-env.cfg
echo "AUTH_PASSWORD=password123" >> test-env.cfg
echo "AUTH_REALM=TestRealm" >> test-env.cfg

kill "$SERVER_PID" 2>/dev/null
./program -e test-env.cfg > /dev/null 2>&1 &
SERVER_PID=$!
sleep 1

# test 5
echo ">> Testing unauthorized access (expecting 401)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" localhost:8080)

if [ "$HTTP_STATUS" -eq 401 ]; then
    pass "Correctly returned 401 Unauthorized"
else
    fail "Expected 401, but got $HTTP_STATUS"
fi

# test 6
echo ">> Testing authorized access (expecting 200)..."
# Using -u for Basic Auth
HTTP_STATUS=$(curl -s -u admin:password123 -o /dev/null -w "%{http_code}" localhost:8080)

if [ "$HTTP_STATUS" -eq 200 ]; then
    pass "Correctly returned 200 OK with valid credentials"
else
    fail "Expected 200, but got $HTTP_STATUS"
fi

# summary
echo ""
echo "================================"
echo "  Tests passed : $PASS"
echo "  Tests failed : $FAIL"
echo "================================"

[ $FAIL -eq 0 ] && exit 0 || exit 1
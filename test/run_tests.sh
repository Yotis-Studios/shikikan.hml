#!/bin/bash
# Run all test files separately (workaround for hemlock testing framework 5-test limit)
#
#   bash test/run_tests.sh              every suite on the interpreter
#   bash test/run_tests.sh --compiled   every suite built with hemlockc and run as a binary --
#                                       production runs the compiled server, so this is the
#                                       run that counts before a release
set -e
cd "$(dirname "$0")/.."

COMPILED=0
[ "${1:-}" = "--compiled" ] && COMPILED=1
BIN=$(mktemp -d)
trap 'rm -rf "$BIN"' EXIT

PASS=0
FAIL=0

for f in test/*_test.hml; do
    echo "=== $f ==="
    if [ $COMPILED = 1 ]; then
        b="$BIN/$(basename "$f" .hml)"
        if hemlockc "$f" -o "$b" && "$b"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    elif hemlock "$f"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

echo "=== Test Suites ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

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
FAILED_SUITES=""

# A suite fails when it exits non-zero OR reports a failed test. @stdlib/testing's run() prints
# "Failed: N" and RETURNS -- it never sets the exit code -- so a describe/test suite with failing
# tests used to count as passed here.
OUT="$BIN/out.txt"
for f in test/*_test.hml; do
    echo "=== $f ==="
    ok=0
    if [ $COMPILED = 1 ]; then
        b="$BIN/$(basename "$f" .hml)"
        if hemlockc "$f" -o "$b" && "$b" 2>&1 | tee "$OUT" && [ "${PIPESTATUS[0]}" = 0 ]; then ok=1; fi
    elif hemlock "$f" 2>&1 | tee "$OUT" && [ "${PIPESTATUS[0]}" = 0 ]; then
        ok=1
    fi
    if [ $ok = 1 ] && sed 's/\x1b\[[0-9;]*m//g' "$OUT" | grep -qE 'Failed: [1-9]|[1-9][0-9]* failed'; then ok=0; fi
    if [ $ok = 1 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_SUITES="$FAILED_SUITES $f"
        echo "*** FAILED: $f"
    fi
    : > "$OUT"
    echo ""
done

echo "=== Test Suites ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL$FAILED_SUITES"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

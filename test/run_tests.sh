#!/bin/bash
# Run all test files separately (workaround for hemlock testing framework 5-test limit)
set -e
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

for f in test/*_test.hml; do
    echo "=== $f ==="
    if hemlock "$f"; then
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

#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
fail=0
for t in "$SCRIPT_DIR"/test_*.sh; do
  echo "=== $(basename "$t") ==="
  bash "$t" || { echo "FAIL: $t"; fail=$((fail+1)); }
done
if [[ $fail -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$fail test(s) FAILED"
  exit 1
fi

#!/usr/bin/env bash
# Run all .github/scripts/ fixture tests sequentially. Exits non-zero on
# first failure. Run from repo root via `bash .github/scripts/test/run-all.sh`.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
FAIL=0

for t in "$DIR"/test-*.sh; do
  echo "=== $(basename "$t") ==="
  if ! bash "$t"; then
    FAIL=1
  fi
  echo ""
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL FIXTURE TESTS PASS"
else
  echo "ONE OR MORE FIXTURE TESTS FAILED"
  exit 1
fi

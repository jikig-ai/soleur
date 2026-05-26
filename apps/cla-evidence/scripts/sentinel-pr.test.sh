#!/usr/bin/env bash
# sentinel-pr.test.sh - dry-run unit tests for sentinel-pr.sh.
#
# All paths use SENTINEL_DRY_RUN=1 so no real PRs are opened. Exercises:
#   TS-A: missing mode arg → exit 64
#   TS-B: unknown mode → exit 64
#   TS-C: dry-run human mode → exit 0
#   TS-D: dry-run bypass mode → exit 0
#   TS-E: dry-run both mode → exit 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sentinel-pr.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

fail=0

# TS-A: missing mode arg
set +e
SENTINEL_DRY_RUN=1 bash "$SUT" </dev/null >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 64 ]]; then
  green "PASS: TS-A missing mode arg → exit 64"
else
  red "FAIL: TS-A expected exit 64, got $rc"
  fail=1
fi

# TS-B: unknown mode
set +e
SENTINEL_DRY_RUN=1 bash "$SUT" not-a-mode >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 64 ]]; then
  green "PASS: TS-B unknown mode → exit 64"
else
  red "FAIL: TS-B expected exit 64, got $rc"
  fail=1
fi

# TS-C: dry-run human mode
set +e
SENTINEL_DRY_RUN=1 bash "$SUT" human >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  green "PASS: TS-C dry-run human → exit 0"
else
  red "FAIL: TS-C expected exit 0, got $rc"
  fail=1
fi

# TS-D: dry-run bypass mode
set +e
SENTINEL_DRY_RUN=1 bash "$SUT" bypass >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  green "PASS: TS-D dry-run bypass → exit 0"
else
  red "FAIL: TS-D expected exit 0, got $rc"
  fail=1
fi

# TS-E: dry-run both mode
set +e
SENTINEL_DRY_RUN=1 bash "$SUT" both >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  green "PASS: TS-E dry-run both → exit 0"
else
  red "FAIL: TS-E expected exit 0, got $rc"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL sentinel-pr.test.sh tests passed."
fi
exit "$fail"

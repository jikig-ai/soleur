#!/usr/bin/env bash
# Tests for _r2-endpoint.sh — canonical R2 endpoint hostname pin (issue #3950
# item 1). assert_r2_endpoint hard-exits 64 with a ::error:: annotation when the
# endpoint is not a canonical `https://<32-hex>.r2.cloudflarestorage.com[/]`.
# RED-first per cq-write-failing-tests-before. No network IO — pure regex gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/_r2-endpoint.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -r "$HELPER" ]]; then
  red "FAIL: $HELPER does not exist (RED phase expected output)."
  exit 1
fi

# shellcheck source=_r2-endpoint.sh disable=SC1091
source "$HELPER"

fail=0

# assert_r2_endpoint <url> runs in a subshell so its `exit 64` does not abort
# the test; capture stderr + the subshell rc.
check() {
  local url="$1" outfile
  outfile=$(mktemp)
  ( assert_r2_endpoint "$url" ) >"$outfile" 2>&1
  local rc=$?
  printf '%s\t%s' "$rc" "$(cat "$outfile")"
  rm -f "$outfile"
}

expect_ok() {
  local label="$1" url="$2" res rc
  res=$(check "$url"); rc=${res%%	*}
  if [[ "$rc" -eq 0 ]]; then
    green "PASS: $label ($url → exit 0)"
  else
    red "FAIL: $label expected exit 0, got rc=$rc for $url"; fail=1
  fi
}

expect_reject() {
  local label="$1" url="$2" res rc body
  res=$(check "$url"); rc=${res%%	*}; body=${res#*	}
  if [[ "$rc" -eq 64 ]] && grep -qE '::error::.*canonical R2 hostname' <<<"$body"; then
    green "PASS: $label ($url → exit 64 + ::error::)"
  else
    red "FAIL: $label expected exit 64 + ::error::canonical R2 hostname; got rc=$rc body=$body for $url"; fail=1
  fi
}

# ── Canonical (accept) ──────────────────────────────────────────────────────
expect_ok   "TS6 prod endpoint shape"        "https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com"
expect_ok   "TS6 trailing slash allowed"     "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com/"
expect_ok   "TS6 synthetic 32-hex"           "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com"

# ── Malformed (reject, exit 64) ─────────────────────────────────────────────
expect_reject "TS7 attacker sink host"       "https://evil.example.com"
expect_reject "TS7 wrong R2 path host"       "https://evil.r2.cloudflarestorage.com.attacker.test"
expect_reject "TS7 non-https scheme"         "http://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com"
expect_reject "TS7 short account id (<32)"   "https://0123456789abcdef.r2.cloudflarestorage.com"
expect_reject "TS7 uppercase hex"            "https://0123456789ABCDEF0123456789ABCDEF.r2.cloudflarestorage.com"
expect_reject "TS7 empty string"             ""

if [[ "$fail" -eq 0 ]]; then
  green "ALL _r2-endpoint.sh tests passed."
fi
exit "$fail"

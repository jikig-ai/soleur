#!/usr/bin/env bash
# test-content-publisher-stale-alert.sh -- Unit and integration tests for the
# stale-content alert path in content-publisher.sh.
#
# Sources the production script (guarded by BASH_SOURCE) to test real code.
# Verifies:
#   - emit_stale_event writes TSV lines to $STALE_EVENTS_FILE
#   - emit_stale_event no-ops (with stderr warning) when STALE_EVENTS_FILE unset
#   - stale detection in main() emits to file, does NOT call curl (no Discord)
#   - file frontmatter transitions to status: stale (exact post-state)
#   - second run is idempotent (no duplicate emit lines)
#
# Usage: bash scripts/test-content-publisher-stale-alert.sh
#   Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Unset third-party credential envs so main() skips publishing branches.
unset DISCORD_WEBHOOK_URL DISCORD_BLOG_WEBHOOK_URL \
      X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET \
      LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN LINKEDIN_ORG_ID \
      BSKY_HANDLE BSKY_APP_PASSWORD BSKY_ALLOW_POST \
      GH_TOKEN || true

# shellcheck source=content-publisher.sh
source "$SCRIPT_DIR/content-publisher.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label}: expected '${expected}', got '${actual}'" >&2
  fi
}

# Flag file that any stubbed curl writes to. Non-empty = curl was invoked.
CURL_FLAG_FILE="$(mktemp)"
curl() {
  echo "curl-invoked: $*" >> "$CURL_FLAG_FILE"
  return 0
}

make_fixture_dir() {
  local dir
  dir=$(mktemp -d)
  cat > "$dir/stale-test.md" <<'EOF'
---
status: scheduled
publish_date: 2020-01-01
channels: discord
title: Test stale file
---

# Body
EOF
  echo "$dir"
}

# ============================================================
# Unit tests: emit_stale_event
# ============================================================

echo "--- emit_stale_event unit tests ---"

# TSV line written when STALE_EVENTS_FILE is set
tmp_events=$(mktemp)
STALE_EVENTS_FILE="$tmp_events" emit_stale_event "/fake/path/foo.md" "2026-04-21" >/dev/null 2>&1
assert_eq "emit-writes-one-line" "1" "$(wc -l < "$tmp_events" | tr -d ' ')"
assert_eq "emit-writes-tsv-content" "$(printf 'foo.md\t2026-04-21')" "$(cat "$tmp_events")"
rm -f "$tmp_events"

# No-op + stderr warning when STALE_EVENTS_FILE is unset
tmp_stderr=$(mktemp)
if (unset STALE_EVENTS_FILE; emit_stale_event "/fake/path/foo.md" "2026-04-21") 2>"$tmp_stderr"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: emit-no-op-returns-zero: expected success exit" >&2
fi
if grep -q "STALE_EVENTS_FILE" "$tmp_stderr"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: emit-no-op-stderr-warning: expected 'STALE_EVENTS_FILE' token in stderr, got: $(cat "$tmp_stderr")" >&2
fi
rm -f "$tmp_stderr"

# Append semantics: two calls produce two lines
tmp_events=$(mktemp)
STALE_EVENTS_FILE="$tmp_events" emit_stale_event "/x/a.md" "2026-04-20" >/dev/null 2>&1
STALE_EVENTS_FILE="$tmp_events" emit_stale_event "/x/b.md" "2026-04-21" >/dev/null 2>&1
assert_eq "emit-append-two-lines" "2" "$(wc -l < "$tmp_events" | tr -d ' ')"
rm -f "$tmp_events"

# ============================================================
# Integration test: stale detection in main()
# ============================================================

echo "--- stale-detection integration test ---"

fixture=$(make_fixture_dir)
tmp_events=$(mktemp)
: > "$CURL_FLAG_FILE"

# First run: stale file should be emitted, transitioned to status: stale, NO curl.
( CONTENT_DIR="$fixture" STALE_EVENTS_FILE="$tmp_events" main ) >/dev/null 2>&1 || true

if [[ -s "$CURL_FLAG_FILE" ]]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: stale-no-discord-call: curl was invoked: $(cat "$CURL_FLAG_FILE")" >&2
else
  PASS=$((PASS + 1))
fi

assert_eq "stale-emit-one-entry" "1" "$(wc -l < "$tmp_events" | tr -d ' ')"

status=$(grep '^status:' "$fixture/stale-test.md" | sed 's/^status: *//')
assert_eq "stale-status-transitions-to-stale" "stale" "$status"

# Second run: idempotent -- file is now status: stale, no new emit line.
( CONTENT_DIR="$fixture" STALE_EVENTS_FILE="$tmp_events" main ) >/dev/null 2>&1 || true
assert_eq "stale-idempotent-still-one-entry" "1" "$(wc -l < "$tmp_events" | tr -d ' ')"

rm -rf "$fixture"
rm -f "$tmp_events" "$CURL_FLAG_FILE"

echo "---"
echo "PASS: $PASS  FAIL: $FAIL"
exit "$FAIL"

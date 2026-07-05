#!/usr/bin/env bash
# test-content-publisher.sh -- Unit and integration tests for content-publisher.sh.
#
# Sources the production script (guarded by BASH_SOURCE) to test real code.
# Covers two areas:
#
#  1. Stale-content alert path (emit_stale_event + main() stale detection):
#     - emit_stale_event writes TSV lines to $STALE_EVENTS_FILE
#     - emit_stale_event no-ops (with stderr warning) when STALE_EVENTS_FILE unset
#     - stale detection in main() emits to file, does NOT call curl (no Discord)
#     - file frontmatter transitions to status: stale (exact post-state)
#     - second run is idempotent (no duplicate emit lines)
#
#  2. Skip sentinel (#6065): every per-channel skip path returns 3 ("skipped,
#     not attempted") instead of 0 ("posted"), the caller counts skips
#     separately, and a file whose channels were ALL skipped stays
#     status: scheduled (NOT published) and surfaces a dedup "Published nowhere"
#     issue whose body enumerates the per-channel skip reason.
#
# Usage: bash scripts/test-content-publisher.sh
#   Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Unset third-party credential envs so main() skips publishing branches.
unset DISCORD_WEBHOOK_URL DISCORD_BLOG_WEBHOOK_URL \
      X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET \
      LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN LINKEDIN_ORG_ID \
      LINKEDIN_ORG_ACCESS_TOKEN LINKEDIN_ALLOW_POST \
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

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label}: expected to contain '${needle}', got '${haystack}'" >&2
  fi
}

# rc helper: run a command with `set -e` suppressed and echo its exit code.
rc_of() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# Flag file that any stubbed curl writes to. Non-empty = curl was invoked.
CURL_FLAG_FILE="$(mktemp)"
curl() {
  echo "curl-invoked: $*" >> "$CURL_FLAG_FILE"
  # Emit an HTTP 2xx code to stdout so post_discord's `-w "%{http_code}"`
  # capture sees success. The real curl writes the body to -o <file>; the
  # stub leaves it empty (fine — success path does not read it).
  echo "200"
  return 0
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

make_stale_fixture_dir() {
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

fixture=$(make_stale_fixture_dir)
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
rm -f "$tmp_events"

# ============================================================
# Unit tests: skip sentinel — each skip path returns 3 (#6065)
# ============================================================

echo "--- skip-sentinel unit tests (rc 3) ---"

# A fixture file with every section present, so skips are driven by env/gate
# state (missing creds / gate off) rather than absent content.
make_full_fixture() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
---
status: scheduled
publish_date: 2099-01-01
channels: discord
title: Full fixture
---

## Discord

Discord body text.

## X/Twitter Thread

Hook tweet body.

## LinkedIn Personal

LinkedIn personal body.

## LinkedIn Company Page

LinkedIn company body.

## Bluesky

Bluesky body.
EOF
  echo "$f"
}

# A fixture file with NO channel-body sections (all extract_section → empty),
# to drive the empty-section skip paths.
make_empty_sections_fixture() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
---
status: scheduled
publish_date: 2099-01-01
channels: discord
title: Empty sections fixture
---

# Body with no channel sections
EOF
  echo "$f"
}

full_fixture=$(make_full_fixture)
empty_fixture=$(make_empty_sections_fixture)

# Discord: no webhook → rc 3
assert_eq "discord-no-webhook-rc3" "3" \
  "$(unset DISCORD_WEBHOOK_URL DISCORD_BLOG_WEBHOOK_URL; rc_of post_discord "body")"

# Discord: webhook set + stubbed curl 2xx → rc 0 (success not mislabelled skip)
assert_eq "discord-success-rc0" "0" \
  "$(DISCORD_WEBHOOK_URL="https://example.test/hook" rc_of post_discord "body")"

# X: no creds → rc 3
assert_eq "x-no-creds-rc3" "3" \
  "$(unset X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET; rc_of post_x_thread "$full_fixture")"

# X: creds set but empty thread section → rc 3
assert_eq "x-empty-thread-rc3" "3" \
  "$(X_API_KEY=k X_API_SECRET=s X_ACCESS_TOKEN=t X_ACCESS_TOKEN_SECRET=ts; export X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET; rc_of post_x_thread "$empty_fixture")"

# LinkedIn personal: no token → rc 3
assert_eq "linkedin-no-token-rc3" "3" \
  "$(unset LINKEDIN_ACCESS_TOKEN; rc_of post_linkedin "$full_fixture" "LinkedIn Personal")"

# LinkedIn personal: token set + empty section → rc 3
assert_eq "linkedin-empty-section-rc3" "3" \
  "$(LINKEDIN_ACCESS_TOKEN=tok rc_of post_linkedin "$empty_fixture" "LinkedIn Personal")"

# LinkedIn company: no org token (tracker-route, stub the tracker append) → rc 3
append_to_linkedin_tracker() { return 0; }  # stub so no gh call
assert_eq "linkedin-company-no-org-token-rc3" "3" \
  "$(unset LINKEDIN_ORG_ACCESS_TOKEN; rc_of post_linkedin_company "$full_fixture")"

# LinkedIn company: org token set + LINKEDIN_ORG_ID unset → rc 3
assert_eq "linkedin-company-no-org-id-rc3" "3" \
  "$(LINKEDIN_ORG_ACCESS_TOKEN=tok; export LINKEDIN_ORG_ACCESS_TOKEN; unset LINKEDIN_ORG_ID; rc_of post_linkedin_company "$full_fixture")"

# LinkedIn company: org token + org id set + LINKEDIN_ALLOW_POST unset (gate off) → rc 3
assert_eq "linkedin-company-gate-off-rc3" "3" \
  "$(LINKEDIN_ORG_ACCESS_TOKEN=tok LINKEDIN_ORG_ID=123; export LINKEDIN_ORG_ACCESS_TOKEN LINKEDIN_ORG_ID; unset LINKEDIN_ALLOW_POST; rc_of post_linkedin_company "$full_fixture")"

# LinkedIn company: all gates on + empty section → rc 3
assert_eq "linkedin-company-empty-section-rc3" "3" \
  "$(LINKEDIN_ORG_ACCESS_TOKEN=tok LINKEDIN_ORG_ID=123 LINKEDIN_ALLOW_POST=true; export LINKEDIN_ORG_ACCESS_TOKEN LINKEDIN_ORG_ID LINKEDIN_ALLOW_POST; rc_of post_linkedin_company "$empty_fixture")"

# Bluesky: no creds → rc 3
assert_eq "bluesky-no-creds-rc3" "3" \
  "$(unset BSKY_HANDLE BSKY_APP_PASSWORD; rc_of post_bluesky "$full_fixture")"

# Bluesky: creds set + BSKY_ALLOW_POST unset (gate off) → rc 3
assert_eq "bluesky-gate-off-rc3" "3" \
  "$(BSKY_HANDLE=h BSKY_APP_PASSWORD=p; export BSKY_HANDLE BSKY_APP_PASSWORD; unset BSKY_ALLOW_POST; rc_of post_bluesky "$full_fixture")"

# Bluesky: creds + gate on + empty section → rc 3
assert_eq "bluesky-empty-section-rc3" "3" \
  "$(BSKY_HANDLE=h BSKY_APP_PASSWORD=p BSKY_ALLOW_POST=true; export BSKY_HANDLE BSKY_APP_PASSWORD BSKY_ALLOW_POST; rc_of post_bluesky "$empty_fixture")"

rm -f "$full_fixture" "$empty_fixture"

# ============================================================
# Integration tests: main() skip-sentinel decision block (#6065)
# ============================================================

echo "--- skip-sentinel integration tests ---"

# Stub the issue-creation seam so main() never touches gh/network. Records
# each call's (title, body, labels) so tests can assert on them.
NOWHERE_FLAG_FILE="$(mktemp)"
create_dedup_issue() {
  # $1=title $2=body $3=labels
  {
    echo "TITLE=$1"
    echo "LABELS=$3"
    echo "BODY<<END"
    echo "$2"
    echo "END"
  } >> "$NOWHERE_FLAG_FILE"
  return 0
}

TODAY="$(date +%Y-%m-%d)"

# Build a single-file fixture dir with a given channels list + section bodies.
# Usage: make_pub_fixture <channels> <extra-body>
make_pub_fixture() {
  local channels="$1" body="$2" dir
  dir=$(mktemp -d)
  cat > "$dir/pub-test.md" <<EOF
---
status: scheduled
publish_date: ${TODAY}
channels: ${channels}
title: Pub Test Case
---

${body}
EOF
  echo "$dir"
}

status_of() { grep '^status:' "$1/pub-test.md" | sed 's/^status: *//'; }

# --- Regression (the bug): all-skip stays scheduled + "Published nowhere" issue ---
: > "$NOWHERE_FLAG_FILE"; : > "$CURL_FLAG_FILE"
fx=$(make_pub_fixture "discord" "## Discord

Discord body.")
rc=0
( unset DISCORD_WEBHOOK_URL DISCORD_BLOG_WEBHOOK_URL
  CONTENT_DIR="$fx" main ) >/dev/null 2>&1 || rc=$?
assert_eq "allskip-exit-0" "0" "$rc"
assert_eq "allskip-stays-scheduled" "scheduled" "$(status_of "$fx")"
assert_contains "allskip-nowhere-issue-title" "$(cat "$NOWHERE_FLAG_FILE")" "Published nowhere"
assert_contains "allskip-nowhere-issue-labels" "$(cat "$NOWHERE_FLAG_FILE")" "action-required,content-publisher"
rm -rf "$fx"

# --- Reason discrimination: issue body enumerates per-channel skip reasons ---
: > "$NOWHERE_FLAG_FILE"
fx=$(make_pub_fixture "bluesky,linkedin-personal" "## Bluesky

Bluesky body.")
# Bluesky: no creds → "no credentials"; LinkedIn personal: token set but the
# "LinkedIn Personal" section is absent → "empty section".
( unset BSKY_HANDLE BSKY_APP_PASSWORD
  LINKEDIN_ACCESS_TOKEN=tok CONTENT_DIR="$fx" main ) >/dev/null 2>&1 || true
body_capture="$(cat "$NOWHERE_FLAG_FILE")"
assert_contains "reason-bluesky-no-creds" "$body_capture" "bluesky: no credentials"
assert_contains "reason-linkedin-empty-section" "$body_capture" "linkedin-personal: empty section"
rm -rf "$fx"

# --- Real success dominates: success + skip → published, no nowhere issue ---
: > "$NOWHERE_FLAG_FILE"; : > "$CURL_FLAG_FILE"
fx=$(make_pub_fixture "discord,bluesky" "## Discord

Discord body.

## Bluesky

Bluesky body.")
# Discord webhook set + stubbed curl 2xx → success; Bluesky no creds → skip.
( unset BSKY_HANDLE BSKY_APP_PASSWORD
  DISCORD_WEBHOOK_URL="https://example.test/hook" CONTENT_DIR="$fx" main ) >/dev/null 2>&1 || true
assert_eq "success-dominates-published" "published" "$(status_of "$fx")"
if grep -q "Published nowhere" "$NOWHERE_FLAG_FILE"; then
  FAIL=$((FAIL + 1)); echo "FAIL: success-dominates-no-nowhere-issue: unexpected nowhere issue" >&2
else
  PASS=$((PASS + 1))
fi
rm -rf "$fx"

# --- Failure wins over skip (multi-channel 0/1/1): exit 2, fallback issue, no nowhere issue ---
: > "$NOWHERE_FLAG_FILE"; : > "$CURL_FLAG_FILE"
fx=$(make_pub_fixture "discord,bluesky" "## Discord

Discord body.

## Bluesky

Bluesky body.")
# Discord webhook set but stub curl to return an HTTP 500 → post_discord fails (rc 1);
# Bluesky no creds → skip (rc 3). No success → failures>0 wins.
curl() { echo "curl-invoked: $*" >> "$CURL_FLAG_FILE"; echo "500"; return 0; }
rc=0
( unset BSKY_HANDLE BSKY_APP_PASSWORD
  DISCORD_WEBHOOK_URL="https://example.test/hook" CONTENT_DIR="$fx" main ) >/dev/null 2>&1 || rc=$?
assert_eq "failure-wins-exit-2" "2" "$rc"
assert_eq "failure-wins-stays-scheduled" "scheduled" "$(status_of "$fx")"
if grep -q "Published nowhere" "$NOWHERE_FLAG_FILE"; then
  FAIL=$((FAIL + 1)); echo "FAIL: failure-wins-no-nowhere-issue: unexpected nowhere issue when a channel failed" >&2
else
  PASS=$((PASS + 1))
fi
# Restore the success-emitting curl stub for any later use.
curl() { echo "curl-invoked: $*" >> "$CURL_FLAG_FILE"; echo "200"; return 0; }
rm -rf "$fx"

# --- F1: degenerate channels list (`channels: ","`) surfaces nowhere issue ---
: > "$NOWHERE_FLAG_FILE"
fx=$(make_pub_fixture '","' "# Body")
rc=0
( CONTENT_DIR="$fx" main ) >/dev/null 2>&1 || rc=$?
assert_eq "f1-empty-token-exit-0" "0" "$rc"
assert_eq "f1-empty-token-stays-scheduled" "scheduled" "$(status_of "$fx")"
assert_contains "f1-empty-token-nowhere-issue" "$(cat "$NOWHERE_FLAG_FILE")" "Published nowhere"
rm -rf "$fx"

rm -f "$NOWHERE_FLAG_FILE" "$CURL_FLAG_FILE"

echo "---"
echo "PASS: $PASS  FAIL: $FAIL"
exit "$FAIL"

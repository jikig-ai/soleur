#!/usr/bin/env bash
# Tests for postgrest-reload-schema.sh — Supabase Management API schema
# reload after a direct-pg migration apply (issue #4285).
#
# Run via:  bash apps/web-platform/scripts/postgrest-reload-schema.test.sh
#
# Test environment isolation: each test prepends a tmpdir to PATH containing
# a fake `curl` binary that records its args and emits a configurable
# response. The live api.supabase.com is NEVER called from this test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/postgrest-reload-schema.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Build a fake curl that:
#   - writes its argv (one per line) to $CURL_ARGS_FILE
#   - prints $CURL_BODY (default "{}") to stdout
#   - exits with $CURL_EXIT (default 0) — drives the script's HTTP-status branch
#     via -w "%{http_code}" output we render at the end of stdout.
make_fake_curl() {
  local dir="$1"
  cat > "$dir/curl" <<'FAKE'
#!/usr/bin/env bash
: "${CURL_ARGS_FILE:=/dev/null}"
: "${CURL_BODY:={}}"
: "${CURL_HTTP_CODE:=200}"
: "${CURL_EXIT:=0}"
printf '%s\n' "$@" > "$CURL_ARGS_FILE"
# Script invokes curl with `-w '\n%{http_code}'` and reads the trailing
# integer after the last newline. Mirror that contract.
printf '%s\n%s' "$CURL_BODY" "$CURL_HTTP_CODE"
exit "$CURL_EXIT"
FAKE
  chmod +x "$dir/curl"
}

# ------------------------------------------------------------------------
# T1 — missing SUPABASE_PAT in strict mode → non-zero exit with clear msg.
# ------------------------------------------------------------------------
echo "T1: missing SUPABASE_PAT (strict mode)"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -qi 'SUPABASE_PAT'; then
  pass "exit 2 (auth) with token-name in stderr"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T2 — missing SUPABASE_PAT in --best-effort mode → exit 0 with warning.
#       run-migrations.sh invokes the reload as a best-effort post-step;
#       the absence of SUPABASE_PAT must not break dev apply.
# ------------------------------------------------------------------------
echo "T2: missing SUPABASE_PAT (--best-effort)"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" --best-effort 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -qiE 'warn|skip'; then
  pass "exit 0 with warn/skip message"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T3 — missing NEXT_PUBLIC_SUPABASE_URL → non-zero exit (cannot derive ref).
# ------------------------------------------------------------------------
echo "T3: missing NEXT_PUBLIC_SUPABASE_URL"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" \
        SUPABASE_PAT="sbp_fake" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -qi 'NEXT_PUBLIC_SUPABASE_URL\|project ref'; then
  pass "non-zero exit with URL/ref message"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T4 — happy path: 200 OK → exit 0, posts to /v1/projects/<ref>/database/query
#       with the NOTIFY pgrst reload-schema body.
# ------------------------------------------------------------------------
echo "T4: happy path 200 OK"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=200 \
        CURL_BODY='{"ok":true}' \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] \
   && grep -q '/v1/projects/abcdefghijklmnopqrst/database/query' "$TMP/args" \
   && grep -qF "NOTIFY pgrst" "$TMP/args" \
   && grep -qE 'Authorization: Bearer sbp_fake' "$TMP/args"; then
  pass "exit 0, correct endpoint, NOTIFY body, bearer token"
else
  fail "rc=$rc"
  echo "    out=$out"
  echo "    --- captured args ---"
  cat "$TMP/args" >&2
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T5 — HTTP 401 → exit 2 (auth class) so run-migrations.sh can distinguish
#       transient from durable failures.
# ------------------------------------------------------------------------
echo "T5: HTTP 401 → exit 2"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=401 \
        CURL_BODY='{"message":"unauthorized"}' \
        SUPABASE_PAT="sbp_bad" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on 401"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T6 — HTTP 503 → exit 1 (transient) so callers can retry.
# ------------------------------------------------------------------------
echo "T6: HTTP 503 → exit 1 (transient)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=503 \
        CURL_BODY='{"message":"unavailable"}' \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]]; then
  pass "exit 1 on 503"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T7 — malformed NEXT_PUBLIC_SUPABASE_URL → non-zero (cannot extract ref).
#       Catches typos like missing host or non-supabase URLs.
# ------------------------------------------------------------------------
echo "T7: malformed URL → non-zero"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://example.com" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -qi 'project ref\|supabase\.co'; then
  pass "non-zero exit, message references ref/supabase.co"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T8 — best-effort mode + HTTP 503 still exits 0 (post-apply hook never
#       fails the migration run on a transient upstream issue).
# ------------------------------------------------------------------------
echo "T8: --best-effort soaks transient failures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=503 \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" --best-effort 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -qiE 'warn|skip|best-effort'; then
  pass "exit 0 with warn under best-effort"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T9 — --help prints usage and exits 0 without requiring any env.
# ------------------------------------------------------------------------
echo "T9: --help renders cleanly"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" --help 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] \
   && printf '%s' "$out" | grep -q '^Usage:' \
   && printf '%s' "$out" | grep -q 'SUPABASE_PAT' \
   && printf '%s' "$out" | grep -q 'Exit codes'; then
  pass "exit 0; renders Usage, SUPABASE_PAT, Exit codes"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T10 — unknown argument exits 2 (per AC).
# ------------------------------------------------------------------------
echo "T10: unknown arg → exit 2"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" --not-a-flag 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -qi 'unknown'; then
  pass "exit 2 with unknown-arg message"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T11 — curl network failure (curl_rc != 0) → exit 1, message scrubs PAT.
# ------------------------------------------------------------------------
echo "T11: curl network failure → exit 1, PAT scrubbed"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_EXIT=6 \
        SUPABASE_PAT="sbp_must_not_leak_aaaaaaaaaaaaaaaaaaaa" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]] \
   && printf '%s' "$out" | grep -q 'curl failed' \
   && ! printf '%s' "$out" | grep -q 'sbp_must_not_leak'; then
  pass "exit 1; PAT not echoed in error path"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T12 — HTTP 404 (wrong ref class) → exit 2 (operator-actionable).
# ------------------------------------------------------------------------
echo "T12: HTTP 404 → exit 2 (config)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=404 \
        CURL_BODY='{"message":"not found"}' \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on 404"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T13 — non-numeric HTTP code (proxy MITM, curl '000', 1xx) → catch-all,
#       exit 1 (transient).
# ------------------------------------------------------------------------
echo "T13: non-numeric HTTP code → catch-all exit 1"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=000 \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -qi 'unexpected'; then
  pass "exit 1 on HTTP 000 (proxy disconnect)"
else
  fail "rc=$rc out=$out"
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T13b — custom-domain CNAME fallback resolves the project ref.
#         Prd uses https://api.soleur.ai (CNAME → <ref>.supabase.co); without
#         the fallback, the strict regex rejects with exit 2.
# ------------------------------------------------------------------------
echo "T13b: custom-domain CNAME fallback (PATH-shimmed dig)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
cat > "$TMP/dig" <<'FAKE_DIG'
#!/usr/bin/env bash
# Shim is query-type-aware: only emits when CNAME is in argv (per cq M2 finding,
# PR #4320 review). Without this, a future switch to `dig +short A` would
# silently match the same hostname and the test would pass on a now-incorrect
# contract.
saw_cname=0
saw_host=0
for arg in "$@"; do
  case "$arg" in
    CNAME) saw_cname=1 ;;
    test-custom-domain.example.com) saw_host=1 ;;
  esac
done
if [[ "$saw_cname" == "1" && "$saw_host" == "1" ]]; then
  printf '%s\n' 'abcdefghijklmnopqrst.supabase.co.'
fi
FAKE_DIG
chmod +x "$TMP/dig"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=200 \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://test-custom-domain.example.com" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] \
   && grep -q '/v1/projects/abcdefghijklmnopqrst/database/query' "$TMP/args"; then
  pass "custom domain resolved via CNAME to canonical project ref"
else
  fail "rc=$rc out=$out"
  cat "$TMP/args" >&2 2>/dev/null || true
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
# T14 — endpoint URL is pinned (no SUPABASE_API_HOST env override leakage).
#       Verifies the security hardening from PR #4286 review.
# ------------------------------------------------------------------------
echo "T14: endpoint URL is pinned to api.supabase.com"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
make_fake_curl "$TMP"
set +e
out=$(PATH="$TMP:$PATH" \
        CURL_ARGS_FILE="$TMP/args" \
        CURL_HTTP_CODE=200 \
        SUPABASE_API_HOST="https://evil.example.com" \
        SUPABASE_PAT="sbp_fake" \
        NEXT_PUBLIC_SUPABASE_URL="https://abcdefghijklmnopqrst.supabase.co" \
        bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] \
   && grep -q 'https://api.supabase.com/v1/projects/abcdefghijklmnopqrst/database/query' "$TMP/args" \
   && ! grep -q 'evil.example.com' "$TMP/args"; then
  pass "endpoint ignores SUPABASE_API_HOST override (PAT exfil-safe)"
else
  fail "rc=$rc"
  cat "$TMP/args" >&2
fi
rm -rf "$TMP"; trap - EXIT

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

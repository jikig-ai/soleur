#!/usr/bin/env bash
# Tests for canary-bundle-claim-check.sh — fixtures F1-F13 covering both
# bundle layouts (pre-#3017 login-chunk-inlined, post-#3017 vendor-chunk-inlined),
# every row of the SKIP-vs-FAIL exit-reason matrix, and a log-injection guard.
#
# Pattern: serve a fixture tree via `python3 -m http.server` on an OS-allocated
# ephemeral port, invoke the script under test against http://localhost:<port>,
# assert exit code and stderr substrings.
#
# Why a dedicated test file (not a section of ci-deploy.test.sh): ci-deploy.test.sh
# mocks the canary script entirely (env-overridable path); these tests exercise
# the script's own logic against a real HTTP server.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/canary-bundle-claim-check.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FATAL: $SCRIPT not found or not executable" >&2
  exit 2
fi

# Capability-absent on a dev host is a printed SKIP with exit 0, not a RED; under
# CI the same absence is a runner-contract breach and must fail. Shape from
# git-data-emit.test.sh's _skip, with the CI predicate widened to -n plus
# GITHUB_ACTIONS (cloud-init-inngest-bootstrap's form): a runner exporting
# CI=1/CI=TRUE or only GITHUB_ACTIONS must fail closed the same as CI=true.
_skip() {
  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "$1 — and CI is set, so this is a FAILURE: the runner must provide this dependency. A gate that cannot run must not report success." >&2
    exit 1
  fi
  echo "$1" >&2
  exit 0
}

command -v python3 >/dev/null 2>&1 || _skip "canary-bundle-claim-check: SKIP — python3 required for fixture HTTP server"
command -v curl >/dev/null 2>&1 || _skip "canary-bundle-claim-check: SKIP — curl required for the fixture readiness probe"
command -v jq >/dev/null 2>&1 || _skip "canary-bundle-claim-check: SKIP — jq required by the script under test (every JWT decode pipes through jq -er)"

# Canonical anon-key payload: {iss:"supabase", role:"anon", ref:"aaaaaaaaaaaaaaaaaaaa"}
# (20-char placeholder ref, passes all canonical claim checks). Pre-baked so each
# fixture does not have to re-encode the JWT. Placeholder (not a real Supabase
# ref) avoids GitHub secret-scanner pattern hits on the dev project ref.
CANONICAL_JWT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6ImFub24iLCJpYXQiOjAsImV4cCI6OTk5OTk5OTk5OX0.signaturedoesnotmattertoclaimcheck' # gitleaks:allow # issue:#3194 synthesized JWT (placeholder ref aaaa..., signaturedoesnotmatter)

# JWTs used by F4-F7 (non-canonical claims) — each crafted to fail exactly one
# claim assertion. Generated via:
#   header='{"alg":"HS256","typ":"JWT"}'
#   for payload in '{"iss":"supabase","role":"anon","ref":"test1234567890123456"}' ...; do
#     printf '%s.%s.sig' "$(printf '%s' "$header" | base64 | tr '+/' '-_' | tr -d '=')" \
#                       "$(printf '%s' "$payload" | base64 | tr '+/' '-_' | tr -d '=')"
#   done
JWT_PLACEHOLDER_REF='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwicmVmIjoidGVzdDEyMzQ1Njc4OTAxMjM0NTYifQ.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, placeholder ref)
JWT_SERVICE_ROLE='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUiLCJyZWYiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYSJ9.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, placeholder ref)
JWT_BAD_ISS='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJldmlsIiwicm9sZSI6ImFub24iLCJyZWYiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYSJ9.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, evil iss for negative test)
JWT_SHORT_REF='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwicmVmIjoiYWJjMTIzIn0.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, short-ref negative test)

# F12: smuggled GitHub Actions annotation in the iss claim. The decoded payload
# contains a literal newline + "::notice::PASS"; if the script does not strip
# C0 controls before echoing claim values to stderr, this becomes a synthetic
# annotation (and could mask the real failure). Built from:
#   payload='{"iss":"supabase\n::notice::PASS","role":"anon","ref":"aaaaaaaaaaaaaaaaaaaa"}'
JWT_LOG_INJECT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZVxuOjpub3RpY2U6OlBBU1MiLCJyb2xlIjoiYW5vbiIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIn0.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, log-injection negative test)

# F12-bis: same idea but the smuggled annotation uses U+2028 (LINE SEPARATOR),
# encoded as 0xE2 0x80 0xA8 in UTF-8. `tr -d '\000-\037\177'` does NOT strip
# this 3-byte sequence; the sed pass after tr does. Payload:
#   payload='{"iss":"supabase\u2028::notice::PASS","role":"anon","ref":"aaaaaaaaaaaaaaaaaaaa"}'
JWT_LOG_INJECT_U2028='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZVx1MjAyODo6bm90aWNlOjpQQVNTIiwicm9sZSI6ImFub24iLCJyZWYiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYSJ9.sig' # gitleaks:allow # issue:#3194 synthesized JWT (.sig signature, U+2028 log-injection negative test)

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_LOG=""

# Per-test fixture root (recreated for each test) and HTTP server PID.
FIXTURE_ROOT=""
HTTP_PID=""
PORT=""

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# Cleanup runs on EXIT — tear down server and fixture tree. Idempotent.
cleanup_test() {
  if [[ -n "$HTTP_PID" ]]; then
    kill "$HTTP_PID" 2>/dev/null || true
    wait "$HTTP_PID" 2>/dev/null || true
    HTTP_PID=""
  fi
  if [[ -n "$FIXTURE_ROOT" ]] && [[ -d "$FIXTURE_ROOT" ]]; then
    rm -rf "$FIXTURE_ROOT"
    FIXTURE_ROOT=""
  fi
}
trap cleanup_test EXIT

# Allocate a free loopback port via the OS (no race window vs. random-range
# picking). Bound to 127.0.0.1 to match the --bind flag start_server passes to
# http.server — a port probed free on loopback must not be re-bound on another
# interface.
alloc_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); p=s.getsockname()[1]; s.close(); print(p)'
}

# Poll http://localhost:$1$2 until curl -fsS succeeds — ~4s on refused
# connections (20 × 0.2s), up to ~24s worst case when the port black-holes and
# every curl -m 1 burns its full second; protects CI from a Python startup
# hang. Shared by start_server and probe_loopback_http so the readiness window
# cannot drift between the capability probe and the fixture servers.
await_http_ready() {
  local port="$1" path="${2:-/}"
  for _ in $(seq 1 20); do
    if curl -fsS -m 1 --noproxy '*' "http://localhost:$port$path" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# Start a python http.server in $FIXTURE_ROOT on $PORT, bound to loopback only —
# the fixture tree must not be served on other interfaces.
start_server() {
  PORT=$(alloc_port)
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIXTURE_ROOT" >/dev/null 2>&1 &
  HTTP_PID=$!
  if await_http_ready "$PORT" /; then
    return 0
  fi
  echo "FATAL: http.server did not start on port $PORT within the readiness window" >&2
  return 1
}

# Up-front capability probe: run the suite's real fixture mechanism once before
# any F-row. A raw socket bind is NOT a substitute — measured on a host where
# `socketserver.TCPServer` binds instantly but `python3 -m http.server` never
# serves loopback within the readiness window, so only the real invocation is an
# honest precondition for all 14 fixtures (F1–F13 + F12-bis). The server's stderr
# is captured (not discarded like start_server's) so the SKIP verdict carries why
# the capability is absent.
probe_loopback_http() {
  # Drive the suite's HTTP_PID/FIXTURE_ROOT globals so the EXIT trap covers this
  # window too — a signal mid-probe must not leak the server or the scratch dir.
  cleanup_test
  FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/canary-probe.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
  assert_fixture_dir "$FIXTURE_ROOT"
  PORT=$(alloc_port)
  # A sentinel file distinguishes "our server answers" from a foreign listener
  # that squatted the port in the alloc/close/rebind window.
  printf 'canary-probe\n' > "$FIXTURE_ROOT/probe-sentinel"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIXTURE_ROOT" >"$FIXTURE_ROOT/server.log" 2>&1 &
  HTTP_PID=$!
  if await_http_ready "$PORT" /probe-sentinel; then
    cleanup_test
    return 0
  fi
  kill "$HTTP_PID" 2>/dev/null || true
  wait "$HTTP_PID" 2>/dev/null || true
  HTTP_PID=""
  echo "http.server probe stderr (last 5 lines):" >&2
  # Scrubbed like the SUT's own stderr emission — a PATH-resolved python3 must
  # not smuggle workflow-command bytes into CI logs via this diagnostic, so the
  # lines are indented (no `::cmd::` at column 0) and C0/U+2028-stripped.
  tail -5 "$FIXTURE_ROOT/server.log" \
    | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/^/    /' \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' >&2
  rm -rf "$FIXTURE_ROOT"
  FIXTURE_ROOT=""
  return 1
}

if ! probe_loopback_http; then
  _skip "canary-bundle-claim-check: SKIP — python3 http.server cannot bind+serve loopback on this host; the fixture mechanism every F-row depends on is absent (on CI the runner provides it and the full suite runs)"
fi

# Build a minimal /login HTML body that references the given chunk paths. Each
# arg is a chunk path under /_next/static/chunks/...; the function emits a
# matching <script src="..."></script> per arg.
build_login_html() {
  printf '<!DOCTYPE html><html><body>'
  for chunk in "$@"; do
    printf '<script src="%s"></script>' "$chunk"
  done
  printf '</body></html>'
}

# Stage a chunk file at $FIXTURE_ROOT$path containing the given JWT (or empty).
# Always writes a non-trivial wrapper so grep -oE eyJ... finds exactly one match
# (not zero; not multiple).
stage_chunk() {
  local path="$1"
  local jwt="${2:-}"
  local full="$FIXTURE_ROOT$path"
  mkdir -p "$(dirname "$full")"
  if [[ -n "$jwt" ]]; then
    printf 'var SUPABASE_KEY="%s";' "$jwt" > "$full"
  else
    printf 'var __NEXT_NOOP=1;' > "$full"
  fi
}

# Stage a chunk with a JWT-shaped string whose payload base64-decodes to bytes
# that are NOT valid JSON. The eyJ... regex matches (only [A-Za-z0-9_-] chars),
# the base64 step succeeds, but `jq -er` fails on non-JSON input — exercises
# the decode-failed exit path.
stage_corrupt_chunk() {
  local path="$1"
  local full="$FIXTURE_ROOT$path"
  mkdir -p "$(dirname "$full")"
  # Payload "Y29ycnVwdGNvcnJ1cHRjb3JydXB0" base64-decodes to "corruptcorruptcorrupt"
  # which is not JSON. Header is the canonical {"alg":"HS256","typ":"JWT"}.
  printf 'var X="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.Y29ycnVwdGNvcnJ1cHRjb3JydXB0.signature";' > "$full"
}

# Run the script with a per-test FIXTURE_ROOT and assert exit code + stderr.
# Args: test_id, expected_exit, expected_stderr_substring (or "" to skip).
run_test() {
  local test_id="$1"
  local expected_exit="$2"
  local expected_substr="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))

  local stderr_file
  stderr_file=$(mktemp "${TMPDIR:-/tmp}/canary-test-stderr.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }

  local actual_exit=0
  "$SCRIPT" "http://localhost:$PORT" 2>"$stderr_file" >/dev/null || actual_exit=$?

  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  local pass=true
  local fail_reason=""

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    pass=false
    fail_reason="exit code: expected $expected_exit, got $actual_exit"
  fi

  if [[ -n "$expected_substr" ]] && ! grep -qF -- "$expected_substr" <<<"$stderr_content"; then
    pass=false
    fail_reason="${fail_reason:+$fail_reason; }stderr missing substring: \"$expected_substr\""
  fi

  if $pass; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS  $test_id"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAIL_LOG="${FAIL_LOG}\n  FAIL  $test_id — $fail_reason\n        stderr: $(printf '%s' "$stderr_content" | head -c 400)"
    echo "  FAIL  $test_id — $fail_reason"
  fi
}

# Per-test setup: fresh fixture root, restart server.
new_fixture() {
  cleanup_test
  FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/canary-test-fixtures.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
  assert_fixture_dir "$FIXTURE_ROOT"
}

# ============================================================================
# F1 — pre-#3017 layout: JWT in login chunk
# ============================================================================
echo "F1: pre-#3017 layout (JWT in login chunk)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/app/(auth)/login/page-abc.js" \
  > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/app/(auth)/login/page-abc.js" "$CANONICAL_JWT"
start_server || exit 2
run_test "F1" 0 ""

# ============================================================================
# F2 — post-#3017 layout (current prod): JWT in vendor chunk
# ============================================================================
echo "F2: post-#3017 layout (JWT in vendor chunk, current prod)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html \
  "/_next/static/chunks/app/(auth)/login/page-def.js" \
  "/_next/static/chunks/8237-xyz.js" \
  > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/app/(auth)/login/page-def.js" ""
stage_chunk "/_next/static/chunks/8237-xyz.js" "$CANONICAL_JWT"
start_server || exit 2
run_test "F2" 0 ""

# ============================================================================
# F3 — JWT in 5th chunk (mid-traversal, verifies non-bail-early)
# ============================================================================
echo "F3: JWT in 5th of 13 chunks (mid-traversal)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
chunks=()
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  chunks+=("/_next/static/chunks/c${i}-deadbeef.js")
done
build_login_html "${chunks[@]}" > "$FIXTURE_ROOT/login/index.html"
for i in 1 2 3 4 6 7 8 9 10 11 12 13; do
  stage_chunk "/_next/static/chunks/c${i}-deadbeef.js" ""
done
stage_chunk "/_next/static/chunks/c5-deadbeef.js" "$CANONICAL_JWT"
start_server || exit 2
run_test "F3" 0 ""

# ============================================================================
# F4 — placeholder ref leak
# ============================================================================
echo "F4: placeholder ref (test1234567890123456)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_PLACEHOLDER_REF"
start_server || exit 2
run_test "F4" 1 "placeholder prefix"

# ============================================================================
# F5 — non-anon role
# ============================================================================
echo "F5: non-anon role (service_role)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_SERVICE_ROLE"
start_server || exit 2
run_test "F5" 1 'expected "anon"'

# ============================================================================
# F6 — non-supabase iss
# ============================================================================
echo "F6: non-supabase iss (evil)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_BAD_ISS"
start_server || exit 2
run_test "F6" 1 'expected "supabase"'

# ============================================================================
# F7 — short ref (6 chars)
# ============================================================================
echo "F7: short ref (abc123)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_SHORT_REF"
start_server || exit 2
run_test "F7" 1 "canonical 20-char shape"

# ============================================================================
# F8 — login HTML 404
# ============================================================================
echo "F8: login HTML 404"
new_fixture
# Empty fixture root → /login returns 404
start_server || exit 2
run_test "F8" 1 "canary_layer3_login_fetch_failed"

# ============================================================================
# F9 — login HTML returns no chunk references
# ============================================================================
echo "F9: login HTML has zero chunk references"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
printf '<html><body>hi</body></html>' > "$FIXTURE_ROOT/login/index.html"
start_server || exit 2
run_test "F9" 1 "canary_layer3_no_chunks"

# ============================================================================
# F10 — all chunks empty (no JWT anywhere)
# ============================================================================
echo "F10: all chunks empty (no JWT)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html \
  "/_next/static/chunks/c1-aa.js" \
  "/_next/static/chunks/c2-bb.js" \
  "/_next/static/chunks/c3-cc.js" \
  > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/c1-aa.js" ""
stage_chunk "/_next/static/chunks/c2-bb.js" ""
stage_chunk "/_next/static/chunks/c3-cc.js" ""
start_server || exit 2
run_test "F10" 1 "canary_layer3_no_jwt"

# ============================================================================
# F11 — JWT decode failure (corrupt base64 payload)
# ============================================================================
echo "F11: JWT decode failure (corrupt base64)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_corrupt_chunk "/_next/static/chunks/8237-xyz.js"
start_server || exit 2
run_test "F11" 1 "canary_layer3_jwt_decode_failed"

# ============================================================================
# F12 — log-injection guard (literal \n::notice::PASS in iss claim)
# ============================================================================
echo "F12: log-injection guard (C0 strip)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_LOG_INJECT"
start_server || exit 2
TESTS_RUN=$((TESTS_RUN + 1))
stderr_file=$(mktemp "${TMPDIR:-/tmp}/canary-test-stderr.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
"$SCRIPT" "http://localhost:$PORT" 2>"$stderr_file" >/dev/null || true
# Assertion: zero lines in stderr begin with "::notice::". The smuggled
# annotation must have been stripped before stderr emission.
inj_lines=$(grep -c '^::notice::' "$stderr_file" || true)
if [[ "$inj_lines" == "0" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS  F12"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAIL_LOG="${FAIL_LOG}\n  FAIL  F12 — $inj_lines smuggled ::notice:: line(s) leaked"
  echo "  FAIL  F12 — $inj_lines smuggled ::notice:: line(s) leaked"
fi
rm -f "$stderr_file"

# ============================================================================
# F12-bis — log-injection guard for U+2028 (LINE SEPARATOR, 3-byte UTF-8)
# ============================================================================
echo "F12-bis: log-injection guard (U+2028 strip)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
build_login_html "/_next/static/chunks/8237-xyz.js" > "$FIXTURE_ROOT/login/index.html"
stage_chunk "/_next/static/chunks/8237-xyz.js" "$JWT_LOG_INJECT_U2028"
start_server || exit 2
TESTS_RUN=$((TESTS_RUN + 1))
stderr_file=$(mktemp "${TMPDIR:-/tmp}/canary-test-stderr.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
"$SCRIPT" "http://localhost:$PORT" 2>"$stderr_file" >/dev/null || true
# U+2028 in stderr would be rendered as a line break by most consumers; assert
# the byte sequence E2 80 A8 is absent. grep -aF matches the same 3 bytes on any
# grep (no PCRE — BSD-safe), so the measurement has no ungated capability.
# rc>=2 is still a grep error — a capability absence must read as a failure to
# measure, not a pass.
grep -aF "$(printf '\xe2\x80\xa8')" "$stderr_file" >/dev/null 2>&1; grep_rc=$?
if [[ "$grep_rc" -eq 0 ]]; then
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAIL_LOG="${FAIL_LOG}\n  FAIL  F12-bis — U+2028 byte sequence leaked into stderr"
  echo "  FAIL  F12-bis — U+2028 byte sequence leaked into stderr"
elif [[ "$grep_rc" -eq 1 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS  F12-bis"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAIL_LOG="${FAIL_LOG}\n  FAIL  F12-bis — grep rc=$grep_rc; the U+2028 assertion could not measure stderr"
  echo "  FAIL  F12-bis — grep rc=$grep_rc; the U+2028 assertion could not measure stderr"
fi
rm -f "$stderr_file"

# ============================================================================
# F13 — cap-at-20 boundary: 21 candidates with JWT only at position 21.
# Asserts the cap is not wider than 20 — if a future change widens to 30,
# the JWT would be reached and the test would flip to exit 0, failing this
# fixture. This proves "cap is no wider than expected", not "cap is exactly 20"
# (a narrower cap of 19 would also pass since chunks 1-19 are also empty).
# ============================================================================
echo "F13: cap boundary (21 candidates, JWT beyond cap of 20 → fail by design)"
new_fixture
mkdir -p "$FIXTURE_ROOT/login"
chunks=()
for i in $(seq 1 21); do
  chunks+=("/_next/static/chunks/c${i}-deadbeef.js")
done
build_login_html "${chunks[@]}" > "$FIXTURE_ROOT/login/index.html"
for i in $(seq 1 20); do
  stage_chunk "/_next/static/chunks/c${i}-deadbeef.js" ""
done
stage_chunk "/_next/static/chunks/c21-deadbeef.js" "$CANONICAL_JWT"
start_server || exit 2
run_test "F13" 1 "canary_layer3_no_jwt"

# ============================================================================
# Verdict-machinery canary — mirrors zot-config-deadlines's helper canary. The
# conservation floor below counts verdicts; it cannot see a verdict-LOGIC
# defect (e.g. `pass=true` forced inside run_test), which would keep
# RUN == PASSED+FAILED balanced on a fully-broken SUT. Drive run_test with a
# deliberately-wrong expectation (the SUT never exits 99) and require
# TESTS_FAILED to move; counters are then restored so the floor stays at 14.
# ============================================================================
_cr=$TESTS_RUN; _cp=$TESTS_PASSED; _cf=$TESTS_FAILED; _fl=$FAIL_LOG
run_test "instrument self-test (deliberately-wrong expectation — MUST register FAIL)" 99 ""
if [[ "$TESTS_RUN" -ne $((_cr + 1)) || "$TESTS_PASSED" -ne "$_cp" || "$TESTS_FAILED" -ne $((_cf + 1)) ]]; then
  echo "FATAL: the verdict machinery is not counting — every PASS/FAIL above is void." >&2
  exit 2
fi
TESTS_RUN=$_cr; TESTS_FAILED=$_cf; FAIL_LOG=$_fl

# ============================================================================
# Summary
# ============================================================================
# Conservation + floor — the probe gates capability, not reachability: a suite
# that silently ran nothing (early exit, a dropped F-row) would read as a clean
# 0/0 pass. 14 rows: F1–F13 plus F12-bis. The message carries the vacuity-floor
# sentinel vocabulary (assertion floor / assertions ran): the meta-guard's
# mutant oracle maps a bare `FATAL:` + rc=2 to CONSTRUCTION, not FIRES.
if [[ "$TESTS_RUN" -lt 14 || "$TESTS_RUN" -ne $((TESTS_PASSED + TESTS_FAILED)) ]]; then
  echo "FATAL: assertion floor/conservation — assertions ran=$TESTS_RUN of 14 required (passed=$TESTS_PASSED failed=$TESTS_FAILED); a dropped or uncounted row is a suite defect" >&2
  exit 2
fi
echo ""
echo "================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
  echo ""
  echo "Failures:"
  printf '%b\n' "$FAIL_LOG"
  exit 1
fi
exit 0

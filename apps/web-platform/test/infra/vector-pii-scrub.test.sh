#!/usr/bin/env bash
# VRL fixture tests for vector.toml pii_scrub_* transforms (PR #4293).
# Runs each transform against synthetic fixtures and asserts the
# `pii_scrub_applied` tag + output shape match the plan's contract
# (AC4-AC6 + AC5 ordering guard).
#
# Contract:
#   - SENTRY_USERID_PEPPER must be a synthetic value (the script refuses
#     to run if it looks like a real Doppler-shaped string).
#   - Vector binary path: VECTOR_BIN env var, defaults to `vector` on PATH.
#   - VRL is extracted from apps/web-platform/infra/vector.toml in-place
#     (single source of truth — the same bytes vector runs at boot).
#
# Why single bash file (not vitest): vector vrl is a CLI; spawning per
# fixture is cheaper than wrapping in a test runner. Plan simplicity-Cut-7.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
VECTOR_TOML="$REPO_ROOT/apps/web-platform/infra/vector.toml"
OBSERVABILITY_TS="$REPO_ROOT/apps/web-platform/server/observability.ts"
VECTOR_BIN="${VECTOR_BIN:-vector}"

if [[ -z "${SENTRY_USERID_PEPPER:-}" ]]; then
  echo "FAIL: SENTRY_USERID_PEPPER must be set (use 'fixture-only-do-not-use-in-prod')" >&2
  exit 1
fi
if [[ "$SENTRY_USERID_PEPPER" != fixture-* ]]; then
  echo "FAIL: SENTRY_USERID_PEPPER must start with 'fixture-' to prove it is synthetic" >&2
  exit 1
fi

if ! command -v "$VECTOR_BIN" >/dev/null 2>&1; then
  echo "FAIL: vector binary not found (set VECTOR_BIN or install Vector 0.43.1)" >&2
  exit 1
fi

# ---------- VRL extraction (single source of truth) ----------
# Extract VRL source blocks from vector.toml between
# [transforms.<name>] ... source = ''' ... ''' markers.
extract_vrl() {
  local transform="$1"
  awk -v target="[transforms.${transform}]" '
    $0 == target { in_block = 1; next }
    in_block && /^\[/ { in_block = 0 }
    in_block && /source = '\'\'\''/ { capturing = 1; next }
    capturing && /^'\'\'\''/ { capturing = 0; in_block = 0; exit }
    capturing { print }
  ' "$VECTOR_TOML"
}

# Vector's TOML loader expands ${VAR} as env vars and $$ as a literal $.
# Mirror that here so the extracted VRL matches what Vector compiles at boot
# (regex replacement strings like "$${1}Bearer ..." become "${1}Bearer ..."
# under Vector's preprocessor, then VRL's `replace` expands the ${1} capture).
unescape_vector_toml() {
  python3 -c 'import sys; sys.stdout.write(sys.stdin.read().replace("$$", "$"))'
}

VRL_DROP=$(extract_vrl pii_scrub_drop_userdata | unescape_vector_toml)
VRL_STRUCT=$(extract_vrl pii_scrub_structured | unescape_vector_toml)
VRL_STRING=$(extract_vrl pii_scrub_string | unescape_vector_toml)

if [[ -z "$VRL_DROP" || -z "$VRL_STRUCT" || -z "$VRL_STRING" ]]; then
  echo "FAIL: VRL extraction from $VECTOR_TOML returned empty for one or more transforms" >&2
  echo "  pii_scrub_drop_userdata: $(echo "$VRL_DROP" | wc -c) chars" >&2
  echo "  pii_scrub_structured: $(echo "$VRL_STRUCT" | wc -c) chars" >&2
  echo "  pii_scrub_string: $(echo "$VRL_STRING" | wc -c) chars" >&2
  exit 1
fi

# Apply transforms SEQUENTIALLY (matches production wiring exactly).
# Vector wires each remap transform as a standalone VRL program; chaining
# them into one VRL program would trigger E651 "expression can't fail"
# because the chained-form type-checker proves `.pii_scrub_applied` is
# always set after transform 1, whereas standalone transforms compile
# against `any`-typed event fields (matching the production runtime path).
apply_pipeline() {
  local input="$1"
  local tmp1 tmp2
  tmp1=$(mktemp)
  tmp2=$(mktemp)
  printf '%s\n' "$input" >"$tmp1"
  "$VECTOR_BIN" vrl --input "$tmp1" --print-object "$VRL_DROP" 2>/tmp/vector-vrl-err >"$tmp2" || { cat /tmp/vector-vrl-err >&2; rm -f "$tmp1" "$tmp2"; return 1; }
  "$VECTOR_BIN" vrl --input "$tmp2" --print-object "$VRL_STRUCT" 2>/tmp/vector-vrl-err >"$tmp1" || { cat /tmp/vector-vrl-err >&2; rm -f "$tmp1" "$tmp2"; return 1; }
  "$VECTOR_BIN" vrl --input "$tmp1" --print-object "$VRL_STRING" 2>/tmp/vector-vrl-err >"$tmp2" || { cat /tmp/vector-vrl-err >&2; rm -f "$tmp1" "$tmp2"; return 1; }
  cat "$tmp2"
  rm -f "$tmp1" "$tmp2"
}

# ---------- Test harness ----------
PASS=0
FAIL=0
FAILS=()

run_fixture() {
  local name="$1"
  local input_json="$2"
  shift 2
  local output
  if ! output=$(apply_pipeline "$input_json"); then
    FAIL=$((FAIL+1))
    FAILS+=("$name: vector vrl pipeline exited non-zero")
    return
  fi

  # All assertions are jq expressions; passed as "$@" arguments.
  local assertion
  local assertion_ok=1
  for assertion in "$@"; do
    if ! echo "$output" | jq -e "$assertion" >/dev/null 2>&1; then
      FAIL=$((FAIL+1))
      FAILS+=("$name: assertion failed: $assertion")
      echo "  --- $name output:" >&2
      echo "  $output" >&2
      assertion_ok=0
      break
    fi
  done
  if [[ "$assertion_ok" == 1 ]]; then
    PASS=$((PASS+1))
    echo "  PASS: $name"
  fi
}

# Expected hash for 'test-user-id' under the fixture pepper:
EXPECTED_HASH_TUI=$(printf 'test-user-id' | openssl dgst -sha256 -hmac "$SENTRY_USERID_PEPPER" -hex | awk '{print $2}')
# Sanity-check parity against TS hashUserId (AC4):
EXPECTED_HASH_TS=$(cd "$REPO_ROOT/apps/web-platform" && \
  SENTRY_USERID_PEPPER="$SENTRY_USERID_PEPPER" \
  bun -e 'import {hashUserId} from "./server/observability"; console.log(hashUserId("test-user-id"))' 2>/dev/null)
if [[ "$EXPECTED_HASH_TUI" != "$EXPECTED_HASH_TS" ]]; then
  echo "FAIL: openssl HMAC != TS hashUserId for 'test-user-id'" >&2
  echo "  openssl: $EXPECTED_HASH_TUI" >&2
  echo "  TS:      $EXPECTED_HASH_TS" >&2
  exit 1
fi
echo "PRE: openssl + TS hashUserId parity confirmed: $EXPECTED_HASH_TUI"

echo "=== Fixture tests ==="

# --- AC4: pino-with-userid -> bit-for-bit parity ---
run_fixture "pino-with-userid (AC4 parity)" \
  "{\"message\":\"{\\\"userId\\\":\\\"test-user-id\\\",\\\"level\\\":\\\"error\\\",\\\"requestId\\\":\\\"req-1\\\"}\"}" \
  "(.pii_scrub_applied | contains(\"structured\"))" \
  "(.message | fromjson | .userIdHash == \"$EXPECTED_HASH_TUI\")" \
  "(.message | fromjson | has(\"userId\") | not)"

# --- AC5(a): drop_userdata strips top-level user-content keys (Art-9) ---
run_fixture "user-content-body-key (AC5a Art-9)" \
  '{"message":"{\"body\":\"chat says secret\",\"content\":\"more secret\",\"message\":\"templated\",\"userMessage\":\"u\",\"prompt\":\"p\",\"chat_message\":\"c\",\"userInput\":\"i\",\"user_input\":\"j\",\"level\":\"info\",\"requestId\":\"r\"}"}' \
  '(.pii_scrub_applied | contains("drop_userdata"))' \
  '(.message | fromjson | has("body") | not)' \
  '(.message | fromjson | has("content") | not)' \
  '(.message | fromjson | has("message") | not)' \
  '(.message | fromjson | has("userMessage") | not)' \
  '(.message | fromjson | has("prompt") | not)' \
  '(.message | fromjson | has("chat_message") | not)' \
  '(.message | fromjson | has("userInput") | not)' \
  '(.message | fromjson | has("user_input") | not)' \
  '(.message | fromjson | .level == "info")'

# --- AC5(b): structured rewrites userId ONLY; workspaceId NOT touched ---
run_fixture "workspaceId-preserved (AC5b SF-P0-3)" \
  '{"message":"{\"userId\":\"u-1\",\"workspaceId\":\"ws-1\",\"workspace_id\":\"ws-2\",\"level\":\"info\"}"}' \
  '(.pii_scrub_applied | contains("structured"))' \
  '(.message | fromjson | has("userId") | not)' \
  '(.message | fromjson | has("userIdHash"))' \
  '(.message | fromjson | .workspaceId == "ws-1")' \
  '(.message | fromjson | .workspace_id == "ws-2")'

# --- AC5(b): structured rewrites user_id (snake) too ---
run_fixture "user_id snake variant" \
  '{"message":"{\"user_id\":\"test-user-id\",\"level\":\"warn\"}"}' \
  '(.pii_scrub_applied | contains("structured"))' \
  "(.message | fromjson | .userIdHash == \"$EXPECTED_HASH_TUI\")" \
  '(.message | fromjson | has("user_id") | not)'

# --- AC5(b): preset userIdHash preserved (defensive idempotence) ---
run_fixture "preset-userIdHash-preserved" \
  '{"message":"{\"userIdHash\":\"already-hashed\",\"level\":\"info\"}"}' \
  '(.message | fromjson | .userIdHash == "already-hashed")'

# --- AC5(b): null userId -> structured_null_sentinel ---
run_fixture "null-userid-value" \
  '{"message":"{\"userId\":null,\"level\":\"warn\"}"}' \
  '(.pii_scrub_applied | contains("structured_null_sentinel"))' \
  '(.message | fromjson | .userIdHash == "pepper_unset_null")' \
  '(.message | fromjson | has("userId") | not)'

# --- AC5(c): string scrub catches kernel-oops userid= substring ---
run_fixture "kernel-oops-userid-substring (AC5c SF-P0-2)" \
  '{"message":"kernel: process[1234] segfault userid=abc-123-def at 0x7fff"}' \
  '(.pii_scrub_applied | contains("string"))' \
  '(.message | test("userid=\\[redacted\\]"))' \
  '(.message | test("userid=abc") | not)'

# --- AC5(c): string scrub catches email ---
run_fixture "kernel-oops-with-email" \
  '{"message":"kernel: oom-killer killed pid 1234 (user@example.com process)"}' \
  '(.pii_scrub_applied | contains("string"))' \
  '(.message | test("\\[email\\]"))' \
  '(.message | test("user@example") | not)'

# --- AC5(c): string scrub catches Authorization Bearer ---
run_fixture "authorization-bearer-leak" \
  '{"message":"req failed Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.foo.bar"}' \
  '(.message | test("Bearer \\[redacted\\]"))' \
  '(.message | test("eyJhbGc") | not)'

# --- AC5(c): line-injection chars stripped ---
run_fixture "line-injection-unicode" \
  '{"message":"foo bar bazqux"}' \
  '(.message == "foobarbazqux")'

# --- AC5(c): /api/auth/callback NOT redacted (UI-F1) ---
run_fixture "oauth-callback-path-preserved (UI-F1)" \
  '{"message":"GET /api/auth/callback/github 200 OK"}' \
  '(.message | test("/api/auth/callback/github"))'

# --- AC5(c): Arch-F2 ordering guard — structured branch SKIPS string scrub ---
# A pino-shape input with userid= in a non-message field should be parsed
# by structured (which doesnt touch the userid= substring inside arbitrary
# fields), and string scrub should be skipped to avoid JSON corruption.
run_fixture "ordering-guard-structured-skips-string (Arch-F2)" \
  '{"message":"{\"userId\":\"test-user-id\",\"raw_log\":\"foo userid=bar\",\"level\":\"info\"}"}' \
  '(.pii_scrub_applied | contains("structured"))' \
  '(.pii_scrub_applied | contains("string_skipped_already_parsed"))' \
  '(.message | fromjson | .raw_log == "foo userid=bar")'

# --- AC6: UTF-8 pepper fixture (assumes pepper already includes multi-byte) ---
# When invoked with the synthetic pepper that contains 'é', parity holds.
if [[ "${SENTRY_USERID_PEPPER}" == *é* ]]; then
  EXPECTED_HASH_UTF8=$(printf 'test-user-id' | openssl dgst -sha256 -hmac "$SENTRY_USERID_PEPPER" -hex | awk '{print $2}')
  run_fixture "utf8-pepper (AC6)" \
    "{\"message\":\"{\\\"userId\\\":\\\"test-user-id\\\",\\\"level\\\":\\\"info\\\"}\"}" \
    "(.message | fromjson | .userIdHash == \"$EXPECTED_HASH_UTF8\")"
else
  echo "  SKIP: utf8-pepper (AC6) — pepper does not contain multi-byte char"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  for f in "${FAILS[@]}"; do echo "  FAIL: $f"; done
  exit 1
fi
exit 0

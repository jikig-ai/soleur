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

# --- F2: OAuth query-param values redacted while path preserved (PR #4293 review) ---
run_fixture "oauth-callback-querystring-redacted (review F2)" \
  '{"message":"GET /api/auth/callback/github?code=ghu_AAAA1111&state=csrf-xyz 200"}' \
  '(.message | test("/api/auth/callback/github"))' \
  '(.message | test("code=\\[redacted\\]"))' \
  '(.message | test("state=\\[redacted\\]"))' \
  '(.message | test("ghu_AAAA1111") | not)' \
  '(.message | test("csrf-xyz") | not)'

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

# ============================================================
# #4773 — app container journald source: routing + WARN+ filter
# ============================================================
echo
echo "=== #4773 app-container source assertions ==="

# (a) Routing wiring (vector validate proves connectivity; these pin the
#     REDACTION path — the app container must traverse pii_scrub, not bypass
#     it to the sink). Asserted against vector.toml directly.
assert_grep() {
  local desc="$1" pattern="$2"
  if grep -qE "$pattern" "$VECTOR_TOML"; then
    PASS=$((PASS+1)); echo "  PASS: $desc"
  else
    FAIL=$((FAIL+1)); FAILS+=("$desc: pattern not found in vector.toml: $pattern")
  fi
}
assert_grep "app_container_journald source exists" '^\[sources\.app_container_journald\]'
assert_grep "warn filter reads the app_container source" '^inputs = \["app_container_journald"\]'
assert_grep "app container routed THROUGH pii_scrub (redaction path, not sink-direct)" \
  '^inputs = \["inngest_journald", "system_journald", "app_container_warn_filter", "host_scripts_journald"\]'
assert_grep "tag_journald tags app-container lines source_kind=app_container" 'source_kind = "app_container"'

# (b) Redaction parity: a cron pino WARN+ line carrying a userId + an Art-9
#     user-content key (prompt) must be scrubbed identically to any other
#     source once it reaches pii_scrub. CONTAINER_NAME rides at the top level
#     (the Vector event shape) and must pass through unchanged.
run_fixture "app-container-cron-line (#4773 redaction parity)" \
  '{"message":"{\"level\":50,\"fn\":\"cron-growth-audit\",\"userId\":\"test-user-id\",\"prompt\":\"secret user prompt\",\"msg\":\"claude-eval nonzero exit\"}","CONTAINER_NAME":"soleur-web-platform"}' \
  '(.pii_scrub_applied | contains("structured"))' \
  '(.message | fromjson | has("prompt") | not)' \
  "(.message | fromjson | .userIdHash == \"$EXPECTED_HASH_TUI\")" \
  '(.message | fromjson | has("userId") | not)' \
  '(.message | fromjson | .fn == "cron-growth-audit")' \
  '(.CONTAINER_NAME == "soleur-web-platform")'

# (c) WARN+ filter behavior. Docker's journald driver maps the app container's
#     pino stdout (every level) to PRIORITY 6, so a journald PRIORITY filter
#     cannot distinguish levels — the filter parses the pino JSON `level`
#     instead. INFO/DEBUG (request firehose) drop; WARN/ERROR/FATAL ship;
#     non-JSON crash lines are kept. Extracted from vector.toml (single source
#     of truth) and the final if-expression bound to `.keep` for evaluation.
extract_filter_condition() {
  awk '
    $0 == "[transforms.app_container_warn_filter]" { in_block = 1; next }
    in_block && /^\[/ { in_block = 0 }
    in_block && /condition = '\'\'\''/ { capturing = 1; next }
    capturing && /^'\'\'\''/ { capturing = 0; in_block = 0; exit }
    capturing { print }
  ' "$VECTOR_TOML"
}
# Prefix the FIRST top-level `if` with `.keep = ` so --print-object exposes the
# boolean result (the preceding parse_json statement stays a standalone stmt).
FILTER_PROG=$(extract_filter_condition | sed '0,/^if /s//.keep = if /')
if [[ -z "$FILTER_PROG" ]] || ! echo "$FILTER_PROG" | grep -q '\.keep = if '; then
  FAIL=$((FAIL+1)); FAILS+=("app_container_warn_filter: condition extraction/rewrite failed")
fi

run_filter_fixture() {
  local name="$1" input_json="$2" expected="$3"
  local tmp out
  tmp=$(mktemp)
  printf '%s\n' "$input_json" >"$tmp"
  if ! out=$("$VECTOR_BIN" vrl --input "$tmp" --print-object "$FILTER_PROG" 2>/tmp/vector-filter-err); then
    cat /tmp/vector-filter-err >&2
    FAIL=$((FAIL+1)); FAILS+=("$name: vector vrl exited non-zero"); rm -f "$tmp"; return
  fi
  rm -f "$tmp"
  if echo "$out" | jq -e "(.keep == $expected)" >/dev/null 2>&1; then
    PASS=$((PASS+1)); echo "  PASS: $name (keep=$expected)"
  else
    FAIL=$((FAIL+1)); FAILS+=("$name: expected keep=$expected, got: $out")
  fi
}
run_filter_fixture "filter DROPS pino INFO (level 30 firehose)" \
  '{"message":"{\"level\":30,\"fn\":\"cron-growth-audit\",\"msg\":\"stdout line\"}"}' "false"
run_filter_fixture "filter KEEPS pino WARN (level 40)" \
  '{"message":"{\"level\":40,\"msg\":\"warn\"}"}' "true"
run_filter_fixture "filter KEEPS pino ERROR (level 50 — cron nonzero exit)" \
  '{"message":"{\"level\":50,\"fn\":\"cron-growth-audit\",\"msg\":\"nonzero exit\"}"}' "true"
run_filter_fixture "filter KEEPS non-JSON crash line (fd2 stack)" \
  '{"message":"Segmentation fault (core dumped)"}' "true"
# Boundary + non-numeric-level edge cases (pin the >= 40 cut and the `?? 0`
# default so a future off-by-one or to_int regression is caught):
run_filter_fixture "filter DROPS pino just-below boundary (level 39)" \
  '{"message":"{\"level\":39,\"msg\":\"just below warn\"}"}' "false"
run_filter_fixture "filter DROPS JSON object missing level (?? 0 default)" \
  '{"message":"{\"msg\":\"no level field\",\"fn\":\"cron-x\"}"}' "false"
run_filter_fixture "filter KEEPS string-typed level (to_int parses \"40\")" \
  '{"message":"{\"level\":\"40\",\"msg\":\"string level\"}"}' "true"

# Canary-exclusion config pin (#4773): the source must use EXACT-value
# include_matches on the production container name only. systemd journal
# matching is FIELD=value equality, so this excludes `soleur-web-platform-canary`
# (which also logs to journald via ci-deploy.sh). A future widen to a prefix /
# regex would silently start ingesting canary lines and double Better Stack
# quota — pin the exact single-element array so that change fails this gate.
assert_grep "source pins exact production container name (no canary, no wildcard)" \
  '^include_matches\.CONTAINER_NAME = \["soleur-web-platform"\]$'

# ============================================================
# #5499 — host-script `logger -t` journald source: config assertions
# ============================================================
# Pure config greps (no vector binary needed for these — they verify the
# source's SHAPE, not its runtime behavior, which `vector validate` covers).
# Kept in this file so validate-vector-config.yml's apps/web-platform/test/infra/**
# path filter runs them on every vector.toml PR.
echo
echo "=== #5499 host-script source assertions ==="

# Extract the [sources.host_scripts_journald] block (its header line through the
# line before the next top-level [section]). Used by the AC1/AC2/AC3 checks below.
HOST_SCRIPTS_BLOCK=$(awk '
  $0 ~ /^\[sources\.host_scripts_journald\]/ { in_block=1; print; next }
  in_block && /^\[/ { in_block=0 }
  in_block { print }
' "$VECTOR_TOML")

# AC1: the dedicated source exists and is a journald source.
if [[ -n "$HOST_SCRIPTS_BLOCK" ]] && echo "$HOST_SCRIPTS_BLOCK" | grep -qE '^type = "journald"$'; then
  PASS=$((PASS+1)); echo "  PASS: host_scripts_journald source exists (type=journald)"
else
  FAIL=$((FAIL+1)); FAILS+=("AC1: [sources.host_scripts_journald] with type=\"journald\" not found")
fi

# AC2: the block has NO include_matches.PRIORITY line. These host-script lines
# are PRIORITY 4-5 (user.warning / user.notice); ANY PRIORITY filter would
# silently drop the very lines this source exists to capture. Regression guard.
if echo "$HOST_SCRIPTS_BLOCK" | grep -qE 'PRIORITY'; then
  FAIL=$((FAIL+1)); FAILS+=("AC2: host_scripts_journald must NOT carry an include_matches.PRIORITY line (would drop PRIORITY 4-5 host-script lines)")
else
  PASS=$((PASS+1)); echo "  PASS: host_scripts_journald has no PRIORITY filter (captures PRIORITY 4-5)"
fi

# AC3: drift guard — the SYSLOG_IDENTIFIER tag set MUST equal the set of infra
# scripts that actually call `logger -t`. Derive the expected set from the
# scripts themselves so a NEW `logger -t` tag (or a removed one) that is not
# mirrored into this source fails CI. (`logger -t <tag>` sets the journal
# SYSLOG_IDENTIFIER field to <tag>; the source matches that field exactly.)
INFRA_DIR="$REPO_ROOT/apps/web-platform/infra"
EXPECTED_TAGS=$(
  for f in "$INFRA_DIR"/*.sh; do
    grep -q 'logger -t' "$f" || continue
    grep -hoP '^\s*(readonly\s+)?LOG_TAG="\K[^"]+' "$f"
  done | sort -u
)
# Array entries are quoted strings on their own lines inside the include_matches
# block; pull the bare tag from each.
ACTUAL_TAGS=$(echo "$HOST_SCRIPTS_BLOCK" | grep -oP '^\s*"\K[a-z0-9-]+(?="\s*,?\s*$)' | sort -u)
if [[ -n "$EXPECTED_TAGS" && "$EXPECTED_TAGS" == "$ACTUAL_TAGS" ]]; then
  PASS=$((PASS+1)); echo "  PASS: SYSLOG_IDENTIFIER tag set matches the logger -t scripts ($(echo "$EXPECTED_TAGS" | grep -c .) tags)"
else
  FAIL=$((FAIL+1)); FAILS+=("AC3: tag-set drift — host_scripts_journald array != logger -t scripts.
    expected (from infra/*.sh logger -t scripts):
$(echo "$EXPECTED_TAGS" | sed 's/^/      /')
    actual (from vector.toml source array):
$(echo "$ACTUAL_TAGS" | sed 's/^/      /')")
fi

# AC4: redaction-boundary guard (GDPR) — host_scripts_journald must traverse the
# 3-stage pii_scrub chain (be an input of pii_scrub_drop_userdata), never bypass
# it to the sink. A new source skipping redaction is a privacy regression.
assert_grep "host_scripts_journald is an input of pii_scrub_drop_userdata (redaction-boundary guard)" \
  '^inputs = \[.*"host_scripts_journald".*\]'

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  for f in "${FAILS[@]}"; do echo "  FAIL: $f"; done
  exit 1
fi
exit 0

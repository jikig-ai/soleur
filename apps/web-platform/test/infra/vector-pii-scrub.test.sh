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
  in_block && (/^\[/ || /^#/ || /^[[:space:]]*$/) { in_block=0 }
  in_block { print }
' "$VECTOR_TOML")

# AC1: the dedicated source exists and is a journald source.
if [[ -n "$HOST_SCRIPTS_BLOCK" ]] && echo "$HOST_SCRIPTS_BLOCK" | grep -qE '^type = "journald"$'; then
  PASS=$((PASS+1)); echo "  PASS: host_scripts_journald source exists (type=journald)"
else
  FAIL=$((FAIL+1)); FAILS+=("AC1: [sources.host_scripts_journald] with type=\"journald\" not found")
fi

# AC2: the block has NO include_matches.PRIORITY line. These host-script lines
# are PRIORITY 4-6 (user.warning / user.notice; #6536's inngest-heartbeat channel is
# PRIORITY 6); ANY PRIORITY filter would silently drop the very lines this source exists
# to capture. Regression guard.
#
# ANCHORED on the assignment construct, NOT the bare word `PRIORITY`. The block-extraction
# above only terminates on a COL-0 `#`, so the array's own indented comments stay inside
# HOST_SCRIPTS_BLOCK — and those comments must be free to explain WHY this source carries no
# PRIORITY filter (that reasoning is the whole point of #6536's Source-4-only fix). A bare
# token grep makes the guard and its own documentation mutually exclusive: it false-FAILS on
# the prose. A comment line cannot produce `include_matches.PRIORITY =`.
if echo "$HOST_SCRIPTS_BLOCK" | grep -qE '^[[:space:]]*include_matches\.PRIORITY[[:space:]]*='; then
  FAIL=$((FAIL+1)); FAILS+=("AC2: host_scripts_journald must NOT carry an include_matches.PRIORITY line (would drop PRIORITY 4-5 host-script lines)")
else
  PASS=$((PASS+1)); echo "  PASS: host_scripts_journald has no PRIORITY filter (captures PRIORITY 4-5)"
fi

# AC3: drift guard — the SYSLOG_IDENTIFIER tag set MUST equal the set of infra
# scripts that actually emit under one. Derive the expected set from the
# scripts themselves so a NEW tag (or a removed one) that is not
# mirrored into this source fails CI. Two independent emission channels feed a
# journal SYSLOG_IDENTIFIER, and each is derived on its own terms below.
INFRA_DIR="$REPO_ROOT/apps/web-platform/infra"
EXPECTED_TAGS=$(
  for f in "$INFRA_DIR"/*.sh; do
    # Channel A (#6536) — a systemd unit heredoc's EXPLICIT `SyslogIdentifier=<tag>`,
    # which retags everything the unit writes (here: doppler's AND curl's stderr).
    # Derived unconditionally, BEFORE the `logger -t` gate below, because the two
    # channels are independent: the heartbeat unit ships under this tag whether or not
    # any `logger -t` call exists in the file. Coupling them would mean a post-cutover
    # removal of the now-pointless dark arm (a `logger -t` form) silently drops
    # `inngest-heartbeat` from EXPECTED — and AC3's failure text would then instruct the
    # engineer to delete the tag from vector.toml, re-blinding the exact channel #6536
    # exists to open. Derived, NOT folded into SYSTEMD_UNIT_IDENTIFIERS below: that list
    # is for identifiers no source line can yield (a bare binary basename), and parking a
    # derivable tag there would trade lockstep for the bypass its own comment forbids.
    grep -hoP '^SyslogIdentifier=\K[a-z0-9-]+$' "$f"
    # Channel B — a real `logger -t` invocation, NOT a comment mention (e.g. ci-deploy.sh
    # has a `# … logger -t …` doc comment) — a stdout-only script that merely
    # documents logger -t must not be pulled in. Three real forms are accepted:
    #   1. a direct `logger -t` at line-start or after a pipe;
    #   2. the fixture-seam form `"${CUTOVER_LOGGER_CMD:-logger}" -t` used by
    #      inngest-cutover-flip.sh (#6178) — the default `logger` sink wrapped so CI
    #      can inject a recorder;
    #   3. (#6536) a logger call carried inside a sed REPLACEMENT string — i.e. rendered
    #      into a generated script at bootstrap time rather than executed by the script
    #      itself. inngest-bootstrap.sh substitutes @@DARK_ARM@@ into the heartbeat ping
    #      script this way, so its `logger -t` sits after a literal `\n` in the sed
    #      expression and matches neither form 1 nor 2. Without this alternative the file
    #      never enters the loop, its LOG_TAG is never derived, and the tag it really does
    #      ship escapes the drift guard SILENTLY — an unmatched emission shape is a hole in
    #      the guard, not caught drift.
    # All three ship to the journal under SYSLOG_IDENTIFIER.
    grep -qE '(^|\|)[[:space:]]*logger -t|:-logger\}" -t|\\n[[:space:]]*logger -t' "$f" || continue
    grep -hoP '^\s*(readonly\s+)?LOG_TAG="\K[^"]+' "$f"
  done
  # #6556 Part 1 coverage extension — explicit SyslogIdentifier= in STANDALONE unit files
  # (*.service) and cloud-init write_files unit bodies (*.yml). These are NOT .sh heredocs and
  # were invisible to the pre-#6556 infra/*.sh-only scan. A comment never matches: the anchor
  # requires SyslogIdentifier= at line-start (the optional indentation covers the YAML-embedded
  # case). luks-monitor.service ships SyslogIdentifier=luks-monitor here (idempotent with the
  # #6627 luks-monitor.sh logger -t derivation — the union is sort -u'd at line ~442).
  grep -rhoP '^[[:space:]]*SyslogIdentifier=\K[a-z0-9-]+' "$INFRA_DIR"/*.service "$INFRA_DIR"/cloud-init*.yml 2>/dev/null
)
# #6178: some legitimate SYSLOG_IDENTIFIER entries come from a systemd UNIT's binary
# writing to stdout — NOT from a `logger -t` call in infra/*.sh — so they are not
# derivable above. webhook.service runs `/usr/local/bin/webhook -verbose` with no
# SyslogIdentifier override, so systemd tags its stdout SYSLOG_IDENTIFIER=webhook (the
# binary basename). Fold these into EXPECTED so AC3 still enforces logger-tag lockstep
# (a new/removed logger tag not mirrored here fails CI) without flagging the binary
# channel. Keep this list to genuine unit-binary identifiers, not a drift-guard bypass.
SYSTEMD_UNIT_IDENTIFIERS="webhook"
EXPECTED_TAGS=$(printf '%s\n%s\n' "$EXPECTED_TAGS" "$SYSTEMD_UNIT_IDENTIFIERS" | grep -v '^$' | sort -u)
# Array entries are quoted strings on their own lines inside the include_matches
# block; pull the bare tag from each.
ACTUAL_TAGS=$(echo "$HOST_SCRIPTS_BLOCK" | grep -oP '^\s*"\K[a-z0-9-]+(?="\s*,?\s*$)' | sort -u)
if [[ -n "$EXPECTED_TAGS" && "$EXPECTED_TAGS" == "$ACTUAL_TAGS" ]]; then
  PASS=$((PASS+1)); echo "  PASS: SYSLOG_IDENTIFIER tag set matches the infra emitters ($(echo "$EXPECTED_TAGS" | grep -c .) tags)"
else
  FAIL=$((FAIL+1)); FAILS+=("AC3: tag-set drift — host_scripts_journald array != the infra emitters.
    Reconcile in the direction the EMITTER dictates. A tag that is still emitted
    (a unit's SyslogIdentifier= or a live logger -t) but is missing from vector.toml
    means the channel does NOT ship — that is #6536 itself. Deleting the vector.toml
    entry to satisfy this assertion re-creates that bug; remove the EMITTER first, or
    add the entry.
    expected (from infra/*.sh SyslogIdentifier= units + logger -t scripts):
$(echo "$EXPECTED_TAGS" | sed 's/^/      /')
    actual (from vector.toml source array):
$(echo "$ACTUAL_TAGS" | sed 's/^/      /')")
fi

# AC3b (#6536): pin the SyslogIdentifier= channel as an INDEPENDENT derivation source.
# The heartbeat tag's justification is the unit's `SyslogIdentifier=inngest-heartbeat`,
# which ships doppler's and curl's stderr — NOT the dark arm's `logger -t`, which is
# cutover-scoped scaffolding and is meant to be deleted once the host goes live. If the
# two ever get re-coupled (e.g. the SyslogIdentifier= derivation is folded back inside
# the `logger -t` gate), removing the dark arm silently drops this tag from EXPECTED and
# AC3 starts demanding its deletion from vector.toml. Assert the channel yields the tag
# on its own, with no reference to any logger call.
SYSLOG_ID_DERIVED=$(grep -hoP '^SyslogIdentifier=\K[a-z0-9-]+$' "$INFRA_DIR"/*.sh | sort -u)
if printf '%s\n' "$SYSLOG_ID_DERIVED" | grep -qx 'inngest-heartbeat'; then
  PASS=$((PASS+1)); echo "  PASS: inngest-heartbeat derives from the unit's SyslogIdentifier= alone (independent of the dark arm)"
else
  FAIL=$((FAIL+1)); FAILS+=("AC3b: inngest-heartbeat is no longer derivable from a SyslogIdentifier= line in infra/*.sh.
    Either the unit lost SyslogIdentifier=inngest-heartbeat (the #6536 regression — its
    stderr silently retags to the ExecStart basename 'doppler' and matches no vector.toml
    source), or the derivation was re-coupled to the logger -t gate. Do NOT satisfy this
    by deleting the vector.toml entry.
    SyslogIdentifier= derived from infra/*.sh:
$(printf '%s\n' "$SYSLOG_ID_DERIVED" | sed 's/^/      /')")
fi

# AC3c (#6556 Part 1) — basename coverage for STANDALONE unit files (the "beyond infra/*.sh"
# half). A systemd unit with NO SyslogIdentifier= tags its journal output with the ExecStart
# BINARY BASENAME (systemd default). That is the #6556 class: inngest-heartbeat once tagged as
# `doppler` and shipped to no source. Require every such basename (from *.service files that
# declare no SyslogIdentifier=) to be EITHER in the Source 4 allowlist OR in the documented
# exclusion list — never silently un-covered. AC3/AC3b cover EXPLICIT declarations; this covers
# the implicit basename channel that AC3 cannot see.
#
# The explicit-exclusion half: a basename that legitimately does NOT ship to Source 4, WITH a
# reason. Keep this to genuine wrapper basenames, never a lockstep bypass for a real emitter.
declare -A SYSLOG_TAG_EXCLUSIONS=(
  [sh]="shared /bin/sh wrapper basename (cron-egress-{firewall,resolve}, cron-egress-alarm@, container-restart-monitor). Not a per-unit diagnostic channel — those units' payload scripts log under their own logger -t tags (covered by AC3); the bare /bin/sh wrapper carries nothing to ship."
  [doppler]="doppler-run wrapper basename (inngest-cutover-flip.service, inngest-redis.service). The wrapped binary's real output is captured by Source 1 inngest_journald (include_units) or is non-diagnostic; the bare 'doppler' channel is not a Source 4 log surface."
)

SERVICE_BASENAMES=""
SERVICE_BASENAME_VIOLATORS=""
SERVICE_SCANNED=0
BN_DERIVED=0
for svc in "$INFRA_DIR"/*.service; do
  SERVICE_SCANNED=$((SERVICE_SCANNED+1))
  # A unit that declares SyslogIdentifier= is covered by AC3 above, not by its basename.
  grep -qE '^[[:space:]]*SyslogIdentifier=' "$svc" && continue
  # Effective identifier = basename of the ExecStart binary (first non-space token). `^ExecStart=`
  # does NOT match ExecStartPre= (needs '=' right after ExecStart).
  binpath=$(grep -m1 -oE '^ExecStart=[^[:space:]]+' "$svc" | sed 's/^ExecStart=//')
  [[ -z "$binpath" ]] && continue
  tag="$(basename "$binpath")"
  SERVICE_BASENAMES+="$tag"$'\n'
  BN_DERIVED=$((BN_DERIVED+1))
  # Covered if shipped (in the allowlist) OR excluded-with-reason.
  printf '%s\n' "$ACTUAL_TAGS" | grep -qxF "$tag" && continue
  [[ -n "${SYSLOG_TAG_EXCLUSIONS[$tag]+x}" ]] && continue
  SERVICE_BASENAME_VIOLATORS+="$(basename "$svc") tags as '$tag' (ExecStart basename) — add SyslogIdentifier= + a Source 4 entry, or exclude '$tag' with a reason"$'\n'
done

if [[ "$SERVICE_SCANNED" -lt 1 || "$BN_DERIVED" -lt 3 ]]; then
  FAIL=$((FAIL+1)); FAILS+=("AC3c non-vacuity: expected >=1 .service scanned and >=3 basenames derived, got scanned=$SERVICE_SCANNED derived=$BN_DERIVED (extractor broke → the coverage check would pass vacuously)")
elif [[ -n "$SERVICE_BASENAME_VIOLATORS" ]]; then
  FAIL=$((FAIL+1)); FAILS+=("AC3c (#6556): a standalone unit tags as its ExecStart basename and is neither in Source 4 nor excluded:
$(printf '%s' "$SERVICE_BASENAME_VIOLATORS" | sed 's/^/      /')")
else
  PASS=$((PASS+1)); echo "  PASS: every no-SyslogIdentifier .service basename is allowlisted or excluded-with-reason ($SERVICE_SCANNED units scanned, $BN_DERIVED basenames)"
fi

# AC3c-disjoint: an exclusion must NOT also be a shipped tag (a tag is shipped OR excluded, never both).
EXCL_SHIPPED=""
for k in "${!SYSLOG_TAG_EXCLUSIONS[@]}"; do
  printf '%s\n' "$ACTUAL_TAGS" | grep -qxF "$k" && EXCL_SHIPPED+="$k "
done
if [[ -n "$EXCL_SHIPPED" ]]; then
  FAIL=$((FAIL+1)); FAILS+=("AC3c-disjoint: exclusion(s) also present in the Source 4 allowlist (a tag is either shipped OR excluded): $EXCL_SHIPPED")
else
  PASS=$((PASS+1)); echo "  PASS: exclusion set is disjoint from the Source 4 allowlist"
fi

# AC3c-stale: every exclusion must correspond to a basename a real .service actually produces —
# a dead exclusion for a non-existent emitter is drift the guard should surface.
STALE_EXCL=""
for k in "${!SYSLOG_TAG_EXCLUSIONS[@]}"; do
  printf '%s\n' "$SERVICE_BASENAMES" | grep -qxF "$k" || STALE_EXCL+="$k "
done
if [[ -n "$STALE_EXCL" ]]; then
  FAIL=$((FAIL+1)); FAILS+=("AC3c-stale: exclusion(s) for a basename no .service produces — remove the dead exclusion: $STALE_EXCL")
else
  PASS=$((PASS+1)); echo "  PASS: every exclusion corresponds to a real .service ExecStart basename"
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

#!/usr/bin/env bash
# Tests for inngest-registry-probe.sh — the 2.0 pre-flight empty-registry probe
# for the Inngest dedicated-host cutover (#6178, ADR-100). Verifies it returns a
# single pure-JSON OBJECT {registry_empty, function_count, function_ids} on stdout
# (webhook combined-stream purity — the workflow jq-parses the body as an object),
# reports registry_empty correctly for empty vs non-empty registries, and FAILS
# LOUD (non-zero + stderr, never a false-clean empty registry) on a non-array
# `.data.functions` — a fetch failure / GraphQL error / unexpected shape.
#
# Test seam: INNGEST_PROBE_FUNCTIONS_FIXTURE (a /v0/gql functions-query response
# file) short-circuits the curl. No network, no inngest, no root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-registry-probe.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

# Build a /v0/gql `functions` query response. $1 = JSON array of ids.
make_functions() {
  jq -nc --argjson ids "$1" '{data:{functions:[ $ids[] | {id:.} ]}}'
}

# --- Test 1: empty registry → registry_empty:true, function_count:0 ---
test_empty_registry() {
  echo "TEST: registry-probe — empty registry reports registry_empty:true count:0"
  local fixture; fixture=$(mktemp)
  make_functions '[]' > "$fixture"

  local out; out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET")
  assert_eq "stdout is a single JSON object" "object" "$(echo "$out" | jq -r 'type')"
  assert_eq "registry_empty is true" "true" "$(echo "$out" | jq -r '.registry_empty')"
  assert_eq "function_count is 0" "0" "$(echo "$out" | jq -r '.function_count')"
  assert_eq "function_ids is empty array" "0" "$(echo "$out" | jq -r '.function_ids | length')"
  rm -f "$fixture"
}

# --- Test 2: non-empty registry → registry_empty:false, function_count:N ---
test_nonempty_registry() {
  echo "TEST: registry-probe — non-empty registry reports registry_empty:false count:N"
  local fixture; fixture=$(mktemp)
  make_functions '["fn-b","fn-a"]' > "$fixture"

  local out; out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET")
  assert_eq "registry_empty is false" "false" "$(echo "$out" | jq -r '.registry_empty')"
  assert_eq "function_count is 2" "2" "$(echo "$out" | jq -r '.function_count')"
  # ids sorted deterministically
  assert_eq "function_ids sorted" "fn-a,fn-b" "$(echo "$out" | jq -r '.function_ids | join(",")')"
  rm -f "$fixture"
}

# --- Test 3: malformed / non-array .data.functions → fail LOUD (non-zero) ---
test_malformed_fails_loud() {
  echo "TEST: registry-probe — non-array .data.functions fails LOUD (non-zero, no false-clean)"
  local fixture; fixture=$(mktemp)
  # A GraphQL error envelope: .data.functions is absent/null, not an array.
  echo '{"errors":[{"message":"server down"}],"data":null}' > "$fixture"

  local rc=0 out
  out=$(INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" 2>/dev/null) || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on malformed response"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on malformed response (got rc=0, out=$out)"; FAIL=$((FAIL + 1)); fi
  # It must NOT emit a false-clean registry_empty:true.
  if echo "$out" | jq -e '.registry_empty == true' >/dev/null 2>&1; then
    echo "  FAIL: emitted a false-clean registry_empty:true on a malformed response"; FAIL=$((FAIL + 1));
  else echo "  PASS: no false-clean empty-registry emitted"; PASS=$((PASS + 1)); fi
  rm -f "$fixture"
}

# --- Test 4: a bare array (pre-#5517 wrong assumption) also fails LOUD ---
test_bare_array_fails_loud() {
  echo "TEST: registry-probe — bare-array response (not {data:{functions}}) fails LOUD"
  local fixture; fixture=$(mktemp)
  echo '[{"id":"fn-a"}]' > "$fixture"
  local rc=0
  INNGEST_PROBE_FUNCTIONS_FIXTURE="$fixture" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero on bare-array shape"; PASS=$((PASS + 1));
  else echo "  FAIL: expected non-zero exit on bare-array shape"; FAIL=$((FAIL + 1)); fi
  rm -f "$fixture"
}

# --- Test 5: script carries curl --max-time (no unbounded network call) ---
test_curl_max_time() {
  echo "TEST: registry-probe — curl carries --max-time"
  if grep -qE 'curl[^|]*--max-time' "$TARGET"; then
    echo "  PASS: curl --max-time present"; PASS=$((PASS + 1));
  else echo "  FAIL: no curl --max-time in $TARGET"; FAIL=$((FAIL + 1)); fi
}

# --- Test 6: targets the dedicated host GQL by default ---
test_default_gql_url() {
  echo "TEST: registry-probe — defaults to the dedicated host 10.0.1.40:8288/v0/gql"
  if grep -q '10.0.1.40:8288/v0/gql' "$TARGET"; then
    echo "  PASS: default INNGEST_REMOTE_GQL_URL targets 10.0.1.40:8288"; PASS=$((PASS + 1));
  else echo "  FAIL: default GQL URL does not target the dedicated host"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-registry-probe.sh test suite ==="
test_empty_registry
test_nonempty_registry
test_malformed_fails_loud
test_bare_array_fails_loud
test_curl_max_time
test_default_gql_url
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi

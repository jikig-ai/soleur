#!/usr/bin/env bash
# Tests for scripts/extract-api-spend.sh — the CI cost-capture redaction boundary
# (#5086). The script reads a claude-code-action `execution_file` (a JSON array
# whose final element is {"type":"result","total_cost_usd":N}) and emits ONLY an
# allowlisted record to stdout. It is the single redaction boundary between the
# raw execution log (which carries prompts, diffs, and runs under ANTHROPIC_API_KEY)
# and the committed api-spend ledger — so the security-critical assertions here are
# load-bearing (brand-survival threshold: single-user incident).
#
# Run via:  bash scripts/extract-api-spend.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/extract-api-spend.sh"
FIXTURE="$SCRIPT_DIR/fixtures/execution-file-sample.json"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixed CI-context env so output is deterministic.
export SOLEUR_RUN_ID="123456789"
export SOLEUR_SHA="abc1234"
export SOLEUR_WORKFLOW="claude-code-review.yml"
export SOLEUR_TIMESTAMP="2026-06-11T00:00:00Z"

ALLOWLIST='["input_tokens","model","output_tokens","provenance","run_id","sha","timestamp","total_cost_usd","workflow"]'

# --- Case (a): happy path emits EXACTLY the 9 allowlist keys, numerics typed ---
out="$($SCRIPT "$FIXTURE")"
keys="$(echo "$out" | jq -cS 'keys')"
[[ "$keys" == "$ALLOWLIST" ]] && pass "(a) keys are exactly the 9-field allowlist" || fail "(a) keys mismatch: $keys"

cost_type="$(echo "$out" | jq -r '.total_cost_usd | type')"
[[ "$cost_type" == "number" ]] && pass "(a) total_cost_usd is a number" || fail "(a) total_cost_usd type=$cost_type"
cost_val="$(echo "$out" | jq -r '.total_cost_usd')"
[[ "$cost_val" == "0.0347" ]] && pass "(a) total_cost_usd value preserved" || fail "(a) cost=$cost_val"

in_type="$(echo "$out" | jq -r '.input_tokens | type')"
out_type="$(echo "$out" | jq -r '.output_tokens | type')"
[[ "$in_type" == "number" && "$out_type" == "number" ]] && pass "(a) token fields are numbers" || fail "(a) token types in=$in_type out=$out_type"
in_sum="$(echo "$out" | jq -r '.input_tokens')"
out_sum="$(echo "$out" | jq -r '.output_tokens')"
[[ "$in_sum" == "300" && "$out_sum" == "100" ]] && pass "(a) tokens summed across assistant turns" || fail "(a) tokens in=$in_sum out=$out_sum"

prov="$(echo "$out" | jq -r '.provenance')"
[[ "$prov" == "recorded-actual" ]] && pass "(a) provenance = recorded-actual" || fail "(a) provenance=$prov"

# --- Case (b): a fake key in an EXCLUDED field never reaches output ---
b_fixture="$TMP/excluded.json"
fake_key="sk-ant-""api03-""AAAABBBBCCCCDDDDEEEEFFFF"  # concatenated; no contiguous literal in source
jq --arg k "$fake_key" '. + [{"type":"diagnostic","leaked_secret":$k}]' "$FIXTURE" > "$b_fixture"
out_b="$($SCRIPT "$b_fixture")"
echo "$out_b" | grep -q "sk-ant" && fail "(b) excluded-field key leaked into output" || pass "(b) excluded-field key absent from output"

# --- Case (c): a fake key injected INSIDE an allowlisted value (model) is scrubbed ---
# The redaction boundary must fail-closed when a secret shape appears in ANY value,
# not just rely on key projection (a leak can ride inside an allowlisted value).
c_fixture="$TMP/injected.json"
jq --arg k "claude-3-$fake_key" '(.[] | select(.type=="assistant") | .message.model) |= $k' "$FIXTURE" > "$c_fixture"
set +e
out_c="$($SCRIPT "$c_fixture")"; rc_c=$?
set -e
if echo "$out_c" | grep -q "sk-ant"; then
  fail "(c) value-injection: secret-shaped substring reached output"
else
  pass "(c) value-injection: no sk-ant substring in output (fail-closed)"
fi
[[ $rc_c -ne 0 ]] && pass "(c) value-injection fails closed (exit != 0)" || fail "(c) expected non-zero exit on secret-shaped value"

# --- Case (d): malformed / empty execution_file → empty output + exit != 0 ---
echo "not json {{{" > "$TMP/malformed.json"
set +e
out_d="$($SCRIPT "$TMP/malformed.json" 2>/dev/null)"; rc_d=$?
set -e
[[ -z "$out_d" && $rc_d -ne 0 ]] && pass "(d) malformed input → empty output + exit != 0" || fail "(d) out='$out_d' rc=$rc_d"

# Result object absent (no cost) → fail closed.
jq 'map(select(.type != "result"))' "$FIXTURE" > "$TMP/noresult.json"
set +e
out_e="$($SCRIPT "$TMP/noresult.json" 2>/dev/null)"; rc_e=$?
set -e
[[ -z "$out_e" && $rc_e -ne 0 ]] && pass "(d) missing result object → empty output + exit != 0" || fail "(d) noresult out='$out_e' rc=$rc_e"

echo
echo "extract-api-spend.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# Tests for tests/scripts/lib/destroy-guard-filter.jq (used inline by
# .github/workflows/apply-github-infra.yml "Destroy guard" step). Closes
# #3915 — proves the widened filter catches `required_check` nested-block
# removals on `github_repository_ruleset` that the pre-existing
# resource-level-only counter missed (AC20 of #4392 / PR #4395 shape).
#
# Deterministic; no network. Uses synthesized fixtures plus one captured
# real `terraform show -json` baseline (redacted).
#
# Re-capturing `tfplan-real-ruleset-baseline.json` (e.g. after a provider
# upgrade trips T5):
#   cd infra/github
#   doppler run -p soleur -c prd_terraform -- terraform init
#   AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain) \
#   AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain) \
#     doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
#       terraform plan -no-color -input=false -out=/tmp/tfplan
#   terraform show -json /tmp/tfplan > /tmp/raw.json
#   # MUST strip .variables — terraform-show-json embeds sensitive HCL vars
#   # (including the App private key) regardless of sensitive=true. See the
#   # 2026-05-25 incident / hr-tfplan-fixture-redaction-mandatory.
#   jq 'del(.variables) | del(.. | .bypass_actors? | .[]?.actor_id?)' /tmp/raw.json \
#     > tests/scripts/fixtures/tfplan-real-ruleset-baseline.json
#   # Verify no PEM/token bytes survive:
#   ! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|ghs_|github_pat_|sbp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' \
#       tests/scripts/fixtures/tfplan-real-ruleset-baseline.json
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter.jq"
FIXTURES="$REPO_ROOT/tests/scripts/fixtures"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Mirror the workflow's bash pipeline exactly so the test exercises the
# same control flow the gate runs in CI. Returns "rdel:ndel:dcount:rc"
# where rc encodes the gate's exit (0 pass, 1 trip). HEAD_MSG passed as
# arg so the [ack-destroy] branch is exercised identically.
_run_gate() {
  local fixture="$1" head_msg="$2"
  local counts rdel ndel dcount ack rc=0
  if ! counts=$(jq -f "$FILTER" < "$fixture" 2>/dev/null); then
    echo "ERROR:ERROR:ERROR:99"
    return
  fi
  rdel=$(echo "$counts" | jq -r '.resource_deletes')
  ndel=$(echo "$counts" | jq -r '.nested_deletes')
  if [[ ! "$rdel" =~ ^[0-9]+$ ]] || [[ ! "$ndel" =~ ^[0-9]+$ ]]; then
    echo "PARSE:PARSE:PARSE:1"
    return
  fi
  dcount=$((rdel + ndel))
  ack=false
  # Byte-identical to apply-github-infra.yml:244.
  if [[ "$head_msg" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
    ack=true
  fi
  if [[ "$dcount" -gt 0 ]] && [[ "$ack" != "true" ]]; then
    rc=1
  fi
  echo "$rdel:$ndel:$dcount:$rc"
}

# Case 1: resource-level delete trips the gate (no ack).
t_resource_delete_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-resource-delete.json" "feat: drop legacy ruleset")
  if [[ "$out" == "1:0:1:1" ]]; then
    _report "T1 resource-delete trips guard (rdel=1 ndel=0 dcount=1 rc=1)" ok
  else
    _report "T1 resource-delete trips guard" fail "got '$out' want '1:0:1:1'"
  fi
}

# Case 2: nested required_check removal trips the gate (PR #4395 shape).
t_nested_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-nested-block-removal.json" "feat: tweak ruleset")
  if [[ "$out" == "0:1:1:1" ]]; then
    _report "T2 nested required_check removal trips guard (rdel=0 ndel=1 dcount=1 rc=1)" ok
  else
    _report "T2 nested required_check removal trips guard" fail "got '$out' want '0:1:1:1'"
  fi
}

# Case 3: no-changes plan passes silently.
t_no_changes_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-no-changes.json" "feat: docs only")
  if [[ "$out" == "0:0:0:0" ]]; then
    _report "T3 no-changes plan passes (rdel=0 ndel=0 dcount=0 rc=0)" ok
  else
    _report "T3 no-changes plan passes" fail "got '$out' want '0:0:0:0'"
  fi
}

# Case 4: nested removal + [ack-destroy] line on its own → gate allows
# the destructive plan through.
t_ack_destroy_allows_nested() {
  local msg
  msg=$'feat: rename CI job\n\n[ack-destroy]\n\nRefs #4395.'
  local out; out=$(_run_gate "$FIXTURES/tfplan-nested-block-removal.json" "$msg")
  if [[ "$out" == "0:1:1:0" ]]; then
    _report "T4 [ack-destroy] line allows nested removal through (rc=0)" ok
  else
    _report "T4 [ack-destroy] line allows nested removal through" fail "got '$out' want '0:1:1:0'"
  fi
}

# Regression anchor: captured real `terraform show -json` against
# infra/github/ HEAD (redacted) is a no-op plan; destroy_count must be 0.
# Drift here = provider upgrade changed the JSON path the filter walks.
t_real_baseline_zero() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-real-ruleset-baseline.json" "")
  if [[ "$out" == "0:0:0:0" ]]; then
    _report "T5 captured real baseline yields destroy_count=0 (regression anchor)" ok
  else
    _report "T5 captured real baseline yields destroy_count=0 (regression anchor)" fail "got '$out' want '0:0:0:0'"
  fi
}

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: $FILTER does not exist — RED phase expected this." >&2
  exit 1
fi

# Case 6: [ack-destroy] as substring mid-line (NOT line-anchored) must NOT
# satisfy the gate. Pins the (^|\n)\[ack-destroy\]($|\n) regex against a
# future "simplification" to bare =~ \[ack-destroy\].
t_ack_destroy_substring_rejected() {
  local msg="chore: discuss [ack-destroy] policy inline"
  local out; out=$(_run_gate "$FIXTURES/tfplan-nested-block-removal.json" "$msg")
  if [[ "$out" == "0:1:1:1" ]]; then
    _report "T6 [ack-destroy] substring (not line-anchored) is rejected (rc=1)" ok
  else
    _report "T6 [ack-destroy] substring (not line-anchored) is rejected" fail "got '$out' want '0:1:1:1'"
  fi
}

# Case 7: one resource-level delete AND one nested removal on a DIFFERENT
# ruleset must sum cleanly without double-counting. Pins the
# `select(.change.actions? | index("delete") | not)` clause in the filter.
t_mixed_delete_and_nested() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-mixed-delete-and-nested.json" "feat: drop legacy + rename CI job")
  if [[ "$out" == "1:1:2:1" ]]; then
    _report "T7 mixed resource-delete + nested removal sum to 2 (no double-count)" ok
  else
    _report "T7 mixed resource-delete + nested removal sum to 2 (no double-count)" fail "got '$out' want '1:1:2:1'"
  fi
}

t_resource_delete_trips
t_nested_removal_trips
t_no_changes_passes
t_ack_destroy_allows_nested
t_real_baseline_zero
t_ack_destroy_substring_rejected
t_mixed_delete_and_nested

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]

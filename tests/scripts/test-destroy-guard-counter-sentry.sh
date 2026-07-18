#!/usr/bin/env bash
# Tests for tests/scripts/lib/destroy-guard-filter-sentry.jq (used inline by
# .github/workflows/apply-sentry-infra.yml "Terraform plan (cron + uptime
# monitors)" step). Closes #4419 (sibling of #4420 — the github-infra widening).
#
# Deterministic; no network. Uses synthesized fixtures plus one captured
# real `terraform show -json` baseline (redacted).
#
# Re-capturing `tfplan-sentry-real-baseline.json` (e.g. after a provider
# upgrade trips T4). The plan is FULL-ROOT (#6589) — no address scoping. The
# ~20-line `-target=` recipe that used to live here has been deleted rather than
# refreshed: it described a mechanism that no longer exists, and a stale recipe
# for a retired mechanism is how #4929's leak survived two months in a comment.
#   cd apps/web-platform/infra/sentry
#   # NOTE: the provider reads a RAW `SENTRY_AUTH_TOKEN`. Do NOT pass it through
#   # `doppler run --name-transformer tf-var` — that mangles it to
#   # TF_VAR_sentry_auth_token and the provider dies with
#   # "failed to perform health check".
#   SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd_terraform --plain) \
#     doppler run -p soleur -c prd_terraform -- terraform init -input=false
#   SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd_terraform --plain) \
#     doppler run -p soleur -c prd_terraform -- \
#       terraform plan -no-color -input=false -out=/tmp/tfplan
#   terraform show -json /tmp/tfplan > /tmp/raw.json
#   # MANDATORY redaction: drop .variables (TF_VAR_*-sourced Doppler tokens),
#   # planned_values/prior_state/configuration (carry resolved provider tokens
#   # at plan time), and Sentry's per-output blocks (applyable/checks/etc.).
#   # The filter only consumes .resource_changes and .output_changes — every
#   # other key is dead weight AND a forward-looking secret-leak surface (a
#   # future schema bump could expose auth_token / DSN bytes in prior_state).
#   jq 'del(.variables, .planned_values, .prior_state, .configuration,
#          .relevant_attributes, .applyable, .complete, .errored, .checks,
#          .timestamp)' /tmp/raw.json \
#     > tests/scripts/fixtures/tfplan-sentry-real-baseline.json
#   # Verify no token bytes survive (extended sentinel covers Cloudflare /
#   # Doppler / Resend / Sentry bespoke shapes beyond the pre-#4419 set):
#   ! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|ghs_|github_pat_|sbp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk_(test|live)_[a-zA-Z0-9]{24,}|sntrys_|dp\.st\.|re_[A-Za-z0-9]{16,}' \
#       tests/scripts/fixtures/tfplan-sentry-real-baseline.json
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter-sentry.jq"
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
  # Byte-identical to apply-sentry-infra.yml's [ack-destroy] regex.
  if [[ "$head_msg" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
    ack=true
  fi
  if [[ "$dcount" -gt 0 ]] && [[ "$ack" != "true" ]]; then
    rc=1
  fi
  echo "$rdel:$ndel:$dcount:$rc"
}

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: $FILTER does not exist — RED phase expected this." >&2
  exit 1
fi

# T1: resource-level delete trips the gate (no ack).
t_resource_delete_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "feat: drop scheduled-foo monitor")
  if [[ "$out" == "1:0:1:1" ]]; then
    _report "T1 sentry_cron_monitor delete trips guard (rdel=1 ndel=0 dcount=1 rc=1)" ok
  else
    _report "T1 sentry_cron_monitor delete trips guard" fail "got '$out' want '1:0:1:1'"
  fi
}

# T2: no-changes plan passes silently.
t_no_changes_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-no-changes.json" "feat: docs only")
  if [[ "$out" == "0:0:0:0" ]]; then
    _report "T2 no-changes plan passes (rdel=0 ndel=0 dcount=0 rc=0)" ok
  else
    _report "T2 no-changes plan passes" fail "got '$out' want '0:0:0:0'"
  fi
}

# T3: resource delete + [ack-destroy] line allows through.
t_ack_destroy_allows_resource_delete() {
  local msg
  msg=$'feat: retire scheduled-foo monitor\n\n[ack-destroy]\n\nRefs #4419.'
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "$msg")
  if [[ "$out" == "1:0:1:0" ]]; then
    _report "T3 [ack-destroy] line allows sentry delete through (rc=0)" ok
  else
    _report "T3 [ack-destroy] line allows sentry delete through" fail "got '$out' want '1:0:1:0'"
  fi
}

# T4: regression anchor against captured real baseline plan.
# (Skipped automatically if the captured fixture does not exist locally
# — operator captures it via the header-comment procedure above.)
t_real_baseline_zero() {
  if [[ ! -f "$FIXTURES/tfplan-sentry-real-baseline.json" ]]; then
    _report "T4 captured real baseline yields destroy_count=0 (regression anchor)" fail \
      "fixture missing — operator must capture per file-header procedure"
    return
  fi
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-real-baseline.json" "")
  if [[ "$out" == "0:0:0:0" ]]; then
    _report "T4 captured real baseline yields destroy_count=0 (regression anchor)" ok
  else
    _report "T4 captured real baseline yields destroy_count=0 (regression anchor)" fail "got '$out' want '0:0:0:0'"
  fi
}

# T5: [ack-destroy] as substring mid-line (NOT line-anchored) must NOT
# satisfy the gate. Pins the (^|\n)\[ack-destroy\]($|\n) regex against a
# future "simplification" to bare =~ \[ack-destroy\].
t_ack_destroy_substring_rejected() {
  local msg="chore: discuss [ack-destroy] policy inline"
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "$msg")
  if [[ "$out" == "1:0:1:1" ]]; then
    _report "T5 [ack-destroy] substring (not line-anchored) is rejected (rc=1)" ok
  else
    _report "T5 [ack-destroy] substring (not line-anchored) is rejected" fail "got '$out' want '1:0:1:1'"
  fi
}

# T6 (#4364): an UPDATE on sentry_issue_alert that removes one filters_v2 block
# (2 -> 1) is a nested-block delete that resource_deletes cannot see. The
# sentry_issue_alert nested-clause must count it (rdel=0 ndel=1 dcount=1 rc=1).
# Pins that the BYOK apply-created rules' array-of-blocks shrink trips the guard.
t_issue_alert_nested_delete_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-issue-alert-nested-delete.json" "feat: narrow byok alert filter")
  if [[ "$out" == "0:1:1:1" ]]; then
    _report "T6 sentry_issue_alert filters_v2 shrink trips nested guard (rdel=0 ndel=1 dcount=1 rc=1)" ok
  else
    _report "T6 sentry_issue_alert filters_v2 shrink trips nested guard" fail "got '$out' want '0:1:1:1'"
  fi
}

# T7 (#6589): resource_creates counts a PURE create. The delete direction was
# guarded and the create direction was not; once full-root brings the 4
# formerly-untargeted alerts into scope, state/config divergence surfaces as an
# unreviewed CREATE — the same billing leak in mirror image.
t_pure_create_counted() {
  local got
  got=$(echo '{"resource_changes":[{"type":"sentry_cron_monitor","address":"sentry_cron_monitor.y","change":{"actions":["create"],"before":null,"after":{}}}]}' \
    | jq -f "$FILTER" -c)
  if [[ "$got" == '{"resource_deletes":0,"resource_creates":1,"nested_deletes":0}' ]]; then
    _report "T7 pure create is counted in resource_creates" ok
  else
    _report "T7 pure create is counted in resource_creates" fail "got '$got'"
  fi
}

# T8 (#6589): a REPLACE (["delete","create"]) must NOT be counted as a create.
# It is already a destroy, so it already trips [ack-destroy]; counting it twice
# would fail a correctly-acknowledged plan for a second reason and push the
# author toward a blanket ack — the ack-blindness the create gate exists to
# avoid training. Pins the exact-equality shape against a "simplification" to
# `index("create")`, which would silently start counting every replace.
t_replace_not_counted_as_create() {
  local got
  got=$(echo '{"resource_changes":[{"type":"sentry_cron_monitor","address":"sentry_cron_monitor.x","change":{"actions":["delete","create"],"before":{},"after":{}}}]}' \
    | jq -f "$FILTER" -c)
  if [[ "$got" == '{"resource_deletes":1,"resource_creates":0,"nested_deletes":0}' ]]; then
    _report "T8 replace counts as a delete, NOT as a create (no double jeopardy)" ok
  else
    _report "T8 replace counts as a delete, NOT as a create" fail "got '$got' want deletes=1 creates=0"
  fi
}

# T9 (#6589): the measured live baseline creates nothing. AC5's sub-assertion.
t_real_baseline_zero_creates() {
  if [[ ! -f "$FIXTURES/tfplan-sentry-real-baseline.json" ]]; then
    _report "T9 captured real baseline yields resource_creates=0" fail "fixture missing"
    return
  fi
  local got; got=$(jq -f "$FILTER" < "$FIXTURES/tfplan-sentry-real-baseline.json" | jq -r '.resource_creates')
  if [[ "$got" == "0" ]]; then
    _report "T9 captured real baseline yields resource_creates=0" ok
  else
    _report "T9 captured real baseline yields resource_creates=0" fail "got '$got'"
  fi
}

t_resource_delete_trips
t_no_changes_passes
t_ack_destroy_allows_resource_delete
t_real_baseline_zero
t_ack_destroy_substring_rejected
t_issue_alert_nested_delete_trips
t_pure_create_counted
t_replace_not_counted_as_create
t_real_baseline_zero_creates

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]

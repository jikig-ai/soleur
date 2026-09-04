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
COUNTS="$REPO_ROOT/scripts/sentry-destroy-counts.sh"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
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
# same control flow the gate runs in CI. Returns "rdel:ndel:rfor:dcount:rc"
# where rc encodes the gate's exit (0 pass, 1 trip). HEAD_MSG passed as
# arg so the [ack-destroy] branch is exercised identically.
#
# The arithmetic is NOT re-derived here. It used to be — `dcount=$((rdel + ndel))`
# hand-rolled in this helper — which made this the FOURTH copy of the sum that
# `scripts/sentry-destroy-counts.sh` exists to be the only copy of. A harness
# that computes the answer itself cannot fail when the thing it is testing stops
# computing it: when `resource_forgets` joined the sum (#7650 Phase 2), a
# hand-rolled `rdel + ndel` here would have reported the gate PASSING a forget-only
# plan while the real gate tripped, or vice versa, with no test going red either
# way. So the helper `eval`s the shipped script, exactly as both workflow jobs do.
_run_gate() {
  local fixture="$1" head_msg="$2"
  local ack rc=0
  local resource_deletes resource_creates resource_forgets nested_deletes destroy_count
  if ! eval "$(bash "$COUNTS" "$fixture" 2>/dev/null)"; then
    echo "ERROR:ERROR:ERROR:ERROR:99"
    return
  fi
  local rdel="$resource_deletes" ndel="$nested_deletes"
  local rfor="$resource_forgets" dcount="$destroy_count"
  for v in "$rdel" "$ndel" "$rfor" "$dcount"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "PARSE:PARSE:PARSE:PARSE:1"
      return
    fi
  done
  ack=false
  # Byte-identical to apply-sentry-infra.yml's [ack-destroy] regex.
  if [[ "$head_msg" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
    ack=true
  fi
  if [[ "$dcount" -gt 0 ]] && [[ "$ack" != "true" ]]; then
    rc=1
  fi
  echo "$rdel:$ndel:$rfor:$dcount:$rc"
}

# Per-FIELD extraction, never a whole-object literal. T7/T8 used to compare the
# filter's entire compact JSON output against a hardcoded string; adding ANY new
# key — `resource_forgets`, say — reds both of them for a reason that has nothing
# to do with what either test is about, which trains "just re-paste the new
# literal" and is how a genuine regression in an unrelated field gets pasted over.
# Reads stdin (a plan document) and emits "rdel:ndel:rfor:rcre".
#
# Two jq invocations on purpose, same reason as `_sa_case` below: `-f FILE` plus a
# positional filter makes jq read the positional as a SECOND program file and die
# with "could not open file".
_fields() {
  jq -f "$FILTER" -c \
    | jq -r '"\(.resource_deletes):\(.nested_deletes):\(.resource_forgets):\(.resource_creates)"'
}

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: $FILTER does not exist — RED phase expected this." >&2
  exit 1
fi
if [[ ! -f "$COUNTS" ]]; then
  echo "ERROR: $COUNTS does not exist — RED phase expected this." >&2
  exit 1
fi

# T1: resource-level delete trips the gate (no ack).
t_resource_delete_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "feat: drop scheduled-foo monitor")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T1 sentry_cron_monitor delete trips guard (rdel=1 ndel=0 rfor=0 dcount=1 rc=1)" ok
  else
    _report "T1 sentry_cron_monitor delete trips guard" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T2: no-changes plan passes silently.
t_no_changes_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-no-changes.json" "feat: docs only")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T2 no-changes plan passes (rdel=0 ndel=0 rfor=0 dcount=0 rc=0)" ok
  else
    _report "T2 no-changes plan passes" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T3: resource delete + [ack-destroy] line allows through.
t_ack_destroy_allows_resource_delete() {
  local msg
  msg=$'feat: retire scheduled-foo monitor\n\n[ack-destroy]\n\nRefs #4419.'
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "$msg")
  if [[ "$out" == "1:0:0:1:0" ]]; then
    _report "T3 [ack-destroy] line allows sentry delete through (rc=0)" ok
  else
    _report "T3 [ack-destroy] line allows sentry delete through" fail "got '$out' want '1:0:0:1:0'"
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
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T4 captured real baseline yields destroy_count=0 (regression anchor)" ok
  else
    _report "T4 captured real baseline yields destroy_count=0 (regression anchor)" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T5: [ack-destroy] as substring mid-line (NOT line-anchored) must NOT
# satisfy the gate. Pins the (^|\n)\[ack-destroy\]($|\n) regex against a
# future "simplification" to bare =~ \[ack-destroy\].
t_ack_destroy_substring_rejected() {
  local msg="chore: discuss [ack-destroy] policy inline"
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-resource-delete.json" "$msg")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T5 [ack-destroy] substring (not line-anchored) is rejected (rc=1)" ok
  else
    _report "T5 [ack-destroy] substring (not line-anchored) is rejected" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T6 (#4364): an UPDATE on sentry_issue_alert that removes one filters_v2 block
# (2 -> 1) is a nested-block delete that resource_deletes cannot see. The
# sentry_issue_alert nested-clause must count it (rdel=0 ndel=1 dcount=1 rc=1).
# Pins that the BYOK apply-created rules' array-of-blocks shrink trips the guard.
t_issue_alert_nested_delete_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-sentry-issue-alert-nested-delete.json" "feat: narrow byok alert filter")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T6 sentry_issue_alert filters_v2 shrink trips nested guard (rdel=0 ndel=1 rfor=0 dcount=1 rc=1)" ok
  else
    _report "T6 sentry_issue_alert filters_v2 shrink trips nested guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T7 (#6589): resource_creates counts a PURE create. The delete direction was
# guarded and the create direction was not; once full-root brings the 4
# formerly-untargeted alerts into scope, state/config divergence surfaces as an
# unreviewed CREATE — the same billing leak in mirror image.
t_pure_create_counted() {
  local got
  got=$(echo '{"resource_changes":[{"type":"sentry_cron_monitor","address":"sentry_cron_monitor.y","change":{"actions":["create"],"before":null,"after":{}}}]}' \
    | _fields)
  if [[ "$got" == "0:0:0:1" ]]; then
    _report "T7 pure create is counted in resource_creates" ok
  else
    _report "T7 pure create is counted in resource_creates" fail "got '$got' want rdel:ndel:rfor:rcre = 0:0:0:1"
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
    | _fields)
  if [[ "$got" == "1:0:0:0" ]]; then
    _report "T8 replace counts as a delete, NOT as a create (no double jeopardy)" ok
  else
    _report "T8 replace counts as a delete, NOT as a create" fail "got '$got' want rdel:ndel:rfor:rcre = 1:0:0:0"
  fi
}

# T10-T14 (#7650): sentry_alert nested surfaces. Added BEFORE any sentry_alert
# enters a plan — the filter counts nested shrink per-type with no walk(), so a
# type with no clause has its shrink counted as 0 and slips silently. That is the
# whole failure mode, and it is not observable from a passing plan.
#
# Attribute names taken from the provider docs at v0.15.5, not from the migration
# plan's prose: that prose had the frequency mapping wrong (Phase 0 evidence,
# knowledge-base/project/specs/fix-7650-sentry-alert-migration/).
_sa_plan() { # $1=before $2=after -> a one-resource update plan
  printf '{"resource_changes":[{"type":"sentry_alert","address":"sentry_alert.zot","change":{"actions":["update"],"before":%s,"after":%s}}]}' "$1" "$2"
}
_SA_FULL='{"trigger_conditions":[{"type":"event_frequency_count"}],"legacy_trigger_conditions":["new_high_priority_issue"],"action_filters":[{"logic_type":"all","conditions":[{"type":"tagged_event"},{"type":"tagged_event"}],"actions":[{"email":{}}]}]}'

_sa_case() { # $1=label $2=after-json $3=want-ndel
  local got want="$3"
  # Two jq invocations on purpose: `-f FILE` plus a positional filter makes jq read
  # the positional as a second program FILE, which fails as "could not open file".
  got=$(_sa_plan "$_SA_FULL" "$2" | jq -f "$FILTER" -c | jq -r '.nested_deletes')
  if [[ "$got" == "$want" ]]; then _report "$1" ok
  else _report "$1" fail "nested_deletes got '$got' want '$want'"; fi
}

t_sentry_alert_noop_is_zero() {
  _sa_case "T10 sentry_alert no-op scores 0" "$_SA_FULL" 0
}

t_sentry_alert_condition_shrink_trips() {
  _sa_case "T11 dropping one action_filters[].conditions[] element trips the guard" \
    '{"trigger_conditions":[{"type":"event_frequency_count"}],"legacy_trigger_conditions":["new_high_priority_issue"],"action_filters":[{"logic_type":"all","conditions":[{"type":"tagged_event"}],"actions":[{"email":{}}]}]}' 1
}

# The one most easily missed: legacy_trigger_conditions is a List of STRING, not
# blocks, and the provider documents "when omitted from config these will be
# removed on the next apply". A shrink here silently drops a live trigger type the
# provider cannot represent natively. Counted for exactly that reason.
t_sentry_alert_legacy_trigger_shrink_trips() {
  _sa_case "T12 dropping a legacy_trigger_conditions entry trips the guard" \
    '{"trigger_conditions":[{"type":"event_frequency_count"}],"legacy_trigger_conditions":[],"action_filters":[{"logic_type":"all","conditions":[{"type":"tagged_event"},{"type":"tagged_event"}],"actions":[{"email":{}}]}]}' 1
}

# Container AND contents are counted, so removing a whole filter registers a larger
# shrink than removing one condition inside it. Pinning the magnitude keeps a
# future "simplification" to counting only the container from passing quietly.
t_sentry_alert_whole_filter_removal_counts_contents() {
  _sa_case "T13 removing a whole action_filters block counts its contents too (4)" \
    '{"trigger_conditions":[{"type":"event_frequency_count"}],"legacy_trigger_conditions":["new_high_priority_issue"],"action_filters":[]}' 4
}

# Growth must not produce a negative that could offset a real shrink elsewhere in
# the same plan. `select(. > 0)` per resource is what enforces this; T14 pins it.
t_sentry_alert_growth_is_not_negative() {
  _sa_case "T14 adding a condition scores 0, never negative" \
    '{"trigger_conditions":[{"type":"event_frequency_count"}],"legacy_trigger_conditions":["new_high_priority_issue"],"action_filters":[{"logic_type":"all","conditions":[{"type":"tagged_event"},{"type":"tagged_event"},{"type":"level"}],"actions":[{"email":{}}]}]}' 0
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

# ── T15-T21 (#7650 Phase 2): Guard C — `forget` counted, for every type ─────
# A `removed { lifecycle { destroy = false } }` block plans as `actions:["forget"]`.
# Before this counter existed NOTHING in the chain saw it: not `resource_deletes`
# (which selects `index("delete")`), and not the nested arithmetic (cron and uptime
# monitors expose zero array-of-blocks by design, so their shrink is always 0). A
# plan that dropped every cron monitor out of state scored `destroy_count = 0` and
# the gate printed `PASS (plan destroys nothing)`.
#
# Every expectation below is stated at the GATE'S VERDICT (the `rc` field), not at
# the counter's output. A matrix that asserts `resource_forgets = 1` and stops is
# green by construction on the one implementation that leaves the hole open: the
# counter emitted, correctly, and never summed.
_forget_plan() { # $1=type -> a one-resource forget plan on stdout
  printf '{"resource_changes":[{"type":"%s","address":"%s.gone","mode":"managed","change":{"actions":["forget"],"before":{},"after":null}}]}' "$1" "$1"
}

_forget_fixture() { # $1=type -> path to a temp fixture file
  local f; f="$TMPD/forget-$1.json"
  _forget_plan "$1" > "$f"
  echo "$f"
}

# Row 1 — cron monitor. The type with no nested clause, so the forget counter is
# the ONLY thing standing between this plan and a green gate.
t_forget_cron_monitor_trips_gate() {
  local out; out=$(_run_gate "$(_forget_fixture sentry_cron_monitor)" "chore: tidy state")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T15 forget on sentry_cron_monitor TRIPS the gate (rdel=0 ndel=0 rfor=1 dcount=1 rc=1)" ok
  else
    _report "T15 forget on sentry_cron_monitor TRIPS the gate" fail \
      "got '$out' want '0:0:1:1:1' — rc=0 here means a plan that drops a monitor out of management passes as 'destroys nothing'"
  fi
}

# Row 2 — uptime monitor. Same argument; asserted separately because the counter
# is deliberately type-independent and a type-scoped 'fix' would pass row 1 alone.
t_forget_uptime_monitor_trips_gate() {
  local out; out=$(_run_gate "$(_forget_fixture sentry_uptime_monitor)" "chore: tidy state")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T16 forget on sentry_uptime_monitor TRIPS the gate" ok
  else
    _report "T16 forget on sentry_uptime_monitor TRIPS the gate" fail "got '$out' want '0:0:1:1:1'"
  fi
}

# Row 3 — the AC4 discrimination. A forget on a nested-block-bearing type is
# counted in BOTH `resource_forgets` and `nested_deletes` (its `after` is null, so
# every block reads as removed), while `resource_deletes` stays 0. That zero is
# what lets the merge say "27 forgets, nothing actually destroyed" and have it be
# checkable rather than asserted.
t_forget_issue_alert_keeps_deletes_zero() {
  local f="$TMPD/forget-ia.json"
  printf '{"resource_changes":[{"type":"sentry_issue_alert","address":"sentry_issue_alert.gone","mode":"managed","change":{"actions":["forget"],"before":{"conditions_v2":[{}],"filters_v2":[{}],"actions_v2":[{}]},"after":null}}]}' > "$f"
  local out; out=$(_run_gate "$f" "chore: adopt as sentry_alert")
  if [[ "$out" == "0:3:1:4:1" ]]; then
    _report "T17 forget on sentry_issue_alert: rfor=1 AND ndel=3, resource_deletes stays 0 (AC4)" ok
  else
    _report "T17 forget on sentry_issue_alert keeps resource_deletes at 0" fail \
      "got '$out' want '0:3:1:4:1' — a non-zero first field means forget was folded into resource_deletes and AC4 is unsatisfiable"
  fi
}

# Row 4 — the mutation that leaves the hole open AND certified closed: implement
# `resource_forgets`, emit it, and never sum it. Mutating the shipped script's sum
# must flip T15's verdict; if it does not, T15 is not testing the sum.
t_forget_must_be_summed_into_destroy_count() {
  local mroot="$TMPD/mut-sum"
  mkdir -p "$mroot/scripts" "$mroot/tests/scripts/lib"
  cp "$FILTER" "$mroot/tests/scripts/lib/destroy-guard-filter-sentry.jq"
  sed 's/resource_deletes + nested_deletes + resource_forgets/resource_deletes + nested_deletes/' \
    "$COUNTS" > "$mroot/scripts/sentry-destroy-counts.sh"
  # Assert the mutation LANDED. A sed that silently matched nothing would leave an
  # identical copy, the test below would behave like the real script, and this row
  # would report a pass while proving nothing.
  local mut="$mroot/scripts/sentry-destroy-counts.sh"
  if grep -qF 'resource_deletes + nested_deletes + resource_forgets' "$mut" \
     || ! grep -qF '$((resource_deletes + nested_deletes))' "$mut"; then
    _report "T18 an un-summed resource_forgets yields destroy_count=0" fail \
      "the mutation did not land — the three-term sum survived or the two-term form is absent, so this row proves nothing"
    return
  fi
  local f; f=$(_forget_fixture sentry_cron_monitor)
  local dc; dc=$(bash "$mut" "$f" 2>/dev/null | grep -oP '^destroy_count=\K.*')
  if [[ "$dc" == "0" ]]; then
    _report "T18 an un-summed resource_forgets yields destroy_count=0 — so T15 is load-bearing" ok
  else
    _report "T18 an un-summed resource_forgets yields destroy_count=0" fail \
      "mutated script gave destroy_count='$dc' (want 0); T15 would pass either way, so the sum is untested"
  fi
}

# Row 6 — a plan with no changes at all. `resource_forgets = 0`, the gate exits 0,
# and the script still emits ALL FIVE keys: a missing key breaks the caller's
# `eval` under `set -u`, which is the exact shipped bug this chain already had once.
t_no_changes_still_emits_forgets_key() {
  local out; out=$(bash "$COUNTS" "$FIXTURES/tfplan-sentry-no-changes.json")
  local missing=()
  for k in resource_deletes resource_creates resource_forgets nested_deletes destroy_count; do
    grep -qE "^${k}=[0-9]+$" <<<"$out" || missing+=("$k")
  done
  if [[ ${#missing[@]} -eq 0 ]] && grep -qx 'resource_forgets=0' <<<"$out"; then
    _report "T19 a no-changes plan emits all five keys with resource_forgets=0" ok
  else
    _report "T19 a no-changes plan emits all five keys" fail "missing: ${missing[*]:-none}; got: $out"
  fi
}

# Row 7 — the operator manifest. `destroy_count` now has three terms, so an
# address-display selecting `== ["delete"]` prints an EMPTY list while the gate
# claims N destructive changes: an ack with no manifest. Both jobs must select
# forgets too, and must label them separately from real deletes.
t_workflow_displays_forget_addresses() {
  local wf="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
  local forget_sel exact_delete_sel
  forget_sel=$(grep -cE 'select\(\.change\.actions \| index\("forget"\)\)' "$wf" || true)
  # The pre-#7650 shape. Exact-equality on the DISPLAY query is what emptied the list.
  exact_delete_sel=$(grep -cE 'select\(\.change\.actions == \["delete"\]\) \| \.address' "$wf" || true)
  if [[ "$forget_sel" -ge 1 && "$exact_delete_sel" -eq 0 ]]; then
    _report "T20 the destroy gate displays forget addresses, not an empty list" ok
  else
    _report "T20 the destroy gate displays forget addresses" fail \
      "forget-selecting display queries=$forget_sel (want >=1), surviving exact-\["delete"\] address queries=$exact_delete_sel (want 0)"
  fi
}

# Harness row (b) — a must-PASS plan. Two `["update"]` rows, no forgets: the gate
# exits 0 and `resource_forgets` is 0. Without this the whole block above could be
# satisfied by a counter stuck at 1.
t_updates_only_yields_zero_forgets() {
  local f="$TMPD/updates.json"
  printf '{"resource_changes":[{"type":"sentry_cron_monitor","address":"sentry_cron_monitor.a","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}},{"type":"sentry_uptime_monitor","address":"sentry_uptime_monitor.b","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}}]}' > "$f"
  local out; out=$(_run_gate "$f" "feat: retune monitors")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T21 two updates and no forgets: resource_forgets=0 and the gate passes (non-vacuity)" ok
  else
    _report "T21 two updates and no forgets pass with resource_forgets=0" fail \
      "got '$out' want '0:0:0:0:0' — a counter stuck at non-zero would red every ordinary retune"
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
t_sentry_alert_noop_is_zero
t_sentry_alert_condition_shrink_trips
t_sentry_alert_legacy_trigger_shrink_trips
t_sentry_alert_whole_filter_removal_counts_contents
t_sentry_alert_growth_is_not_negative
t_forget_cron_monitor_trips_gate
t_forget_uptime_monitor_trips_gate
t_forget_issue_alert_keeps_deletes_zero
t_forget_must_be_summed_into_destroy_count
t_no_changes_still_emits_forgets_key
t_workflow_displays_forget_addresses
t_updates_only_yields_zero_forgets

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]

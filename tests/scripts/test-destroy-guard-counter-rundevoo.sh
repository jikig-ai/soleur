#!/usr/bin/env bash
# Tests for tests/scripts/lib/destroy-guard-filter-rundevoo.jq +
# scripts/rundevoo-destroy-counts.sh (used by .github/workflows/
# apply-rundevoo-infra.yml's plan_pr and apply jobs). #12971.
#
# Deterministic; no network. Fixtures are synthesized inline (the root has
# exactly 3 resource types — no captured baseline is worth the redaction
# machinery; a real no-drift plan's resource_changes is an empty array,
# already covered by the no-changes row).
#
# Output contract of the filter: {plan_ok, resource_deletes, resource_forgets,
# nested_deletes, undecidable_actions}. NO resource_creates key — see the
# filter header for why (additive drift is the set-equality probe's job;
# creates here would only train a blanket ack). undecidable_actions > 0 is a
# HALT: the counts script exits before emitting, so no ack can rescue it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter-rundevoo.jq"
COUNTS="$REPO_ROOT/scripts/rundevoo-destroy-counts.sh"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
EXPECTED_TESTS=19

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

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: $FILTER does not exist — RED phase expected this." >&2
  exit 1
fi
if [[ ! -f "$COUNTS" ]]; then
  echo "ERROR: $COUNTS does not exist — RED phase expected this." >&2
  exit 1
fi

# Mirror the workflow's gate pipeline exactly: eval the shipped counts script,
# then the canonical anchored-ack regex over HEAD_MSG + EVENT_MSGS_JSON.
# Returns "rdel:ndel:rfor:dcount:rc".
_run_gate() {
  local fixture="$1" head_msg="$2" event_msgs_json="${3:-}"
  local ack rc=0
  local resource_deletes resource_forgets nested_deletes destroy_count
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
  local policy_msgs="$head_msg" more_msgs
  more_msgs="$(jq -r 'join("\n")' <<<"${event_msgs_json:-null}" 2>/dev/null || true)"
  [[ -n "$more_msgs" && "$more_msgs" != "null" ]] && policy_msgs="${policy_msgs}"$'\n'"${more_msgs}"
  ack=false
  # Byte-identical to apply-rundevoo-infra.yml's [ack-destroy] regex.
  if [[ "$policy_msgs" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
    ack=true
  fi
  if [[ "$dcount" -gt 0 ]] && [[ "$ack" != "true" ]]; then
    rc=1
  fi
  echo "$rdel:$ndel:$rfor:$dcount:$rc"
}

_plan() { # $1=type $2=actions(json array literal) -> one-resource plan on stdout
  printf '{"resource_changes":[{"type":"%s","address":"%s.x","mode":"managed","change":{"actions":%s,"before":{},"after":{}}}]}' "$1" "$1" "$2"
}
_fixture() { local f="$TMPD/$2"; _plan "$1" "$3" > "$f"; echo "$f"; }

# T1: cloudflare_zone delete trips the gate.
t_zone_delete_trips() {
  local out; out=$(_run_gate "$(_fixture zdel.json cloudflare_zone '["delete"]')" "feat: drop zone mgmt")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T1 cloudflare_zone delete trips guard (rdel=1 ndel=0 rfor=0 dcount=1 rc=1)" ok
  else
    _report "T1 cloudflare_zone delete trips guard" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T2: no-changes plan passes silently.
t_no_changes_passes() {
  local f="$TMPD/nochange.json"
  printf '{"resource_changes":[]}' > "$f"
  local out; out=$(_run_gate "$f" "docs: typo")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T2 no-changes plan passes" ok
  else
    _report "T2 no-changes plan passes" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T3: [ack-destroy] line allows the zone delete through.
t_ack_destroy_allows() {
  local msg
  msg=$'chore: retire rundevoo zone mgmt\n\n[ack-destroy]\n\nRefs #12971.'
  local out; out=$(_run_gate "$(_fixture zdel2.json cloudflare_zone '["delete"]')" "$msg")
  if [[ "$out" == "1:0:0:1:0" ]]; then
    _report "T3 [ack-destroy] line allows zone delete through (rc=0)" ok
  else
    _report "T3 [ack-destroy] line allows zone delete through" fail "got '$out' want '1:0:0:1:0'"
  fi
}

# T4: [ack-destroy] as mid-line substring is NOT accepted.
t_ack_substring_rejected() {
  local msg="chore: discuss [ack-destroy] policy inline"
  local out; out=$(_run_gate "$(_fixture zdel3.json cloudflare_zone '["delete"]')" "$msg")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T4 [ack-destroy] substring rejected (rc=1)" ok
  else
    _report "T4 [ack-destroy] substring rejected" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T5/T6: `forget` trips the gate on both shape-bearing types — the state-drop
# IS the incident for this root (zone or hardening record silently unmanaged).
t_forget_zone_trips() {
  local out; out=$(_run_gate "$(_fixture fzone.json cloudflare_zone '["forget"]')" "chore: tidy state")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T5 forget on cloudflare_zone trips gate (rfor=1 rc=1)" ok
  else
    _report "T5 forget on cloudflare_zone trips gate" fail "got '$out' want '0:0:1:1:1'"
  fi
}
t_forget_record_trips() {
  local out; out=$(_run_gate "$(_fixture frec.json cloudflare_record '["forget"]')" "chore: tidy state")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T6 forget on cloudflare_record trips gate (rfor=1 rc=1)" ok
  else
    _report "T6 forget on cloudflare_record trips gate" fail "got '$out' want '0:0:1:1:1'"
  fi
}

# T7: forget must be SUMMED into destroy_count — a counter emitted but not
# summed is a report, not a gate. Mutate the shipped sum and confirm the
# forget-only plan then scores dcount=0 (the hole T5/T6 close).
t_forget_must_be_summed() {
  local mroot="$TMPD/mut-sum"
  mkdir -p "$mroot/scripts" "$mroot/tests/scripts/lib"
  cp "$FILTER" "$mroot/tests/scripts/lib/destroy-guard-filter-rundevoo.jq"
  sed 's/resource_deletes + nested_deletes + resource_forgets/resource_deletes + nested_deletes/' \
    "$COUNTS" > "$mroot/scripts/rundevoo-destroy-counts.sh"
  local mut="$mroot/scripts/rundevoo-destroy-counts.sh"
  # shellcheck disable=SC2016 # intentional literal: matching source text, not expanding
  if grep -qF 'resource_deletes + nested_deletes + resource_forgets' "$mut" \
     || ! grep -qF '$((resource_deletes + nested_deletes))' "$mut"; then
    _report "T7 an un-summed resource_forgets yields destroy_count=0" fail \
      "the mutation did not land — this row proves nothing"
    return
  fi
  local f; f=$(_fixture fsum.json cloudflare_zone '["forget"]')
  local dc; dc=$(bash "$mut" "$f" 2>/dev/null | grep -oP '^destroy_count=\K.*' || true)
  if [[ "$dc" == "0" ]]; then
    _report "T7 an un-summed resource_forgets yields destroy_count=0 — so T5/T6 are load-bearing" ok
  else
    _report "T7 an un-summed resource_forgets yields destroy_count=0" fail \
      "mutated script gave destroy_count='$dc' (want 0)"
  fi
}

# T8: all five keys emitted on a no-change plan; resource_creates deliberately
# absent (eval'ing it under set -u must fail — the absence is the contract).
t_no_changes_emits_all_keys() {
  local f="$TMPD/nochange2.json"
  printf '{"resource_changes":[]}' > "$f"
  local out; out=$(bash "$COUNTS" "$f")
  local missing=()
  for k in resource_deletes resource_forgets nested_deletes undecidable_actions destroy_count; do
    grep -qE "^${k}=[0-9]+$" <<<"$out" || missing+=("$k")
  done
  if [[ ${#missing[@]} -eq 0 ]] && ! grep -q '^resource_creates=' <<<"$out"; then
    _report "T8 all five keys emitted; resource_creates deliberately absent" ok
  else
    _report "T8 all five keys emitted; resource_creates deliberately absent" fail \
      "missing: ${missing[*]:-none}; resource_creates leak: $(grep -c '^resource_creates=' <<<"$out")"
  fi
}

# T9: plan_ok=false on a non-plan document fails CLOSED in the counts script —
# an unread input must never score 0 and green the gate.
t_plan_ok_false_fails_closed() {
  local f="$TMPD/notaplan.json"
  printf '{"format_version":"1.0"}' > "$f"   # state-shaped doc: no resource_changes
  local rc=0
  bash "$COUNTS" "$f" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    _report "T9 non-plan document fails closed (counts script exits 1)" ok
  else
    _report "T9 non-plan document fails closed" fail "counts script rc=$rc want 1"
  fi
}

# T10: the FILTER still reports plan_ok=true on a real plan — the key
# distinguishes, it does not merely refuse.
t_plan_ok_true_on_plan() {
  local got; got=$(_plan cloudflare_zone '["update"]' | jq -f "$FILTER" | jq -r '.plan_ok')
  if [[ "$got" == "true" ]]; then
    _report "T10 plan_ok=true on a plan document" ok
  else
    _report "T10 plan_ok=true on a plan document" fail "got '$got'"
  fi
}

# T11: nested_deletes stays 0 when a record's SCALAR attributes shrink — a
# comment/metadata map-attribute shrink is not a `data`-block removal (the
# `data` shrink itself is counted; T16 pins it).
t_nested_stays_zero_on_record_update() {
  local f="$TMPD/rec-update.json"
  printf '{"resource_changes":[{"type":"cloudflare_record","address":"cloudflare_record.null_mx","change":{"actions":["update"],"before":{"comment":"x","metadata":{"a":"1"}},"after":{"comment":null,"metadata":{}}}}]}' > "$f"
  local out; out=$(_run_gate "$f" "feat: drop record comment")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T11 record attribute shrink is not a nested-block delete (ndel=0, gate passes)" ok
  else
    _report "T11 record attribute shrink is not a nested-block delete" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T12: [ack-destroy] below the tip (event.commits) allows through — the merge
# queue coalesces squashes below head_commit (#12501).
t_ack_below_tip_allows() {
  local head="docs: merge-queue coalesced tip"
  local events='["infra: retire rundevoo zone\n\n[ack-destroy]\n\nRefs #12971.","docs: merge-queue coalesced tip"]'
  local out; out=$(_run_gate "$(_fixture zdel4.json cloudflare_zone '["delete"]')" "$head" "$events")
  if [[ "$out" == "1:0:0:1:0" ]]; then
    _report "T12 [ack-destroy] below the tip allows zone delete through (rc=0)" ok
  else
    _report "T12 [ack-destroy] below the tip allows zone delete through" fail "got '$out' want '1:0:0:1:0'"
  fi
}

# T13: workflow feed pin — every commit-message reader carries EVENT_MSGS_JSON
# and reads POLICY_MSGS, never $HEAD_MSG alone.
t_workflow_feeds_all_push_messages() {
  local wf="$REPO_ROOT/.github/workflows/apply-rundevoo-infra.yml"
  local feeds skip_reads ack_reads prov_guards
  # Comment-stripped counts: a `#`-commented line carrying the literal must
  # not satisfy the pin — dead wiring that still greps is a false green.
  # shellcheck disable=SC2016 # intentional literal: matching source text, not expanding
  feeds=$(grep -v '^[[:space:]]*#' "$wf" | grep -cF 'EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}' || true)
  # shellcheck disable=SC2016 # intentional literal: matching source text, not expanding
  skip_reads=$(grep -v '^[[:space:]]*#' "$wf" | grep -cF 'if [[ "$POLICY_MSGS" =~ (^|$'"'"'\n'"'"')\[skip-rundevoo-apply\]($|$'"'"'\n'"'"') ]]' || true)
  # shellcheck disable=SC2016 # intentional literal: matching source text, not expanding
  ack_reads=$(grep -v '^[[:space:]]*#' "$wf" | grep -cF 'if [[ "$POLICY_MSGS" =~ (^|$'"'"'\n'"'"')\[ack-destroy\]($|$'"'"'\n'"'"') ]]' || true)
  # The provisioner-class guard is duplicated across the plan_pr and apply
  # legs by CAP-COUPLING convention; a deleted leg must red this pin.
  prov_guards=$(grep -v '^[[:space:]]*#' "$wf" | grep -cF 'local-exec|remote-exec' || true)
  if [[ "$feeds" -ge 2 && "$skip_reads" -eq 1 && "$ack_reads" -eq 1 && "$prov_guards" -eq 2 ]]; then
    _report "T13 workflow feeds event.commits to both readers; provisioner guard in both legs" ok
  else
    _report "T13 workflow feeds event.commits to both readers; provisioner guard in both legs" fail \
      "feeds=$feeds (want >=2) skip-reads=$skip_reads ack-reads=$ack_reads (want 1 each) prov-guards=$prov_guards (want 2)"
  fi
}

# T14: the destroy gate displays forget addresses, not an empty list — an ack
# with no manifest is a blanket ack.
t_workflow_displays_forget_addresses() {
  local wf="$REPO_ROOT/.github/workflows/apply-rundevoo-infra.yml"
  local forget_sel exact_delete_sel
  forget_sel=$(grep -v '^[[:space:]]*#' "$wf" | grep -cE 'select\(\.change\.actions \| index\("forget"\)\)' || true)
  exact_delete_sel=$(grep -v '^[[:space:]]*#' "$wf" | grep -cE 'select\(\.change\.actions == \["delete"\]\) \| \.address' || true)
  if [[ "$forget_sel" -ge 1 && "$exact_delete_sel" -eq 0 ]]; then
    _report "T14 the destroy gate displays forget addresses, not an empty list" ok
  else
    _report "T14 the destroy gate displays forget addresses" fail \
      "forget-selecting display queries=$forget_sel (want >=1), exact-delete address queries=$exact_delete_sel (want 0)"
  fi
}

# T15: updates only → zero forgets and the gate passes (non-vacuity).
t_updates_only_passes() {
  local f="$TMPD/updates.json"
  printf '{"resource_changes":[{"type":"cloudflare_record","address":"cloudflare_record.a","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}},{"type":"cloudflare_zone_dnssec","address":"cloudflare_zone_dnssec.b","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}}]}' > "$f"
  local out; out=$(_run_gate "$f" "feat: retune records")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T15 two updates, no forgets: gate passes (non-vacuity)" ok
  else
    _report "T15 two updates, no forgets pass" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T16: a composed actions array still counts — `index("delete")`, never
# `== ["delete"]`. A zone REPLACE ("create","delete") is the realistic
# destructive action on this root and must trip the gate.
t_composed_actions_trips() {
  local out; out=$(_run_gate "$(_fixture zreplace.json cloudflare_zone '["create","delete"]')" "feat: replace zone")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T16 replace ([\"create\",\"delete\"]) counts as a destroy (rdel=1 rc=1)" ok
  else
    _report "T16 replace counts as a destroy" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T17/T18: undecidable actions HALT the counts script outright — exit 1 before
# any counts emit, so no [ack-destroy] can rescue an unclassifiable change.
t_empty_actions_halts() {
  local f="$TMPD/empty-actions.json"
  printf '{"resource_changes":[{"type":"cloudflare_record","address":"x","mode":"managed","change":{"actions":[],"before":{},"after":{}}}]}' > "$f"
  local rc=0
  bash "$COUNTS" "$f" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    _report "T17 empty actions array HALTs (counts exits 1)" ok
  else
    _report "T17 empty actions array HALTs" fail "counts rc=$rc want 1"
  fi
}
t_missing_actions_halts() {
  local f="$TMPD/missing-actions.json"
  printf '{"resource_changes":[{"type":"cloudflare_record","address":"x","mode":"managed","change":{"before":{},"after":{}}}]}' > "$f"
  local rc=0
  bash "$COUNTS" "$f" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    _report "T18 missing actions HALTs (counts exits 1)" ok
  else
    _report "T18 missing actions HALTs" fail "counts rc=$rc want 1"
  fi
}

# T19: the data-block shrink is a nested delete — dropping a record's `data {}`
# payload block plans as "update" yet rewrites live record content.
t_data_shrink_is_nested_delete() {
  local f="$TMPD/data-shrink.json"
  printf '{"resource_changes":[{"type":"cloudflare_record","address":"cloudflare_record.srv","mode":"managed","change":{"actions":["update"],"before":{"data":[{"service":"_sip","proto":"_tls","target":"old.example"}]},"after":{"data":[]}}}]}' > "$f"
  local out; out=$(_run_gate "$f" "feat: drop srv data")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T19 cloudflare_record data{} shrink counts as nested delete (ndel=1 rc=1)" ok
  else
    _report "T19 data{} shrink counts as nested delete" fail "got '$out' want '0:1:0:1:1'"
  fi
}

t_zone_delete_trips
t_no_changes_passes
t_ack_destroy_allows
t_ack_substring_rejected
t_forget_zone_trips
t_forget_record_trips
t_forget_must_be_summed
t_no_changes_emits_all_keys
t_plan_ok_false_fails_closed
t_plan_ok_true_on_plan
t_nested_stays_zero_on_record_update
t_ack_below_tip_allows
t_workflow_feeds_all_push_messages
t_workflow_displays_forget_addresses
t_updates_only_passes
t_composed_actions_trips
t_empty_actions_halts
t_missing_actions_halts
t_data_shrink_is_nested_delete

echo "=== $pass passed, $fail failed ==="
# HARNESS FLOOR. A commented-out dispatch line reads green forever without this.
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]

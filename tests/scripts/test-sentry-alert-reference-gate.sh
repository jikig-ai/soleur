#!/usr/bin/env bash
# Tests for scripts/sentry-alert-reference-gate.sh and the `tf`/`reference`
# sides of tests/scripts/lib/sentry-alert-projection.jq (#8050).
#
# THE FAILURE THIS SUITE IS SHAPED AGAINST. The gate compares a projection of
# the Terraform plan to the committed `alert-reference.json` and the degenerate
# implementation — always exit 1, or always exit 0 — satisfies half of any
# suite. So G0 is a POSITIVE CONTROL (the shipped gate PASSES on a plan and its
# own projection; without it every RED row below is indistinguishable from "the
# gate always exits 1"), and every mutation row asserts a DISTINCT literal, so a
# RED for the wrong reason cannot pass as a RED for the right one.
#
# Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only): a two-rule
# `planned_values` document in the exact shape `terraform show -json` renders
# for provider jianyuan/sentry 0.15.7 (every optional key present as null — see
# the state forensics measured for #8050). One rule carries TWO trigger
# conditions and TWO actions so the array-order rows are meaningful.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/sentry-alert-reference-gate.sh"
PROJ="$REPO_ROOT/tests/scripts/lib/sentry-alert-projection.jq"
pass=0; fail=0
EXPECTED_TESTS=42

# A sandbox harness inherits the bare 4 GiB /tmp tmpfs on a direct invocation;
# every other runner in this repo defaults TMPDIR to /var/tmp. Match them.
export TMPDIR="${TMPDIR:-/var/tmp}"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2; fi
}

for f in "$GATE" "$PROJ"; do
  [[ -f "$f" ]] || { echo "ERROR: $f does not exist — RED phase expected this." >&2; exit 1; }
done

# Every optional provider key rendered as null, exactly as `terraform show -json`
# does. Only the shape matters here; the KEY SET below is the one the forensics
# state for #8050 carried on every element.
_null_cond='"age_comparison":null,"assigned_to":null,"event_attribute":null,"event_frequency_count":null,"event_frequency_percent":null,"event_unique_user_frequency_count":null,"issue_category":null,"issue_occurrences":null,"issue_priority_deescalating":null,"issue_priority_greater_or_equal":null,"issue_type":null,"latest_adopted_release":null,"latest_release":null,"level":null,"percent_sessions_count":null,"percent_sessions_percent":null,"tagged_event":null'
_null_trig='"event_frequency_count":null,"first_seen_event":null,"issue_resolved_trigger":null,"reappeared_event":null,"regression_event":null'
_null_act='"discord":null,"email":null,"github":null,"jira":null,"jira_server":null,"msteams":null,"opsgenie":null,"pagerduty":null,"plugin":null,"sentry_app":null,"slack":null,"vsts":null,"webhook":null'

# _rule <tf-name> <name> <trigger-conditions-json> <action-filters-json>
_rule() {
  jq -n --arg tfname "$1" --arg name "$2" --argjson tc "$3" --argjson af "$4" '{
    address: ("sentry_alert." + $tfname), mode: "managed", type: "sentry_alert", name: $tfname,
    provider_name: "registry.terraform.io/jianyuan/sentry", schema_version: 0,
    values: { action_filters: $af, enabled: true, environment: null, frequency_minutes: 22,
              id: "1", legacy_trigger_conditions: null, monitor_ids: ["1213799"], name: $name,
              organization: "jikigai-eu", trigger_conditions: $tc },
    sensitive_values: { action_filters: ($af | map({actions: (.actions | map({})), conditions: (.conditions | map({}))})),
                        monitor_ids: ($tc | map(false)) [0:1], trigger_conditions: ($tc | map({})) } }'
}
# Trigger element with one live key set; every other key null.
_trig() { jq -n --arg k "$1" --argjson v "$2" "{${_null_trig}} + {(\$k): \$v}"; }
_cond() { jq -n --arg k "$1" --argjson v "$2" "{${_null_cond}} + {(\$k): \$v}"; }
_act()  { jq -n --arg k "$1" --argjson v "$2" "{${_null_act}} + {(\$k): \$v}"; }

# Rule A: two trigger conditions, one filter with two conditions and TWO actions.
TC_A=$(jq -n --argjson a "$(_trig first_seen_event '{}')" --argjson b "$(_trig event_frequency_count '{"interval":"1h","value":5}')" '[$a,$b]')
AF_A=$(jq -n \
  --argjson c1 "$(_cond tagged_event '{"key":"feature","match":"eq","value":"alpha"}')" \
  --argjson c2 "$(_cond tagged_event '{"key":"op","match":"in","value":"a,b"}')" \
  --argjson a1 "$(_act email '{"fallthrough_type":"ActiveMembers","target_id":null,"target_type":"issue_owners"}')" \
  --argjson a2 "$(_act email '{"fallthrough_type":"NoOne","target_id":"7","target_type":"member"}')" \
  '[{logic_type:"all", conditions:[$c1,$c2], actions:[$a1,$a2]}]')
# Rule B: one trigger condition (the single-trigger constant case), one action.
TC_B=$(jq -n --argjson a "$(_trig event_frequency_count '{"interval":"1h","value":0}')" '[$a]')
AF_B=$(jq -n \
  --argjson c1 "$(_cond tagged_event '{"key":"stage","match":"eq","value":"x"}')" \
  --argjson a1 "$(_act email '{"fallthrough_type":"ActiveMembers","target_id":null,"target_type":"issue_owners"}')" \
  '[{logic_type:"any-short", conditions:[$c1], actions:[$a1]}]')

_plan_doc() { # $1 = JSON array of resource objects, $2 = child_modules JSON (default [])
  jq -n --argjson r "$1" --argjson cm "${2:-[]}" '{
    format_version: "1.2", terraform_version: "1.10.5",
    planned_values: { root_module: { resources: $r, child_modules: $cm } },
    resource_changes: ($r | map({address, mode, type, name, change: {actions: ["no-op"], before: .values, after: .values, after_unknown: {}}})) }'
}

RULE_A=$(_rule two_trigger "two-trigger" "$TC_A" "$AF_A")
RULE_B=$(_rule single_trigger "single-trigger" "$TC_B" "$AF_B")
PLAN="$TMPD/plan.json"
_plan_doc "$(jq -n --argjson a "$RULE_A" --argjson b "$RULE_B" '[$a,$b]')" > "$PLAN"
REF="$TMPD/reference.json"
jq -S --arg side tf -f "$PROJ" "$PLAN" > "$REF" 2>"$TMPD/ref.err" \
  || { echo "ERROR: the tf projection of the synthetic plan failed: $(cat "$TMPD/ref.err")" >&2; exit 1; }

# Fixture self-check: the projection must have produced exactly the two rules
# with the shape the gate requires, or every row below measures the fixture.
if ! jq -e 'keys == ["single-trigger","two-trigger"]
            and .["two-trigger"].triggerLogicType == "any-short"
            and .["single-trigger"].triggerLogicType == "single"
            and (.["two-trigger"].actionFilters[0].actions | length) == 2
            and (.["two-trigger"].actionFilters[0].conditions | length) == 2
            and (.["two-trigger"].triggerConditions | length) == 2
            and (.["two-trigger"].triggerConditions | map(select(.type=="first_seen_event")) | .[0].comparison) == true' "$REF" >/dev/null; then
  echo "ERROR: fixture self-check failed — the projected reference is not the expected two-rule document: $(jq -c . "$REF" | head -c 600)" >&2
  exit 1
fi

# _gate <plan> <reference> — sets $_rc and $_out (stdout+stderr merged).
_rc=0; _out=""
_gate() {
  _rc=0
  _out=$(GITHUB_STEP_SUMMARY="$TMPD/summary.md" RUNNER_TEMP="$TMPD" bash "$GATE" "$1" "$2" 2>&1) || _rc=$?
}

# _mut <src> <label> <jq-program> [jq-args…] — mutated copy of $src, asserted to
# have LANDED (a selector that matches nothing returns the input unchanged, and
# the row built on it would compare the fixture to itself).
_mut() {
  local src="$1" f="$TMPD/mut-$2.json"
  jq "${@:4}" "$3" "$src" > "$f" 2>/dev/null || { echo "JQFAIL"; return; }
  if jq -S -c . "$f" | cmp -s - <(jq -S -c . "$src"); then echo "NOOP"; return; fi
  echo "$f"
}
_mut_plan() { _mut "$PLAN" "$@"; }
_mut_ref()  { _mut "$REF"  "$@"; }

# _red <label> <plan> <ref> <expected-literal>
_red() {
  local label="$1" plan="$2" ref="$3" want="$4"
  for x in "$plan" "$ref"; do
    if [[ "$x" == "JQFAIL" || "$x" == "NOOP" ]]; then
      _report "$label" fail "the mutation did not land ($x) — this row compared the fixture to itself"; return
    fi
  done
  _gate "$plan" "$ref"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "$want" <<<"$_out" && ! grep -q 'reference gate: PASS' <<<"$_out"; then
    _report "$label" ok
  else
    _report "$label" fail "rc=$_rc (want 1), literal '$want' $(grep -qF -- "$want" <<<"$_out" && echo present || echo ABSENT). Output: $(head -c 500 <<<"$_out")"
  fi
}
# _green <label> <plan> <ref> <expected-pass-literal>
_green() {
  local label="$1" plan="$2" ref="$3" want="$4"
  for x in "$plan" "$ref"; do
    if [[ "$x" == "JQFAIL" || "$x" == "NOOP" ]]; then
      _report "$label" fail "the mutation did not land ($x)"; return
    fi
  done
  _gate "$plan" "$ref"
  if [[ "$_rc" -eq 0 ]] && grep -qF -- "$want" <<<"$_out"; then
    _report "$label" ok
  else
    _report "$label" fail "rc=$_rc (want 0), want '$want'. Output: $(head -c 500 <<<"$_out")"
  fi
}

# ── G0 — the positive control. ───────────────────────────────────────────────
t_g0() { _green "G0 the plan and its own projection PASS (2 rules, plan == alert-reference.json)" "$PLAN" "$REF" "PASS (2 rules, plan == alert-reference.json)"; }

# ── Guard 1 mutation matrix — each row RED with its own literal. ─────────────
t_m1() {
  local extra; extra=$(_rule third "third-rule" "$TC_B" "$AF_B")
  _red "M1 a third sentry_alert in the plan, reference unchanged → ADDED" \
    "$(_mut_plan m1 '.planned_values.root_module.resources += [$r]' --argjson r "$extra")" "$REF" \
    'ADDED in .tf, missing from reference: "third-rule"'
}
t_m2() {
  _red "M2 a changed event_frequency_count.value in the plan → leaf path naming comparison.value" \
    "$(_mut_plan m2 '(.planned_values.root_module.resources[] | select(.name=="two_trigger") | .values.trigger_conditions[] | select(.event_frequency_count != null) | .event_frequency_count.value) = 99')" "$REF" \
    '"two-trigger".triggerConditions'
  # The same row must ALSO name the leaf. Checked separately so the reason is
  # legible when only one half fails.
  grep -qF -- "comparison.value: planned=99 reference=5" <<<"$_out" \
    && _report "M2b the leaf line renders planned=99 reference=5" ok \
    || _report "M2b the leaf line renders planned=99 reference=5" fail "$(grep -F 'comparison' <<<"$_out" | head -3)"
}
t_m3() {
  _red "M3 a rule removed from the plan, reference unchanged → REMOVED" \
    "$(_mut_plan m3 '.planned_values.root_module.resources |= map(select(.name != "single_trigger"))')" "$REF" \
    'REMOVED from .tf, still in reference: "single-trigger"'
}
t_m4() {
  # Three rules: A and B match; C is in BOTH plan and reference but differs in
  # the plan. Only C may be named.
  local c; c=$(_rule third "third-rule" "$TC_B" "$AF_B")
  local plan3="$TMPD/plan-m4.json"; jq --argjson r "$c" '.planned_values.root_module.resources += [$r]' "$PLAN" > "$plan3"
  local ref3="$TMPD/ref-m4.json"; jq -S --arg side tf -f "$PROJ" "$plan3" > "$ref3"
  jq '(.planned_values.root_module.resources[] | select(.name=="third") | .values.frequency_minutes) = 45' "$plan3" > "$plan3.mut"
  _gate "$plan3.mut" "$ref3"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- '"third-rule".frequency: planned=45 reference=22' <<<"$_out" \
     && ! grep -qE '"two-trigger"\.|"single-trigger"\.' <<<"$_out"; then
    _report "M4 with three rules where two match, ONLY the third is named" ok
  else
    _report "M4 three rules, only the third named" fail "rc=$_rc. Output: $(head -c 500 <<<"$_out")"
  fi
}
t_m5() {
  _red "M5 a plan with zero sentry_alert resources → the projection floor, never PASS (0 rules" \
    "$(_mut_plan m5 '.planned_values.root_module.resources |= map(select(.type != "sentry_alert"))')" "$REF" \
    "projection yielded 0 rules"
}
t_m6() {
  local arr="$TMPD/ref-m6.json"; printf '[{"name":"two-trigger","enabled":true}]' > "$arr"
  _red "M6 an API-shaped capture (array) as the reference → shape floor before comparison" \
    "$PLAN" "$arr" "not a name-indexed projection object"
}
t_m7() {
  _red "M7 enabled flipped true→false in the reference renders false, not <absent>" \
    "$PLAN" "$(_mut_ref m7 '.["two-trigger"].enabled = false')" \
    '"two-trigger".enabled: planned=true reference=false'
  # D1's negative twin: a non-detectorIds diff must NOT carry the hint that
  # tells the author "this is not an authoring error".
  if grep -qF 'issue-stream detector id moved' <<<"$_out"; then
    _report "M7b the detectorIds hint is absent on a non-detectorIds diff" fail "hint printed on an enabled diff"
  else
    _report "M7b the detectorIds hint is absent on a non-detectorIds diff" ok
  fi
}
t_m8() {
  local cm; cm=$(jq -n --argjson r "$RULE_B" '[{address:"module.x", resources:[$r]}]')
  _red "M8 a child_modules entry holding a sentry_alert → refused" \
    "$(_mut_plan m8 '.planned_values.root_module.child_modules = $cm' --argjson cm "$cm")" "$REF" \
    "the root carries child_modules"
}
t_m9() {
  _red "M9 a create row with enabled unknown (null) → enabled is not a boolean" \
    "$(_mut_plan m9 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.enabled) = null')" "$REF" \
    "enabled is not a boolean"
}
t_m10() {
  # `event_unique_user_frequency_count` is in `excluded` and is now DROPPED on the
  # TF side (Guard 1 row L3), so the unmapped-kind floor is exercised with a kind
  # that is neither mapped nor excluded.
  local t; t=$(_trig event_frequency_count '{"interval":"1h","value":1}' | jq '. + {event_frequency_percent: {"interval":"1h","value":1}} | .event_frequency_count = null')
  _red "M10 a trigger kind outside the allowlist and outside excluded (event_frequency_percent) → not mapped" \
    "$(_mut_plan m10 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.trigger_conditions) = [$t]' --argjson t "$t")" "$REF" \
    "trigger kind 'event_frequency_percent' is not mapped by the projection"
}
t_m11() {
  _red "M11 two resources sharing one name → duplicate sentry_alert name" \
    "$(_mut_plan m11 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.name) = "two-trigger"')" "$REF" \
    "duplicate sentry_alert name"
}
t_m12() {
  _red "M12 a condition element with two non-null keys → exactly one non-null key" \
    "$(_mut_plan m12 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.trigger_conditions[0].first_seen_event) = {}')" "$REF" \
    "exactly one non-null key"
}

# ── Floors the first battery never mutated (review): each deletable-at-green
# before these rows existed. Each asserts the module's own literal.
t_m13() {
  local a; a=$(_act slack '{"channel":"#ops","channel_id":"C1"}')
  _red "M13 an action kind outside the allowlist (slack) → not mapped by the projection" \
    "$(_mut_plan m13 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.action_filters[0].actions) = [$a]' --argjson a "$a")" "$REF" \
    "action kind 'slack' is not mapped by the projection"
}
t_m14() {
  _red "M14 a sensitive leaf on a sentry_alert → refused (terraform show -json renders sensitive values in plaintext)" \
    "$(_mut_plan m14 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .sensitive_values.name) = true')" "$REF" \
    "a sensitive attribute is set on a sentry_alert"
}
t_m15() {
  local doc="$TMPD/not-a-plan.json"; printf '{"format_version":"1.2"}' > "$doc"
  _red "M15 a document with neither planned_values nor values → not a terraform show -json document" \
    "$doc" "$REF" "not a terraform show -json plan or state document"
}
t_m16() {
  _red "M16 frequency_minutes rendered as a string → not a number" \
    "$(_mut_plan m16 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.frequency_minutes) = "22"')" "$REF" \
    "frequency_minutes is not a number"
}
t_m17() {
  local c; c=$(_cond level '{"match":"eq","level":"error"}')
  _red "M17 a condition kind outside the allowlist (level) → not mapped by the projection" \
    "$(_mut_plan m17 '(.planned_values.root_module.resources[] | select(.name=="single_trigger") | .values.action_filters[0].conditions) = [$c]' --argjson c "$c")" "$REF" \
    "condition kind 'level' is not mapped by the projection"
}
t_m18() {
  _red "M18 sensitive_values absent from a resource → refused (no sensitivity mask)" \
    "$(_mut_plan m18 '(.planned_values.root_module.resources[] | select(.name=="single_trigger")) |= del(.sensitive_values)')" "$REF" \
    "sensitive_values is absent or not an object"
}
t_m19() {
  local rc=0 out
  out=$(jq --arg side bogus -f "$PROJ" "$PLAN" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF -- "must be one of tf|live|reference" <<<"$out"; then
    _report "M19 the module refuses an unknown --arg side rather than falling through to a side" ok
  else
    _report "M19 unknown --arg side refused" fail "rc=$rc out=$(head -c 200 <<<"$out")"
  fi
}

# ── Must-PASS (non-canonical) rows — the gate is order-insensitive. ──────────
t_reorder_passes() {
  # BOTH array elements reversed AND the keys inside every comparison reversed.
  # F13 in the probe's suite reverses keys only; array order is what `normalise`
  # exists for, so this row exercises the half F13 cannot.
  _green "P1 reference with arrays reversed and comparison keys reversed still PASSES (normalise on both sides)" \
    "$PLAN" "$(_mut_ref p1 '
      def rev_keys: walk(if type == "object" then (to_entries | reverse | from_entries) else . end);
      with_entries(.value |= (
        .triggerConditions |= reverse
        | .actionFilters |= map(.conditions |= reverse | .actions |= reverse)
        | .actionFilters |= reverse
        | .triggerConditions |= map(.comparison |= (if type=="object" then rev_keys else . end))))')" \
    "PASS (2 rules"
}
t_show_state_passes() {
  # A `terraform show -json` STATE document (`values`, no `planned_values`) for
  # the same two rules projects identically.
  local st="$TMPD/state.json"
  jq '{format_version, terraform_version, values: .planned_values}' "$PLAN" > "$st"
  _green "P2 a show-state document (values, not planned_values) PASSES against the same reference" "$st" "$REF" "PASS (2 rules"
}
t_whitespace_passes() {
  local ws="$TMPD/ref-ws.json"; jq --indent 7 . "$REF" > "$ws"; printf '\n\n' >> "$ws"
  _green "P3 a reference differing only in indentation/trailing whitespace PASSES" "$PLAN" "$ws" "PASS (2 rules"
}
t_swap_values_reds() {
  # Negative twin of P1: swapping DATA between two conditions is not a reorder.
  _red "N1 swapping comparison.value between the two-trigger rule's conditions → RED on comparison.value (data, not order)" \
    "$(_mut_plan n1 '
      (.planned_values.root_module.resources[] | select(.name=="two_trigger") | .values.action_filters[0].conditions)
        |= [ (.[0] | .tagged_event.value = "a,b"), (.[1] | .tagged_event.value = "alpha") ]')" "$REF" \
    "comparison.value"
}
t_detector_hint() {
  _red "D1 a detectorIds-only divergence carries the monitor-binding hint" \
    "$PLAN" "$(_mut_ref d1 'with_entries(.value.detectorIds = ["9999"])')" \
    "issue-stream detector id moved"
}
t_remedy_and_expected_file() {
  local f; f=$(_mut_ref r1 '.["two-trigger"].frequency = 1')
  _gate "$PLAN" "$f"
  local why=()
  [[ "$_rc" -eq 1 ]] || why+=("rc=$_rc")
  grep -qF -- 'Regenerate (needs the Doppler prd_terraform triplet): jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq' <<<"$_out" || why+=("regeneration command absent")
  grep -qF -- 'gh run download' <<<"$_out" || why+=("credential-free artifact fetch absent")
  [[ -s "$TMPD/sentry-alert-reference.expected.json" ]] || why+=("expected file not written")
  # The expected file IS the projection of the plan — byte-equal to the fixture
  # reference the gate was told was stale — and is `jq -S .` formatted so a
  # `cp` over alert-reference.json is byte-exact.
  cmp -s "$TMPD/sentry-alert-reference.expected.json" <(jq -S . "$REF") || why+=("expected file is not the jq -S projection of the plan")
  # The gate publishes to NEITHER channel itself (one sweep in the workflow
  # precedes both): no step summary may be written here.
  [[ ! -e "$TMPD/summary.md" ]] || why+=("the gate wrote the step summary directly, bypassing the sweep")
  if [[ ${#why[@]} -eq 0 ]]; then
    _report "R1 a mismatch prints the regeneration command + the credential-free fetch, writes the expected document to RUNNER_TEMP, and writes NO step summary itself" ok
  else
    _report "R1 mismatch remedy + expected document" fail "${why[*]}. Output: $(head -c 400 <<<"$_out")"
  fi
  rm -f "$TMPD/sentry-alert-reference.expected.json" "$TMPD/summary.md"
}

# ── Harness row H2 — an EMPTY plan file is refused at the plan floor (named as
# the plan step having written nothing — distinct from the reference floor).
t_h2_empty_plan() {
  local empty="$TMPD/empty.json"; : > "$empty"
  _gate "$empty" "$REF"
  if [[ "$_rc" -eq 1 ]] && ! grep -q 'reference gate: PASS' <<<"$_out" && grep -qF -- 'plan JSON not readable or empty' <<<"$_out"; then
    _report "H2 an empty plan file is refused (no PASS line, names the floor)" ok
  else
    _report "H2 empty plan refused" fail "rc=$_rc. Output: $(head -c 300 <<<"$_out")"
  fi
}

# ── Guard 1 (#8451) — projection scope symmetry. A `sentry_alert` whose trigger
# type is in `excluded` is outside the TF-side projection exactly as it is
# outside the live side's `in_scope`, in EITHER representation: native
# (`trigger_conditions[]` key) or legacy (`legacy_trigger_conditions` string —
# what the provider's Read returns for an adopted type-only rule). A legacy type
# NOT in `excluded` is an error, never a silent under-projection.
#
# _rule_legacy <tf-name> <name> <legacy-json> <trigger-conditions-json|null> [nomask]
# `nomask` drops `sensitive_values` — a type-only adopted rule under
# `ignore_changes = all` may render with `trigger_conditions: null` and no mask,
# and the exclusion must run BEFORE `tf_rule`'s floors see it.
_rule_legacy() {
  local r; r=$(_rule "$1" "$2" '[]' "$AF_B")
  jq --argjson l "$3" --argjson tc "$4" --arg mask "${5:-}" '
    .values.legacy_trigger_conditions = $l | .values.trigger_conditions = $tc
    | if $mask == "nomask" then del(.sensitive_values) else . end' <<<"$r"
}
# 30 normal rules (the live scope's size) and the reference projected from them
# alone — the adopted rows must add NOTHING to it.
NORMAL30=$(jq -n --argjson r "$RULE_B" '[range(30) as $i | $r
  | .name = "normal_\($i)" | .address = "sentry_alert.normal_\($i)" | .values.name = "normal-\($i)"]')
REF30="$TMPD/reference-30.json"
_plan_doc "$NORMAL30" > "$TMPD/plan-30.json"
jq -S --arg side tf -f "$PROJ" "$TMPD/plan-30.json" > "$REF30" 2>"$TMPD/ref30.err" \
  || { echo "ERROR: the tf projection of the 30-rule plan failed: $(cat "$TMPD/ref30.err")" >&2; exit 1; }
[[ "$(jq 'length' "$REF30")" == "30" ]] \
  || { echo "ERROR: fixture self-check failed — the 30-rule reference has $(jq length "$REF30") keys" >&2; exit 1; }
_NATIVE_EUU=$(_trig event_frequency_count '{"interval":"1h","value":1}' \
  | jq '. + {event_unique_user_frequency_count: {"interval":"1h","value":20}} | .event_frequency_count = null')

# _plan30 <label> <extra-resources-json> — the 30 normal rows plus the extras.
_plan30() {
  local f="$TMPD/plan30-$1.json"
  _plan_doc "$(jq -n --argjson n "$NORMAL30" --argjson x "$2" '$n + $x')" > "$f"
  echo "$f"
}

t_l1_legacy_excluded_drops() {
  # Matrix row 1: two well-formed adopted rows (trigger_conditions [], mask
  # present). Without the exclusion they project → 32 names vs 30 → ADDED.
  local x; x=$(jq -n \
    --argjson a "$(_rule_legacy auth_per_user_loop "auth-per-user-loop" '["event_unique_user_frequency_count"]' '[]')" \
    --argjson b "$(_rule_legacy sandbox_startup_failure "sandbox-startup-failure" '["event_unique_user_frequency_count"]' '[]')" '[$a,$b]')
  _green "L1 30 normal + 2 legacy-excluded rows project to the 30-key reference (TF side mirrors live in_scope)" \
    "$(_plan30 l1 "$x")" "$REF30" "PASS (30 rules, plan == alert-reference.json)"
}
t_l3_native_excluded_drops() {
  # Matrix row 3: a legacy row PLUS a second row carrying the excluded type in
  # the NATIVE form (the post-#7985 shape). Both must be dropped.
  local x; x=$(jq -n \
    --argjson a "$(_rule_legacy auth_per_user_loop "auth-per-user-loop" '["event_unique_user_frequency_count"]' '[]')" \
    --argjson b "$(_rule native_euu "native-euu" "$(jq -n --argjson t "$_NATIVE_EUU" '[$t]')" "$AF_B")" '[$a,$b]')
  _green "L3 a native-form excluded row is dropped alongside the legacy one" \
    "$(_plan30 l3 "$x")" "$REF30" "PASS (30 rules, plan == alert-reference.json)"
}
t_l4_unmapped_legacy_errors() {
  # Matrix row 4: a legacy type NOT in `excluded` must ERROR (jq exit 5), never
  # project with no triggers.
  local x plan rc=0 out
  x=$(jq -n --argjson a "$(_rule_legacy resolution "resolution-change" '["issue_resolution_change"]' '[]')" '[$a]')
  plan=$(_plan30 l4 "$x")
  out=$(jq --arg side tf -f "$PROJ" "$plan" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -eq 5 ]] && grep -qF -- "unmapped legacy trigger type" <<<"$out" && grep -qF -- "issue_resolution_change" <<<"$out"; then
    _report "L4 a legacy trigger type outside excluded (issue_resolution_change) → jq exit 5, unmapped legacy trigger type" ok
  else
    _report "L4 unmapped legacy trigger type errors" fail "rc=$rc (want 5). Output: $(head -c 400 <<<"$out")"
  fi
  _red "L4b the gate refuses the same plan (projection floor), never PASS" "$plan" "$REF30" "unmapped legacy trigger type"
}
t_l5_legacy_null_nomask() {
  # Matrix row 5: the imported-state render — `trigger_conditions: null` and no
  # `sensitive_values`. The exclusion runs before `tf_rule`, so neither floor fires.
  local x; x=$(jq -n \
    --argjson a "$(_rule_legacy auth_per_user_loop "auth-per-user-loop" '["event_unique_user_frequency_count"]' 'null' nomask)" \
    --argjson b "$(_rule_legacy sandbox_startup_failure "sandbox-startup-failure" '["event_unique_user_frequency_count"]' 'null' nomask)" '[$a,$b]')
  _green "L5 legacy rows with trigger_conditions null and no sensitive_values are dropped before tf_rule (no crash)" \
    "$(_plan30 l5 "$x")" "$REF30" "PASS (30 rules, plan == alert-reference.json)"
}

# ── Guard 2 (#8630) — the unknown-detector projection floor. A `sentry_alert`
# whose `monitor_ids` carries an element unknown at plan time (a
# `sentry_cron_monitor` created or recreated in the same plan — its id does not
# exist until the apply) must NEVER project. Without the floor the PR-time gate
# goes green once the author commits the null-carrying projection, and the
# post-apply probe then compares live (the real id) with a reference projected
# from the apply plan (`null`) — `main` red after a COMPLETE apply, the #8050
# class. Each row asserts the exact rc and the floor's own text.
G2_FLOOR_TEXT="detector id(s) that do not exist yet (a monitor created or recreated in this plan)"
# _g2_null_plan <label> <tf-name> <monitor-ids-json> — the base plan with one
# rule's monitor_ids replaced and `sensitive_values.monitor_ids` given the SAME
# length (a real `terraform show -json` mask is element-wise).
_g2_null_plan() {
  _mut_plan "$1" '(.planned_values.root_module.resources[] | select(.name == $n))
      |= (.values.monitor_ids = $ids | .sensitive_values.monitor_ids = ($ids | map(false)))' \
    --arg n "$2" --argjson ids "$3"
}
# The reference the #8050 author would commit: the SAME null-carrying plan
# projected by a module WITHOUT the floor. The tf side emits `detectorIds:
# $v.monitor_ids` verbatim and the reference side re-normalises (sort), so this
# is that projection exactly. Against it, a floorless gate compares equal and
# exits 0 — the row cannot pass for the wrong reason.
G2_PLAN=$(_g2_null_plan g2p single_trigger '["1", null]')
G2_REF=$(_mut_ref g2r '.["single-trigger"].detectorIds = (["1", null] | sort)')
t_g2_1_null_detector_floor() {
  _red "G2-1 monitor_ids [\"1\", null] with the reference a floorless projection would commit → floor refuses (rc 1)" \
    "$G2_PLAN" "$G2_REF" "sentry_alert.single_trigger: monitor_ids carries 1 ${G2_FLOOR_TEXT}"
}
t_g2_2_unknown_not_first() {
  # Three rules; the unknown one is LAST by resource order AND by name, and its
  # null is not the first element — a floor that checks only the first rule or
  # the first element passes this row.
  local third plan ref
  third=$(_rule third "third-rule" "$TC_B" "$AF_B")
  plan="$TMPD/mut-g2-2.json"
  jq --arg n two_trigger --argjson ids '["1213799", "7", null]' --argjson t "$third" '
      (.planned_values.root_module.resources[] | select(.name == $n))
        |= (.values.monitor_ids = $ids | .sensitive_values.monitor_ids = ($ids | map(false)))
      | .planned_values.root_module.resources = (
          [.planned_values.root_module.resources[] | select(.name == "single_trigger")] + [$t]
          + [.planned_values.root_module.resources[] | select(.name == "two_trigger")])' "$PLAN" > "$plan"
  ref="$TMPD/ref-g2-2.json"
  jq -S --argjson t "$third" '.planned_values.root_module.resources += [$t]' "$PLAN" \
    | jq -S --arg side tf -f "$PROJ" \
    | jq -S '.["two-trigger"].detectorIds = (["1213799", "7", null] | sort)' > "$ref"
  if ! jq -e '[.planned_values.root_module.resources[].values.name] == ["single-trigger","third-rule","two-trigger"]
              and (.planned_values.root_module.resources[2].values.monitor_ids[2] == null)' "$plan" >/dev/null; then
    _report "G2-2 unknown detector in the last rule, not the first element" fail "fixture did not land: $(jq -c '[.planned_values.root_module.resources[] | {n: .name, m: .values.monitor_ids}]' "$plan")"
    return
  fi
  _red "G2-2 three rules, the unknown detector in the LAST rule (by order and by name) at a non-first element → floor names that rule" \
    "$plan" "$ref" "sentry_alert.two_trigger: monitor_ids carries 1 ${G2_FLOOR_TEXT}"
}
t_g2_3_remedy_pointer() {
  _gate "$G2_PLAN" "$G2_REF"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "list it in local.cron_monitor_alert_unrouted in cron-monitor-alerts.tf with a (#N) reason and route it in a follow-up PR after the first apply" <<<"$_out"; then
    _report "G2-3 the floor names its remedy (local.cron_monitor_alert_unrouted, a follow-up PR)" ok
  else
    _report "G2-3 the floor names its remedy" fail "rc=$_rc. Output: $(head -c 500 <<<"$_out")"
  fi
}
t_g2_4_direct_jq_rc5() {
  local rc=0 out
  out=$(jq --arg side tf -f "$PROJ" "$G2_PLAN" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -eq 5 ]] && grep -qF -- "monitor_ids carries 1 ${G2_FLOOR_TEXT}" <<<"$out"; then
    _report "G2-4 jq -f projection.jq --arg side tf on the null-carrying plan → rc 5 with the floor text" ok
  else
    _report "G2-4 direct jq refuses the null-carrying plan" fail "rc=$rc (want 5). Output: $(head -c 400 <<<"$out")"
  fi
}
t_g2_5_no_wrong_remedy() {
  # The generic arm matches `*"unknown at plan time"*` and says "Set the
  # attribute explicitly in the block" — the WRONG remedy for a detector id that
  # does not exist yet. The floor's text must not trip it.
  _gate "$G2_PLAN" "$G2_REF"
  if [[ "$_rc" -eq 1 ]] && ! grep -qF -- "Set the attribute explicitly" <<<"$_out" \
     && ! grep -qF -- "unknown at plan time" <<<"$_out"; then
    _report "G2-5 the generic 'Set the attribute explicitly' remedy is ABSENT on the unknown-detector floor" ok
  else
    _report "G2-5 the wrong remedy is absent" fail "rc=$_rc. Output: $(head -c 600 <<<"$_out")"
  fi
}
t_g2_5b_dedicated_arm() {
  _gate "$G2_PLAN" "$G2_REF"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "::error::A monitor created or recreated in this plan has no detector id until this apply creates it" <<<"$_out"; then
    _report "G2-5b the gate's dedicated case arm echoes the floor's own remedy" ok
  else
    _report "G2-5b dedicated remedy arm" fail "rc=$_rc. Output: $(head -c 600 <<<"$_out")"
  fi
}
# Must-PASS twins: the floor refuses only a null element.
G2_KNOWN_A='["1213799", "42", "7"]'
G2_KNOWN_B='["1213799", "9"]'
G2_KNOWN_PLAN="$TMPD/g2-known.json"
jq --argjson a "$G2_KNOWN_A" --argjson b "$G2_KNOWN_B" '
    (.planned_values.root_module.resources[] | select(.name == "two_trigger"))
      |= (.values.monitor_ids = $a | .sensitive_values.monitor_ids = ($a | map(false)))
    | (.planned_values.root_module.resources[] | select(.name == "single_trigger"))
      |= (.values.monitor_ids = $b | .sensitive_values.monitor_ids = ($b | map(false)))' "$PLAN" > "$G2_KNOWN_PLAN"
t_g2_p1_all_known_reverse_order() {
  local rev="$TMPD/g2-p1-rev.json" ref="$TMPD/g2-p1-ref.json"
  jq -S --arg side tf -f "$PROJ" "$G2_KNOWN_PLAN" > "$ref"
  # Rules reversed AND every monitor_ids array reversed.
  jq '.planned_values.root_module.resources |= (reverse | map(.values.monitor_ids |= reverse))' "$G2_KNOWN_PLAN" > "$rev"
  if jq -e '.planned_values.root_module.resources[0].name == "single_trigger"
            and .planned_values.root_module.resources[1].values.monitor_ids == ["7","42","1213799"]' "$rev" >/dev/null; then
    _green "G2-P1 two rules with every detector id known, rules and ids in reverse order, PASS" "$rev" "$ref" "PASS (2 rules"
  else
    _report "G2-P1 all-known reverse order" fail "fixture did not land: $(jq -c '[.planned_values.root_module.resources[] | {n: .name, m: .values.monitor_ids}]' "$rev")"
  fi
}
t_g2_p2_live_side_equal() {
  # The live side (what the post-apply probe reads) carrying the SAME known ids
  # in a different order projects byte-equal to the tf side.
  local live="$TMPD/g2-p2-live.json" rc_t=0 rc_l=0 t l
  t=$(jq -S -c --arg side tf -f "$PROJ" "$G2_KNOWN_PLAN" 2>&1) || rc_t=$?
  jq --argjson a "$G2_KNOWN_A" --argjson b "$G2_KNOWN_B" '[ to_entries[] | .value | {
      name, enabled,
      detectorIds: (if .name == "two-trigger" then ($a | reverse) else ($b | reverse) end),
      config: {frequency: .frequency},
      triggers: {logicType: (if .triggerLogicType == "single" then "all" else .triggerLogicType end),
                 conditions: [.triggerConditions[] | {type, comparison}]},
      actionFilters: [.actionFilters[] | {logicType,
        conditions: [.conditions[] | {type, comparison}],
        actions: [.actions[] | {type, config: {targetType, targetIdentifier}, data: {fallthroughType}}]}] } ]' \
    <<<"$t" > "$live"
  l=$(jq -S -c --arg side live -f "$PROJ" "$live" 2>&1) || rc_l=$?
  if [[ "$rc_t" -eq 0 && "$rc_l" -eq 0 && -n "$t" && "$t" == "$l" ]] \
     && jq -e '.["two-trigger"].detectorIds == ["1213799","42","7"]' <<<"$l" >/dev/null; then
    _report "G2-P2 the live-shape side with the same known ids (reordered) compares equal to the tf side" ok
  else
    _report "G2-P2 live side equal" fail "rc_t=$rc_t rc_l=$rc_l tf=$(head -c 300 <<<"$t") live=$(head -c 300 <<<"$l")"
  fi
}

t_g0
t_m1
t_m2
t_m3
t_m4
t_m5
t_m6
t_m7
t_m8
t_m9
t_m10
t_m11
t_m12
t_m13
t_m14
t_m15
t_m16
t_m17
t_m18
t_m19
t_reorder_passes
t_show_state_passes
t_whitespace_passes
t_swap_values_reds
t_detector_hint
t_remedy_and_expected_file
t_h2_empty_plan
t_l1_legacy_excluded_drops
t_l3_native_excluded_drops
t_l4_unmapped_legacy_errors
t_l5_legacy_null_nomask
t_g2_1_null_detector_floor
t_g2_2_unknown_not_first
t_g2_3_remedy_pointer
t_g2_4_direct_jq_rc5
t_g2_5_no_wrong_remedy
t_g2_5b_dedicated_arm
t_g2_p1_all_known_reverse_order
t_g2_p2_live_side_equal

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]

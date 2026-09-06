#!/usr/bin/env bash
# Tests for scripts/sentry-alert-live-fidelity.sh (#7650 §2.9) — the probe that
# notices one of the 27 adopted rules going dark WEEKS after the adopting apply.
#
# THE FAILURE THIS SUITE IS SHAPED AGAINST. A fidelity probe compares a document
# to itself for a living, and the degenerate implementation — return PASS —
# satisfies every happy-path test anyone writes. So the identity case is worth
# exactly one row here; the other rows are one per DRIFT CLASS the probe claims
# to detect, and the claim in its header is only true if each of them reds.
#
# Every mutant is derived from the committed capture by a single scoped `jq`
# edit and is asserted to have LANDED, so no row can report a pass from a
# fixture that differs for some second reason.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/sentry-alert-live-fidelity.sh"
CAPTURE="$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json"
pass=0; fail=0
EXPECTED_TESTS=13

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

for f in "$PROBE" "$CAPTURE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f does not exist — RED phase expected this." >&2; exit 1; }
done

# _run <live-fixture> — sets the globals $_rc and $_out (stdout+stderr merged).
#
# NOT `rc=$(_run …)`. A command substitution runs in a SUBSHELL, so the callee's
# assignment to `_out` would be discarded and every marker assertion below would
# grep an empty string — reporting "the probe failed to detect" for nine drift
# classes it detects correctly.
_out=""; _rc=0
_run() {
  _rc=0
  _out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
         SENTRY_FIXTURE_RULES="$1" bash "$PROBE" 2>&1) || _rc=$?
}

# _mutant <label> <jq-program> -> path to the mutated live payload.
# Asserts the edit CHANGED the document. A jq filter whose selector no longer
# matches (a renamed rule, a reshaped capture) returns the input unchanged, and
# the row built on it would compare the capture to itself and report the probe
# "failed to detect" — or, worse, pass its identity assertion.
_mutant() {
  # Separate statements, not `local a=$1 b="$TMPD/$a.json"`. Bash declares every
  # name in a `local` list before assigning any of them, so the second
  # expansion sees the *unset local*, not the argument — fatal under `set -u`.
  local label="$1"
  local prog="$2"
  local f="$TMPD/$label.json"
  jq -c "$prog" "$CAPTURE" > "$f" 2>/dev/null || { echo "JQFAIL"; return; }
  if jq -S -c . "$f" | cmp -s - <(jq -S -c . "$CAPTURE"); then
    echo "NOOP"
    return
  fi
  echo "$f"
}

_drift_case() { # $1=label $2=jq-program $3=expected-marker $4=human description
  local f; f=$(_mutant "$1" "$2")
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then
    _report "$4" fail "the mutation did not land ($f) — this row compared the capture to itself and proves nothing"
    return
  fi
  _run "$f"
  if [[ "$_rc" -eq 1 ]] && grep -q "$3" <<<"$_out"; then
    _report "$4" ok
  else
    _report "$4" fail "rc=$_rc (want 1), marker '$3' not found. Output: $(head -c 400 <<<"$_out")"
  fi
}

# F13 — THE LIVE API'S SHAPE, which every other row in this file structurally
# cannot see.
#
# Every fixture here is derived from the committed capture, so both sides of the
# comparison are already normalised and their shapes agree BY CONSTRUCTION. The
# real API does not look like that: it returns server-assigned fields (`id`,
# `conditionResult`, `organizationId` on triggers and conditions;
# `integrationId`, `status` on actions) and does not sort object keys. Measured
# against production on 2026-09-04, the probe reported 38 divergences on a
# completely healthy org — and this probe files a p1 and runs daily, so that is
# a 38-finding false alarm on its first scheduled run and every one after.
#
# This row rebuilds an API-SHAPED payload from the capture — server fields added
# back, key order reversed — and asserts the probe still reports PASS. It is the
# only row that would have caught it.
#
# WHAT IT PINS, precisely: the DEEP KEY CANONICALISATION. Mutation-tested —
# removing `canon` from the projection reds this row. The allowlist projection
# of `actions` does NOT red it, because `integrationId`/`status` are siblings of
# `config`/`data` and a `{type, config, data}` shorthand drops them anyway. The
# allowlist is therefore defence-in-depth against a FUTURE server field landing
# inside `config` or `data`, not something this row proves today. Said plainly so
# nobody reads a green F13 as coverage it does not give.
t_live_api_shape() {
  local shaped="$TMPD/api-shaped.json"
  # Reverse keys RECURSIVELY. The projection REBUILDS the outer objects, so their
  # input key order is irrelevant — but `comparison` is passed through verbatim by
  # the `{type, comparison}` shorthand, so ITS internal order survives into the
  # serialised string the probe compares. That is where the real 11 false
  # findings came from, and a top-level-only reversal reproduces none of it.
  jq -c '
    def deep_reverse_keys:
      walk(if type == "object" then (to_entries | reverse | from_entries) else . end);
    def add_server:
      walk(if type == "object" and has("type")
           then . + {id: "9999", conditionResult: true}
           else . end);
    map(
      add_server
      | .triggers += {id: "8888", organizationId: "1"}
      | .actionFilters = [ .actionFilters[] | .actions = [ .actions[] | . + {integrationId: null, status: "active"} ] ]
      | deep_reverse_keys
    )
  ' "$CAPTURE" > "$shaped" 2>/dev/null

  if [[ ! -s "$shaped" ]] || ! jq -e 'length == 30' "$shaped" >/dev/null 2>&1; then
    _report "F13 an API-shaped payload (server fields + unsorted keys) still PASSES" fail \
      "the shaped fixture was not built — this row proves nothing"
    return
  fi
  # Landing assert 1: it must differ from the capture as RAW BYTES (server fields
  # and key order), or it is the identity case F1 already covers.
  if jq -c . "$shaped" | cmp -s - <(jq -c . "$CAPTURE"); then
    _report "F13 an API-shaped payload still PASSES" fail \
      "the shaped fixture is byte-identical to the capture"
    return
  fi
  # Landing assert 2: it must be SEMANTICALLY equal (same data, different shape).
  # Without this the row could pass by feeding the probe genuinely different data.
  # Scoped to `triggers` and `actionFilters` ONLY. A blanket `del(.id, …)` also
  # strips each RULE's real workflow id (e.g. "566201"), which the capture
  # legitimately carries — so the two sides would differ for a reason that has
  # nothing to do with the shape under test. (This assert caught that in its own
  # first draft.)
  if ! jq -S -c 'map(
         .triggers      |= walk(if type=="object" then del(.id,.conditionResult,.organizationId) else . end)
       | .actionFilters |= walk(if type=="object" then del(.id,.conditionResult,.organizationId,.integrationId,.status) else . end)
       )' "$shaped" \
       | cmp -s - <(jq -S -c . "$CAPTURE"); then
    _report "F13 an API-shaped payload still PASSES" fail \
      "the shaped fixture is not semantically identical to the capture — it changes DATA, not just SHAPE, so a RED would not mean what this row claims"
    return
  fi

  _run "$shaped"
  if [[ "$_rc" -eq 0 ]] && grep -q 'in-scope rules match' <<<"$_out"; then
    _report "F13 an API-shaped payload (server fields + unsorted keys) still PASSES" ok
  else
    _report "F13 an API-shaped payload still PASSES" fail \
      "rc=$_rc — the projection is not normalising both sides, so the probe would open a false p1 on its first real run. Output: $(head -c 300 <<<"$_out")"
  fi
}

# ── The identity row. ONE row, because it is the one a broken probe passes. ──
t_identity_passes() {
  _run "$CAPTURE"
  if [[ "$_rc" -eq 0 ]] && grep -q 'all 27 in-scope rules match' <<<"$_out"; then
    _report "F1 live == capture PASSES, and reports having compared all 27" ok
  else
    _report "F1 live == capture passes over all 27" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

# ── One row per drift class the header claims. ─────────────────────────────
t_deleted() {
  _drift_case deleted 'map(select(.name != "byok-art-33-breach"))' 'DELETED or RENAMED' \
    "F2 a DELETED rule is detected (byok-art-33-breach — the GDPR Art. 33 control)"
}

# Anchored on the FINDING, not the token. The probe's epilogue prints "DISABLED
# and MONITOR UNBIND are live state an apply will not touch" on every failing
# run, and `enabled` ALSO reds through the generic per-field loop as
# `DRIFT: '…'.enabled` — so suppressing the dedicated DISABLED finding left this
# row green while the classification silently changed. That is not cosmetic: the
# drift issue routes DRIFT to "re-run the apply" and DISABLED to "an apply will
# NOT fix this", so a misclassified UI mute sends the operator down the wrong
# path. Verified by the review's mutation battery.
t_disabled() {
  _drift_case disabled 'map(if .name=="byok-art-33-breach" then .enabled=false else . end)' \
    "DISABLED: 'byok-art-33-breach'" \
    "F3 a rule muted in the UI is detected AND classified as DISABLED, not DRIFT"
}

t_detector_unbind() {
  _drift_case unbind 'map(if .name=="byok-art-33-breach" then .detectorIds=["9999999"] else . end)' 'MONITOR UNBIND' \
    "F4 a detector REBIND is detected (the rule watches nothing while looking healthy)"
}

t_detector_empty() {
  _drift_case unbind0 'map(if .name=="byok-art-33-breach" then .detectorIds=[] else . end)' 'MONITOR UNBIND' \
    "F5 a detector UNBIND to the empty set is detected"
}

t_logictype_flip() {
  _drift_case logicflip 'map(if .name=="byok-art-33-breach" then .triggers.logicType="all" else . end)' 'LOGICTYPE FLIP' \
    "F6 a triggers.logicType flip is detected"
}

# The narrow one. A renamed tag key leaves the rule present, enabled, bound and
# planning clean — and matching nothing. It is the reason this probe compares
# fields rather than existence.
t_tagged_event_key_drift() {
  _drift_case tagkey \
    'map(if .name=="byok-art-33-breach" then .actionFilters[0].conditions[0].comparison.key="renamed" else . end)' \
    'comparison.key' \
    "F7 a renamed tagged_event KEY is detected, and the finding names the leaf path"
}

t_comparison_value_drift() {
  _drift_case cmpvalue \
    'map(if .name=="auth-signout-burst" then .triggers.conditions[0].comparison.value=999 else . end)' \
    'comparison.value' \
    "F8 a changed comparison.value is detected"
}

t_comparison_interval_drift() {
  _drift_case cmpinterval \
    'map(if .name=="auth-signout-burst" then .triggers.conditions[0].comparison.interval="1h" else . end)' \
    'comparison.interval' \
    "F9 a changed comparison.interval is detected"
}

# The other direction. A live in-scope rule the capture never saw is one nothing
# in this repo manages, and regenerating from the capture would not produce it.
t_unmanaged_new_rule() {
  _drift_case unmanaged \
    '. + [{"name":"created-in-the-ui","enabled":true,"detectorIds":["1213799"],"environment":null,"id":"999999","config":{"frequency":5},"triggers":{"logicType":"any-short","conditions":[{"type":"first_seen_event","comparison":true}],"actions":[]},"actionFilters":[]}]' \
    'UNMANAGED' \
    "F10 an in-scope live rule absent from the capture is reported as UNMANAGED"
}

# ── Anti-vacuity: the probe must refuse to certify having checked nothing. ──
t_empty_capture_refuses() {
  local cap="$TMPD/empty-capture.json"
  printf '[]' > "$cap"
  local rc=0
  local out
  out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
        SENTRY_CAPTURE_FILE="$cap" SENTRY_FIXTURE_RULES="$CAPTURE" bash "$PROBE" 2>&1) || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'ZERO in-scope rules' <<<"$out"; then
    _report "F11 a capture yielding zero in-scope rules REFUSES to report a clean verdict" ok
  else
    _report "F11 a capture yielding zero in-scope rules refuses" fail \
      "rc=$rc (want 1); output: $(head -c 300 <<<"$out")"
  fi
}

# The two survivors must NOT be in scope. If the predicate ever widened to
# include them, this probe would alarm forever on rules it was never meant to
# cover — and the operator would mute it.
t_survivors_out_of_scope() {
  _run "$CAPTURE"
  local names_ok=1
  # 30 live workflows, 27 in scope: the vendor default plus the two carrying
  # `event_unique_user_frequency_count` are excluded by the predicate, not by a
  # name list. Assert the COUNT and that neither survivor is named in a finding.
  grep -q 'comparing 27 captured in-scope rule' <<<"$_out" || names_ok=0
  if [[ "$_rc" -eq 0 && "$names_ok" -eq 1 ]]; then
    _report "F12 scope is 27: the vendor default and the two survivors are excluded by predicate" ok
  else
    _report "F12 scope is 27, survivors excluded" fail \
      "rc=$_rc; expected 'comparing 27 captured in-scope rule' in: $(head -c 300 <<<"$_out")"
  fi
}

t_identity_passes
t_live_api_shape
t_deleted
t_disabled
t_detector_unbind
t_detector_empty
t_logictype_flip
t_tagged_event_key_drift
t_comparison_value_drift
t_comparison_interval_drift
t_unmanaged_new_rule
t_empty_capture_refuses
t_survivors_out_of_scope

echo "=== $pass passed, $fail failed ==="

ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]

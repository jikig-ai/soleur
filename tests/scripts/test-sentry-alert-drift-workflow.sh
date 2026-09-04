#!/usr/bin/env bash
# The verdict branching in scheduled-sentry-alert-drift.yml (#7650 §2.9).
#
# WHY THIS EXISTS AS A TEST RATHER THAN A READING. The probe step decides which of
# three things happens to a divergence in 27 live paging rules: file an issue,
# close one, or neither. Two of those three outcomes are SILENT when wrong —
# a verdict that files nothing looks exactly like a clean run, and a wrongly
# closed issue looks exactly like a fixed one. Neither is visible in a green
# workflow list.
#
# The step's shell is EXTRACTED FROM THE SHIPPED YAML and executed, never
# restated here. A restatement passes forever after the workflow changes
# underneath it — the failure mode test-sentry-brownout-retry.sh's header
# records having shipped twice.
#
# TWO ROWS WERE CUT AT REVIEW and the reason is worth keeping. `t_discriminates`
# re-asserted `verdict == drift` and `verdict == unavailable`, which W2 and W3
# already assert — it could not fail unless one of them had already failed. And a
# status-function check on the issue steps duplicated
# `scripts/alarm-issue-filing-guard.test.sh`, which walks EVERY workflow in the
# repo and ratchets against a highwater file; that highwater is unchanged by this
# PR, which is itself the evidence the repo-wide gate already walked this file
# and found it clean. A second implementation of a live gate is not
# defence-in-depth, it is a second thing to keep true.
#
# The one branch that matters most is `unavailable`. If the probe cannot reach
# Sentry, this run establishes NOTHING; closing a real drift issue on that
# basis is the worst outcome the workflow can produce, and it is the outcome a
# `!= drift` condition would have produced.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/scheduled-sentry-alert-drift.yml"
pass=0; fail=0
EXPECTED_TESTS=5

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2; fi
}

[[ -f "$WF" ]] || { echo "ERROR: $WF does not exist — RED phase expected this." >&2; exit 1; }

# Extract the shipped `run:` block for the step whose id is `probe`.
if ! python3 - "$WF" "$TMPD/probe-step.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["drift-check"]["steps"]
probe = [s for s in steps if s.get("id") == "probe"]
if len(probe) != 1:
    sys.exit(f"expected exactly one step with id 'probe', found {len(probe)}")
open(sys.argv[2], "w").write(probe[0]["run"])
PY
then
  echo "ERROR: could not extract the probe step from $WF — the anchor (id: probe) moved." >&2
  exit 1
fi

# Non-vacuity on the EXTRACTION itself. An empty or truncated slice would let
# every case below "pass" by doing nothing.
if [[ ! -s "$TMPD/probe-step.sh" ]] || ! grep -q 'verdict=' "$TMPD/probe-step.sh"; then
  echo "ERROR: the extracted probe step is empty or carries no verdict assignment." >&2
  exit 1
fi

# _drive <stub-body> — runs the SHIPPED step with the probe script stubbed.
# Sets $_rc (the step's exit) and $_out (its GITHUB_OUTPUT contents).
_rc=0; _out=""
_drive() {
  local dir="$TMPD/run.$RANDOM"
  mkdir -p "$dir/scripts"
  printf '%s' "$1" > "$dir/scripts/sentry-alert-live-fidelity.sh"
  _rc=0
  _out=$( cd "$dir" && RUNNER_TEMP="$dir" GITHUB_OUTPUT="$dir/out.txt" \
          bash "$TMPD/probe-step.sh" >/dev/null 2>&1; echo "rc=$?"; cat "$dir/out.txt" 2>/dev/null )
  _rc=$(sed -n 's/^rc=//p' <<<"$_out" | head -1)
}

STUB_CLEAN='#!/usr/bin/env bash
echo "sentry_alert live fidelity: PASS (all 27 in-scope rules match the committed capture field-for-field)"
exit 0'
STUB_DRIFT='#!/usr/bin/env bash
echo "  DELETED or RENAMED: byok-art-33-breach"
echo "ERROR: sentry_alert live fidelity FAILED — 1 divergence(s)." >&2
exit 1'
STUB_UNAVAIL='#!/usr/bin/env bash
echo "ERROR: Sentry workflows response is not a JSON array." >&2
exit 1'

t_clean() {
  _drive "$STUB_CLEAN"
  if [[ "$_rc" == "0" ]] && grep -q '^verdict=clean$' <<<"$_out"; then
    _report "W1 a matching probe yields verdict=clean and a green step" ok
  else _report "W1 clean" fail "rc=$_rc out='$_out'"; fi
}

# The step must SUCCEED on drift. A failing step would skip the filer under its
# own `always()`-less siblings and, more importantly, would conflate "drift
# found" with "probe broken" — the distinction the whole verdict exists to draw.
t_drift() {
  _drive "$STUB_DRIFT"
  if [[ "$_rc" == "0" ]] && grep -q '^verdict=drift$' <<<"$_out"; then
    _report "W2 a divergence yields verdict=drift and a GREEN step, so the filer can run" ok
  else _report "W2 drift" fail "rc=$_rc out='$_out'"; fi
}

# The probe exits 1 for BOTH drift and transport failure. The discriminator is
# the marker it prints, so a transport failure must not be read as drift.
t_unavailable() {
  _drive "$STUB_UNAVAIL"
  if [[ "$_rc" == "1" ]] && grep -q '^verdict=unavailable$' <<<"$_out"; then
    _report "W3 a probe that could not complete yields verdict=unavailable and REDS the step" ok
  else _report "W3 unavailable" fail "rc=$_rc out='$_out'"; fi
}

# The close arm must be gated on `clean` ITSELF, never on `!= drift`. Under
# `!= drift`, an `unavailable` run closes a real drift issue because the probe
# could not reach Sentry — a false all-clear on 27 paging rules.
t_close_gated_on_clean_only() {
  local cond
  cond=$(python3 - "$WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for s in d["jobs"]["drift-check"]["steps"]:
    if "Close" in (s.get("name") or ""):
        print(s.get("if", ""))
PY
)
  if grep -q "verdict == 'clean'" <<<"$cond" && ! grep -q "!=" <<<"$cond"; then
    _report "W5 the close arm is gated on verdict == 'clean', never on '!= drift'" ok
  else
    _report "W5 close arm gating" fail "if: '$cond' — an inequality here closes a real drift issue on a run that established nothing"
  fi
}

# W7 — THE CONTRACT BETWEEN THE STEP AND THE PROBE.
#
# W1-W5 drive the shipped step against STUBS, and `STUB_DRIFT` hard-codes the
# marker `live fidelity FAILED` because that is what the step greps. So the
# suite verifies the step reads its own literal correctly and says NOTHING about
# whether the probe still emits it. Renaming the marker in
# `scripts/sentry-alert-live-fidelity.sh` left this suite AND the probe's own
# suite fully green while, in production, every drift verdict would reclassify as
# `unavailable`: the drift issue would never file, and the close arm would never
# fire. Verified by the review's mutation battery.
#
# This row closes the gap by running the REAL probe on a REAL divergence and
# asserting its output carries the literal the REAL step greps — both sides read
# from the shipped files, neither is restated here.
t_probe_marker_matches_what_the_step_greps() {
  local probe="$REPO_ROOT/scripts/sentry-alert-live-fidelity.sh"
  local capture="$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json"
  if [[ ! -f "$probe" || ! -f "$capture" ]]; then
    _report "W7 the probe emits the marker the step greps" fail "probe or capture missing"
    return
  fi
  # The literal the SHIPPED step greps, extracted rather than retyped.
  local marker
  marker=$(grep -oE "grep -q '[^']+' \"\\$\{RUNNER_TEMP\}/probe.txt\"" "$TMPD/probe-step.sh" \
           | sed "s/.*grep -q '//; s/'.*//")
  if [[ -z "$marker" ]]; then
    _report "W7 the probe emits the marker the step greps" fail \
      "could not extract the step's grep literal — the anchor moved"
    return
  fi
  # A REAL divergence through the REAL probe.
  local mut="$TMPD/w7-drift.json"
  jq -c 'map(select(.name != "byok-art-33-breach"))' "$capture" > "$mut" 2>/dev/null
  local out
  out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture SENTRY_FIXTURE_RULES="$mut" \
        bash "$probe" 2>&1) || true
  if grep -qF "$marker" <<<"$out"; then
    _report "W7 the real probe emits the exact marker the real step greps ('$marker')" ok
  else
    _report "W7 the real probe emits the marker the step greps" fail \
      "the step greps '$marker' and the probe does not emit it — every drift would reclassify as 'unavailable', so no drift issue is ever filed"
  fi
}

t_clean
t_drift
t_unavailable
t_close_gated_on_clean_only
t_probe_marker_matches_what_the_step_greps

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]

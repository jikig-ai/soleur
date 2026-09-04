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
# The one branch that matters most is `unavailable`. If the probe cannot reach
# Sentry, this run establishes NOTHING; closing a real drift issue on that
# basis is the worst outcome the workflow can produce, and it is the outcome a
# `!= drift` condition would have produced.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/scheduled-sentry-alert-drift.yml"
pass=0; fail=0
EXPECTED_TESTS=6

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

# W2 vs W3 is the whole design: same exit code from the probe, different verdict.
t_discriminates() {
  local d u
  _drive "$STUB_DRIFT";   d=$(sed -n 's/^verdict=//p' <<<"$_out")
  _drive "$STUB_UNAVAIL"; u=$(sed -n 's/^verdict=//p' <<<"$_out")
  if [[ "$d" == "drift" && "$u" == "unavailable" ]]; then
    _report "W4 drift and unavailable are DISTINGUISHED despite identical probe exit codes" ok
  else
    _report "W4 drift vs unavailable" fail "drift='$d' unavailable='$u' — the marker discriminator is gone, so a Sentry outage would file a drift issue naming no drift"
  fi
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

# Both issue steps must carry an explicit status function. A bare-expression
# `if:` inherits success() and skips after ANY earlier failure, so the verdict
# reaches nobody. This is the alarm-issue-filing-guard property, asserted here
# too because that guard is a repo-wide baseline and this is the specific claim.
t_issue_steps_have_status_fn() {
  local bad=()
  while IFS=$'\t' read -r name cond; do
    [[ -n "$name" ]] || continue
    grep -qE '\b(always|success|failure|cancelled)\s*\(' <<<"$cond" || bad+=("$name")
  done < <(python3 - "$WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for s in d["jobs"]["drift-check"]["steps"]:
    n = s.get("name") or ""
    if "issue" in n.lower():
        print(f"{n}\t{s.get('if','')}")
PY
)
  if [[ ${#bad[@]} -eq 0 ]]; then
    _report "W6 every issue step carries an explicit status function (no implicit success())" ok
  else
    _report "W6 issue steps carry a status function" fail "bare-expression if: on: ${bad[*]}"
  fi
}

t_clean
t_drift
t_unavailable
t_discriminates
t_close_gated_on_clean_only
t_issue_steps_have_status_fn

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]

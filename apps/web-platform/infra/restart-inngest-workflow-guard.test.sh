#!/usr/bin/env bash
# Tests for .github/workflows/restart-inngest-server.yml — the self-trigger guard (#6425 AC7).
#
# The workflow carries a `push` trigger scoped to its own path. That trigger exists SOLELY to
# register the workflow in the Actions UI (a workflow_dispatch-only workflow can take 30+ min to
# appear). Without a job-level event guard, the registration trigger has a side effect: editing
# this file on main RESTARTS inngest-server in PRODUCTION.
#
# Asserted against the PARSED YAML rather than a grep, so a reformat, a comment mentioning the
# idiom, or a guard moved onto a different job cannot false-PASS the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/restart-inngest-server.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== restart-inngest-server.yml self-trigger guard tests (#6425) ==="

assert "workflow file exists" "[[ -f '$WF' ]]"
assert "YAML parses (pyyaml)" "python3 -c 'import yaml; yaml.safe_load(open(\"$WF\"))'"

# Probe the parsed shape. The comparison happens in python, which emits bare yes/no tokens —
# the job's `if` string contains both spaces and single quotes, so round-tripping it through a
# shell variable into `eval` mangles the quoting (and silently false-FAILS a correct workflow).
# `on` is YAML 1.1 truthy: pyyaml keys it as boolean True, not the string "on", so probe both
# spellings or this reads as "no triggers" and passes vacuously.
probe() {
  python3 - "$WF" "$1" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get("on", wf.get(True)) or {}
# (#7278 back-port) ITERATE ALL JOBS — do not index one key. This probe used to read
# `jobs["restart"]` only, so a future second job added to this workflow would ship WITHOUT the
# guard, pass this test green, and fire on every registration push: the #6425 class re-entering
# through the one door the guard does not watch. An empty jobs map is NOT a pass. The paired
# `jobs_exact` check makes adding a job a deliberate act rather than a silent one.
jobs = wf.get("jobs") or {}
checks = {
    "push": "push" in on,
    "dispatch": "workflow_dispatch" in on,
    "guard": bool(jobs) and all(
        "github.event_name == 'workflow_dispatch'" in str(j.get("if", ""))
        for j in jobs.values()
    ),
    "jobs_exact": set(jobs) == {"restart"},
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

# Precondition: the guard is only meaningful while BOTH triggers exist. If the push trigger is
# ever dropped the guard is moot — this states the premise instead of silently passing.
assert "workflow still carries the registration push trigger (guard premise)" \
  "[[ \$(probe push) == 'yes' ]]"
assert "workflow still carries workflow_dispatch (the real entry point)" \
  "[[ \$(probe dispatch) == 'yes' ]]"

# The guard itself. EVERY job must no-op on every non-dispatch event — not just the one this
# test used to pin by name (#7278 back-port; see the probe comment).
assert "EVERY job is gated on workflow_dispatch (never fires on the registration push)" \
  "[[ \$(probe guard) == 'yes' ]]"
assert "the job set is exactly {restart} (a new job must be added to the guard deliberately)" \
  "[[ \$(probe jobs_exact) == 'yes' ]]"

# #6921/#8077 — the two inngest pollers name a quiesced refusal legibly. ci-deploy.sh's `restart`
# handler and `deploy inngest` arm refuse a unit op=quiesce-web stopped+disabled, writing
# inngest_quiesced_restart_refused / inngest_quiesced_deploy_refused. Without an arm the operator
# reads a generic "Restart failed" or a misleading "likely inngest-redis-bootstrap" and retries the
# very refusal. Anchored on the case-arm SHAPE (the `case "$REASON" in` opener immediately followed
# by the glob arm and its exact ::error:: text) over COMMENT-STRIPPED text, so prose mentioning the
# reason cannot satisfy it.
DEPLOY_WF="$REPO_ROOT/.github/workflows/deploy-inngest-image.yml"
POLL_CLASSIFIER="$REPO_ROOT/scripts/inngest-restart-poll-classify.sh"
# shellcheck disable=SC2034  # read inside the assert eval string below
Q_TXT='inngest_quiesced_*_refused) echo "::error::the web inngest unit is quiesced by op=quiesce-web — deliberate; only op=rollback re-arms it" ;;'
# shellcheck disable=SC2034  # read inside the assert eval string below
U_TXT='inngest_disabled_unattributed_*_refused) echo "::error::the web inngest unit is disabled with no valid quiesce marker (not a deliberate op=quiesce-web) — dispatch op=rollback to re-arm it" ;;'
# branch_probe <workflow> <step name> <mode> [<arm text>] — parses the YAML, takes the named step's
# `run:` body, drops comment lines, and answers yes/no:
#   in_fail_branch  the arm text sits INSIDE the failure branch — for the restart workflow the
#                   `terminal_fail)` arm of `case "$verdict"` (up to its lone `;;`); for the deploy
#                   workflow the fresh-inngest `if` inside the `*)` arm of `case "$EXIT_CODE"` (up to
#                   its `fi`) — and directly after a `case "$REASON" in` opener. The panel's WG1
#                   mutation moved the arm into the `success)` branch and the old whole-file row
#                   stayed green; position is the property, so position is what is asserted.
#   verdict_arms    every verdict classify_restart_frame can echo (derived from the classifier) has
#                   an arm in `case "$verdict"` (a missing arm is a silent no-op frame).
#   success_reason  the deploy workflow's `0)` success exit requires an inngest START success reason.
branch_probe() {
  python3 - "$1" "$2" "$3" "${4:-}" "$POLL_CLASSIFIER" <<'PY2'
import re, sys, yaml
wf, step_name, mode, arm, classifier = sys.argv[1:6]
doc = yaml.safe_load(open(wf)) or {}
run = ""
for job in (doc.get("jobs") or {}).values():
    for st in job.get("steps") or []:
        if st.get("name") == step_name:
            run = st.get("run", "")
lines = [l for l in run.splitlines() if not re.match(r"^\s*#", l)]
def block(start_re, end_re):
    for i, l in enumerate(lines):
        if re.match(start_re, l):
            for j in range(i + 1, len(lines)):
                if re.match(end_re, lines[j]):
                    return lines[i + 1:j]
            return None
    return None
ok = False
if mode == "in_fail_branch":
    if "restart-inngest-server" in wf:
        body = block(r"^\s*terminal_fail\)\s*$", r"^\s*;;\s*$")
    else:
        star = block(r"^\s*\*\)\s*$", r"^\s*;;\s*$")
        body = None
        if star:
            for i, l in enumerate(star):
                if re.search(r'if \[ "\$COMPONENT" = "inngest" \] && \[ "\$START_TS" -ge "\$FRESH_FLOOR" \]; then', l):
                    for j in range(i + 1, len(star)):
                        if re.match(r"^\s*fi\s*$", star[j]):
                            body = star[i + 1:j]; break
                    break
    if body:
        for i, l in enumerate(body):
            if l.strip() == arm:
                ok = any(re.match(r'^\s*case "\$REASON" in\s*$', body[k]) for k in range(max(0, i - 3), i))
                break
elif mode == "verdict_arms":
    src = [l for l in open(classifier).read().splitlines() if not re.match(r"^\s*#", l)]
    verdicts = sorted(set(m.group(1) for l in src for m in [re.search(r'echo "([a-z_]+)"', l)] if m and m.group(1) not in ("yes", "no")))
    # Nesting-aware: terminal_fail) carries its own `case "$REASON" … esac`, so the first `esac`
    # is NOT the end of the verdict case — only arms at depth 1 count.
    arms, depth, inside = set(), 0, False
    for l in lines:
        if not inside:
            inside = bool(re.match(r'^\s*case "\$verdict" in\s*$', l)); depth = 1 if inside else 0
            continue
        if re.search(r"\bcase\b.*\bin\s*$", l): depth += 1; continue
        if re.match(r"^\s*esac\s*$", l):
            depth -= 1
            if depth == 0: break
            continue
        m = re.match(r"^\s*([a-z_]+)\)\s*$", l)
        if m and depth == 1: arms.add(m.group(1))
    ok = len(verdicts) >= 9 and set(verdicts) <= arms
elif mode == "success_reason":
    zero = block(r"^\s*0\)\s*$", r"^\s*;;\s*$") or []
    ok = any(re.search(r'if \[ "\$COMPONENT" = "inngest" \] && \[ "\$START_TS" -ge "\$FRESH_FLOOR" \] && \{ \[ "\$REASON" = "success" \] \|\| \[ "\$REASON" = "success_degraded_durability" \]; \}; then', l) for l in zero)
print("yes" if ok else "no")
PY2
}
RESTART_STEP="Verify restart completion"
DEPLOY_STEP="Verify deploy completion"
assert "#8077 restart-inngest-server.yml: the quiesced arm sits INSIDE terminal_fail) after case \"\$REASON\" in" \
  "[[ \$(branch_probe '$WF' '$RESTART_STEP' in_fail_branch \"\$Q_TXT\") == 'yes' ]]"
assert "#8077 restart-inngest-server.yml: the disabled-unattributed arm (op=rollback) sits INSIDE terminal_fail)" \
  "[[ \$(branch_probe '$WF' '$RESTART_STEP' in_fail_branch \"\$U_TXT\") == 'yes' ]]"
assert "#8077 deploy-inngest-image.yml: the quiesced arm sits INSIDE the fresh-inngest failure branch" \
  "[[ \$(branch_probe '$DEPLOY_WF' '$DEPLOY_STEP' in_fail_branch \"\$Q_TXT\") == 'yes' ]]"
assert "#8077 deploy-inngest-image.yml: the disabled-unattributed arm (op=rollback) sits INSIDE the fresh-inngest failure branch" \
  "[[ \$(branch_probe '$DEPLOY_WF' '$DEPLOY_STEP' in_fail_branch \"\$U_TXT\") == 'yes' ]]"
assert "#8077 restart-inngest-server.yml: every classify_restart_frame verdict (incl. other_op) has a case \"\$verdict\" arm" \
  "[[ \$(branch_probe '$WF' '$RESTART_STEP' verdict_arms) == 'yes' ]]"
assert "#8077 deploy-inngest-image.yml: the 0) success exit requires an inngest START success reason (not quiesced/enabled)" \
  "[[ \$(branch_probe '$DEPLOY_WF' '$DEPLOY_STEP' success_reason) == 'yes' ]]"
# PROBE CANARY: the position probe must say `no` for an arm text that is NOT in the branch.
assert "probe canary: an absent arm text is not found in terminal_fail) (the probe can say no)" \
  "[[ \$(branch_probe '$WF' '$RESTART_STEP' in_fail_branch 'no_such_reason) echo x ;;') == 'no' ]]"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed ==="

# EXACT ASSERTION COUNT (#8077 review) — see the sibling note in registry-zot-inventory-workflow-guard.test.sh
# for why a count gate exists at all. Exact rather than a floor: a row that silently stops
# dispatching keeps a floor green. Adding a row means bumping this in the same diff.
EXPECTED_ASSERTIONS=13
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf 'FAIL: %s assertions ran, expected exactly %s — treat this as UN-RUN, not as a pass.\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS"
  exit 1
fi

if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi

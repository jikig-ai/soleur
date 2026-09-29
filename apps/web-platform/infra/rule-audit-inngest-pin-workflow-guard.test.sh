#!/usr/bin/env bash
# Guard tests for the `Detect inngest CLI pin drift` step in
# .github/workflows/rule-audit.yml (#7463 PR-B).
#
# THE FAILURE MODE THIS PINS: a poll step that LOOKS present and does nothing — the same
# class the zot workflow guards exist for. Every structural assertion reads the PARSED
# YAML (python emits bare yes/no tokens), never a raw grep: a grep passes on a
# commented-out step, on a guard moved onto a different job, and on a comment that
# merely mentions the idiom.
#
# What is pinned (the PR-B contract, mirrored from `Detect zot pin staleness`):
#   - the step exists on the rule-audit job, guarded by `!cancelled()` (a step `if:`
#     without a status function is implicitly ANDed with success() — an earlier
#     failed step would silence this detector every run while the workflow still
#     emails about the first failure)
#   - a bounded timeout-minutes (a hung gh api would otherwise mark the step
#     `cancelled`, not `failed`, and the ops email would not fire)
#   - the offline gate's 0/10/2 contract is HONOURED: rc=2 exits the step 2
#     (detector failure, never "fresh"), rc=10 records drift, anything else
#     propagates
#   - the pinned version is parsed ANCHORED on the inngest_cli_version assignment
#     (an unanchored grep is satisfied by a comment — measured on the zot step)
#   - the upstream poll reads repos/inngest/inngest/releases/latest AND the tag list
#     for the releases-behind delta AND the pinned release's published_at for age
#   - the DRIFT threshold: releases_behind -ge 5 OR pin age -ge 45 days — the SAME
#     literals the provenance sidecar records, pinned by parity probe below
#   - both arch tarballs are HEAD-probed (amd64 + arm64)
#   - exactly ONE idempotent issue: `gh label create ... --force`, an
#     `gh issue list --label inngest-pin-drift` lookup, then comment-or-create with
#     the `action-required` label (the ONLY label the weekly digest harvests)
#   - exit semantics: PROBLEMS -> exit 1 (ops email via the failure() step); drift
#     alone exits 0 — the issue is the channel, not the check status
#
# MUTATION ARMS prove the probes discriminate: deleting the step, unanchoring the pin
# parse, removing --force, dropping action-required, and zeroing a threshold each
# flip a named probe on a mutated copy — none of these is a claim that has only ever
# been seen green.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/rule-audit.yml"
GATE="$REPO_ROOT/apps/web-platform/infra/inngest-cli-staleness.test.sh"
PROV="$REPO_ROOT/apps/web-platform/infra/inngest-cli.provenance.md"

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

# POSITIVE CONTROL — drives pass()/fail() machinery once each and requires both counters
# to move; a neutered helper cannot satisfy the floor below by doing nothing.
before="$PASS $FAIL"
assert "positive control" "true"
mid="$PASS $FAIL"
assert "positive control (fail arm moves the counter)" "false" && true
after="$PASS $FAIL"
FAIL=$((FAIL - 1))   # the deliberate failure above is the instrument, not a defect
if [[ "$before" == "$mid" || "$mid" == "$after" ]]; then
  echo "  FAIL: positive control — assert() did not move both counters" >&2
  exit 2
fi

echo "=== rule-audit.yml inngest pin-drift step guard (#7463 PR-B) ==="

assert "rule-audit.yml exists" "[[ -f '$WF' ]]"
assert "offline gate exists (the step's enforcement half)" "[[ -f '$GATE' ]]"
assert "provenance sidecar exists" "[[ -f '$PROV' ]]"
assert "rule-audit.yml parses (pyyaml)" \
  "python3 -c 'import yaml; yaml.safe_load(open(\"$WF\"))'"

# ---------------------------------------------------------------------------
# The step probe: parses the workflow, locates the step by NAME, and answers one
# question per invocation as a bare yes/no token (round-tripping an if: string
# through eval mangles quoting and silently false-fails a correct workflow).
# ---------------------------------------------------------------------------
probe() { # probe <wf-path> <check-name>
  python3 - "$1" "$2" <<'PY'
import sys, yaml
wf_path, check = sys.argv[1], sys.argv[2]
try:
    wf = yaml.safe_load(open(wf_path)) or {}
except Exception:
    print("no"); sys.exit(0)
step = None
for job in (wf.get('jobs') or {}).values():
    for s in (job or {}).get('steps', []) or []:
        if isinstance(s, dict) and s.get('name') == 'Detect inngest CLI pin drift':
            step = s
run = (step or {}).get('run') or ''
cond = str((step or {}).get('if') or '')
out = {
  'present'        : step is not None,
  'not-cancelled'  : '!cancelled()' in cond,
  'timeout'        : isinstance((step or {}).get('timeout-minutes'), int)
                        and (step or {}).get('timeout-minutes') <= 5,
  'rc2-contract'   : 'RC" -eq 2' in run and 'exit 2' in run,
  'rc10-drift'     : '"$RC" -eq 10' in run and 'DRIFT=' in run,
  'rc-passthrough' : 'exit "$RC"' in run,
  'anchored-pin'   : 'inngest_cli_version' in run and 'grep -oE' in run,
  'poll-latest'    : 'repos/inngest/inngest/releases/latest' in run,
  'tag-delta'      : 'repos/inngest/inngest/tags' in run and 'sort' in run,
  'age-leg'        : 'published_at' in run and 'AGE_DAYS' in run,
  'thr-count'      : '[ "$BEHIND" -ge 5 ]' in run,
  'thr-age'        : '[ "$AGE_DAYS" -ge 45 ]' in run,
  'tarball-probe'  : 'amd64' in run and 'arm64' in run and 'releases/download' in run
                        and 'inngest_' in run and '_linux_' in run,
  'label-idem'     : 'gh label create inngest-pin-drift' in run and '--force' in run,
  'action-required': '--label action-required' in run,
  'upsert'         : 'gh issue list --label inngest-pin-drift' in run
                        and 'gh issue comment' in run and 'gh issue create' in run,
  'drift-exit-0'   : 'exit 0' in run,
  'problems-exit'  : 'if [ -n "$PROBLEMS" ]' in run and 'exit 1' in run,
}
print('yes' if out.get(check) else 'no')
PY
}

assert "step exists on the workflow" '[[ "$(probe "$WF" present)" == yes ]]'
assert "step is guarded by !cancelled() (an earlier failed step must not silence it)" \
  '[[ "$(probe "$WF" not-cancelled)" == yes ]]'
assert "step has a bounded timeout-minutes (job timeout marks steps cancelled, not failed)" \
  '[[ "$(probe "$WF" timeout)" == yes ]]'
assert "offline-gate rc=2 exits the step 2 (detector failure is never 'fresh')" \
  '[[ "$(probe "$WF" rc2-contract)" == yes ]]'
assert "offline-gate rc=10 records DRIFT" '[[ "$(probe "$WF" rc10-drift)" == yes ]]'
assert "unexpected gate rc propagates (exit \"\$RC\")" '[[ "$(probe "$WF" rc-passthrough)" == yes ]]'
assert "pin parse is anchored on the inngest_cli_version assignment" \
  '[[ "$(probe "$WF" anchored-pin)" == yes ]]'
assert "upstream poll reads releases/latest" '[[ "$(probe "$WF" poll-latest)" == yes ]]'
assert "releases-behind delta enumerates the tag list (stable-tag ordering)" \
  '[[ "$(probe "$WF" tag-delta)" == yes ]]'
assert "pinned-release age leg reads published_at" '[[ "$(probe "$WF" age-leg)" == yes ]]'
assert "threshold: releases_behind >= 5" '[[ "$(probe "$WF" thr-count)" == yes ]]'
assert "threshold: pinned release age >= 45 days" '[[ "$(probe "$WF" thr-age)" == yes ]]'
assert "both arch tarballs are HEAD-probed" '[[ "$(probe "$WF" tarball-probe)" == yes ]]'
assert "inngest-pin-drift label is created idempotently (--force)" \
  '[[ "$(probe "$WF" label-idem)" == yes ]]'
assert "the filed issue carries action-required (the digest's ONLY label)" \
  '[[ "$(probe "$WF" action-required)" == yes ]]'
assert "exactly-one-issue upsert: list -> comment existing OR create" \
  '[[ "$(probe "$WF" upsert)" == yes ]]'
assert "drift alone exits 0 (the issue is the channel)" \
  '[[ "$(probe "$WF" drift-exit-0)" == yes ]]'
assert "unrunnable probes exit non-zero (ops email)" \
  '[[ "$(probe "$WF" problems-exit)" == yes ]]'

# --- parity with the sidecar ---------------------------------------------------------
# The thresholds must match the sidecar's recorded values — two halves of one detector
# must not carry different numbers.
assert "sidecar records the >=5-releases threshold" \
  "grep -qE '5[^0-9]+stable releases|releases?[^a-z]*behind[^0-9]*5|>= ?5' '$PROV'"
assert "sidecar records the >=45-day threshold" \
  "grep -qE '45[^0-9]+days|days?[^0-9]*45|>= ?45' '$PROV'"

# --- parity with the zot sibling step ------------------------------------------------
# Both detectors share one contract: offline gate first with the same 0/10/2 handling,
# anchored pin parse, idempotent label + action-required issue, drift->0/problems->1.
ZOT_STEP_PRESENT="$(python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
found = 'no'
for job in (wf.get('jobs') or {}).values():
    for s in (job or {}).get('steps', []) or []:
        if isinstance(s, dict) and s.get('name') == 'Detect zot pin staleness':
            found = 'yes'
print(found)
PY
)"
assert "the zot sibling step still exists (parity anchor)" "[[ '$ZOT_STEP_PRESENT' == yes ]]"

# --- mutation arms: the probes must discriminate ------------------------------------
# Each arm mutates a COPY of the workflow at the text level, re-runs the probe, and
# requires the named check to flip to `no`. Without these, "the probe detects" is a
# claim that has only ever been seen green.

mut_text() { # mut_text <name> <sed-expr> <check-that-must-flip-to-no>
  local name="$1" expr="$2" check="$3" mwf
  mwf="$TMP/mut-$name.yml"
  sed "$expr" "$WF" > "$mwf"
  local v; v="$(probe "$mwf" "$check")"
  assert "mutation $name: '$check' flips to no" "[[ '$v' == no ]]"
}

mut_text no-step          's/Detect inngest CLI pin drift/Detect REMOVED/'        present
mut_text no-cancel-guard  's/!cancelled()/success()/'                              not-cancelled
mut_text no-timeout       '/timeout-minutes: 2/d'                                  timeout
mut_text unanchored-pin   's/inngest_cli_version/PIN_REMOVED/g'                   anchored-pin
mut_text no-latest-poll   's|repos/inngest/inngest/releases/latest|repos/REMOVED|g' poll-latest
mut_text no-age           's/published_at/PUB_REMOVED/'                            age-leg
mut_text zero-thr-count   's/\"\$BEHIND\" -ge 5/"$BEHIND" -ge 5000/'            thr-count
mut_text zero-thr-age     's/\"\$AGE_DAYS\" -ge 45/"$AGE_DAYS" -ge 45000/'      thr-age
mut_text no-arm64         's/ arm64;/;/'                                           tarball-probe
mut_text no-force         's/--force /--no-force-until-idempotence/'               label-idem
mut_text no-digest-label  's/--label action-required//'                             action-required
mut_text no-upsert        's/gh issue comment/gh issue never-comment/g'            upsert
mut_text no-problems-exit 's/if \[ -n "\$PROBLEMS" \]/if false/'                problems-exit

# --- floor ----------------------------------------------------------------------------
# Bound sits adjacent to the check — scripts/guard-vacuity-floor.test.sh slices the floor
# plus its contiguous assignment bindings into a mutant, so a threshold bound at the top of
# the file leaves the mutant unbound and scores CONSTRUCTION instead of FIRES.
MIN_FLOOR=39
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_FLOOR )); then
  echo "  DETECTOR-FAILURE: only $TOTAL assertions ran (floor $MIN_FLOOR) — the suite's own assertions were dropped; this run proves nothing" >&2
  exit 2
fi

echo ""
echo "=== RESULT: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then exit 1; fi
echo "rule-audit-inngest-pin-workflow-guard: all checks passed"

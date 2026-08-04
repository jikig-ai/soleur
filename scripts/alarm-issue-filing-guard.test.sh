#!/usr/bin/env bash
# Structural gate: an alarm step that FILES an issue must be able to run when the alarm
# FIRED (#7242).
#
# THE DEFECT THIS PINS. A GitHub Actions step whose `if:` contains no status-check function
# inherits an implicit `success()`, so it skips whenever ANY earlier step failed —
# regardless of its own condition. `scheduled-zot-restart-loop.yml` had seven issue-filing
# steps in that shape, and its checker signals FIRE by exiting 1. So the recurrence alarm
# built for exactly this failure could not open its issue on the one verdict it exists to
# report. Measured on run 30851584863 (2026-08-03 20:44): checker = failure, all seven
# filing steps = skipped, while zot restarted ~4x/min for four hours and no
# [ci/zot-restart-loop] issue was ever opened.
#
# THE INVERSE DEFECT, which a mechanical sweep introduces. A status function alone is WRONG
# for a step that treats an EMPTY output as good news. `scheduled-inngest-health.yml` closes
# up to five tracking issues (including P1 [ci/inngest-down]) on
# `steps.effmode.outputs.failure_mode == ''` — and empty is precisely what a crashed effmode
# produces. Adding a bare `always()` there converts "the checker died" into "Inngest healthy
# again". Those steps need a producer-liveness guard, so this gate checks for one rather
# than accepting a status function as sufficient everywhere.
#
# WHY IT DISCOVERS RATHER THAN LISTS. An earlier version hardcoded two TARGETS. The repo has
# 24 workflows that write to the issue tracker; the guard walked 13 steps of ~55 and
# reported "certified". Dropping a THIRD alarm workflow carrying BOTH defects into
# .github/workflows/ left it 15/15 green — population growth was completely silent, so the
# next alarm someone builds would inherit #7242's defect and ship green. It now walks every
# workflow and carries a .highwater for the pre-existing population, in the same shape as
# lint-diagnosis-claims.highwater: a ratcheting baseline, not a merge blocker.
#
# This is a static gate because the condition is evaluated by GitHub, not by any code we can
# execute: there is nothing to drive at runtime, so the workflow YAML is the artifact under
# test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HIGHWATER="$SCRIPT_DIR/alarm-issue-filing-guard.highwater"

# ALARM_GUARD_ROOT is the TEST SEAM. Without it this gate could only ever run over the live
# tree, so its violation branches had a discriminating population of ZERO — they had never
# been observed firing, which is indistinguishable from being unable to. The fixtures below
# assert both rules actually trip.
scan() {
  python3 - "$1" "${2:-0}" <<'PY'
import sys, os, re, yaml

root, strict = sys.argv[1], sys.argv[2] == "1"

STATUS_FN = re.compile(r"\b(always|failure|success|cancelled)\s*\(")
# Steps that WRITE to the issue tracker. Reads (`gh issue list`/`view`) are excluded: a read
# that skips costs nothing, and widening this would drag in steps whose skip behaviour is
# not a reporting defect.
FILES_ISSUE = re.compile(r"gh issue (create|comment|close|edit)\b")
CLOSES_ISSUE = re.compile(r"gh issue close\b")
EMPTY_AS_VERDICT = re.compile(r"outputs\.[A-Za-z0-9_]+\s*==\s*''")
# A comparison against a NON-EMPTY, NON-NUMERIC literal. Both qualifiers are load-bearing.
#
# Non-empty: a crashed producer writes nothing, so a clause demanding a real value cannot be
# satisfied by it. Non-NUMERIC: GitHub Actions `==` is LOOSE — when operand types differ both
# cast to Number, so an unset output (null) casts to 0 and `null == '0'` is TRUE. An earlier
# version of this regex accepted `== '0'` as proof of safety, so the gate written to catch the
# inversion class would have passed the auto-close step that fires on a checker that measured
# nothing. Numeric literals are excluded for exactly that reason.
NONEMPTY_LITERAL = re.compile(r"outputs\.[A-Za-z0-9_]+\s*==\s*'(?![0-9]+')[^']+'")
NUMERIC_LITERAL = re.compile(r"outputs\.[A-Za-z0-9_]+\s*==\s*'[0-9]+'")
LIVENESS_GUARD = re.compile(r"steps\.[A-Za-z0-9_-]+\.outcome\s*==\s*'success'")

wf_dir = os.path.join(root, ".github", "workflows")
violations, scanned, files = [], 0, 0
for fn in sorted(os.listdir(wf_dir)) if os.path.isdir(wf_dir) else []:
    if not fn.endswith((".yml", ".yaml")):
        continue
    path = os.path.join(wf_dir, fn)
    if os.path.islink(path):
        continue
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8"))
    except Exception:
        continue
    if not isinstance(doc, dict):
        continue
    files += 1
    for job in (doc.get("jobs") or {}).values():
        if not isinstance(job, dict):
            continue
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            # Strip comments before the write-verb search: a comment mentioning
            # `gh issue create` would otherwise inflate the scanned count and mask a real
            # step being removed.
            body = "\n".join(
                ln for ln in (step.get("run") or "").splitlines()
                if not ln.strip().startswith("#")
            )
            if not FILES_ISSUE.search(body):
                continue
            scanned += 1
            label = f"{fn}: {step.get('name') or step.get('id') or '<unnamed>'}"
            cond = str(step.get("if", ""))
            # NARROW, deliberately. A step with NO `if:` at all is ordinary
            # unconditional-on-success structure, not this defect — flagging it produced 6
            # false positives out of 22 and would have made the ratchet carry noise it can
            # never drive to zero. The defect is specifically a step GATED ON ANOTHER STEP'S
            # OUTPUT with no status function: the producer can fail while still having
            # written that output, and the implicit success() then skips the consumer on
            # exactly the run it exists for.
            if cond and re.search(r"steps\.[A-Za-z0-9_-]+\.outputs\.", cond) and not STATUS_FN.search(cond):
                violations.append(("no-status-fn", label, cond))
            if (CLOSES_ISSUE.search(body)
                    and STATUS_FN.search(cond)
                    and EMPTY_AS_VERDICT.search(cond)
                    and not NONEMPTY_LITERAL.search(cond)
                    and not LIVENESS_GUARD.search(cond)):
                violations.append(("close-on-empty", label, cond))
            # Rule 3, the COERCION twin of rule 2. GitHub Actions `==` casts across types,
            # so an unset output (null) equals '0'. A step that auto-closes on
            # `exit_code == '0'` therefore fires on a producer that wrote nothing at all —
            # the same false all-clear as close-on-empty, reached through a numeric literal
            # instead of an empty one. Cleared by ANY non-numeric discriminator (pairing the
            # code with its verdict) or by an explicit liveness guard.
            if (CLOSES_ISSUE.search(body)
                    and STATUS_FN.search(cond)
                    and NUMERIC_LITERAL.search(cond)
                    and not NONEMPTY_LITERAL.search(cond)
                    and not LIVENESS_GUARD.search(cond)):
                violations.append(("close-on-coercible-numeric", label, cond))

for kind, label, cond in violations:
    print(f"VIOLATION\t{kind}\t{label}\t{cond}")
print(f"SCANNED={scanned}")
print(f"FILES={files}")
print(f"COUNT={len(violations)}")
PY
}

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== alarm-issue-filing-guard ==="

# ── The violation branches must be OBSERVED firing ─────────────────────────────────────
# Without these, both branches have a discriminating population of zero: they have never
# fired on any input, so a one-character edit disabling either is undetectable.
FIX="$(mktemp -d -t alarm-guard-fix.XXXXXXXX)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.github/workflows"

cat > "$FIX/.github/workflows/rule1.yml" <<'YAML'
name: rule1
jobs:
  a:
    steps:
      - name: File the recurrence issue
        if: steps.checker.outputs.verdict == 'fire'
        run: gh issue create --title x --body y
YAML
assert_eq "rule 1 fires: a filing step with no status function is a violation" "1" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

cat > "$FIX/.github/workflows/rule1.yml" <<'YAML'
name: rule1fixed
jobs:
  a:
    steps:
      - name: File the recurrence issue
        if: always() && steps.checker.outputs.verdict == 'fire'
        run: gh issue create --title x --body y
YAML
assert_eq "rule 1 clears once a status function is present" "0" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

cat > "$FIX/.github/workflows/rule2.yml" <<'YAML'
name: rule2
jobs:
  a:
    steps:
      - name: Auto-close when healthy
        if: always() && steps.checker.outputs.failure_mode == ''
        run: gh issue close 1
YAML
assert_eq "rule 2 fires: closing on an EMPTY output with no liveness guard is a violation" "1" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

cat > "$FIX/.github/workflows/rule2.yml" <<'YAML'
name: rule2fixed
jobs:
  a:
    steps:
      - name: Auto-close when healthy
        if: always() && steps.checker.outcome == 'success' && steps.checker.outputs.failure_mode == ''
        run: gh issue close 1
YAML
assert_eq "rule 2 clears once producer liveness is asserted" "0" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

# THE COERCION CASE. `null == '0'` is TRUE in GitHub Actions, so a numeric literal is NOT
# proof that a crashed producer cannot satisfy the condition. This fixture is the auto-close
# step that shipped in this PR's first draft.
cat > "$FIX/.github/workflows/rule2.yml" <<'YAML'
name: rule2numeric
jobs:
  a:
    steps:
      - name: Auto-close on green
        if: always() && steps.checker.outputs.exit_code == '0'
        run: gh issue close 1
YAML
assert_eq "a NUMERIC literal does not exempt an auto-close (null == '0' coerces true)" "1" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

cat > "$FIX/.github/workflows/rule2.yml" <<'YAML'
name: rule2paired
jobs:
  a:
    steps:
      - name: Auto-close on green
        if: always() && steps.checker.outputs.exit_code == '0' && steps.checker.outputs.verdict == 'GREEN'
        run: gh issue close 1
YAML
assert_eq "pairing the numeric arm with a non-numeric verdict clears it" "0" \
  "$(scan "$FIX" | sed -n 's/^COUNT=//p')"

# A comment naming a write verb must not inflate the scanned count. Cleared to a tree with
# NO other filing step first — otherwise the surviving rule1 fixture supplies the count and
# the assertion measures nothing.
rm -f "$FIX/.github/workflows/rule1.yml" "$FIX/.github/workflows/rule2.yml"
cat > "$FIX/.github/workflows/commented.yml" <<'YAML'
name: commented
jobs:
  a:
    steps:
      - name: Not a filing step
        run: |
          # we deliberately do not gh issue create here
          echo ok
YAML
assert_eq "a comment naming a write verb is not counted as a filing step" "0" \
  "$(scan "$FIX" | sed -n 's/^SCANNED=//p')"

# ── The live repo, against a ratcheting baseline ────────────────────────────────────────
LIVE="$(scan "$REPO_ROOT")"
live_count="$(printf '%s\n' "$LIVE" | sed -n 's/^COUNT=//p')"
live_scanned="$(printf '%s\n' "$LIVE" | sed -n 's/^SCANNED=//p')"
live_files="$(printf '%s\n' "$LIVE" | sed -n 's/^FILES=//p')"

# ANTI-VACUITY, exiting DIRECTLY rather than through the assertion helpers. Routing the
# floor through the same primitive it protects means neutering that primitive also silences
# the floor — which was true of the previous version.
if [[ "${live_files:-0}" -lt 20 || "${live_scanned:-0}" -lt 40 ]]; then
  echo "FAIL: walked ${live_files:-0} workflows / ${live_scanned:-0} filing steps — too few." >&2
  echo "      The walk is not reaching what it claims to certify. Fix the scanner, not the floor." >&2
  exit 1
fi

if [[ ! -f "$HIGHWATER" ]]; then
  echo "FAIL: $HIGHWATER is missing — the ratchet has no baseline, so this run certifies nothing." >&2
  exit 1
fi
allowed="$(sed 's/#.*//' "$HIGHWATER" | tr -d '[:space:]')"
if ! [[ "$allowed" =~ ^[0-9]+$ ]]; then
  echo "FAIL: $HIGHWATER does not contain a non-negative integer (got '${allowed}')." >&2
  exit 1
fi

if [[ "$live_count" -gt "$allowed" ]]; then
  printf '%s\n' "$LIVE" | grep '^VIOLATION' | sed 's/^/  /' >&2
  echo "" >&2
  echo "FAIL: ${live_count} issue-filing steps cannot report (baseline ${allowed})." >&2
  echo "      no-status-fn  -> the step inherits success() and skips after ANY earlier failure." >&2
  echo "      close-on-empty -> the step auto-closes on a value a CRASHED producer also emits." >&2
  echo "      Do NOT raise the baseline. It ratchets down only." >&2
  exit 1
fi
assert_eq "the live repo is at or below its committed baseline" "0" "0"
if [[ "$live_count" -lt "$allowed" ]]; then
  echo "  note: live count is ${live_count}, below the baseline of ${allowed} — lower $HIGHWATER to lock it in."
fi
echo "  (walked ${live_files} workflows, ${live_scanned} issue-filing steps, ${live_count} violations)"

echo "=== Results: $PASS passed, $FAIL failed ==="

MIN_ASSERTIONS=7   # derived from a green run (8 at time of writing), with headroom
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS}." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]

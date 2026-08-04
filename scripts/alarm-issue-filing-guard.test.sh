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
# THE INVERSE DEFECT, which a mechanical sweep introduces. `always()` alone is WRONG for a
# step that treats an EMPTY output as good news. `scheduled-inngest-health.yml` closes up
# to five tracking issues (including P1 [ci/inngest-down]) on
# `steps.effmode.outputs.failure_mode == ''` — and empty is precisely what a crashed
# effmode produces. Adding a bare `always()` there converts "the checker died" into
# "Inngest healthy again". Those steps need a producer-liveness guard as well, so this gate
# checks for one rather than accepting `always()` as sufficient everywhere.
#
# This is a static gate because the condition is evaluated by GitHub, not by any code we
# can execute: there is nothing to drive at runtime, so the workflow YAML is the artifact
# under test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import sys, os, re, yaml

root = sys.argv[1]
TARGETS = [
    ".github/workflows/scheduled-zot-restart-loop.yml",
    ".github/workflows/scheduled-inngest-health.yml",
]

STATUS_FN = re.compile(r"\b(always|failure|success|cancelled)\s*\(")
# Steps that WRITE to the issue tracker. `gh issue list`/`view` are reads and are excluded
# deliberately: a read that skips costs nothing, and widening this to every gh invocation
# would drag in steps whose skip behaviour is not a reporting defect.
FILES_ISSUE = re.compile(r"gh issue (create|comment|close|edit)\b")
CLOSES_ISSUE = re.compile(r"gh issue close\b")
# `x.outputs.y == ''` — the shape where a crashed producer's empty output reads as a verdict.
EMPTY_AS_VERDICT = re.compile(r"outputs\.[A-Za-z0-9_]+\s*==\s*''")
# `x.outputs.y == 'something'` — a comparison against a NON-EMPTY literal. This is what
# makes the difference, and getting it wrong in either direction matters:
#
#   `failure_mode == ''`                              <- crashed producer SATISFIES this
#   `failure_mode == '' && durability_state == 'durable'`  <- crashed producer CANNOT
#
# In the second, the empty-output clause is conjoined with one that demands a real value,
# so a dead producer skips the step on its own. Flagging it anyway would be a false
# positive, and a gate that cries wolf on a correct condition gets silenced wholesale —
# which costs more than the case it was protecting.
NONEMPTY_LITERAL = re.compile(r"outputs\.[A-Za-z0-9_]+\s*==\s*'[^']+'")
LIVENESS_GUARD = re.compile(r"steps\.[A-Za-z0-9_-]+\.outcome\s*==\s*'success'")

PASS = FAIL = 0
def ok(msg):
    global PASS; PASS += 1; print(f"  PASS: {msg}")
def bad(msg, detail=""):
    global FAIL; FAIL += 1; print(f"  FAIL: {msg}")
    if detail: print(f"    {detail}")

scanned = 0
for rel in TARGETS:
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        bad(f"{rel} is missing — this gate cannot certify a file it cannot read")
        continue
    doc = yaml.safe_load(open(path))
    name = os.path.basename(rel)
    for job in doc.get("jobs", {}).values():
        for step in job.get("steps", []):
            body = step.get("run") or ""
            if not FILES_ISSUE.search(body):
                continue
            scanned += 1
            label = step.get("name") or step.get("id") or "<unnamed>"
            cond = str(step.get("if", ""))

            if not cond:
                bad(f"{name}: '{label}' files an issue with NO if: at all")
                continue
            if not STATUS_FN.search(cond):
                bad(f"{name}: '{label}' files an issue but its if: has no status-check function",
                    f"if: {cond}  -- it inherits success() and skips whenever an earlier step failed")
            else:
                ok(f"{name}: '{label}' can run after an earlier failure")

            # The inversion class: closing issues on a verdict a CRASHED producer can
            # satisfy. Only fires when the condition has an `== ''` clause and NOTHING
            # demanding a real value — see NONEMPTY_LITERAL above.
            if (CLOSES_ISSUE.search(body)
                    and EMPTY_AS_VERDICT.search(cond)
                    and not NONEMPTY_LITERAL.search(cond)):
                if LIVENESS_GUARD.search(cond):
                    ok(f"{name}: '{label}' closes on an empty output but guards producer liveness")
                else:
                    bad(f"{name}: '{label}' CLOSES issues when an output is empty, with no producer-liveness guard",
                        f"if: {cond}  -- a crashed producer emits empty, so this reads a dead checker as an all-clear")

# ANTI-VACUITY POSITIVE CONTROL. Every assertion above is conditional on the walk finding
# steps. A typo in FILES_ISSUE, a yaml schema change, or a renamed workflow would make this
# gate scan zero steps and report a clean pass forever — the exact
# "a check that cannot report is indistinguishable from one that passed" shape this PR is
# about. Pin a floor, not equality, so adding a filing step never edits this line.
FLOOR = 12
if scanned >= FLOOR:
    ok(f"anti-vacuity: scanned {scanned} issue-filing steps (floor {FLOOR})")
else:
    bad(f"anti-vacuity: only {scanned} issue-filing steps found, expected >= {FLOOR}",
        "the walk is not reaching the steps it claims to certify — fix the scanner, do not lower the floor")

print(f"=== Results: {PASS} passed, {FAIL} failed ===")
sys.exit(1 if FAIL else 0)
PY

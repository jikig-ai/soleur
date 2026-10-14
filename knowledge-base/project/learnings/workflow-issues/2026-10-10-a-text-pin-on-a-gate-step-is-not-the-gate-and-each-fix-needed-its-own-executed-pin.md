---
title: A text pin on a gate step is not the gate, and each fix needed its own executed pin
date: 2026-10-10
category: workflow-patterns
tags: [terraform, github-actions, ruleset, by-value-gate, guard-pin, executed-test, github-env, here-string, 9362, 9913]
symptoms: [a gate step could be made inert by "set +e" or a "true ||" prefix while every structural pin stayed green, "never written to disk" was false for a large here-string, a multi-line value could add lines to $GITHUB_ENV]
module: .github/workflows
component: tooling
problem_type: workflow_issue
resolution_type: workflow_improvement
root_cause: missing_validation
severity: high
---

# Learning: a text pin on a gate step is not the gate, and each fix needed its own executed pin

## Problem

PR #9913 (issue #9362) removed the `doppler run --name-transformer tf-var` injection from `apply-github-infra.yml` and added a pre-apply by-value gate (`scripts/verify-ruleset-required-checks.sh`) on the two rulesets' required checks. The 11-seat panel then found that the first draft's tests pinned the gate's TEXT:

- the gate step could be neutered (`set +e`, `true || terraform show ...`, `if: always()` on apply, an apply that no longer used the gated `tfplan`, `BASH_ENV` at job level) with every pin green;
- the one surviving Tier-A read (backend credentials) wrote an unvalidated value to `$GITHUB_ENV`, so a planted multi-line value could add `TF_VAR_*` or `BASH_ENV` lines: the property the PR claimed to close ("a value in prd_terraform cannot change what the apply writes");
- "never written to disk" was false: bash backs a large here-string with a temp file;
- the Guard 1 rows asserted only the exit code, and the suite took 67 s because the plan builder emitted pretty JSON into a quadratic whitespace test.

Round 2 then found the round-1 fixes themselves had the same shape: the new shape check could lose its `exit 1` and still pass a regex-count pin.

## Solution

- Execute the thing the pin describes. The real gate step (extracted from the parsed workflow) runs under `bash -e` against a stub `terraform` for clean, rebound-ci, rebound-cla and empty plans, and a harness row with errexit switched off proves the rows can fail. The same for the backend step in BOTH workflows against multi-line and spaced values (`GITHUB_ENV` file must stay empty).
- Allow-list a gate step's body (exactly `set -euo pipefail` plus the invocations), pin adjacency to apply, the apply being unconditional and applying `tfplan`, exactly one apply, one `terraform` token in the apply step, and scan env keys at all three levels.
- Assert the output contract with a canary planted in the plan's `.variables`; pipe with `printf '%s' "$x" | jq`.

## Key Insight

For a control whose property is "nothing can skip or alter X", a text pin certifies a spelling, not a behaviour. Pin it twice: once structurally (allow-list, index, count) and once by executing it on the failing input with a mutant of the same shape that must go red. And grade every fix commit for the same defect class as the change it fixes: the backend-step fix needed its own executed pin for the same reason the gate did.

## Session Errors

- **Working directory drifted to the main checkout mid-session (environment update).** Recovery: absolute worktree paths in every command. **Prevention:** start each Bash call with the absolute worktree path while a worktree is the target.
- **Ran a bash script through `python3` by mistake while extracting a checker.** Harmless syntax error, discarded. **Prevention:** extract embedded checkers with a dedicated script, never by re-running the host script.
- **First-draft tests pinned text only; gate neuterable with all pins green (found by the test-design and structural seats).** Recovery: executed-gate rows plus allow-list pins. **Prevention:** for any "cannot be skipped" control, add an executed row and a must-fail harness row in the first commit.
- **"Never written to disk" asserted without testing bash here-string behaviour (security, quality, user-impact seats).** Recovery: pipes, reworded comments. **Prevention:** run the falsifying command (`readlink /proc/self/fd/0` on a >64 KB here-string) before writing a secrecy claim.
- **Round-1 fixes introduced unpinned behaviours (backend check without an executed pin; drift copy unpinned).** Recovery: round 2. **Prevention:** grade the fix commit as its own change; pair every added guard with an executed row before the review round.

## Tags

category: workflow-patterns
module: .github/workflows

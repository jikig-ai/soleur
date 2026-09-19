# Decision challenges — feat-one-shot-8361-workflow-size-limit

Taste / User-Challenge findings from `plan-review` (headless one-shot; not auto-applied per ADR-084).
The operator's stated direction — a runbook with one-line pointers, a minimal PR — is the default.
`ship` Phase 6 renders these into the PR body and files the `action-required` issue.

## UC-1 (User-Challenge, dhh-rails-reviewer) — delete the prose instead of relocating it

- **Finding:** "The runbook is the wrong fix; delete the prose. Git history is the runbook." Would drop the runbook file, the KB-index regeneration, the human-steps-lint reword step, AC6 and AC7.
- **Operator direction:** issue #8361 §Fix 1 asks to "move long comment essays … into a runbook under knowledge-base/engineering/operations/runbooks/ and leave one-line pointers".
- **Plan keeps:** the runbook (P4 is issue-sourced). code-simplicity-reviewer concurred: "keep P4, do not expand it".
- **Reversible later:** yes — deleting the runbook is a one-file PR.

## T-1 (Taste, cto) — shrink to ≤ 462,000 and add a WARN tier

- **Finding:** at the measured growth rate (~3 KB on each of the last three commits) 480,000 buys only a few PRs; take every reserve block (→ ~462 K) and add `WORKFLOW_FILE_WARN_BYTES = 470_000` printing a stderr warning (exit 0) mirroring `scripts/lint-agents-rule-budget.py`'s warn/reject tiers.
- **Plan keeps:** the 480,000 target (blocks 1–10 measured to 476,525 plus a "next-largest block" rule), one hard gate. Simplification panel (DHH + simplicity) explicitly cut the reserve list; the measured 12-commit average is ~1.5 KB/commit, so ~22 KB of headroom under the gate is 7–15 commits.
- **If accepted:** add the WARN constant + one fixture row to Guard 1; lower the step-2 stop rule.

## T-2 (Taste, cto) — append rationale to the existing per-target runbooks instead of one new file

- **Finding:** blocks 2, 3, 5, 9 already have per-target runbooks (`vector-redeliver.md`, `git-data-birth.md`, `registry-luks-recut-6929.md`, `ci-ssh-token-replace.md`); a third home for the same job's rationale rots fastest. Also update `apply-web-platform-infra-red-run.md`'s "the decision content lives in that job's own header" line.
- **Plan keeps:** one new runbook (the issue says "a runbook"; one `§<job_id>` anchor scheme; four fewer files touched in a P1).
- **If accepted:** four extra file edits and the pointer path varies per block.

## T-3 (Taste, cto) — a "how to shrink this file next time" section

- **Finding:** the anchor analysis lives only in this plan; add a `## How to shrink this file next time` section to the runbook (Keep rule, untouchable blocks, AC3 parity command, AC5 suite-list command) and cite it from the workflow header.
- **Plan keeps:** scope minimal; the plan file and this branch's spec carry the method. Cheap to add at /work if the operator wants it (≈ 15 lines in the runbook preamble).

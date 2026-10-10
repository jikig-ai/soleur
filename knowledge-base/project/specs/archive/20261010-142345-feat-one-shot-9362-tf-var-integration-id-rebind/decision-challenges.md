# Decision challenges: #9362 rebind fix (plan-review, headless)

Taste items surfaced by the review panel; none changes a direction the owner stated.

1. **Post-apply by-value check cut, pre-apply kept.** Issue candidate 1 names the post-apply verify. The panel (DHH, code-simplicity, CTO) split on which single mode to keep; the plan keeps the pre-apply gate because it prevents the write and is the safety net for deleting the wrapper, and relies on the daily `cron-ruleset-bypass-audit` for after-the-fact detection. Revisit if the owner wants in-run detection of rebinds made outside Terraform.
2. **New suite cut.** The Guard 1 and Guard 2 checks join the existing `test-apply-github-infra-mint-shape.sh` instead of a new registered suite, to avoid test-all/tsv/affected-paths churn (a rebase hazard with #9893).
3. **Milestone and priority mismatch on #9362** (`Post-MVP / Later` vs `p1-high`): stated in the PR body, not changed.

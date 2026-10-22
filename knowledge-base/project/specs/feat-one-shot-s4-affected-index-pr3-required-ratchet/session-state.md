# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking (plan-review and deepen-plan corrected four plan statements in place).

### Decisions
- Ratchet compares live gap pairs to a committed shrink-only baseline (the size is whatever `wc -l scripts/ci-pr-affected-audit.baseline.tsv` reports: 1,884 pairs measured on `4da1673510` plus the pairs this PR's own test text creates); own `affected-index-ratchet` job in ci.yml.
- PR3a ships advisory (job-level continue-on-error, pull_request + merge_group only); PR3b (required context) held for the budget owner, tracked in #10859; soak tracker #10865.
- No edit to scripts/ci-pr-selection.sh, test-all.sh, test-affected-paths.sh, required-checks.txt, ruleset.
- PR4 #10860, PR5 #10861, no-run investigation #10862 filed as follow-ons.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; cto x3 plus review/research agents.

cto_spawns=3

## Review fix round (2026-10-23, PR #10851)

The review panel returned no P1. The CTO ruled the forks of that round on 2026-10-23 (`decision-challenges.md`, rows 34 to 41).

Fixed in the documentation (fix round B): the ADR-276 amendment (MD012 blank line, baseline count wording, item 4 quote and numbering, item 5 residuals and the ADR-290 divergence, item 6 cost and canary honesty, item 8 squash-shaped rollback, new item 9 with the PR3b entry conditions); the runbook (baseline wording, reason-token table with `floor-bad-row`, `floor-unreadable`, `accept-unreadable`, `timeout` and `no-marker`, oracle-notice list, remedy text without "a reviewer blocks it", the squash-shaped rollback and the honest simulation receipt, observation-window rules and the provisional ceilings, the PR5 adoption-closure note, the draft-cost figures); decision-challenges rows 34 to 41 and the row 33 amendment; `.gitattributes` for the baseline; drafted (not posted) replacement bodies for #10865, #10859 and #10861.

Pending, lead-owned: the throwaway canary (tasks.md 3.5; the ci.yml comment, ADR item 6, the runbook and the probe header say UNMEASURED until it runs), the squash-shaped revert re-simulation, the follow-through enrollment on #10865 (E.2) and the `s4-drain` label (E.3). Code changes of the round (row grammar, notice list, merge-base helper load, probe exit codes and read budget) belong to the code fix agent.

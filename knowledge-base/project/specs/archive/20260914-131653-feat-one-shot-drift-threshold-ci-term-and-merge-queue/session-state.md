# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-14-chore-drift-threshold-ci-term-and-pr-fanout-ledger-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- First plan Write denied by the IaC write guard (a passing "the GitHub UI" mention matched the vendor-dashboard regex); reworded, no content lost.
- Attribution sweep: `codeql-1537-revisit-watch.yml` resolves its tracking issue by the `merge-queue-revisit` label, not by `#5840`; corrected at all four sites.
- `plugin:github` and `playwright` MCP servers failed to connect; not needed (all GitHub reads via `gh`).

### Decisions
- Item 1 -> option (a), corrected: unify the three inconsistent critical-path formulas on `max(ci, release) + resolve-target + migrate + verify-migrations + deploy`, put the CI term into B9, lower `resolve-target` 60->15 (measured 12-14 s over nine runs), raise `DRIFT_SUSTAINED_THRESHOLD_MIN` 207->225. `CI_BUDGET_MIN` partition subtracts resolve-target so the creep soft-ceiling stays ~52 m.
- Item 2 -> option (b); merge queue (a) is NOT adoptable: enabled 2026-06-30 (PR #5800), deadlocked main in 5 min because CodeQL default setup never posts on `merge_group` (codeql-action#1537 still open), workaround prototyped and removed (#5811/#5812), ADR-032 records "queue stays off". Reopeners named. `merge_group:` triggers already wired; no ruleset change.
- (b) concretely: fold three 0.2-min ci.yml jobs into `lint-bot-statuses` (encryption-posture kept standalone on the #6901/#6907 soak), PR-only `cancel-in-progress` on five stateless per-PR workflows (three mutex/state-lock holders excluded), `scripts/pr-fanout-ledger.txt` + `plugins/soleur/test/pr-fanout-ledger.test.sh` filing-time lever (ADR-216 second instance).
- Rejected: path-filtering `constraint-gates.yml` (parity-locked to scaffold template); deleting disabled `claude-code-review.yml` (Art. 30 PA-33 member snapshot).
- No new ADR: ADR-032 gets `## Amendment — 2026-09-14`, ADR-216 an `### Addendum`, ADR-217 D4 a blockquote addendum. No issues filed; no `gh api` mutations run.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review (inline 5-agent panel), soleur:deepen-plan
- Plan-phase agents: repo-research-analyst, learnings-researcher (x2), functional-discovery, cto (x2), spec-flow-analyzer, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, scoped advisor consult
- Deepen-phase agents: architecture-strategist, test-design-reviewer, security-sentinel, observability-coverage-reviewer, pattern-recognition-specialist, git-history-analyzer, verify-the-negative sweep, best-practices-researcher
- Local tools: lint-guard-contract.py, lint-infra-no-human-steps.py, prod-version-drift-check.test.sh (153/153 baseline), workflow-run-deploy-invariants.test.sh (67/67), constraint-scaffold parity.test.sh, c4-count-parity.test.sh, gh api (read-only)

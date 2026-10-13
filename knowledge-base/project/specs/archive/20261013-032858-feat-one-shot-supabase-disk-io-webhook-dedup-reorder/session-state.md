# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-fix-webhook-dedup-drop-before-insert-plan.md
- Status: complete

### Errors
None. (One non-fatal retry: initial Write targeted the main checkout, re-issued to worktree path. CWD verification passed first attempt.)

### Decisions
- Reorder, not rewrite: move the processed_github_events dedup INSERT into a claimDedupRow() closure invoked immediately before each of the two dispatch sites (push reconcile + non-push inngest.send), after every drop-filter. Drop paths return existing 200/4xx with no row written.
- Test-first WITH inversions: three test files import the route (github-route.test.ts, webhook-push-dispatch.test.ts, github-webhook-founder-attribution.test.ts). Six existing mockDeleteEq assertions on founder 404/db-error paths must INVERT (no row written -> nothing to release): github-route.test.ts:361,407 and github-webhook-founder-attribution.test.ts:189,207,263,357. Highest-risk finding — not purely additive.
- ADR-036 amendment + header-comment rewrite are in-scope deliverables (the reorder invalidates ADR-036's recorded Decision text). Divergence from Stripe parity rests on volume + actioned-ratio (workflow_run non-failure no-op = 63% WAL case).
- Do NOT reorder the actionClass guard before founder resolution (AC4b check_suite regression test asserts resolver reached first).
- Scope discipline: migration 094 retention + GitHub App manifest untouched; threshold single-user incident -> requires_cpo_signoff: true.

### Components Invoked
- soleur:plan, soleur:deepen-plan, data-integrity-guardian (no gaps), architecture-strategist (no blocking; ADR-036 amendment folded in)

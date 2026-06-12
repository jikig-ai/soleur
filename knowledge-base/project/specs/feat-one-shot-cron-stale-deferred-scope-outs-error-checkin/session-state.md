# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-12-fix-stale-deferred-scope-outs-cron-transient-fault-resilience-plan.md
- Status: complete

### Errors
None. CWD verified == worktree; branch is a feature branch; all deepen-plan halt gates (User-Brand Impact, Observability, PAT-shaped, UI-wireframe) passed.

### Decisions
- Confirmed root cause: Sentry `error` check-in fires only when `sweepFailed=true`, set solely by the catch wrapping `step.run("sweep…")`. Per-issue write 403s are caught in-loop and do NOT set `sweepFailed` (constraint #1 confirmed). Only throwing paths: `createProbeOctokit()` (401-only retry; throws on 429/5xx/post-budget-401) and the bare `GET /search/issues` (zero retry).
- Second confirmed bug ("page before retry"): the `error` heartbeat is POSTed on Inngest attempt 0 BEFORE the rethrow that triggers `retries: 1`, so a first-attempt transient pages the operator even though the retry recovers it.
- Fix cut from two to one: gate the heartbeat on the final Inngest attempt — path-agnostic, necessary, and sufficient for the acceptance bar. The wider `createProbeOctokit` retry-class change was moved to "Alternative Considered" (mutated a ~10-caller helper; novel rate-limit heuristic with no repo precedent).
- Load-bearing Phase 0: verify Inngest delivers/increments `ctx.attempt`/`maxAttempts` on a `step.run` throw before coding (cited `cron-bug-fixer` precedent was false — no in-repo handler reads `attempt`).
- Scope minimal vs parallel #5199 worktree: only edit to `_cron-shared.ts` is two optional `HandlerArgs` fields (does not touch TIER2/allowlist lists). No `probe-octokit.ts` edit. No Terraform change.

### Components Invoked
soleur:plan, soleur:deepen-plan; Explore×2, observability-coverage-reviewer, code-simplicity-reviewer, test-design-reviewer

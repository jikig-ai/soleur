# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-19-feat-inngest-soak-6178-followthrough-enrollment-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Two brief premises were stale, reconciled in the plan: PR #8321 had already MERGED (2026-09-19T03:03:39Z) — `origin/main` merged into the branch (`61d82c336`) so its new lints apply locally; the "archived" 07-07 plan path does not exist (the plan is still live at `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`).
- The 09-15 `op=verify` pass was `anchor_source=floor(override)` / `VERIFIED (QUALIFIED)`, not an fsm-anchored proof — caught by the deepen attribution pass after the first draft asserted otherwise; corrected throughout.
- `gh issue create --body-file` for the deferred sweeper-heartbeat issue was blocked twice by `guardrails.sh` (heredoc-in-same-call, then missing `meta/machinery` label); resolved on the third attempt as #8349.
- Forwarded from the parent session (pre-plan): the soak-window `op=verify` (run 35415585389) reported DOUBLE-FIRE on 2 groups that routine_runs attribution showed to be the 09-17 catch-up replay — the startedAt-bucket proxy conflates catch-up with double-fire (design input, recorded on #6178 comment 5738682595).

### Decisions
- Notify-only exit vocabulary (2/3/5, never 0/1) with a two-layer structural guarantee: per-call-site `jq` rc capture (`jq_failed`) plus a single EXIT-only `on_exit` trap rewriting any unmapped rc to 3.
- Population slicing by round-robin over a density-sorted 52-id file (5 slices ≤11 ids; measured live: all 200, heaviest slice 369 runs at day 3.6), plus a one-GET registry-drift gate (`REGISTRY_COUNT=70`, population ⊆ registry); explained set pinned as exact `(functionID, bucket, count)` triples; below-pin renders UNEXPLAINED; window-head coverage as the retention canary; `RUN_FLOOR=800`.
- Cut after both panels fired: ADR-`status:` self-quieting arm, REQUIRED-presence triples, `foreign_function_id` check, `ACTIVE_FLOOR`; kept against DHH alone: `POPULATION_SIZE=52`, `RUN_FLOOR`.
- Operator-stated `earliest=2026-09-22T13:23:00Z` kept; the advisor+session recommendation to enroll earlier is persisted as User-Challenge DC1 (+ T1–T3) in `decision-challenges.md` for ship Phase 6.
- ACTION REQUIRED output carries the P2-a scope caveat, the QUALIFIED anchor provenance, the P2-c residual, the post-day-7 page-budget horizon, and close-#6178-LAST ordering; the sweeper's missing `sentry-heartbeat` deferred as #8349.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review (inline), soleur:deepen-plan
- Plan-phase agents: repo-research-analyst, learnings-researcher (×2), functional-discovery, cto (blocking + devex), spec-flow-analyzer, advisor consult (fable tier), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer
- Deepen-phase agents: verify-the-negative (sonnet), git-history-analyzer, security-sentinel, test-design-reviewer, observability-coverage-reviewer, architecture-strategist, pattern-recognition-specialist

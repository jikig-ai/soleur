# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-fix-cron-digest-dedup-sweep-7-crons-plan.md
- Status: complete

### Errors
None. CWD verified first tool call. All deepen-plan hard gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shape, 4.9 UI-wireframe); kb-citation clean.

### Decisions
- Campaign-calendar title shape → option B: generalize `isRealScheduledDigest`/`digestIssueExistsForDate` to take per-cron `titlePrefix` + optional `titleSuffix`. Prod evidence: all campaign-calendar dups (#5366/5368/5712/5713) carry ` (heartbeat)` suffix → exact-anchor would silently never match. Suffix single-sourced; community-monitor preserved byte-identically (its constant + empty suffix).
- Test strategy: ONE parametrized `cron-cohort-dedup.test.ts` (7-row `it.each` through the REAL handlers via a fake octokit store, reusing #5751's `makeStep`/partial-`importOriginal`-mock/frozen-clock harness; all 7 share the `({step,logger,attempt,maxAttempts})` signature). Per-cron files stay anchor-only; cohort test is the SOLE behavioral gate.
- Spec-flow P0: wrong/missing suffix fails OPEN (no RED monitor) → pinned a row-derived seed/key + HANDLER mutation assertion (AC1c) so dropping `titleSuffix` reds the row; partial-mock/LIST-route/GREEN-skip-path guards (AC1b) prevent vacuous passes.
- Architecture P1: documented campaign-calendar partial-dedup asymmetry (its `(heartbeat)` digest minted only on NEW==0 days → overdue days correctly no-op, fail-OPEN); AC1d added; 2 extra resilient test consumers named in blast-radius.
- Simplicity trim: dropped 6 NEW in-prompt LIST rules (`concurrency:fn:limit:1` already precludes the race; contradicts #5751's "dedup out of the prompt"); kept ONLY roadmap-review's real `--search`→LIST fix.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Explore ×2 (handler-wiring map; dedup-helper/test-infra/title-shape map)
- Review ×3: architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer

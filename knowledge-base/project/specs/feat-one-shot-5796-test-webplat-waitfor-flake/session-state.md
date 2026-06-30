# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-fix-test-webplat-vi-waitfor-flake-plan.md
- Status: recovered from partial-artifact (subagent hit session limit mid-Session-Summary; plan body + tasks.md were on disk, scope clean — only knowledge-base/project/{plans,specs}/ touched)

### Errors
- Planning subagent (adc08072d2e44ee65) terminated on a session usage limit during Session Summary emission. Plan + deepen artifacts had already been written; recovered per one-shot fallback step 1.

### Decisions
- Diagnosed as TWO distinct mechanisms, not one: (1) vitest `vi.waitFor` 1s-default gap (47 sites / 9 files; the proven CI-red culprit, never raised by #5113 which only touched RTL `asyncUtilTimeout`); (2) render-under-contention timeouts in no-waitFor files under unsharded full-suite load.
- Phase 1 (core, high-confidence): raise the `vi.waitFor` floor systematically — Approach A (global wrapper in both setup-dom.ts + setup-node.ts) preferred, Approach D (per-site `{ timeout: 10_000 }` sweep + guard) as fallback; decided by a Phase-0 spike.
- Phase 2 (evidence-gated, descopable): cap `poolOptions.forks.maxForks` on the component project only if measurement confirms render-contention persists after Phase 1.
- Explicitly does NOT re-raise `testTimeout` (16s, #4128) or `asyncUtilTimeout` (10s, #5113) — avoids the timeout treadmill.
- Fix must land in BOTH node and component vitest projects (vi.waitFor is used in both).

### Components Invoked
- soleur:plan, soleur:deepen-plan (via general-purpose planning subagent)

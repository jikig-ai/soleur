# 2026-05-15 — kb-chat-sidebar + chat-page flake recurrence (#3818)

## Problem

Issue #3818 reported 4 vitest files failing during `/ship` Phase 4 for an
unrelated content-only PR (PR #3798, content-only, no `apps/web-platform/`
diff):

- `apps/web-platform/test/chat-page.test.tsx` — "does NOT send msg when
  sessionConfirmed is false"
- `apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` — sidebar dialog
  aria-label + focus-to-textarea
- `apps/web-platform/test/kb-chat-sidebar-close-abort.test.tsx` — unmount
  teardown + reopen-starts-fresh-session
- `apps/web-platform/test/kb-chat-sidebar.test.tsx` — close-button aria-label
  + filename-in-monospace header

Counts on the failing run: `Test Files 4 failed | 394 passed | 7 skipped (405)`.

## Root Cause

**Non-reproducible / flake-class, not deterministic-broken.** Repro probe on
`feat-one-shot-3818` (which carries only the minimal worktree init commit
vs `main`):

- 3/3 sequential full-suite runs (`npm run test:ci`): 400/407 files passing,
  4367/4406 tests passing — **zero failures from the named 4 files**.
- Pool-pressure probe (`--pool=threads --poolOptions.threads.maxThreads=2`
  on the 4 named files): 51/51 pass in 3.43s.
- `WEBPLAT_TEST_USE_FORKS=1` (post-fix): 51/51 pass in 3.52s.

The 4 named tests are the same surface PR #2819 hardened with `isolate: true`
+ `afterAll` scrub + drift-guard (closed issues #2594, #2505). The most
likely vector is worker-pool resource-contention under `/ship` Phase 4
runner conditions (CPU-pinned + parallel sibling test suites), not a
component-side regression.

## Solution

**Prophylactic hardening** — no deterministic bug to fix, so ship monitoring
+ escape hatch + drift-guard extension rather than guess:

1. **`apps/web-platform/vitest.config.ts`** — added `WEBPLAT_TEST_USE_FORKS=1`
   escape hatch. Flips the `component` project from `pool: 'threads'`
   (default, fast) to `pool: 'forks'` (per-file process isolation, ~2-3x
   slower but eliminates worker-graph aliasing entirely). Default off.
2. **`apps/web-platform/test/setup-dom-leak-guard.test.ts`** — added a
   proximity-pinning `it()` asserting `afterAll(...)` followed within ~200
   chars by `vi.restoreAllMocks()`. Catches a silent rewrite of the hook
   to `afterEach(...)` — the exact regression learning
   `2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` Error 1
   captured.

### Plan Deliverables Trimmed

The plan also called for a `WEBPLAT_TEST_FAILURES_LOG` capture in
`scripts/test-all.sh` line 145. **Skipped intentionally** — the existing
`TEST_TIMING_LOG` path in `run_suite()` (test-all.sh:109) already records
`<label>\t<elapsed_ms>\tFAIL` for failing suites. Duplicating into a
separate log adds an unread file with no automation consuming it. Reopen
this scope only if a recurrence captures inadequate diagnostic data.

## Key Insight

`isolate: true` closes vitest module-graph aliasing on `pool: 'threads'`,
but **does NOT close worker-pool resource-contention races**. The
`afterAll` scrub + drift-guard pattern from PR #2819 covers the
deterministic class; the remaining flake surface is environmental
(runner CPU, memory pressure, parallel sibling-suite scheduling).

When a flake-class issue arrives with no operator-side repro, the right
move is **escape hatch + observability + drift-guard**, NOT speculative
fix. Component file edits land only if the next recurrence captures a
deterministic vector.

## Prevention

- **Drift-guard extended** (this PR): a future PR that silently moves the
  scrub out of `afterAll` now fails at unit-test time.
- **Escape hatch documented** (this PR): a future investigator hitting a
  CI-only recurrence can flip `WEBPLAT_TEST_USE_FORKS=1` in their workflow
  without a code change. Document the diagnostic value in the next
  recurrence's issue (e.g., "tried `WEBPLAT_TEST_USE_FORKS=1`: failure
  persists → not a worker-aliasing vector; failure clears → confirmed
  worker-aliasing, file follow-up to bake into config").
- **Recurrence-monitoring rule**: if the same 4 tests fail again within 7
  days of this fix, reopen #3818 and escalate to a deeper investigation
  (chasing `pool: 'threads'` worker-reuse semantics in vitest 3.2.4).

## Related

- PR #2819 (closed #2594, #2505): original `isolate: true` + drift-guard
  fix for the kb-chat-sidebar family.
- `knowledge-base/project/learnings/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`:
  the `afterAll`-vs-`afterEach` regression class this drift-guard pins.
- Issue #3818 (this PR's `Ref` target).

# Tasks — fix `test-webplat` `vi.waitFor` 1s-default flake (#5796)

Plan: `knowledge-base/project/plans/2026-06-30-fix-test-webplat-vi-waitfor-flake-plan.md`
Lane: cross-domain (no spec.md — fail-closed default)

## Phase 0 — Approach spike

- [ ] 0.1 Verify `vi.waitFor` reassignment is permitted + visible to test files in vitest `4.1.0` (writable, same module singleton within a worker).
- [ ] 0.2 Confirm a wrapper preserves the `number | WaitForOptions` overload and does not break `vi.useFakeTimers()` + `vi.waitFor` (smoke-run one fake-timers file).
- [ ] 0.3 Decide Approach A (global wrapper, recurrence-proof) vs Approach D (per-site sweep, established convention). Record decision + evidence for the PR body.

## Phase 1 — Raise the `vi.waitFor` floor (core)

### Approach A (if spike + review accept)
- [ ] 1.A.1 Add the top-level `vi.waitFor` wrapper (default `{ timeout: 10_000 }`, non-destructive over explicit per-site values) to `apps/web-platform/test/setup-dom.ts`.
- [ ] 1.A.2 Add the same wrapper to `apps/web-platform/test/setup-node.ts` (node project: `cc-dispatcher.test.ts`, `is-template-authorized.test.ts`).
- [ ] 1.A.3 Extend `setup-dom-leak-guard.test.ts` with a source-token row asserting the wrapper in `setup-dom.ts`, and add an equivalent guard for `setup-node.ts`.

### Approach D (fallback / convention)
- [ ] 1.D.1 Sweep `{ timeout: 10_000 }` onto the 42 bare `vi.waitFor` sites across the 8 files (+2 bare sites in `live-repo-badge.test.tsx`); do not alter the 5 already-explicit sites.
- [ ] 1.D.2 Create `apps/web-platform/test/vi-waitfor-floor-guard.test.ts` — source-grep guard rejecting any bare `vi.waitFor(` without a timeout (tolerate multi-line forms).

### Both
- [ ] 1.x Optional micro-hardening: for any bare absence-wait touched, add a positive settle anchor first (`live-repo-badge.test.tsx:188` pattern, #5234). Inline only.

## Phase 2 — Reduce component-project worker contention (evidence-gated, descopable)

- [ ] 2.1 Measure: `TEST_TIMING_LOG=… TEST_GROUP=webplat bash scripts/test-all.sh` with Phase 1 applied; confirm `dashboard-layout-sidebar-settings` + `chat-surface-sidebar-wrap` still exceed 16s under load.
- [ ] 2.2 If Phase 1 alone stabilizes (no >16s render timeouts ×3 runs) → **descope Phase 2**, record in PR body.
- [ ] 2.3 Else: add `poolOptions.forks.maxForks` cap to the component project in `vitest.config.ts` (verify the key against vitest `4.1.0`); re-measure; record wall-clock delta.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (AC3).
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx test/cc-dispatcher.test.ts test/org-switcher-container.test.tsx` passes (AC4).
- [ ] 3.3 `TEST_GROUP=webplat bash scripts/test-all.sh` green ×3 consecutive (AC5).
- [ ] 3.4 `git diff` confirms `asyncUtilTimeout: 10_000` and `testTimeout: 16_000` unchanged (AC6).
- [ ] 3.5 PR body: `Ref #5796` + Phase-0 A/D decision + Phase-2 apply/descope decision (AC7/AC8).
- [ ] 3.6 Post-merge: close #5796 after the next clean `test-webplat` CI run (no `vi.waitFor`/`waitFor` timeout) confirms the event-grep re-eval criterion.

---
date: 2026-05-06
branch: feat-one-shot-theme-selector-reload-persistence
plan: knowledge-base/project/plans/2026-05-06-fix-theme-selector-reload-persistence-and-active-state-plan.md
status: derived
---

# Tasks — Theme Selector Reload Persistence + Active-State Reliability

Derived from the deepened plan. Phase ordering matches the plan's
Implementation Phases section.

## 1. Phase 1 — Lightweight Confirmation

- [x] 1.1 Write the SSR-hydration repro test (currently RED).
  - [x] 1.1.1 Create `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx`.
  - [x] 1.1.2 Confirm RED on the current branch tip — 4 of 7 assertions failed (data-active attribute did not exist; collapsed cycle data-active also missing).
  - [x] 1.1.3 RED state recorded in commit message; full diagnostic transcript captured in vitest output above.
- [/] 1.2 F2 verification (deferred). Mounted-gate fix is independent of NoFoucScript execution path (lazy initializer falls back to localStorage if dataset.theme is unset). Production AC8 reload check covers this empirically.
- [x] 1.3 F3 ruled out at deepen-pass (single `<ThemeProvider>` mount in `app/layout.tsx`).

## 2. Phase 2 — Implement the Fix (Phase 2a: mounted gate)

- [x] 2.1 Edit `apps/web-platform/components/theme/theme-toggle.tsx`.
  - [x] 2.1.1 Added `mounted` state + first-mount `useEffect`.
  - [x] 2.1.2 Replaced `const active = theme === seg.value;` with `const active = mounted && theme === seg.value;`.
  - [x] 2.1.3 Added `data-active="true|false"` to each expanded segment AND the collapsed cycle button.
  - [x] 2.1.4 Collapsed branch: `visibleIndex = mounted ? safeRealIndex : PRE_MOUNT_INDEX` so SSR / first paint always shows the System glyph; post-mount flips to the real `theme`.
- [x] 2.2 No changes to `theme-provider.tsx`; existing lazy initializer is correct.

## 3. Phase 3 — Tests

- [x] 3.1 SSR-hydration test now PASSES (7/7).
- [x] 3.2 Extended `apps/web-platform/test/components/theme-toggle.test.tsx`:
  - [x] 3.2.1 Added "data-active mirrors aria-pressed: exactly one segment is data-active='true' post-mount" test.
  - [x] 3.2.2 `aria-pressed` retained as screen-reader contract; `data-active` added as visual-state probe per plan.
- [/] 3.3 NoFoucScript script-execution test deferred. Reason: deepen-pass ruled out F2; mounted-gate fix is independent of NoFoucScript runtime behavior. Adding JSDOM script execution would protect a vector that is not in the failure path.
- [/] 3.4 Playwright e2e deferred. Reason: dashboard route requires Supabase-mock-backed auth setup (existing e2e tests via `e2e/global-setup.ts` go through OTP/OAuth flows); wiring a reload-persistence e2e in this PR is disproportionate to the fix size. AC8 (post-merge prod reload) is the load-bearing check. Filed as follow-up issue.
- [x] 3.5 Full app test suite: `vitest run` → 3608 passed, 24 skipped, 0 failed.
- [x] 3.6 `tsc --noEmit` clean (zero errors).

## 4. Phase 4 — Manual QA

- [ ] 4.1 Build production bundle locally: `cd apps/web-platform && bun run build && bun run start`.
- [ ] 4.2 For each of `dark`, `light`, `system` and for each of `expanded`/`collapsed` sidebar (six combinations total):
  - [ ] 4.2.1 Set `localStorage.setItem("soleur:theme", <value>)`, reload.
  - [ ] 4.2.2 Verify exactly one segment / the cycle button reflects the stored value.
  - [ ] 4.2.3 Capture a screenshot and attach to the PR description.
- [ ] 4.3 (Optional) Repeat with NoFoucScript nonce stripped to confirm defense-in-depth.

## 4. Phase 4 — Manual QA

- 4.1 Build production bundle locally: `cd apps/web-platform && bun run build && bun run start`.
- 4.2 For each of `dark`, `light`, `system` and for each of `expanded`/`collapsed` sidebar (six combinations total):
  - 4.2.1 Set `localStorage.setItem("soleur:theme", <value>)`, reload.
  - 4.2.2 Verify exactly one segment / the cycle button reflects the stored value.
  - 4.2.3 Capture a screenshot and attach to the PR description.
- 4.3 Repeat one combination with the browser's "Disable JavaScript" off but with the inline script's nonce stripped (DevTools → Network → block-pattern on `text/html` won't help — instead temporarily edit middleware to omit the nonce header in a local-only branch). Confirm the `data-active` invariant still holds (defense-in-depth: the mounted gate still works even when NoFoucScript fails because both code paths agree pre-mount).

## 5. Phase 5 — Compound + Ship

- 5.1 Run `skill: soleur:compound` to capture learnings (likely categories: `runtime-errors`, `bug-fixes`, `best-practices`).
  - Specifically capture: "React 18 production hydration does not patch className/attribute mismatches; mounted-gate is the canonical SSR-safe pattern; #3318's lazy-init-now-canonical change inadvertently removed the only path that previously repainted the className."
- 5.2 Open PR via `skill: soleur:ship`. Use semver label `patch` (UI bug fix; no public API change).
- 5.3 PR body MUST include `Closes <issue-number>` if a tracking issue exists for this bug; if not, file one before opening the PR (per AGENTS.md `wg-when-tests-fail-and-are-confirmed-pre`-class workflow gates).

## 6. Acceptance Criteria Mapping

| AC | Tasks |
|---|---|
| AC1 (SSR repro test) | 1.1, 3.1 |
| AC2 (single-active invariant) | 1.1.1 (assertion), 3.2 |
| AC3 (NoFoucScript JSDOM exec) | 3.3 |
| AC4 (no nested provider grep) | 1.3 (regression-prevention test) |
| AC5 (Playwright reload) | 3.4 |
| AC6 (existing suites green) | 3.5 |
| AC7 (tsc clean) | 3.6 |
| AC8 (manual prod reload) | 4.2 |

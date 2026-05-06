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

- 1.1 Write the SSR-hydration repro test (currently RED).
  - 1.1.1 Create `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` from the plan's Test Implementation Sketch.
  - 1.1.2 Run `bun test apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` and confirm it fails on the current branch tip — at least for `stored=dark` and `stored=light`.
  - 1.1.3 Append a `### Phase 1 Results` section to the plan with the failing-output excerpt.
- 1.2 Verify F2 ruled out.
  - 1.2.1 Inspect dev-preview DOM: confirm `<script nonce="...">` is rendered for `<NoFoucScript>` and the body executes.
  - 1.2.2 Set `localStorage.setItem("soleur:theme", "dark")` in DevTools, reload, confirm `document.documentElement.dataset.theme === "dark"` BEFORE clicking anything.
- 1.3 Confirm F3 ruled out (already verified at deepen-pass) — record `git grep` output in Phase 1 Results.

## 2. Phase 2 — Implement the Fix (Phase 2a: mounted gate)

- 2.1 Edit `apps/web-platform/components/theme/theme-toggle.tsx`.
  - 2.1.1 Add `mounted` state + first-mount `useEffect` (per plan code sketch).
  - 2.1.2 Replace `const active = theme === seg.value;` with `const active = activeFor(seg.value);` (gated on mounted).
  - 2.1.3 Add `data-active={active ? "true" : "false"}` to each segment button — both expanded segments AND the collapsed cycle button.
  - 2.1.4 Apply the same mounted-gate to the collapsed branch's `current` / `next` derivation: pre-mount, render the System icon as the visible glyph; post-mount, switch to the real values.
- 2.2 (Optional cleanup) `apps/web-platform/components/theme/theme-provider.tsx`: confirm the lazy initializer + first-mount useEffect path is internally consistent post-fix. No behavior change expected.

## 3. Phase 3 — Tests

- 3.1 SSR-hydration test (created in 1.1) now PASSES — confirm by re-running.
- 3.2 Extend `apps/web-platform/test/components/theme-toggle.test.tsx`:
  - 3.2.1 Add a "pre-mount: all segments are data-active=false" test (uses `act` to suppress the post-mount flip).
  - 3.2.2 Migrate any `aria-pressed`-based assertions to `data-active`-based assertions where the test's intent is "active visual state" (do NOT remove `aria-pressed` — it's the screen-reader contract).
- 3.3 Extend `apps/web-platform/test/components/theme-no-fouc-script.test.tsx`:
  - 3.3.1 Add a test that executes the script content in a JSDOM scaffold and asserts `document.documentElement.dataset.theme` matches the seeded localStorage value.
- 3.4 Add `apps/web-platform/playwright/theme-reload.e2e.ts` (per plan sketch).
  - 3.4.1 Run locally with `bun run --filter=web-platform test:e2e -- theme-reload` (or the project's equivalent).
  - 3.4.2 Generate baseline screenshots with `--update-snapshots` on first run.
- 3.5 Run the full app test suite: `bun test apps/web-platform/test/`.
- 3.6 Run `bun run --filter=web-platform tsc:check` (or equivalent `tsc --noEmit`).

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

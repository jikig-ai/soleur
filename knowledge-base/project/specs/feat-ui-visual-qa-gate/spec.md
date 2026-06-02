---
feature: ui-visual-qa-gate
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 4834
date: 2026-06-02
branch: feat-ui-visual-qa-gate
pr: 4833
brainstorm: knowledge-base/project/brainstorms/2026-06-02-ui-visual-qa-gate-brainstorm.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md
  - knowledge-base/engineering/architecture/decisions/ADR-048-headless-visual-regression-gate.md
---

# Spec — Headless Visual-Regression Gate for UI-Structural Diffs

## Problem Statement

PR #4810 (single nav rail) passed every automated gate — 8166 vitest green, tsc clean, 6-agent
review, GDPR gate — and shipped two CSS-layout bugs to prod because **no pre-merge gate renders
real CSS**. jsdom (vitest) sees no `md:w-14` / `hidden md:block` / `flex-wrap` / `display:none`;
the real-browser walkthrough (AC10) was deferred to post-merge; and a direct `/soleur:work`
invocation skips `/soleur:qa` (only one-shot runs qa pre-merge). The non-technical Soleur operator
(n=1) landed on a broken, unnavigable dashboard.

## Goals

1. A **committed, headless, CI-portable visual-regression spec** that fails RED on the two live
   #4810 bugs and passes GREEN after they are fixed — and stays as a regression guard.
2. Fix the two bugs: drilled-state chrome leak (Bug 1) and missing collapsed band form (Bug 2).
3. Close the process gaps: wire the gate into direct `/soleur:work`; strengthen the jsdom test;
   reposition `/soleur:test-browser` so its pre-merge value isn't deferred to post-ship.
4. Codify the standing convention in an ADR.

## Non-Goals

- **No dev-signin / live-`doppler -c dev` server gate.** Rejected: reintroduces 307→/login, forces
  real creds into CI, headed-only. (Decision 2)
- **No broad per-page visual regression.** Scope to the nav/dashboard shell + 1-2 drilled routes;
  defer wider coverage to a tracked issue. (Decision 12, YAGNI)
- **No headed Playwright MCP as a merge blocker.** Vision pass is advisory only. (Decision 6)
- No redesign of the expanded rail states.

## Functional Requirements

- **FR1 — nav-states e2e spec.** Add `nav-states-*.e2e.ts` to the existing `authenticated`
  Playwright project (`apps/web-platform/playwright.config.ts`), reusing the offline mock-Supabase
  storageState (`e2e/global-setup.ts`). Real headless Chromium + real Next.js SSR.
- **FR2 — route × state × viewport matrix.** Cover the shell + drilled routes
  ({`/dashboard`, `/dashboard/kb`, `/dashboard/kb/<file>`, `/dashboard/settings/members`,
  `/dashboard/chat`}) × {expanded, collapsed} × {desktop 1280, mobile 390}. Build as a data-driven
  list so adding a route is one line. Seed 1-2 drilled routes now (Decision 12).
- **FR3 — deterministic assertions** (jsdom-impossible):
  - On a drilled route, the `Soleur` wordmark and `ThemeToggle` are NOT visible (Bug 1).
  - The rail has no horizontal overflow (`scrollWidth <= clientWidth`).
  - Collapsed band is icon-only: no text wrap / `scrollWidth <= clientWidth` (or assert a
    `data-collapsed` marker the impl exposes) (Bug 2).
  - The workspace-identity band is visible in every drill state × viewport (ADR-047 invariant).
- **FR4 — Bug 1 fix.** Drill-hide (or move into the `drill === null` swap) the brand row +
  collapse chevron + `ThemeToggle` so they render only at the top level.
- **FR5 — Bug 2 fix.** Give `WorkspaceContextBand` an icon-only collapsed form (pass/derive a
  `collapsed` signal; gate text content on it without unmounting the identity). Follow the
  ux-design-lead wireframe for the collapsed icon-only band + the collapsed-drilled tree behavior.
- **FR6 — strengthen jsdom test.** In `test/nav-rail-drill.test.tsx`, assert the drilled rail
  contains band + section + secondary-nav ONLY, and does NOT contain wordmark / ThemeToggle /
  footer (pure DOM-presence; would have caught Bug 1).
- **FR7 — wire into `/soleur:work` Phase 4** behind the diff-path predicate; spec also runs
  CI-blocking. Reposition `/soleur:test-browser` to post-ship smoke only.
- **FR8 — ADR-048** codifies the standing gate + mock-vs-live seeding rationale.

## Technical Requirements

- **TR1 — seeding.** Mock-Supabase offline storageState only. Zero real credentials; no
  `FLAG_DEV_SIGNIN`, no `DEV_USER_*`, in local OR CI. (Decisions 1-2)
- **TR2 — deterministic collapsed state.** Force collapse by seeding
  `localStorage["soleur:sidebar.main.collapsed"]` (backed by `useSidebarCollapse`) before
  navigation — never click the toggle + wait on animation. (Decision 3)
- **TR3 — testMatch.** Extend the `authenticated` project's `testMatch` with a
  `**/nav-states-*.e2e.ts` pattern (currently `start-fresh-*` / `cc-soleur-go-*`).
- **TR4 — diff-path predicate** for the `/work` Phase 4 trigger: `apps/web-platform/app/(dashboard)/**`,
  `apps/web-platform/components/dashboard/**`, any `layout.tsx`. Do NOT fire on leaf-component or
  content-only `.tsx`. (Decision 8)
- **TR5 — synthetic-fixture-only baselines.** Any committed screenshot/baseline artifact must
  contain solely synthetic fixture content (`test@e2e.com` + mock UUID). Never point at a live
  origin. (CLO condition; mirrors `cq-test-fixtures-synthesized-only`)
- **TR6 — vision pass advisory.** `/soleur:qa` Playwright-MCP screenshots are informational, not
  a blocker (headed MCP can't run headless/autonomous).

## Acceptance Criteria

- AC1: On `main`'s buggy code, `nav-states-*.e2e.ts` FAILS on Bug 1 and Bug 2 assertions (RED
  baseline captured in the PR). *(Prove the gate before fixing.)*
- AC2: After FR4 + FR5, the spec PASSES (GREEN) across the full matrix.
- AC3: The strengthened jsdom test (FR6) fails on the pre-fix DOM and passes after.
- AC4: `npm run lint` / `tsc` / `vitest` all green; the e2e spec runs headless with no display.
- AC5: ADR-048 committed; `/soleur:test-browser` repositioned; `/work` predicate wired.

## Test Scenarios

> Note: these run via the `authenticated` Playwright project (mock Supabase), NOT via live
> `doppler -c dev`. The vision pass below is advisory.

- Browser: navigate each {route × state × viewport}; assert FR3 invariants; screenshot each.
- Browser (advisory vision): `/soleur:qa` Playwright-MCP captures the same routes for an LLM
  visual-diff pass flagging anything assertions miss.

## Open Questions (carry to plan)

- Collapsed-drilled KB-tree behavior — resolved by ux-design-lead wireframe (force-expand vs
  icon-tree vs auto-expand-on-click).
- Exact `/work` Phase 4 hook point (operator observed qa-skip; SKILL.md text reads as terminal).
- CI wall-clock cost of the added `authenticated` webServer + viewport matrix.

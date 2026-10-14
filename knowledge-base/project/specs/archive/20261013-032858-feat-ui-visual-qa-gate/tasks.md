---
feature: ui-visual-qa-gate
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4834
pr: 4833
plan: knowledge-base/project/plans/2026-06-02-feat-ui-visual-qa-gate-plan.md
date: 2026-06-02
---

# Tasks — Headless Visual-Regression Gate (+ fix two #4810 bugs)

> One PR, ordered: **build gate → prove RED on the live bugs → fix → GREEN.** Do not reorder.

## Phase 0 — Prove the harness + capture seeding (precondition; gate the rest on this)
- [x] 0.1 Run from `apps/web-platform/`; `npx playwright install chromium` (must match `@playwright/test` 1.58.2); `rm -rf .next/types` before any `tsc --noEmit`.
- [x] 0.2 `npx playwright test --project=authenticated start-fresh-conversations-rail` — require an actual **PASS** (not SKIP). Do not proceed until green.
- [x] 0.3 Read `e2e/helpers/supabase-mocks.ts`; confirm `injectFakeSupabaseSession` (seeds `localStorage["sb-localhost-auth-token"]`) + `mockSupabaseAuth` are the shared exports to import.
- [x] 0.4 Confirm the band's app routes need mocking: `/api/workspace/active-repo`, `/api/workspace/list-memberships` (children return `null` until they resolve).

## Phase 1 — Build the gate RED (TDD)
- [x] 1.1 Create `e2e/nav-states-shell.e2e.ts` in the `authenticated` project: import the seeding helper; `page.route`-mock the two `/api/workspace/*` routes (non-empty repo + ≥1 membership); lean matrix desktop{1280}×{expanded,collapsed}×{`/dashboard`, `/dashboard/kb`} + mobile{390}×{`/dashboard`}.
- [x] 1.2 Seed collapsed via `page.addInitScript(() => localStorage.setItem("soleur:sidebar.main.collapsed","1"))` — literal `"1"`; assert collapsed width with a **retrying** locator assertion.
- [x] 1.3 FR3 invariant assertions (NOT bare proxies): Bug 1 wordmark+ThemeToggle absent-from-DOM when drilled; identity = org-id testid AND repo-badge testid visible every state; Bug 2 text-labels hidden + icon visible + `boundingBox().width<=56` collapsed. `page.screenshot()` → `test-results/` (non-committed, advisory).
- [x] 1.4 `playwright.config.ts` DUAL edit: add `**/nav-states-*.e2e.ts` to `authenticated.testMatch` (L45) AND `chromium.testIgnore` (L36). Keep the global `testMatch` (L14). Verify it does NOT run under `--project=chromium`.
- [x] 1.5 Strengthen `test/nav-rail-drill.test.tsx` (jsdom): drilled → `queryByText("Soleur")`/ThemeToggle/footer absent; `workspace-context-band` (rail) present.
- [x] 1.6 **Run both → confirm RED** on current code. Capture RED output for the PR body (AC1).

## Phase 2 — Fix Bug 1 (drilled chrome leak)
- [x] 2.1 `layout.tsx`: wrap the `Soleur` `<span>` (≈L251) + theme `<div>` (≈L277-279) in `{drill === null && (…)}` (render-conditional / DOM-removal). Gate INDIVIDUALLY — never the brand-row `<div>` (L250). Keep mobile close button + chevron (frame 07 chevron→pin).
- [x] 2.2 Re-run jsdom + expanded-drilled e2e → GREEN for Bug 1.

## Phase 3 — Fix Bug 2 (collapsed band icon-only)
- [x] 3.1 `workspace-context-band.tsx`: add `collapsed?: boolean`; render band-level icon substitutes (org avatar + repo dot + section-icon, hover tooltips) when collapsed per frame 06; identity never unmounts. Do NOT thread a prop through child components unless substitutes can't reuse their data hooks.
- [x] 3.2 `layout.tsx`: pass `collapsed={collapsed}` at the rail mount (≈L293).
- [x] 3.3 Re-run collapsed e2e → GREEN for Bug 2.

## Phase 4 — Confirm GREEN + advisory vision
- [x] 4.1 Full lean matrix GREEN headless; `vitest` + `tsc --noEmit` (after `rm -rf .next/types`) + lint green.
- [x] 4.2 Advisory: `/soleur:qa` Playwright-MCP vision pass over the same routes (non-blocking).

## Phase 5 — Close workflow gaps (skill wiring)
- [x] 5.1 `work/SKILL.md` (load-bearing): ADD a diff-path-gated `skill: soleur:qa` step to the Phase 4 Invocation Mode list (≈L762-773), BOTH direct + one-shot branches; predicate = `app/(dashboard)/**` | `components/dashboard/**` | any `layout.tsx`; non-terminal handoff phrasing.
- [x] 5.2 `qa/SKILL.md`: add the auth-seeded nav-states phase + advisory MCP vision (mock-fork, no dev-signin).
- [x] 5.3 `test-browser/SKILL.md`: reposition to post-ship smoke (one-line note).
- [x] 5.4 `bun test plugins/soleur/test/components.test.ts` green (body edits only; no skill-budget regression).

## Phase 6 — Ship
- [x] 6.1 PR body: `Closes #4834`, paste RED→GREEN evidence. Verify `gh pr checks` (CI `e2e` job green = gate ran in CI).
- [x] 6.2 Post-deploy Playwright-MCP smoke of drilled+collapsed dashboard in prod (automatable; via /soleur:ship).

---
title: "feat: Headless visual-regression gate for UI-structural diffs (+ fix two #4810 layout bugs)"
date: 2026-06-02
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 4834
pr: 4833
branch: feat-ui-visual-qa-gate
brainstorm: knowledge-base/project/brainstorms/2026-06-02-ui-visual-qa-gate-brainstorm.md
spec: knowledge-base/project/specs/feat-ui-visual-qa-gate/spec.md
adr: knowledge-base/engineering/architecture/decisions/ADR-048-headless-visual-regression-gate.md
related: [4810, 4813, 4835]
---

# ✨ Headless Visual-Regression Gate for UI-Structural Diffs

## Overview

PR #4810 (single nav rail) passed every automated gate — 8166 vitest green, tsc clean, 6-agent
review, GDPR gate — and shipped two CSS-layout bugs to prod because **no pre-merge gate renders
real CSS**. Build a committed headless `@playwright/test` spec that fails RED on the two live bugs
and passes GREEN after they are fixed, then fix the bugs. One PR, ordered: **build gate → prove RED
→ fix → GREEN.**

The gate is **one new `nav-states-*.e2e.ts` file** added to the existing `authenticated` Playwright
project (real headless Chromium + real Next.js SSR + offline mock-Supabase storageState). Zero
credentials, headless, and **CI-blocking by construction** — `ci.yml`'s `e2e` job already runs
`npx playwright test` in the pinned `playwright:v1.58.2-jammy` container.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Add `nav-states-*.e2e.ts` to the `authenticated` project" (TR3) | `playwright.config.ts`: the `authenticated` project's `testMatch` is an **array** `["**/start-fresh-*.e2e.ts","**/cc-soleur-go-*.e2e.ts"]`; the `chromium` (public, unreachable-Supabase) project has a matching `testIgnore`. A new `nav-states-*` file lands on **chromium** (not ignored) → 307/login fail, and is **excluded from authenticated** (not matched). | **Dual edit required:** add `**/nav-states-*.e2e.ts` to the `authenticated` `testMatch` (line 45) AND to the `chromium` `testIgnore` (line 36). |
| "Seed `localStorage["soleur:sidebar.main.collapsed"]`" (TR2) | `use-sidebar-collapse.ts` stores the **literal `"1"`** and checks `=== "1"`; it hydrates from `false` in a `useEffect`. `global-setup.ts` writes **cookies only** (`origins: []`). | Seed via `page.addInitScript(() => localStorage.setItem("soleur:sidebar.main.collapsed","1"))` with the literal `"1"`; assert collapsed width with a **retrying** locator assertion (post-hydration), never an immediate read. |
| "spec also runs CI-blocking" (FR7) | `ci.yml` `e2e` job runs `npx playwright test` (all projects) in `mcr.microsoft.com/playwright:v1.58.2-jammy`. | **No new CI job.** Routing the spec to `authenticated` makes it CI-blocking automatically. Keep the matrix lean (CPO) to bound wall-clock; `workers: 1`. |
| "{expanded, collapsed} × {desktop 1280, mobile 390}" matrix (FR2) | Collapse is `md:w-14` — **desktop-only**; below `md` the rail is a drawer and the band lives in the mobile top bar. | Collapsed states are desktop-only. Matrix = desktop{1280}×{expanded,collapsed}×{shell, kb-drilled, chat-drilled} + mobile{390}×{shell, kb-drilled} (no collapse). ~8 states. |
| "Give `WorkspaceContextBand` an icon-only collapsed form" (FR5) | The band renders `OrgSwitcherContainer` + `LiveRepoBadge` (separate components with their own text). | FR5 likely also edits `org-switcher-container.tsx` + `live-repo-badge.tsx` (add a `compact`/icon-only mode) OR the band renders icon-only substitutes. /work confirms the cleaner shape; both listed in Files to Edit. |

## Research Insights (institutional learnings)

- `2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md` (keystone — this feature's post-mortem): seed client state deterministically; assert what jsdom can't; committed gate; RED-then-GREEN same PR; close the `/work` vs `/one-shot` asymmetry.
- `ADR-047` (invariants the assertions encode): band outside the swap, visible every drill state, single-mount, ⌘B sole collapse owner. `ADR-048` (this gate's accepted decision).
- `2026-04-10-supabase-e2e-localstorage-session-injection.md`: seed BOTH cookie AND `localStorage["sb-localhost-auth-token"]` (browser client short-circuits on localStorage) — Phase 0 step 3.
- `2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase.md`: glob (not regex) testMatch; authenticated timeout 60s for SSR cold-compile.
- `2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`: verify Playwright APIs against `node_modules/playwright-core/types/types.d.ts`; `rm -rf .next/types` before tsc.
- `2026-03-20-playwright-shared-cache-version-coupling.md`: chromium revision lookup is exact-match; pin to 1.58.2.
- `2026-03-03`/`2026-03-02` skill-handoff: non-terminal phrasing when wiring into `/work` Phase 4.
- `2026-02-17-playwright-screenshots-land-in-main-repo.md`: screenshots resolve to bare-repo root — keep non-committed.

## User-Brand Impact

**If this lands broken, the user experiences:** a non-technical Soleur operator (n=1) lands on a
broken, unnavigable dashboard (exactly #4810) — total loss of the product surface for the only user.
**If this leaks, the user's session is exposed via:** the auth-seeding path — closed by design (mock
synthetic session `test@e2e.com`/fabricated UUID only; no `dev-signin`, no `DEV_USER_*`, no real
credential in local or CI; CLO-confirmed).
**Brand-survival threshold:** `single-user incident` (CPO-confirmed: the event already happened; no
statistical buffer at n=1). CPO sign-off carried forward from brainstorm; `user-impact-reviewer`
runs at PR review.

## Implementation Phases

### Phase 0 — Prove the harness reaches `/dashboard` + capture the seeding pattern (precondition)
1. Hygiene first (per `2026-05-14` + `2026-03-20` learnings): run from `apps/web-platform/`;
   confirm the pinned chromium is installed (`npx playwright install chromium`, revision must match
   `@playwright/test` 1.58.2); `rm -rf .next/types` before any `tsc --noEmit` to avoid stale-artifact
   false regressions.
2. Run an existing `authenticated` spec locally (`npx playwright test --project=authenticated
   start-fresh-conversations-rail` — it drills the nav rail) to confirm the mock-Supabase harness
   renders authenticated routes without 307. **Do not write a line of `nav-states` until this passes.**
   This is the single biggest de-risk (it is *why* all prior local attempts failed).
3. **Capture the client-auth seeding pattern.** `global-setup.ts` writes only the SSR **cookie**
   (`origins: []`). But `@supabase/ssr`'s *browser* client reads `localStorage` first and
   short-circuits auth (learning `2026-04-10-supabase-e2e-localstorage-session-injection.md`), so the
   client-side `getSession()` in `layout.tsx` (L128) + the band's `OrgSwitcherContainer`/`LiveRepoBadge`
   may need `localStorage["sb-localhost-auth-token"]` seeded via `page.addInitScript()` to render full
   identity (not an auth-error state). Read how `start-fresh-*`/`cc-soleur-go-*` seed the browser
   session and replicate that exact pattern in `nav-states-shell.e2e.ts` — do NOT invent a new one.

### Phase 1 — Build the gate RED (TDD)
1. `nav-states-shell.e2e.ts` (new) in the `authenticated` project: data-driven matrix (Research
   Reconciliation row 4). Per state, assert FR3 invariants (below). **Blocking layer = deterministic
   assertions ONLY** (`expect(locator).toBeVisible()/.not.toBeVisible()`, `boundingBox`, `scrollWidth`).
   **Do NOT use `toHaveScreenshot()` pixel baselines** — they are font/OS-flaky AND Playwright writes
   them to the bare/main repo root invisibly to the worktree (`2026-02-17` learning). Capture
   `page.screenshot()` into `test-results/` as **non-committed** artifacts for the advisory vision
   pass + debugging only (also satisfies the CLO synthetic-fixture condition: no committed baseline
   PNGs at all).
2. Wire `playwright.config.ts` (dual `testMatch`/`testIgnore` edit).
3. Strengthen `test/nav-rail-drill.test.tsx` (jsdom): add the DOM-presence half of Bug 1 — when
   drilled, `queryByText("Soleur")`, the ThemeToggle, and footer (`Sign out`) are **absent**; the
   `workspace-context-band` (rail) IS present. Add the band-present assertion to the existing
   drilled `it.each`.
4. **Run both → confirm RED** on current `main` code (wordmark/theme leak when drilled; collapsed
   band overflows). Capture the RED output in the PR body (AC1).

**FR3 deterministic assertions (jsdom-impossible):** on a drilled route the `Soleur` wordmark and
`ThemeToggle` are NOT visible; the rail has no horizontal overflow (`scrollWidth <= clientWidth`);
the collapsed rail band is icon-only (`scrollWidth <= clientWidth`, no text wrap); the
`workspace-context-band` (identity) is visible in every drill state × viewport.

### Phase 2 — Fix Bug 1 (drilled chrome leak)
`layout.tsx`: gate the `Soleur` wordmark `<span>` (≈L251) and the theme-toggle `<div>` (≈L277-279)
on `drill === null`. Keep the mobile close button. For the collapse chevron in drilled states,
follow wireframe **frame 07** (chevron→pin) — do NOT orphan ⌘B as the only collapse control. Re-run
jsdom + the expanded-drilled e2e states → those go GREEN.

### Phase 3 — Fix Bug 2 (collapsed band has no icon-only form)
`workspace-context-band.tsx`: add `collapsed?: boolean` (default false; meaningful for
`variant="rail"`); `layout.tsx` passes `collapsed={collapsed}` at the rail mount (≈L293). When
`collapsed`, render the icon-only form per wireframe **frame 06** (org avatar icon, repo dot, hidden
text + section-title-as-icon, hover tooltips recover labels; identity never unmounts — ADR-047). Add
a `compact`/icon-only mode to `org-switcher-container.tsx` + `live-repo-badge.tsx` as needed. Collapsed-
drilled KB tree = wireframe **option (c)** (200px tree-peek anchored to the 56px spine; chevron→pin).
Re-run collapsed e2e states → GREEN.

### Phase 4 — Confirm GREEN + screenshot review
Full matrix GREEN headless. Vision pass (advisory): `/soleur:qa` Playwright-MCP screenshots of the
same routes for an LLM visual-diff overlay (informational, not blocking).

### Phase 5 — Close the workflow gaps (skill wiring)
1. `qa/SKILL.md`: add an auth-seeded nav-states phase that runs the `authenticated` project + the
   advisory MCP vision pass; document the mock-fork seeding (no dev-signin).
2. `work/SKILL.md`: wire the gate into Phase 4 pre-ready handoff behind the diff-path predicate
   (`apps/web-platform/app/(dashboard)/**`, `apps/web-platform/components/dashboard/**`, any
   `layout.tsx`); do NOT fire on leaf-component/content-only `.tsx`. (Read the exact Phase 4
   insertion point at /work time; the operator observed direct `/work` skipping qa.) **Use
   non-terminal handoff phrasing** — scope-boundary ("do not invoke X yourself") + "continue
   executing the next instruction", NEVER stop-like/"announce to the user" language, or the model
   treats it as a turn boundary and the gate silently doesn't run (`2026-03-03`/`2026-03-02` learnings).
2. `test-browser/SKILL.md`: reposition to post-ship smoke only (its pre-merge value folds into the
   e2e spec).

### Phase 6 — ADR + docs (already committed this branch)
ADR-048 + brainstorm + spec + learning already on the branch. Verify links resolve at ship.

## Files to Create
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — the gate (matrix + FR3 assertions + screenshots).

## Files to Edit
- `apps/web-platform/playwright.config.ts` — dual `testMatch`(L45)/`testIgnore`(L36) add `**/nav-states-*.e2e.ts`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — Bug 1 (gate wordmark+theme on `drill===null`; pass `collapsed` to band).
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — Bug 2 (`collapsed` prop + icon-only form).
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — compact/icon-only mode (verify at /work).
- `apps/web-platform/components/dashboard/live-repo-badge.tsx` — compact/icon-only mode (verify at /work).
- `apps/web-platform/test/nav-rail-drill.test.tsx` — strengthen (FR6 DOM-presence half of Bug 1).
- `plugins/soleur/skills/qa/SKILL.md` — add nav-states phase (body edit, not `description:`).
- `plugins/soleur/skills/work/SKILL.md` — wire gate into Phase 4 predicate (body edit).
- `plugins/soleur/skills/test-browser/SKILL.md` — reposition to post-ship smoke (body edit).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1:** On current `main` code, `nav-states-shell.e2e.ts` FAILS Bug 1 + Bug 2 assertions, and the strengthened jsdom test FAILS the drilled wordmark/theme-absent assertions — **RED baseline pasted in PR body.**
- [ ] **AC2:** After Phase 2+3, the full matrix PASSES GREEN headless (`npx playwright test --project=authenticated nav-states`).
- [ ] **AC3:** Strengthened jsdom test GREEN; `vitest` + `tsc --noEmit` + lint all green.
- [ ] **AC4:** `playwright.config.ts` shows `**/nav-states-*.e2e.ts` in BOTH `authenticated.testMatch` AND `chromium.testIgnore` (verify: the spec does NOT run under `--project=chromium`).
- [ ] **AC5:** Identity band (`workspace-context-band`) asserted visible in every drill state × viewport; collapsed band asserts `scrollWidth <= clientWidth`.
- [ ] **AC6:** `qa`/`work`/`test-browser` SKILL.md edits land; `bun test plugins/soleur/test/components.test.ts` green (no skill-budget regression — body edits only).
- [ ] **AC7:** PR body uses `Closes #4834`.

### Post-merge (operator — automatable, runs in /soleur:ship)
- [ ] **AC8:** CI `e2e` job green on the PR (the gate ran in CI). Verify via `gh pr checks`.
- [ ] **AC9:** Post-deploy, the dashboard renders correctly drilled + collapsed in prod (Playwright-MCP smoke — automatable, not operator-eyeball).

## Open Code-Review Overlap
**#2193** (refactor billing past_due/unpaid banners + extract `useDismissiblePersistent`) touches
`layout.tsx`. **Disposition: Acknowledge** — different concern (billing banners in `<main>`, ≈L388-405)
from the nav rail brand/band swap (≈L249-294); negligible conflict surface. Scope-out remains open.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** Extend the existing `authenticated` Playwright
project with one spec; mock-fork seeding (no dev-signin anywhere); deterministic spec blocking +
advisory MCP vision; tight diff-path predicate into `/work` Phase 4. Biggest risk: re-solving the
solved auth-seeding problem (dev-signin-against-live) — avoided.

### Product/UX Gate
**Tier:** blocking (mechanical UI-surface override: `layout.tsx` + `components/dashboard/**` in Files to Edit).
**Decision:** reviewed. **Agents invoked:** ux-design-lead (brainstorm Phase 3.55 — frames 06/07), cpo (brainstorm carry-forward), spec-flow-analyzer (this plan).
**Skipped specialists:** copywriter (none — no copy surface, nav chrome only).
**Pencil available:** yes (`single-nav-rail.pen` frames 06/07 committed, referenced in spec FR5).
#### Findings
CPO: `single-user incident` correct; scope to shell + 1-2 drilled routes, matrix cheap to extend, defer broad coverage (#4835); one PR build→red→fix→green. ux-design-lead: collapsed-drilled tree = option (c) tree-peek + chevron→pin (frames 06/07).

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** mock-fork eliminates the auth-bypass/credential surface (synthetic session only). No residual risk; **gdpr-gate not required** (no regulated-data surface, synthetic fixtures only — `hr-gdpr-gate-on-regulated-data-surfaces` not triggered). **Condition:** baselines synthetic-fixture-only, never a live origin (mirrors `cq-test-fixtures-synthesized-only`).

## Observability

```yaml
liveness_signal:    # CI `e2e` job runs nav-states on every PR matching the diff-path predicate / on every push; alert_target = PR status check; configured_in = .github/workflows/ci.yml (e2e job) + work/SKILL.md Phase 4
error_reporting:    # destination = CI job failure annotation (GitHub Checks) + Playwright HTML report artifact; fail_loud = blocking required check
failure_modes:      # [{mode: nav-shell CSS regression, detection: nav-states e2e RED, alert_route: PR blocked}, {mode: harness can't reach /dashboard, detection: Phase 0 precondition + e2e 307, alert_route: CI red}]
logs:               # where = Playwright trace (on-first-retry) + test-results/ artifact; retention = CI artifact default
discoverability_test:  # command (NO ssh): npx playwright test --project=authenticated nav-states ; expected_output: matrix PASS, screenshots in test-results/
```
*(Presentational fixes + a test gate carry no runtime observability surface; the CI pass/fail IS the liveness signal for nav-shell regressions.)*

## Test Scenarios
- Browser (blocking): `nav-states-shell.e2e.ts` walks the matrix, asserts FR3, screenshots each.
- Browser (advisory vision): `/soleur:qa` Playwright-MCP captures the same routes for LLM visual-diff.
- Unit (jsdom): strengthened `nav-rail-drill.test.tsx` (DOM-presence half of Bug 1).

## Sharp Edges
- **Seed the literal `"1"`, not `true`/`"true"`** — `use-sidebar-collapse.ts` checks `=== "1"`. Wrong value = no collapse = false-GREEN.
- **Collapse hydrates in a `useEffect`** (starts `false`) — use a **retrying** locator assertion on the `md:w-14` width; an immediate read races hydration.
- **Dual config edit** — `testMatch` (authenticated) AND `testIgnore` (chromium). Missing the `testIgnore` half runs the spec against the unreachable-Supabase public server → 307 → confusing red. (PR #3743 class.)
- **Glob, never regex, in `testMatch`/`testIgnore`** — a regex like `/nav-states/` matches the worktree DIRECTORY name (`.worktrees/feat-ui-visual-qa-gate/`) and mis-routes every test (`2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase` learning). Use `**/nav-states-*.e2e.ts`.
- **No committed pixel baselines** — blocking assertions are deterministic (`scrollWidth`/visibility); screenshots are non-committed `test-results/` artifacts. Avoids font/OS flake AND the Playwright-writes-to-bare-repo-root trap (`2026-02-17`).
- **Collapse is desktop-only** (`md:w-14`) — do not assert a collapsed state at the 390 mobile viewport (the rail is a drawer there).
- **Don't orphan ⌘B** — when hiding the brand row in drilled states, preserve a collapse/expand affordance per wireframe frame 07 (chevron→pin).
- **OrgSwitcher/LiveRepoBadge compact mode** — Bug 2's icon-only form likely needs a prop on each child component, not just the band; enumerate at /work (Files to Edit lists both).
- **Playwright version coupling** — the spec runs under the pinned `v1.58.2` container; use only 1.58.2 `@playwright/test` APIs (per `2026-03-20-playwright-shared-cache-version-coupling.md`). No `--max-time`-less network calls.
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled.

## Risks
- **CI wall-clock:** `workers: 1` + ~8 states adds to the `e2e` job. Mitigate: lean matrix (CPO), reuse the running `authenticated` webServer.
- **Flake from animation/hydration:** mitigated by localStorage-seed (no toggle click) + retrying assertions.
- **Bug 2 scope creep into child components:** bounded by listing `org-switcher-container.tsx`/`live-repo-badge.tsx` up front and following the wireframe.

## Alternatives Considered
| Approach | Rejected because |
|---|---|
| Live `doppler -c dev` + `/api/auth/dev-signin` | Reintroduces 307→/login; forces real `DEV_USER_*` creds + `FLAG_DEV_SIGNIN` into CI; headed-only. (ADR-048) |
| Agent-driven Playwright MCP walkthrough as the gate | Headed-only, non-durable, no CI regression guard. Kept as advisory vision. |
| New CI job for e2e | Unnecessary — `ci.yml` `e2e` job already runs `npx playwright test`. |
| Broad per-page visual regression now | YAGNI (CPO); deferred to #4835. |

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
| "Add `nav-states-*.e2e.ts` to the `authenticated` project" (TR3) | `playwright.config.ts`: a **global** `testMatch: "**/*.e2e.ts"` (L14); the `chromium` project has NO project-level `testMatch` so it **inherits the global** (runs everything except its `testIgnore`); the `authenticated` project's array `testMatch` (L45) overrides the global. A new `nav-states-*` file is inherited by **chromium** (unreachable-Supabase → 307) and **excluded from authenticated**. Only 2 projects — no third glob. | **Dual edit (sufficient):** add `**/nav-states-*.e2e.ts` to `authenticated.testMatch` (L45) AND to `chromium.testIgnore` (L36). Do NOT delete the global `testMatch` (Kieran P1-2). |
| "Seed `localStorage["soleur:sidebar.main.collapsed"]`" (TR2) | `apps/web-platform/hooks/use-sidebar-collapse.ts` stores the **literal `"1"`** and checks `=== "1"`; hydrates from `false` in a `useEffect`. `global-setup.ts` writes **cookies only** (`origins: []`). | Seed via `page.addInitScript(() => localStorage.setItem("soleur:sidebar.main.collapsed","1"))` — literal `"1"`, NOT `true`; assert collapsed width with a **retrying** locator assertion (post-hydration), never an immediate read. |
| "Band shows identity" (FR3/AC5) | `LiveRepoBadge` returns `null` until `GET /api/workspace/active-repo` resolves; `OrgSwitcherContainer` returns `null` until `GET /api/workspace/list-memberships` resolves — **app routes, not Supabase REST**, uncovered by `supabase-mocks.ts`. | **Mock both app routes** in-spec (Kieran P0-1); assert the band CONTAINS visible org + repo content, not just `band.toBeVisible()`. Else Bug 2 / identity assertions false-GREEN on an empty band. |
| "spec also runs CI-blocking" (FR7) | `ci.yml` `e2e` job runs `npx playwright test` (all projects) in `mcr.microsoft.com/playwright:v1.58.2-jammy`. | **No new CI job.** Routing the spec to `authenticated` makes it CI-blocking automatically. Keep the matrix lean (CPO) to bound wall-clock; `workers: 1`. |
| "{expanded, collapsed} × {desktop 1280, mobile 390}" matrix (FR2) | Collapse is `md:w-14` — **desktop-only**; below `md` the rail is a drawer and the band lives in the mobile top bar. Bug 1 is the single `drill !== null` branch (route-agnostic); Bug 2 is the single collapsed band-render path. | **Lean matrix (simplicity P1, ~5 states):** desktop{1280}×{expanded,collapsed}×{shell, kb-drilled} + mobile{390}×{shell}. One drilled route (kb) exercises Bug 1's branch; `chat-drilled` + `mobile-drilled` add no new code path (deferred to #4835). |
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
   renders authenticated routes without 307. **Require an actual PASS, not a SKIP** — that spec has
   `test.skip` on dev-server 500s (CSS cold-compile); a skip is not a passing harness (Kieran P2-2).
   **Do not write a line of `nav-states` until this PASSES.** Single biggest de-risk.
3. **Reuse the existing seeding helper — do not invent one.** `global-setup.ts` writes only the SSR
   **cookie** (`origins: []`). The browser-client localStorage seed + the API mocks live in the shared
   helper `e2e/helpers/supabase-mocks.ts` (`injectFakeSupabaseSession` seeds
   `localStorage["sb-localhost-auth-token"]` via `addInitScript`; `mockSupabaseAuth`). **Import** these
   (they are shared exports, not copy-paste) and call them in `nav-states-shell.e2e.ts` setup.
4. **Mock the band's app API routes (CRITICAL — else Bug 2 RED false-GREENs; Kieran P0-1).**
   `LiveRepoBadge` returns `null` until `GET /api/workspace/active-repo` resolves; `OrgSwitcherContainer`
   returns `null` until `GET /api/workspace/list-memberships` resolves. These are **Next.js app routes,
   NOT Supabase REST**, so `supabase-mocks.ts` does NOT cover them. Add `page.route(
   "**/api/workspace/active-repo", …)` (non-empty repo) and `page.route(
   "**/api/workspace/list-memberships", …)` (≥1 membership). Without these the band renders empty,
   `scrollWidth<=clientWidth` passes trivially, and the identity-visible AC passes vacuously.

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

**FR3 deterministic assertions (jsdom-impossible) — assert the INVARIANT, never a bare proxy
(spec-flow P0-2/P0-3, Kieran P0-1):**
- Bug 1: on a drilled route the `Soleur` wordmark and `ThemeToggle` are NOT in the DOM
  (`toBeHidden()`/absent) — and the band's identity CONTENT is present.
- Identity (ADR-047): the band CONTAINS a **visible org identifier** (OrgSwitcher avatar/name testid)
  AND a **visible repo badge** testid in every drill state × viewport — not just `band.toBeVisible()`
  (a zero-box band passes that). **This requires mocking the app API routes the band depends on**
  (see Phase 0/Phase 1) or both children render `null` and the assertion passes vacuously.
- Bug 2 (collapsed, desktop): the band's **text labels are `toBeHidden()`** AND an **icon/avatar
  testid IS visible** AND the band `boundingBox().width <= 56`. Keep `scrollWidth <= clientWidth` only
  as a supporting check — never the sole assertion (an empty/truncated/wrapped band also passes it).

### Phase 2 — Fix Bug 1 (drilled chrome leak)
`layout.tsx`: **render-conditional, not CSS-hide** (spec-flow P0-1 — the wordmark at ≈L251 currently
carries only `collapsed ? "md:hidden"` and is never DOM-removed; jsdom ignores classes, so a
`md:hidden` "fix" leaves the jsdom assertion unsatisfiable). Wrap the `Soleur` wordmark `<span>`
(≈L251) and the theme-toggle `<div>` (≈L277-279) in `{drill === null && ( … )}` so they leave the
DOM when drilled. **Gate the `<span>` and the theme `<div>` INDIVIDUALLY — NOT the brand-row `<div>`
at L250** (the mobile close button + collapse chevron are siblings in that row and must survive;
Kieran P2-1). The wordmark's existing `collapsed ? md:hidden` composes (render only at top level,
hide-on-collapse within). Collapse chevron in drilled states: follow wireframe **frame 07**
(chevron→pin) — do NOT orphan ⌘B. Re-run jsdom + expanded-drilled e2e → GREEN.

### Phase 3 — Fix Bug 2 (collapsed band has no icon-only form)
`workspace-context-band.tsx`: add `collapsed?: boolean` (default false; meaningful for
`variant="rail"`); `layout.tsx` passes `collapsed={collapsed}` at the rail mount (≈L293). When
`collapsed`, **the band itself renders icon-only substitutes** (org avatar icon + repo dot +
section-title-as-icon, hover tooltips recover labels; identity never unmounts — ADR-047) per wireframe
**frame 06**. **Default to band-level substitutes — do NOT thread a `compact` prop through
`org-switcher-container.tsx`/`live-repo-badge.tsx`** unless /work proves the substitutes can't reuse
those children's data hooks (simplicity P2 — keeps the change in one file, removes the child-component
scope-creep risk by construction). Collapsed-drilled KB tree = wireframe **option (c)** (200px
tree-peek; chevron→pin) — note the **gate asserts the invariants** (no overflow, icon-only identity
visible), NOT the 200px tree-peek geometry (that's the implementation, not a brittle gate assertion;
spec-flow P1-3). Re-run collapsed e2e states → GREEN.

### Phase 4 — Confirm GREEN + screenshot review
Full matrix GREEN headless. Vision pass (advisory): `/soleur:qa` Playwright-MCP screenshots of the
same routes for an LLM visual-diff overlay (informational, not blocking).

### Phase 5 — Close the workflow gaps (skill wiring)
> **The gate is already CI-blocking** (it runs in `ci.yml`'s `e2e` job once routed to `authenticated`).
> Phase 5 closes the *local pre-push* gap so the bug is caught before CI too.
1. `work/SKILL.md` (**load-bearing — without it the gate never fires on direct `/work`**): the Phase 4
   "Invocation Mode" list (≈L762-773) runs review → resolve-todo → compound → ship with **NO qa step**
   (spec-flow P1-1 — a diff-path "predicate" would gate nothing; there is nothing to gate). **ADD a new
   step**: before `soleur:review`, "if the diff matches `apps/web-platform/app/(dashboard)/**` |
   `apps/web-platform/components/dashboard/**` | any `layout.tsx` → run `skill: soleur:qa`". Do NOT
   fire on leaf-component/content-only `.tsx`. **Use non-terminal handoff phrasing** — scope-boundary
   ("do not invoke X yourself") + "continue executing the next instruction"; NEVER stop-like/"announce
   to the user" language (`2026-03-03`/`2026-03-02` learnings — else the model treats it as a turn
   boundary and the step silently no-ops). Wire the SAME predicate into BOTH the direct-mode and
   one-shot-mode branches so the asymmetry the feature exists to close is actually closed (spec-flow P1-2).
2. `qa/SKILL.md`: add an auth-seeded nav-states phase (run the `authenticated` project; mock-fork
   seeding, no dev-signin) + the advisory MCP vision pass (non-blocking). This is the gate's semantic
   home (brainstorm Decision 1).
3. `test-browser/SKILL.md`: reposition to post-ship smoke only (one-line note; its pre-merge value
   folds into the e2e spec). Cleanup — lowest priority of the three.

### Phase 6 — ADR + docs (already committed this branch)
ADR-048 + brainstorm + spec + learning already on the branch. Verify links resolve at ship.

## Files to Create
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — the gate (lean matrix + FR3 invariant assertions + non-committed screenshots). Imports `e2e/helpers/supabase-mocks.ts` (`injectFakeSupabaseSession` + `mockSupabaseAuth`) and `page.route`-mocks `/api/workspace/active-repo` + `/api/workspace/list-memberships`.

## Files to Edit
- `apps/web-platform/playwright.config.ts` — dual `testMatch`(L45)/`testIgnore`(L36) add `**/nav-states-*.e2e.ts`.
- `apps/web-platform/app/(dashboard)/layout.tsx` — Bug 1 (gate wordmark+theme on `drill===null`; pass `collapsed` to band).
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — Bug 2 (`collapsed` prop + icon-only form).
- `apps/web-platform/test/nav-rail-drill.test.tsx` — strengthen (FR6 DOM-presence half of Bug 1).
- _(Conditional, default NOT edited)_ `org-switcher-container.tsx` / `live-repo-badge.tsx` — only if band-level icon substitutes (Phase 3) can't reuse their data hooks. Default: band renders substitutes; children untouched (simplicity P2).
- `plugins/soleur/skills/qa/SKILL.md` — add nav-states phase (body edit, not `description:`).
- `plugins/soleur/skills/work/SKILL.md` — wire gate into Phase 4 predicate (body edit).
- `plugins/soleur/skills/test-browser/SKILL.md` — reposition to post-ship smoke (body edit).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1:** On current `main` code, `nav-states-shell.e2e.ts` FAILS Bug 1 + Bug 2 assertions, and the strengthened jsdom test FAILS the drilled wordmark/theme-**in-DOM** assertions (jsdom proves only Bug 1's DOM-presence half; Bug 2/collapse-overflow RED is **e2e-only** — jsdom renders no CSS) — **RED baseline pasted in PR body.**
- [ ] **AC2:** After Phase 2+3, the full matrix PASSES GREEN headless (`npx playwright test --project=authenticated nav-states`).
- [ ] **AC3:** Strengthened jsdom test GREEN; `vitest` + `tsc --noEmit` + lint all green.
- [ ] **AC4:** `playwright.config.ts` shows `**/nav-states-*.e2e.ts` in BOTH `authenticated.testMatch` AND `chromium.testIgnore` (verify: the spec does NOT run under `--project=chromium`).
- [ ] **AC5:** With `/api/workspace/active-repo` + `/api/workspace/list-memberships` mocked (non-empty), the band asserts a **visible org identifier AND repo badge** in every drill state × viewport (not bare `band.toBeVisible()`); collapsed band asserts text-labels-hidden + icon visible + `boundingBox().width <= 56` (`scrollWidth <= clientWidth` is supporting only).
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
- **Mock the band's app API routes or Bug 2 RED is a false-GREEN** (Kieran P0-1). `LiveRepoBadge`/`OrgSwitcherContainer` render `null` until `/api/workspace/active-repo` + `/api/workspace/list-memberships` resolve — app routes, NOT Supabase REST, uncovered by `supabase-mocks.ts`. Unmocked = empty band = `scrollWidth<=clientWidth` passes trivially = the gate validates nothing.
- **Assert the invariant, not a proxy** (spec-flow P0-2/3). `scrollWidth<=clientWidth` and bare `band.toBeVisible()` pass on empty/zero-box bands. Assert org+repo content present (expanded) and text-hidden+icon-visible+width≤56 (collapsed).
- **Bug 1 fix = render-conditional, not CSS** (spec-flow P0-1). The wordmark is never DOM-removed today (only `collapsed?md:hidden`); a `md:hidden` "fix" leaves the jsdom assertion unsatisfiable. Use `{drill===null && …}`; gate the `<span>`/theme-`<div>` individually, never the brand-row `<div>` (preserves the chevron+close siblings, Kieran P2-1).
- **`/work` Phase 4 has no qa step to gate** (spec-flow P1-1). ADD a concrete gated qa invocation to the Invocation Mode list (both direct + one-shot); a predicate alone gates nothing.
- **Seed the literal `"1"`, not `true`/`"true"`** — `apps/web-platform/hooks/use-sidebar-collapse.ts` checks `=== "1"`. Wrong value = no collapse = false-GREEN.
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
- **CI wall-clock:** `workers: 1` + ~5 states adds to the `e2e` job. Mitigate: lean matrix (CPO), reuse the running `authenticated` webServer.
- **Flake from animation/hydration:** mitigated by localStorage-seed (no toggle click) + retrying assertions.
- **Bug 2 scope creep into child components:** bounded by listing `org-switcher-container.tsx`/`live-repo-badge.tsx` up front and following the wireframe.

## Alternatives Considered
| Approach | Rejected because |
|---|---|
| Live `doppler -c dev` + `/api/auth/dev-signin` | Reintroduces 307→/login; forces real `DEV_USER_*` creds + `FLAG_DEV_SIGNIN` into CI; headed-only. (ADR-048) |
| Agent-driven Playwright MCP walkthrough as the gate | Headed-only, non-durable, no CI regression guard. Kept as advisory vision. |
| New CI job for e2e | Unnecessary — `ci.yml` `e2e` job already runs `npx playwright test`. |
| Broad per-page visual regression now | YAGNI (CPO); deferred to #4835. |

---
date: 2026-06-02
topic: Pre-push visual-regression gate for UI-structural diffs (+ fix two #4810 layout bugs)
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
issue: 4834
branch: feat-ui-visual-qa-gate
pr: 4833
related:
  - knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md
  - knowledge-base/project/specs/feat-single-nav-rail/spec.md
  - knowledge-base/project/learnings/2026-06-02-server-audit-must-read-rpc-body-and-ssr-identity-needs-css-placement.md
---

# UI Visual-QA Gate — Brainstorm

## What We're Building

A **headless real-browser visual-regression gate** for UI-structural diffs, so a CSS-layout
regression can never again pass every automated gate and ship to prod. The companion
deliverable is fixing the two layout bugs PR #4810 shipped (which are the gate's own
acceptance test).

Three observed failures let #4810 ship broken despite 8166 green vitest + tsc clean + 6-agent
review + GDPR gate:

1. **jsdom sees no CSS.** vitest renders no `md:w-14`, `hidden md:block`, `flex-wrap`, or
   `display:none`. The plan itself said "never assert jsdom layout values → Playwright."
2. **The Playwright walkthrough (AC10) was deferred to post-merge** — nothing rendered the
   real page pre-merge.
3. **A direct `/soleur:work` invocation skipped `/soleur:qa` entirely.** Only `/soleur:one-shot`
   runs qa pre-merge; this PR went direct, so it had no browser check on any path.

### The two bugs (the gate's red baseline)

- **Bug 1 — top-level chrome leaks into drilled states.** In `app/(dashboard)/layout.tsx`, the
  `Soleur` wordmark + collapse chevron + `ThemeToggle` render *above* `WorkspaceContextBand`,
  OUTSIDE the `drill === null ? <primaryNav+footer> : <slot>` swap — so on a drilled route
  (chat/kb/settings) they stack on top of the band. Wireframes show only the compact band +
  section + secondary nav when drilled.
- **Bug 2 — the context band has no collapsed presentation.** `WorkspaceContextBand` is mounted
  unconditionally (correct — fixes the unmount-on-collapse bug, ADR-047), but when the rail is
  `md:w-14` the org switcher + "Working on" repo + section title wrap into an unreadable strip
  and the KB tree is crushed. It receives no `collapsed` prop and has no icon-only form.

## Why This Approach

The operator framed the "key unknown" as **dev-signin vs storageState** for auth-seeding,
because every local attempt to reach `/dashboard/*` headlessly 307'd to `/login`. The CTO
assessment found a **third, better answer** that reverses the agreed premise:

> The existing `@playwright/test` `authenticated` project (`apps/web-platform/playwright.config.ts`)
> **already** runs real headless Chromium against a real Next.js SSR dev server (full middleware +
> the ADR-047 SSR-identity path), seeded by an **offline mock-Supabase storageState**
> (`e2e/global-setup.ts`). No dev-signin, no live backend, no credentials, CI-portable.

So we **do not build a live-`doppler -c dev` + dev-signin gate.** That path would (a) reintroduce
the exact 307→/login failure that blocked all prior local attempts (mock JWT won't validate
against live dev Supabase), (b) force `FLAG_DEV_SIGNIN=1` + real `DEV_USER_*` creds into CI — an
auth-bypass / creds-in-CI exfil surface the existing 4-layer defense was built to avoid, and
(c) be headed-only (Playwright MCP is pinned `headless:false`), so it could never run in
autonomous `/work` or CI.

Instead: **add one committed `nav-states-*.e2e.ts` spec to the existing `authenticated` project.**
It is deterministic, headless, CI-portable, needs zero credentials, and becomes a permanent
regression guard (catches the *next* nav regression automatically, not just this one). The CSS
bugs are client-render/layout; the mock SSR path renders identical DOM, so fidelity is not lost.

The collapsed rail state is **deterministically forceable** without a flaky click+animation wait:
collapse is backed by `useSidebarCollapse("soleur:sidebar.main.collapsed")` (localStorage), so the
spec seeds that key before navigation.

The LLM **vision pass** (`/soleur:qa`'s Playwright-MCP screenshots) composes as an **advisory
overlay, not the blocking gate** — it flags what assertions can't encode, but headed MCP is never
a merge blocker.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Gate = committed `nav-states-*.e2e.ts` in the existing `authenticated` Playwright project** (mock-Supabase offline storageState, real headless Chromium + real SSR). | Durable, headless, CI-portable, zero credentials. Reverses the "live dev-server + dev-signin" framing. (CTO) |
| 2 | **No dev-signin anywhere in the gate** — local and CI use the same mock fork. | Avoids widening the auth-bypass surface + the 307 failure mode. (CTO + CLO) |
| 3 | **Force collapsed state by seeding `localStorage["soleur:sidebar.main.collapsed"]`**, not by clicking the toggle. | Removes the most likely spec-flakiness source (animation wait). |
| 4 | **Deterministic assertions** (jsdom-impossible): on a drilled route the wordmark + ThemeToggle are NOT visible; rail has no horizontal overflow; collapsed band is icon-only (`scrollWidth <= clientWidth` or a `data-collapsed` attr); workspace identity band is visible in every drill state × viewport. | These are exactly the invariants the two bugs violate. |
| 5 | **Also strengthen the jsdom test** `test/nav-rail-drill.test.tsx`: assert the drilled rail contains band + section + secondary-nav ONLY, NOT wordmark/ThemeToggle/footer. | Pure DOM-presence, jsdom-catchable — would have caught Bug 1 for free; cheap belt-and-suspenders. |
| 6 | **Vision pass = advisory overlay** in `/soleur:qa`; headed Playwright MCP is never a blocker. | Headed MCP can't run in autonomous `/work`/CI. (CTO) |
| 7 | **Wire the gate into `/soleur:work` Phase 4** (pre-ready handoff) behind a diff-path predicate; the spec also runs CI-blocking. NOT a PreToolUse/pre-push hook (too coarse, no plan context, fires on docs). | Fixes the skip where it happened (direct `/work`). (CTO) |
| 8 | **Diff-path predicate:** `apps/web-platform/app/(dashboard)/**`, `apps/web-platform/components/dashboard/**`, any `layout.tsx`. Do NOT fire on leaf-component or content-only `.tsx`. | Tight to structural shells = highest blast radius without over-firing. (CTO) |
| 9 | **Reposition `/soleur:test-browser`** — its pre-merge value folds into the e2e spec; post-ship it is a smoke only (stop running it AFTER ship as the deferral trap). | Removes the post-merge deferral that hid #4810. |
| 10 | **Create an ADR** codifying "structural-UI diffs require a headless visual-regression gate; jsdom cannot see CSS" + the mock-vs-live seeding rationale. | So it isn't re-litigated. Relates to ADR-047. |
| 11 | **One PR, ordered:** build gate → capture RED baseline on the live bugs → fix both bugs → gate goes GREEN. | The gate is proven by catching the bugs; the diff tells the story. (CPO) |
| 12 | **Scope = nav/dashboard shell + 1-2 drilled routes**; build the matrix (route list × viewport) so adding routes is cheap; defer broad per-page visual regression to a tracked issue (YAGNI). | Captures the actual failure class (shell leakage, collapsed-state absence) without flaky snapshot-maintenance cost. (CPO) |
| 13 | **Visual design:** collapsed-rail wireframe authored via ux-design-lead — `single-nav-rail.pen` frames 06 (collapsed top-level) + 07 (collapsed-drilled KB tree-peek). Collapsed-drilled tree = **option (c): 200px tree-peek panel anchored to the 56px spine; chevron→pin**. | wg-ui-feature-requires-pen-wireframe; the collapsed band was genuinely new UI. Resolves OQ1. |

## User-Brand Impact

- **Artifact:** the dashboard nav shell — the chrome every authenticated route renders inside.
- **Vector:** a structural-UI regression (chrome leak, collapsed-state breakage) ships to prod
  because no pre-merge gate renders real CSS; the non-technical Soleur operator lands on a
  broken, unnavigable dashboard — total loss of the product surface for the only user (n=1).
  Secondary vector: if the gate were built with dev-signin, real `DEV_USER_*` creds + a prod-
  capable auth-bypass flag would enter CI.
- **Threshold:** `single-user incident`. CPO confirmed: the event already happened (#4810); with
  one non-technical operator there is no statistical buffer. Both vectors are closed by the
  mock-fork design (no creds; deterministic CSS gate).

## Open Questions

1. ~~Collapsed-drilled tree behavior~~ — **RESOLVED (option c)** by the ux-design-lead wireframe:
   drilling auto-expands a 200px tree-peek panel anchored to the collapsed 56px spine; the collapse
   chevron becomes a pin. Carry into the plan (frames 06/07 in `single-nav-rail.pen`).

## Session Errors

- **Pencil MCP adapter is destructive in this headless environment.** `mcp__pencil__open_document`
  loaded an empty editor and **truncated `single-nav-rail.pen` to 0 bytes on open** (twice), and
  also touched a stray copy at the bare-repo path. The ux-design-lead recovered from a git-HEAD
  backup, hand-authored the two new frames as schema-validated JSON, and rendered review PNGs via
  headless Chrome instead of `export_nodes`. Both the worktree `.pen` (verified valid JSON, 7
  frames) and the main-checkout `.pen` (verified hash-identical to the committed blob) are intact.
  Matches the `cq-pencil-mcp-silent-drop` failure class. Tracked: #3274 (recurrence noted).
  end. The MCP adapter must be repaired (or the Pencil GUI used) before the next `.pen` edit.
2. **`/work` Phase 4 wiring mechanics** — the operator observed direct `/work` chaining
   `review → resolve-todo → compound → ship` and skipping qa; the work SKILL.md text reads as if
   Phase 4 is terminal. Confirm at plan time exactly where the structural-UI predicate hooks so
   the gate actually fires on direct `/work` (not just one-shot).
3. **testMatch wiring** — add a `**/nav-states-*.e2e.ts` pattern to the `authenticated` project's
   `testMatch` (currently `start-fresh-*` / `cc-soleur-go-*`), or name the file to match the
   existing glob? Plan-time detail.
4. **CI cost** — does adding the `authenticated` webServer + a viewport matrix to the blocking CI
   path add meaningful wall-clock? Measure; gate scope (Decision 12) keeps it small.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Reframed the key unknown decisively — the existing `authenticated` Playwright project
already provides real headless Chromium + real SSR + offline mock-Supabase storageState, so the
gate is one additive spec file, NOT a new credentialed live-server harness. Recommended mock-fork
seeding (no dev-signin anywhere), deterministic spec as the blocking layer + advisory MCP vision,
and a tight diff-path predicate wired into `/work` Phase 4 rather than a coarse pre-push hook.
Biggest risk: re-solving the already-solved auth-seeding problem (dev-signin-against-live) — net-
negative on security + flakiness + non-headless. No capability gap; primitives all exist.

### Product (CPO)

**Summary:** `single-user incident` threshold correctly calibrated (n=1, the event already
happened). Scope to the nav/dashboard shell + 1-2 drilled routes, build the route×viewport matrix
so coverage is cheap to extend, defer broad per-page regression (YAGNI). Ship gate + bug fixes in
ONE PR ordered build → red baseline → fix → green, so the gate is proven by catching the bugs.

### Legal (CLO)

**Summary:** Mock-fork eliminates the auth-bypass / credential-exposure surface entirely — the
storageState is a self-signed synthetic session (`test@e2e.com`, fabricated UUID, dummy refresh
token) valid only against the offline mock server; no real Supabase secret, no `DEV_USER_*`, no
prod token. No residual risk; gdpr-gate NOT required. **Condition:** baselines/screenshots must be
captured only against mock-seeded routes (synthetic-fixture-only, mirroring
`cq-test-fixtures-synthesized-only`); the gate must never point at a live/staging origin — if it
ever does, re-trigger the gdpr-gate.

## Capability Gaps

None. CTO confirmed all primitives exist: `apps/web-platform/playwright.config.ts` (`authenticated`
project, verified at the `name: "authenticated"` + `storageState` + mock-Supabase `webServer`
entries), `apps/web-platform/e2e/global-setup.ts` (offline seeding, verified — mints the synthetic
JWT), `/soleur:qa` (Playwright-MCP vision). The collapse mechanism
(`useSidebarCollapse("soleur:sidebar.main.collapsed")`, verified in `layout.tsx`) is localStorage-
backed, so collapsed state is deterministically seedable.

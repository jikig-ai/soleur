# Tasks — fix(kb): mobile drill-in navigation for the Knowledge Base

**Issue:** #7186
**Plan:** `knowledge-base/project/plans/2026-08-03-fix-kb-mobile-drill-in-navigation-plan.md` (v2)
**Branch:** `feat-one-shot-7186-kb-mobile-drill-in-nav`
**Lane:** `cross-domain` (no `spec.md` — fail-closed default)
**Brand-survival threshold:** `single-user incident`

All paths below are relative to the repo root unless prefixed. Test/typecheck commands run from
`apps/web-platform` — **never** `bun test`, **never** `npm run -w`.

---

## Phase 0 — Wireframe + operator sign-off 🚧 BLOCKING

No product code until 0.4 closes (`wg-ui-feature-requires-pen-wireframe`).

- [x] 0.1 `.pen` + 8 frames (`29-`…`36-`) produced and committed (`15ac70b19`)
- [ ] 0.2 Add the **768px tablet** frame (the switch point) as `37-*.png`, a direct child of
      `knowledge-base/product/design/navigation/screenshots/`; verify with `git check-ignore -v`
- [ ] 0.3 Surface the five open design questions — see
      `knowledge-base/project/specs/feat-one-shot-7186-kb-mobile-drill-in-nav/decision-challenges.md`
      (DC1 back-ownership, DC2 drawer row, DC3 doc-header budget, DC4 corner radius, DC5 ⌘K trigger)
- [ ] 0.4 **Operator sign-off gate.** `xdg-open` the screenshots dir. Headless: record
      `wireframes ready for async review at <dir>`, put DC1–DC5 in the PR body, and do **not** mark
      the PR ready until the operator signs off. On approval run
      `bash plugins/soleur/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md kb aesthetic-direction kb-mobile-drill-in "$(date -u +%F)"`
- [ ] 0.5 `gh issue edit 7186 --milestone "Phase 4: Validate + Scale"`

## Phase 1 — RED (`cq-write-failing-tests-before`)

- [ ] 1.1 `apps/web-platform/test/kb-layout.test.tsx` — generalise "does not render FileTree twice"
      into the full matrix: `{desktop, mobile} × {/dashboard/kb, /dashboard/kb/<path>} ×
      {populated, empty}` + a desktop↔mobile mock flip. Assert length **=== 1** *and which host*
      (inside `rail-secondary-slot` or not). Use the settable module mock from
      `test/kb-layout-panels.test.tsx:15-17`
- [ ] 1.2 `apps/web-platform/test/kb-mobile-browse.test.tsx` (new) — written against
      `app/(dashboard)/dashboard/kb/layout.tsx`, **not** an unwritten component (otherwise it fails
      as a module-resolution error). Cases: mobile+populated+landing → tree in content column, rail
      slot empty; mobile+populated+doc → document, no tree; mobile+empty → unchanged `fullWidth`
      body, tree still in rail; search query survives landing → doc → landing
- [ ] 1.3 `apps/web-platform/e2e/nav-states-shell.e2e.ts` — extend the desktop block (`:418`/`:419`)
      and the mobile block (`:911`/`:912`). `DESKTOP = 1280×900` (`:383`), `MOBILE = 390×844`
      (`:384`). Arms: 1280×900 populated; 390×844 populated; 390×844 **empty** (fixture at
      `:948-953`); the 390×844 drill-in round trip with no full reload; 768×1024 per DC1
- [ ] 1.4 Run all three; confirm each fails on an **assertion**, not an import

## Phase 2 — GREEN

- [ ] 2.1 `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — add optional `inRail = true`;
      `const collapsed = useRailCollapsed() && inRail` (with the `RailCollapsedProvider`-wraps-
      `<main>` comment, `app/(dashboard)/layout.tsx:295`–`:735`); switch wrapper `data-testid`
      between `kb-rail-tree` / `kb-browse-tree`; keep `data-tour-id="action:kb-tree"` on that same
      wrapper; move `KbErrorBoundary` **inside** so both hosts inherit it
- [ ] 2.2 `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — portal becomes
      `<RailSlotPortal>{isDesktop || fullWidth ? <KbSidebarShell /> : null}</RailSlotPortal>`, with
      the D1-reason-2 comment (the slot is null until its ref callback fires, so this is never
      server-rendered). **Change nothing else in this file** — the `fullWidth` block stays
      byte-for-byte identical (AC3)
- [ ] 2.3 `apps/web-platform/components/kb/kb-mobile-layout.tsx` — branch the content column:
      `isContentView ? <KbDocShell isContentView>{children}</KbDocShell> : <KbSidebarShell inRail={false} />`.
      Correct the ADR-047 comment at `:30-33`. Apply the DC1 outcome **on the populated view only**
- [ ] 2.4 `apps/web-platform/components/kb/kb-doc-shell.tsx` — delete the `md:hidden` stopgap
      (`:32-48`) and its `RAIL_EXPAND_EVENT` import; keep `DesktopPlaceholder`
- [ ] 2.5 `apps/web-platform/app/(dashboard)/layout.tsx` — remove the dead `inKbDocView` (`:229`)
      and the comment asserting a doc-view back-suppression that does not happen. Add the DC2 row
      here only if the operator asked for it
- [ ] 2.6 Lift the search query into `hooks/use-kb-layout-state.tsx` and read it from
      `components/kb/search-overlay.tsx`. Per `hr-type-widening-cross-consumer-grep`, update the
      typed literal `function makeState(): UseKbLayoutStateResult` at
      `test/components/kb/kb-reconnect-banner.test.tsx:51-75` in the same commit — this breaks
      **`tsc`, not any test**
- [ ] 2.7 Re-check the `RAIL_EXPAND_EVENT` census after 2.4: dispatchers are `kb-sidebar-shell.tsx`
      (desktop collapsed rail) and `components/tour/tour-provider.tsx`; the sole listener stays
      `app/(dashboard)/layout.tsx:246-263`. Do **not** remove the event

## Phase 3 — Reconcile existing tests (each change enumerated in the PR body)

- [ ] 3.1 `test/kb-sidebar-collapse.test.tsx` — split into a desktop arm (`mockIsDesktop = true`)
      re-asserting every ADR-047 rail contract, and a mobile arm asserting the empty-tree path still
      portals into the rail. No `react-resizable-panels` mock needed
- [ ] 3.2 `test/kb-layout.test.tsx` — the `#4915` landing-header case changes **only** under DC1
      option (a); if so, record in the PR body that the original assertion encoded a false premise
- [ ] 3.3 `e2e/nav-states-shell.e2e.ts:948` — verify the single `/back to menu/i` assertion on the
      mobile empty-tree landing stays green; it is the one e2e assertion DC1 can reach
- [ ] 3.4 `test/components/kb/kb-reconnect-banner.test.tsx` — `makeState()` gains the search-query
      field; pin the `usePathname` mock to a document route (or add a landing arm)
- [ ] 3.5 `test/kb-tree-scroll-resume.test.tsx` — add a mobile arm for the content-column host

## Phase 4 — ADR + docs

- [ ] 4.1 Create
      `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-mounts-by-breakpoint.md`
      — one decision clause, two seriously-weighed alternatives, and the two structural safety facts
      (no JS-gated DOM in the `fullWidth` block; `RailSlotPortal` null until its ref callback)
- [ ] 4.2 Amend `ADR-047-nav-context-band-outside-swap.md` — `md+` qualifier on Decision 2;
      `related_adrs += ADR-158`. Do not touch its rejected-alternatives table
- [ ] 4.3 No `.c4` edit → do **not** run `scripts/regenerate-c4-model.sh`
- [ ] 4.4 If `/ship` renumbers ADR-158, sweep
      `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-7186-kb-mobile-drill-in-nav/`
      plus the plan body and AC8 in the same edit

## Phase 5 — Verification

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (catches 2.6)
- [ ] 5.2 Run the canonical suite list — the `discoverability_test.command` in the plan's
      `## Observability` block (single source of truth; do not maintain a second list)
- [ ] 5.3 `bash scripts/test-all.sh` — **read per-suite lines, not the summary count**
- [ ] 5.4 `/soleur:qa` — the ADR-049 headless-Chromium nav-states gate (mandatory: the diff touches
      `app/(dashboard)/**` and a `layout.tsx`)
- [ ] 5.5 Post-deploy prod device-mode on `https://app.soleur.ai` at desktop, **exactly 768px**, and
      mobile. Attempt via Playwright MCP first (`automation-status: UNVERIFIED`)

## Phase 6 — Deferrals

- [ ] 6.1 File tracking issues for Non-Goals #1–#14. Three are the most likely scope-creep magnets
      at `/work` and must be filed, not fixed: **#3** sync fails silently
      (`kb-sync-status.tsx:36` accepts `onError`, neither caller passes it), **#4** search failure
      shows stale results and swallows its catch (`search-overlay.tsx:25/29/33`), **#6** the
      document route's loading/error branches render no back at all
      (`[...path]/page.tsx:130,:161`) — file #6 at `priority/p2-medium` or above
- [ ] 6.2 Note in the PR body that Non-Goal #6 is a real mobile dead end this plan does not fix

---

## Guardrails (read before starting)

- **Exactly one file-tree instance at any breakpoint.** No CSS `hidden md:flex` / `md:hidden`
  dual-render of the tree — ADR-047 rejects it and PR #6874 shipped the regression (12 broken tests
  + hidden-component effects on desktop).
- **Do not touch `hooks/use-media-query.ts`.** The seed idea was a provable client-side no-op and
  would have created a hydration mismatch (plan D1 / Revision R2).
- **Do not add JS-gated DOM to the `fullWidth` block** in `kb/layout.tsx` — that is the single most
  likely way to get this wrong, and AC3 pins it.
- **Do not introduce a bare `pathname.startsWith("/dashboard/kb")`** — `test/nav-drill-authority.test.ts`
  fails the build on it. Nothing here needs `pathname`.
- **Grep `app/globals.css` for every `soleur-*` token before use** — a wrong token is a silent
  no-op, no `tsc` error, no test failure.
- **Do not open** `knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen`
  (destructive-open bug #3274).

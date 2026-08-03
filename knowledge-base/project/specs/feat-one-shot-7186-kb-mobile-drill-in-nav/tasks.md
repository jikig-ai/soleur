# Tasks — fix(kb): mobile drill-in navigation for the Knowledge Base

**Issue:** #7186
**Plan:** `knowledge-base/project/plans/2026-08-03-fix-kb-mobile-drill-in-navigation-plan.md` (**v3**, post-deepen)
**Branch:** `feat-one-shot-7186-kb-mobile-drill-in-nav`
**Lane:** `cross-domain` (no `spec.md` — fail-closed default)
**Brand-survival threshold:** `single-user incident`

All paths below are relative to the repo root unless prefixed. Test/typecheck commands run from
`apps/web-platform` — **never** `bun test`, **never** `npm run -w`.

---

## Phase 0 — Wireframe + operator sign-off 🚧 BLOCKING

No product code until 0.4 closes (`wg-ui-feature-requires-pen-wireframe`).

- [x] 0.1 `.pen` + 8 frames (`29-`…`36-`) produced and committed (`15ac70b19`)
- [~] 0.2 ~~768px tablet frame as `37-*.png`~~ — **WAIVED** with reason recorded in
      `decision-challenges.md`: operator signed off on the eight committed frames, and the 768px
      switch point is pinned behaviourally by the unconditional `768×1024` e2e arm (task 1.3), which
      is stronger than a static frame
- [x] 0.3 Five design questions surfaced (DC1–DC5) in `decision-challenges.md`
- [x] 0.4 **Operator sign-off gate — CLOSED 2026-08-03.** Screenshots dir opened via `xdg-open`;
      operator answered DC1(a) / DC2 default / DC3 overflow-menu-this-PR. DC4 deferred to its own
      issue; DC5 resolved by code verification (not a taste call). Resolutions table is in
      `decision-challenges.md`. Still to run on this approval:
      `bash plugins/soleur/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md kb aesthetic-direction kb-mobile-drill-in "$(date -u +%F)"`
- [x] 0.5 `gh issue edit 7186 --milestone "Phase 4: Validate + Scale"`

## Phase 1 — RED (`cq-write-failing-tests-before`)

- [x] 1.1 `apps/web-platform/test/kb-layout.test.tsx` — `it.each` **host table** (6 cells, not 8):
      `(isDesktop, pathname, fixture, expectedHost)` per the plan's AC2 table. Assert the host by
      **containment** — `expect(slot).toContainElement(nav)` / `.not.toContainElement(nav)` against
      `rail-slot-harness`, where `nav` is the `role="navigation"` node — **never** by a wrapper
      testid (`kb-rail-tree` renders even when the tree is DOM-removed). Plus a desktop↔mobile flip
      driven by RTL `rerender()` on the **same tree** (a fresh `render()` makes it vacuous). Reset
      `mockIsDesktop`/`mockPathname` in `beforeEach`. **No in-repo test has ever flipped this mock
      to `false` mid-render** — write it deliberately
- [x] 1.1b `apps/web-platform/test/kb-sidebar-shell-host.test.tsx` (new, component-level) — the RED
      for the `host` guard: `host="content"` → `kb-browse-tree`; `host="content"` under
      `<RailSlotHarness collapsed>` → still renders `SearchOverlay` + `FileTree` and **not**
      `kb-rail-collapsed-expand`; default `host` → `kb-rail-tree` with collapse honoured
- [x] 1.2 `apps/web-platform/test/kb-mobile-browse.test.tsx` (new) — written against
      `app/(dashboard)/dashboard/kb/layout.tsx`, **not** an unwritten component. Cases:
      mobile+populated+landing → tree in content column **and** the rail slot holds no
      `role="navigation"` named /knowledge base file tree/ (**this is where AC6 lives** — it is
      vacuous in `nav-rail-drill.test.tsx`, which never renders `KbLayout`);
      mobile+populated+doc → document, **tree back in the rail slot**; mobile+empty → unchanged
      `fullWidth` body, tree in rail; **`fullWidth` viewport-invariance** (identical `innerHTML` at
      both `mockIsDesktop` values — the behavioural form of AC3); **stopgap gone** +
      `DesktopPlaceholder` still on the desktop landing; **`KbErrorBoundary`** (throwing `FileTree`
      → fallback at BOTH hosts); **search query survives** landing → doc → landing (mutate
      `mockPathname` + `rerender()`, mock `/api/kb/search`, assert `findByDisplayValue`); DD1(a)
      back affordance if the operator picks it
- [x] 1.3 `apps/web-platform/e2e/nav-states-shell.e2e.ts` — extend the desktop block (`:418`/`:419`)
      and the mobile block (`:911`/`:912`). `DESKTOP = 1280×900` (`:383`), `MOBILE = 390×844`
      (`:384`). Assert host by containment via the existing `secondarySlot(page)` locator (`:400`).
      Arms: 1280×900 populated; 390×844 populated landing; 390×844 populated **doc route** (tree
      back in the slot); 390×844 **empty** (fixture at `:948-953`); the drill-in round trip using a
      `window.__kbNoReload` **sentinel** (NOT `page.on("framenavigated")`, which fires on correct
      SPA navs); **drawer-opened-during-fetch** (D3's transition); and **768×1024 UNCONDITIONALLY**
      — the only test anywhere that exercises the real `(min-width: 768px)` literal
- [x] 1.3b `apps/web-platform/test/kb-content-header.test.tsx` (new or extend if present) — RED for
      DC3 (task 2.8). Mobile arm (`useIsMobile` → `true`): Download, sync status, and Share are NOT
      in the header's own action row, ARE reachable after activating the `⋯` trigger, and exactly
      ONE `kb-content-download` node exists in the tree (the single-mount assertion — a `md:hidden`
      twin would make this two). Desktop arm: today's inline cluster, unchanged. Plus Escape and
      outside-pointerdown both close the menu and restore focus to the trigger
- [x] 1.4 Run all five; confirm each fails on an **assertion**, not an import

## Phase 2 — GREEN

- [x] 2.0 `apps/web-platform/hooks/use-kb-layout-state.tsx` — **D5, do this first.** Move
      `fullWidth` in from `kb/layout.tsx:37` and derive
      `const treeHost: "rail" | "content" = !isDesktop && !fullWidth && !isContentView ? "content" : "rail"`.
      Export both. This is what makes the single-host property structural instead of emergent
- [x] 2.1 `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — add optional
      `host?: "rail" | "content"` (a **named host, not a boolean**);
      `const collapsed = useRailCollapsed() && host === "rail"`, carrying the comment that the
      provider **cannot** be narrowed instead (it wraps `<main>` at
      `app/(dashboard)/layout.tsx:295`–`:735` and must, because the portaled shell reads context
      through the REACT tree — narrowing it would break ADR-047 Decision 2). Switch wrapper
      `data-testid` between `kb-rail-tree` / `kb-browse-tree`; keep `data-tour-id="action:kb-tree"`
      on that same wrapper; move `KbErrorBoundary` **inside** so both hosts inherit it
- [x] 2.2 `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — portal becomes
      `<RailSlotPortal>{treeHost === "rail" ? <KbSidebarShell /> : null}</RailSlotPortal>`, with
      the D1-reason-2 comment (the slot is null until its ref callback fires, so this is never
      server-rendered); `fullWidth` is now read from the hook. **Change nothing else in this file**
      — the `fullWidth` JSX block stays byte-for-byte identical (AC3)
- [x] 2.3 `apps/web-platform/components/kb/kb-mobile-layout.tsx` — branch on the same one value:
      `treeHost === "content" ? <KbSidebarShell host="content" /> : <KbDocShell isContentView>{children}</KbDocShell>`.
      Correct the ADR-047 comment at `:30-33`. Apply the DC1 outcome **on the populated view only**
- [x] 2.4 `apps/web-platform/components/kb/kb-doc-shell.tsx` — delete the `md:hidden` stopgap
      (`:32-48`) and its `RAIL_EXPAND_EVENT` import; keep `DesktopPlaceholder`
- [x] 2.5 `apps/web-platform/app/(dashboard)/layout.tsx` — remove the dead `inKbDocView` (`:229`)
      and the comment asserting a doc-view back-suppression that does not happen. Add the DC2 row
      here only if the operator asked for it
- [x] 2.6 Persist the search query through **`hooks/use-nav-resume.ts`** (add
      `readSearchQuery`/`writeSearchQuery`), NOT `useKbLayoutState` — that hook already owns the
      query's two siblings (`readExpanded`/`writeExpanded`, `readScrollTop`/`writeScrollTop`), and
      routing it there avoids widening `UseKbLayoutStateResult` at all. `SearchOverlay` seeds its
      `useState` from it and writes on change; **reset on workspace change** so it does not leak
      between workspaces. Note seeding is one frame late (`useNavResume` gates reads on
      `workspaceId`) — same as `expanded` already behaves
- [x] 2.7 Re-check the `RAIL_EXPAND_EVENT` census after 2.4: dispatchers are `kb-sidebar-shell.tsx`
      (desktop collapsed rail) and `components/tour/tour-provider.tsx`; the sole listener stays
      `app/(dashboard)/layout.tsx:246-263`. Do **not** remove the event
- [x] 2.8 **DC3 — mobile doc-header overflow (operator-approved scope addition).**
      `apps/web-platform/components/kb/kb-content-header.tsx` (`:64-109`): below `md`, the trailing
      cluster becomes `KbChatTrigger` + a `⋯` overflow button whose menu holds **Download**
      (`:65-103`), **`KbSyncStatus`** (`:104-106`), and **`SharePopover`** (`:107`). Desktop
      (`md+`) renders today's inline cluster, byte-for-byte unchanged.
      - **Operator chose an anchored overflow MENU, not a bottom sheet** — do not substitute
        `ResponsiveModal`/`Sheet`.
      - **Single-mount, same as the tree.** Gate on `hooks/use-is-mobile.ts` (SSR-safe `false` seed,
        flips after mount) and render ONE cluster — never `hidden md:flex` / `md:hidden` twins of
        `SharePopover` or `KbSyncStatus`, both of which own state and fetches.
      - `SharePopover` is *moved into* the menu, not wrapped twice; its own popover
        (`share-popover.tsx:174`, `absolute right-0 top-full`) must still be reachable and not clip
        inside the overflow container.
      - a11y: trigger is `aria-haspopup="menu"` + `aria-expanded`, ≥44px; menu dismisses on Escape
        **and** outside-pointerdown with focus restored to the trigger (`SharePopover` currently
        implements neither — do not copy that gap forward).
- [x] 2.9 Grep every `KbContentHeader` consumer before changing its render shape
      (`hr-type-widening-cross-consumer-grep`): `grep -rn "KbContentHeader" apps/web-platform`.
      Props are unchanged by 2.8, so this is a render-shape check, not a type check

## Phase 3 — Reconcile existing tests (each change enumerated in the PR body)

- [x] 3.1 `test/kb-sidebar-collapse.test.tsx` — split into a desktop arm (`mockIsDesktop = true`)
      re-asserting every ADR-047 rail contract, and a mobile arm asserting the empty-tree path still
      portals into the rail. No `react-resizable-panels` mock needed
- [ ] 3.2 ~~`test/kb-layout.test.tsx` `#4915` landing-header case~~ — **no change needed.** That
      case uses `EMPTY_TREE_FETCH()` → `fullWidth`, a block DC1(a) is forbidden to touch (DC1(a) is
      constrained to the *populated* browse view), so the two cannot meet. Deleted as a phantom
      reconciliation; do not "fix" it
- [ ] 3.3 `e2e/nav-states-shell.e2e.ts:948` — verify the single `/back to menu/i` assertion on the
      mobile empty-tree landing stays green; it is the one e2e assertion DC1 can reach
- [x] 3.4 `test/components/kb/kb-reconnect-banner.test.tsx` — `makeState()` gains `treeHost` +
      `fullWidth` from 2.0 — a **`tsc`-only** failure, invisible to vitest
      (`hr-type-widening-cross-consumer-grep`). The v2 search-query field edit is **gone** (2.6 no
      longer widens the interface). Also pin the `usePathname` mock to a document route, or add a
      landing arm, so the `KbMobileLayout` arm still exercises the banner
- [x] 3.5 `test/kb-tree-scroll-resume.test.tsx` — add a mobile arm for the content-column host

## Phase 4 — ADR + docs

- [x] 4.1 Create
      `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-mounts-by-breakpoint.md`
      — one decision clause, two seriously-weighed alternatives, and the two structural safety facts
      (no JS-gated DOM in the `fullWidth` block; `RailSlotPortal` null until its ref callback)
- [x] 4.2 Amend `ADR-047-nav-context-band-outside-swap.md` as a **dated append-only
      `## Amendment` section** (the file already carries a 2026-06-22 one) — do NOT edit Decision 2
      in place, and do NOT use the `md+` qualifier v2 proposed: the portal is live *below* `md` in
      every non-populated state, so the breakpoint is not the discriminator. Use the scoped
      exception clause quoted in the plan's ADR section. `related_adrs += ADR-158`. Do not touch the
      rejected-alternatives table
- [x] 4.3 No `.c4` edit → do **not** run `scripts/regenerate-c4-model.sh`
- [ ] 4.4 If `/ship` renumbers ADR-158, sweep
      `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-7186-kb-mobile-drill-in-nav/`
      plus the plan body and AC8 in the same edit

## Phase 5 — Verification

- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (catches 2.6)
- [x] 5.2 Run the canonical suite list — the `discoverability_test.command` in the plan's
      `## Observability` block (single source of truth; do not maintain a second list)
- [x] 5.3 `bash scripts/test-all.sh` — **read per-suite lines, not the summary count**
- [ ] 5.4 `/soleur:qa` — the ADR-049 headless-Chromium nav-states gate (mandatory: the diff touches
      `app/(dashboard)/**` and a `layout.tsx`)
- [ ] 5.5 Post-deploy prod device-mode on `https://app.soleur.ai` at desktop, **exactly 768px**, and
      mobile. Attempt via Playwright MCP first (`automation-status: UNVERIFIED`)

## Phase 6 — Deferrals

- [x] 6.1 File tracking issues for Non-Goals #1–#14. Three are the most likely scope-creep magnets
      at `/work` and must be filed, not fixed: **#3** sync fails silently
      (`kb-sync-status.tsx:36` accepts `onError`, neither caller passes it), **#4** search failure
      shows stale results and swallows its catch (`search-overlay.tsx:25/29/33`), **#6** the
      document route's loading/error branches render no back at all
      (`[...path]/page.tsx:130,:161`) — file #6 at `priority/p2-medium` or above
- [ ] 6.2 Note in the PR body that Non-Goal #6 is a real mobile dead end this plan does not fix
- [x] 6.3 **DC4** — file a `domain/marketing` issue for the brand-guide contradiction: the guide says
      "Sharp (0px border-radius)… No rounded corners" while the shipped dashboard surface and all
      nine committed navigation wireframes use 8–10px. Resolution is a brand-guide edit (or a
      surface change), owned by the CMO domain — not this PR

---

## Guardrails (read before starting)

- **Exactly one file-tree instance at any breakpoint.** No CSS `hidden md:flex` / `md:hidden`
  dual-render of the tree — ADR-047 rejects it and PR #6874 shipped the regression (12 broken tests
  + hidden-component effects on desktop).
- **Do not touch `hooks/use-media-query.ts`.** The seed idea was a provable client-side no-op and
  would have created a hydration mismatch (plan D1 / Revision R2).
- **Do not add JS-gated DOM to the `fullWidth` block** in `kb/layout.tsx` — that is the single most
  likely way to get this wrong, and AC3 pins it behaviourally (identical `innerHTML` at both
  viewports). Note a production hydration mismatch there would be **invisible**: React does not
  reconcile className mismatches in production builds, only logging a dev-only error.
- **Derive the host ONCE (`treeHost`, 2.0) and consume it in both places.** Do not write two
  conditions that happen to agree — that is what v2 did, and it produced both an AC that was false
  on a correct implementation and a silently deleted capability.
- **Assert the host by containment, never by a wrapper testid.** `kb-rail-tree` renders even when
  the tree is DOM-removed (`kb-sidebar-shell.tsx:107`, outside the `collapsed ?` ternary), and a
  testid the component emits about its own placement will agree with a mis-placement bug.
- **Do NOT widen `UseKbLayoutStateResult` for the search query** — use `useNavResume` (2.6).
- **Three P1/P2 defects are deliberately OUT of scope**: silent "Sync now" failure, silent search
  failure, and the document route's headerless loading/error branches. They are real, they are
  pre-existing, and they are the most tempting scope-creep magnets in this diff. File them (6.1);
  do not fix them here.
- **Do not introduce a bare `pathname.startsWith("/dashboard/kb")`** — `test/nav-drill-authority.test.ts`
  fails the build on it. Nothing here needs `pathname`.
- **Grep `app/globals.css` for every `soleur-*` token before use** — a wrong token is a silent
  no-op, no `tsc` error, no test failure.
- **Do not open** `knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen`
  (destructive-open bug #3274).

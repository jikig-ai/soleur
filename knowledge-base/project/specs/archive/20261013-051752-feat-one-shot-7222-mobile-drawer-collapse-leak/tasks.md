# Tasks — feat-one-shot-7222-mobile-drawer-collapse-leak

Derived from
[`knowledge-base/project/plans/2026-08-03-fix-mobile-drawer-collapse-leak-plan.md`](../../plans/2026-08-03-fix-mobile-drawer-collapse-leak-plan.md)
after 8-reviewer plan review. Read the plan's **Implementer's summary** first.

**Line numbers in the plan shift** once task 2.2 lands (~15 inserted lines near
`:145`). Use content anchors, not the plan's numbers, for anything after that.

---

## Phase 1 — Baseline + unblock the local e2e loop

- [ ] **1.1** Fix the dev server (closes #3562). In `apps/web-platform/package.json`,
      prefix the `dev` script with
      `mkdir -p .next && printf '{"type": "commonjs"}' > .next/package.json && …`.
      Verify: `rm -rf .next && npm run dev` reaches `Server ready`.
      **Do not** move `instrumentation.ts` aside — it is tracked, so `git commit -am`
      stages it as a deletion, and losing `onRequestError` in prod is silent.
- [ ] **1.2** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — record green.
- [ ] **1.3** `cd apps/web-platform && npm run test:ci` — record the baseline count.

## Phase 2 — Core: scope collapse to the desktop rail

- [ ] **2.1 (RED)** Create `apps/web-platform/test/rail-collapse-viewport-scope.test.tsx`.
      Must assert **both** viewport arms and use the task-2.6 helper. Comment it as
      fast local signal, not the proof.
- [ ] **2.2 (GREEN)** In `app/(dashboard)/layout.tsx`, next to the `useSidebarCollapse`
      call, add `MD_QUERY = "(min-width: 768px)"` (exactly Tailwind's `md:` literal),
      an `isDesktop` via `useSyncExternalStore(subscribe, () => matchMedia(MD_QUERY).matches, () => false)`,
      and `const railCollapsed = collapsed && isDesktop;`. Copy the plan's comment
      block verbatim — it pins the dead-band, stuck-false and short-circuit reasoning.
- [ ] **2.3** Swap to `railCollapsed`: the `RailCollapsedProvider` value; the nav
      `px-1`/`px-3`; **all four** `NavBadge collapsed={…}` props; the footer
      `p-1`/`p-3`; the `userEmail && !collapsed` gate; the theme-toggle wrapper
      padding; the `ThemeToggle` prop. Optional/cosmetic: the five
      `title={collapsed ? … : undefined}` attrs.
- [ ] **2.4** Leave raw `collapsed` on every `md:`-scoped site, and add the two
      in-file `// raw collapsed ON PURPOSE — the breakpoint decision stays in CSS
      (PR #4871, #7222). Do NOT route through railCollapsed.` comments above
      `md:w-14`/`md:w-56` and above `kbExpanded`/`mainExpanded`.
- [ ] **2.5** In the `RAIL_EXPAND_EVENT` handler keep **both** reads imperative:
      `const desktop = window.matchMedia("(min-width: 768px)").matches;`
      then `if (desktop && collapsed) toggleCollapsed();` and
      `if (!desktop) setDrawerOpen(true);`. **No dep-array change, no React state**
      — a state-based handler closes over the seeded value and breaks the mobile tour.
- [ ] **2.6** Create `apps/web-platform/test/helpers/match-media.ts` exporting
      `installMatchMedia({ viewport, colorScheme })` — **two axes**; a viewport-only
      stub silently flips the theme in `ThemeProvider`-wrapping tests. Wire into the
      5 layout-rendering tests: `dashboard-sidebar-collapse`,
      `dashboard-layout-sidebar-settings`, `dashboard-layout-signout`,
      `dashboard-layout-inbox-badge`, `nav-rail-drill`. Leave the other 11 alone.
- [ ] **2.6b** Update `dashboard-sidebar-collapse.test.tsx` "adds title attributes
      when collapsed" / "does not show title attributes when expanded" to drive the
      desktop arm — they probe the `title=` sites task 2.3 rewrites.
- [ ] **2.7** Update the contract docs the change falsifies:
      `components/dashboard/rail-slot.tsx` docstring (new meaning + the provider
      spans `<main>` + no consumer may re-derive the viewport term);
      `test/helpers/rail-slot-harness.tsx` docstring (rename the prop
      `railCollapsed`); `components/kb/kb-sidebar-shell.tsx` comment — **the guard
      expression itself stays byte-identical** (DC-1).
- [ ] **2.8** Pin the short-circuit invariant at the line that would violate it: a
      comment at `hooks/use-sidebar-collapse.ts` `useState(false)`, plus a vitest
      case asserting first render is `false` with `localStorage` pre-set to `"1"`.

## Phase 3 — Restore the drawer back gold

- [ ] **3.1** In `app/(dashboard)/layout.tsx`, on the `drawer-back-to-menu`
      `className`: `text-soleur-text-muted` → `text-soleur-accent-gold-fg` and
      `hover:text-soleur-text-secondary` → `hover:text-soleur-text-primary`. Keep
      every other class. **No separator** — DC-2 records the mitigations; the device
      check decides.
- [ ] **3.2** Do **not** touch `components/kb/kb-mobile-page-header.tsx` (deferred to
      #7201, task 5.6).

## Phase 4 — Two mobile KB defaults (structural half deferred)

- [ ] **4.1** `hooks/use-kb-layout-state.tsx` — seed `embeddedConciergeOpen` `false`
      when the viewport is mobile.
- [ ] **4.2** `components/kb/kb-mobile-layout.tsx` — gate `KbChatSidebar` on
      `state.showChat` instead of `chatCtxValue.enabled && contextPath`, matching
      `kb-desktop-layout.tsx`. Closes the double-`ChatSurface` draft-loss path.

## Phase 5 — Touch target

- [ ] **5.1** `components/theme/theme-toggle.tsx` — the expanded `role="group"` is
      `h-8` (32px) while the collapsed button is `min-h-[44px]`. Use `h-11 md:h-8`
      and `h-4 w-4 md:h-3 md:w-3` so restoring it on mobile does not shrink the
      target below 44px. Desktop renders byte-identical.

## Phase 6 — E2E

- [ ] **6.1** Extend `apps/web-platform/e2e/nav-states-shell.e2e.ts` with two
      `describe` blocks (one mobile, one desktop). **Reuse** the file's existing
      `seedCollapsed`, `MOBILE`, `DESKTOP`, `setupNavMocks`, `gotoOrSkip`,
      `routeEmptyKbTree`, `secondarySlot` — redeclaring is a duplicate-implementation
      error.
- [ ] **6.2** T1 `/dashboard/settings` @390 — **visible text** `General` (not
      role+name: `aria-label` supplies the same name in both states);
      `settings-rail-icons` count 0; `drawer-back-to-menu` colour == `nav-back-chevron`
      colour (both measurable at 390 — the desktop band is `display:none`, not
      unmounted); hover class present; light-theme contrast reported.
- [ ] **6.3** T2 `/dashboard` @390 — theme group has 3 buttons **and height ≥44px**;
      `theme-cycle-button` count 0; email row present; `inbox-nav-badge-dot` and
      `releases-nav-badge-dot` resolve.
- [ ] **6.4** T3 KB **document** route @390 — `secondarySlot` contains
      `kb-tree-scrollport`; `kb-rail-collapsed-expand` count 0. **Not** the populated
      landing: `treeHost === "content"` there and the existing gate already pins the
      rail slot empty.
- [ ] **6.5** T4 `/dashboard/kb` empty @390 — `kb-rail-empty` **and** the `Sync now`
      control both reachable in the drawer.
- [ ] **6.6** T5 `/dashboard/chat` @390 — assert **containment**
      (`secondarySlot` → "Recent conversations", "New conversation"), never the
      wrapper testid, which mounts unconditionally.
- [ ] **6.7** T6 `/dashboard` @390 — dispatch `RAIL_EXPAND_EVENT`; the drawer opens
      **and** `localStorage["soleur:sidebar.main.collapsed"]` is still `"1"`.
- [ ] **6.8** T7 `/dashboard/settings` @1280 — `settings-rail-icons` count 1 and
      `theme-cycle-button` count 1. **The anti-regression gate.**

## Phase 7 — Records, tracker, ship

- [ ] **7.1** Amend `ADR-047-nav-context-band-outside-swap.md` with the full
      `useRailCollapsed` contract (collapse is md+-only; the value is viewport-aware;
      no consumer may re-derive the viewport term; the provider spans `<main>`).
- [ ] **7.2** Amend `ADR-158-kb-file-tree-host-is-a-derived-value.md` narrowly —
      correct its stale corollary and record DC-1's retention rationale. **No new ADR.**
- [ ] **7.3** Verify the full suite: `tsc --noEmit`, `npm run test:ci`,
      `npx playwright test e2e/nav-states-shell.e2e.ts --grep 7222`.
- [ ] **7.4** PR body: `Ref #7222` (**not** `Closes`) and `Closes #3562`.
- [ ] **7.5** Tick #7201's collapse-leak checklist item; link this PR.
- [ ] **7.6** Amend #7222's `priority/p2-medium` rationale — strike "workaround
      exists", keep the P2 number.
- [ ] **7.7** File **before merge**: the C follow-up (branch-qualified `.pen` path,
      and `screenshots/05-decisions-and-deltas.png` as the authoritative decision
      list); one combined "one breakpoint authority for viewport-gated render
      branches" issue (size: medium, regression risk — `useMediaQuery` is live in 4
      files; folds in the `768`-literal item); the closed-drawer `inert` gap; the
      light-theme gold-token contrast fix; and the `kb-mobile-page-header` duplicate
      back-affordance question routed to **#7201**.

---

## Definition of done

All 18 acceptance criteria in the plan pass, with the three gates green: **AC3**
(the CSS-scoped sites still read raw `collapsed`), **AC5** (mobile, seeded — the fix
works), **AC7** (desktop, seeded — collapse still works).

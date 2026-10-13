# Decision challenges — feat-one-shot-7186-kb-mobile-drill-in-nav

Persisted in headless mode (no TTY / one-shot pipeline), per `plan` §Plan Review and ADR-084.
`/ship` renders these into the PR body and files them as an `action-required` issue.

Each item below is a **taste** or **user-challenge** decision that the pipeline deliberately did
NOT resolve unilaterally. The plan records a recommendation for each; none has been applied as if
approved.

---

## RESOLVED — operator sign-off 2026-08-03 (Phase 0.4 gate CLOSED)

| # | Resolution | Source |
|---|---|---|
| DC1 | **Option (a) — follow the wireframe.** Back arrow on the *populated* mobile browse view only; never in the shared `fullWidth` block. The `#4915` assertion is updated as a false-premise correction. | operator |
| DC2 | **Default — empty secondary slot on mobile.** No "Browse files" row in the drawer. | operator |
| DC3 | **Overflow menu, in this PR.** Mobile doc header keeps back + breadcrumb + Ask; Download, `KbSyncStatus`, and `SharePopover` move behind a `⋯` overflow. No capability dropped. Adds scope to `kb-content-header.tsx` (previously untouched by this plan). | operator |
| DC4 | **Deferred — not this PR.** Brand-guide vs shipped-surface radius contradiction is a brand-guide edit; filed as its own issue at Phase 6. Wireframes keep 8–10px to match the shipped dashboard and the eight sibling wireframes. | pipeline, per DC4's own "not blocking this PR" |
| DC5 | **Verified, not a choice — global bar is NOT suppressed on KB routes.** `app/(dashboard)/layout.tsx:320-334` renders the `md:hidden` top bar (hamburger-left, `MobilePaletteTrigger`-right) unconditionally for every dashboard route. The plan's assumption holds; the mobile ⌘K trigger survives on KB. | verified in code, no operator input needed |

### CORRECTION to DC1's premise (post-review, 2026-08-03)

The premise put to the operator — *"the mobile KB landing has no reachable in-page back at all
today"* — was **wrong**, and the operator approved DC1(a) on it. Multi-agent review found a FOURTH
back-renderer that neither the plan nor the wireframe pass counted: `drawer-back-to-menu` in
`app/(dashboard)/layout.tsx`, an `md:hidden` "Back to menu" → `/dashboard` rendered on every
drilled route. The drawer `<aside>` is translated off-canvas — not unmounted, not `inert` — so
that link is in the accessibility tree in the state the premise called empty.

What this does and does not change:

- **It does not invalidate the decision.** The drawer back is behind a hamburger tap; an in-page
  back on the browse view is still the better affordance, and the wireframe the operator signed
  off on is unaffected.
- **It does add a consequence the operator was not told about:** the populated mobile landing now
  renders TWO links with the same accessible name and the same href. Not visually simultaneous
  (one is off-canvas), but identical to a screen reader and to any composition-scoped query.
- The unit assertion that appeared to guard this (`kb-mobile-browse.test.tsx`) renders `KbLayout`
  without `DashboardLayout`, so it was structurally incapable of seeing the second link. The real
  count is now asserted at the composition root in the 390x844 e2e arm, and the durable fix
  (making the closed drawer `inert`) is filed as a follow-up.

Recorded here rather than quietly fixed, because the operator's approval rested on the false half.

---

**Waived:** task 0.2 (a 9th `37-*` wireframe frame at the 768px switch point). The operator signed off
on the eight committed frames, and the 768px switch is pinned behaviourally by the unconditional
`768×1024` e2e arm in task 1.3 — which is stronger evidence than a static frame. Recorded here rather
than silently dropped.

---

## DC1 — Who owns "back" on the mobile KB browse view (taste, design)

**Class:** taste — blocks Phase 1.

The wireframe (`knowledge-base/product/design/navigation/kb-mobile-drill-in-nav.pen`, frame
`29-kb-mobile-browse-populated.png`) gives the browse view a header with a back arrow to
`/dashboard`. The shipped `#4915` contract, asserted in `apps/web-platform/test/kb-layout.test.tsx`,
says the KB landing header *omits* the back "because the persistent band owns it".

**Verified finding:** that contract's premise is factually false on mobile. `inKbDocView` at
`apps/web-platform/app/(dashboard)/layout.tsx:229` is computed and never used, and the mobile band
at `:403-410` is `suppressBack` unconditionally *inside the drawer* — so the mobile KB landing has
no reachable in-page back at all today.

- **Option (a) — recommended:** follow the wireframe. Updating the `#4915` assertion is then a
  correction of a false premise, not a weakening. **Constraint:** the arrow may go only on the
  *populated* browse view, never in the shared `fullWidth` block (that would reintroduce
  JS-gated first-paint DOM, and would break `e2e/nav-states-shell.e2e.ts:948`).
- **Option (b):** keep the shipped contract — no in-page back on the landing.

---

## DC2 — Does the mobile drawer keep a "Browse files" row? (taste, design)

**Class:** taste.

Wireframe frame `34-kb-mobile-drawer-no-tree.png` shows a "Browse files" row in the drawer's
secondary slot. The plan's default (D3) is to render **nothing** there: the drawer already holds
the workspace switcher and "Back to menu", and the browse view is literally the content directly
behind the drawer — so the row's only job would be to close the drawer covering it, and a naive
`<Link>` to the route you are already on is a dead tap (the drawer auto-closes on `[pathname]`
change only).

- **Default (plan):** empty secondary slot on mobile.
- **If the operator wants the row:** implement it in `app/(dashboard)/layout.tsx`, where
  `setDrawerOpen` (`:138`) and `drill` (`:199`) are already in scope — a static link needs no
  portal and no new window event.

---

## DC3 — Doc-header action budget on a phone (taste, capability)

**Class:** taste, with a capability consequence.

The wireframe's document frame shows `[← | breadcrumb | chat]`. The shipped `KbContentHeader` also
renders Download, `KbSyncStatus`, and `SharePopover`. Four actions do not fit 375px — but silently
dropping Share is a capability regression, and Download is the **only** way to consume a
non-markdown attachment on a phone.

No code in this plan changes that header. This needs a named resolution (overflow menu / bottom
sheet / keep as-is) before it becomes an unowned follow-up.

---

## DC4 — Corner radius: the brand guide contradicts the shipped surface (taste, brand)

**Class:** taste — brand-guide integrity, not blocking this PR.

`knowledge-base/marketing/brand-guide.md` states "Sharp (0px border-radius)… No rounded corners".
The new wireframes use 8–10px to match the shipped dashboard surface and the eight sibling
wireframes already committed in `knowledge-base/product/design/navigation/`.

Either the guide or the surface is stale. The design agent flagged it rather than silently picking
a side. Resolving it is a brand-guide edit, not a code change.

---

## DC5 — Global top bar / ⌘K trigger on KB routes (verification, not a choice)

**Class:** user-challenge — needs confirmation, not a decision.

The wireframe's browse frame places the hamburger on the right with no palette trigger; the shipped
global bar (`app/(dashboard)/layout.tsx:320`) is hamburger-left + palette-right. If the global bar
were suppressed on KB routes, the mobile ⌘K trigger (#6903 — the only non-keyboard palette entry)
would disappear there.

**The plan assumes it is NOT suppressed.** Confirm at the Phase 0.4 gate; if the wireframe intends
suppression, that is a separate decision with an accessibility cost.

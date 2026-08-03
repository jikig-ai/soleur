# Decision challenges — feat-one-shot-7186-kb-mobile-drill-in-nav

Persisted in headless mode (no TTY / one-shot pipeline), per `plan` §Plan Review and ADR-084.
`/ship` renders these into the PR body and files them as an `action-required` issue.

Each item below is a **taste** or **user-challenge** decision that the pipeline deliberately did
NOT resolve unilaterally. The plan records a recommendation for each; none has been applied as if
approved.

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

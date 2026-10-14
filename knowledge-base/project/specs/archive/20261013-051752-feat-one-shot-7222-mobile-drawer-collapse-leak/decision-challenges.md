# Decision Challenges — feat-one-shot-7222-mobile-drawer-collapse-leak

Recorded per ADR-084 / `decision-principles.md`. This plan ran **headless** (one-shot
pipeline), so these are persisted here instead of surfaced at an interactive gate.
`/ship` renders them into the PR body and files an `action-required` issue.

The operator's stated direction is the default in every case. Nothing here has been
silently applied against it.

---

## DC-1 — User-Challenge — the `kb-sidebar-shell` guard is KEPT, not simplified

**Operator's stated direction (issue #7222 / the brief):**

> "The existing narrow guard in kb-sidebar-shell must then be SIMPLIFIED, not left
> as a second condition that merely agrees with the first (the repo has a documented
> rule against that)."

**What the plan does instead:** keeps `components/kb/kb-sidebar-shell.tsx:64`
(`useRailCollapsed() && host === "rail"`) byte-identical, rewrites the stale comment
above it, and files a follow-up to unify the two breakpoint authorities — after
which the guard becomes provably redundant and can be deleted.

**Who raised it:** `cto` and `architecture-strategist` independently, consistent
with `test/kb-sidebar-shell-host.test.tsx:7`, which calls the collapsed case "the
load-bearing one".

**Why.** Redundancy requires that the layout's viewport term and
`useKbLayoutState`'s `isDesktop` (`hooks/use-kb-layout-state.tsx:239-240`, from
`useMediaQuery`) agree. They do agree **at rest** — but their **seeds are
deterministically contradictory on the first mobile frame**: at 390px
`useIsMobile()` seeds `false` (meaning "desktop") while
`useMediaQuery("(min-width: 768px)")` seeds `false` (meaning "mobile"). Both
literally `false`, opposite meanings, every mobile load. The guard covers exactly
that frame.

Concrete failure if the guard is deleted now: under the measured stuck-false mode
(`knowledge-base/project/learnings/ui-bugs/2026-06-03-dynamic-width-needs-css-var-not-tailwind-arbitrary-or-usemediaquery.md`,
corroborated by the layout's own comment at `app/(dashboard)/layout.tsx:151-152`),
`treeHost` resolves to `"content"` on a **desktop** while the layout's term says
desktop-true → the provider publishes collapsed → the content-column browse view
renders as a 56px icon strip on a 1280px screen.

**Note on the brief's premise:** it cites "a documented rule". No `AGENTS.rules.md`
rule id exists for this. The principle is recorded in **ADR-158 lines 52-54**, as a
design decision rather than an enforced gate.

**Why this honours the intent:** the operator's intent is "do not leave a
permanently-redundant condition". The plan removes it on a schedule where deletion
is safe rather than shipping a desktop regression to satisfy the letter of the
instruction. ADR-158 shipped the same day (2026-08-03) and is e2e-pinned at three
viewports.

**Sizing note for the follow-up:** it is **not** a chore. `useMediaQuery` is live in
four files (`use-kb-layout-state.tsx:82`, `components/ui/sheet.tsx:33`,
`components/ui/responsive-modal.tsx:56`,
`components/workstream/workstream-board.tsx:116`), and swapping any of them changes
first-client-render semantics — precisely the regression `hooks/use-is-mobile.ts`'s
own docstring says broke the mobile kanban board. Size it medium, with regression
risk.

**If the operator overrules:** delete `&& host === "rail"`, delete
`test/kb-sidebar-shell-host.test.tsx:115`, and unify both call sites on one
breakpoint source **in the same PR** — the unification is what makes the deletion
safe, so it cannot be deferred if the guard goes now.

---

## DC-2 — Taste — two reviewers argue the gold restore is the wrong token

**Operator's stated direction (issue #7222, report 3):**

> "Restore it to the band's token" — `drawer-back-to-menu` from
> `text-soleur-text-muted` to `text-soleur-accent-gold-fg`.

**What the plan does:** implements the operator's literal ask, **unmitigated** (no
separator, no substitute token), and defers the contested `kb-mobile-page-header`
sweep.

**The dissents.** `spec-flow-analyzer` (P1-2): gold in this codebase is reserved for
*active state* (`app/(dashboard)/layout.tsx:491`,
`components/settings/settings-shell.tsx:110`, `components/kb/file-tree.tsx:425`) and
*primary CTA* (`components/kb/kb-chat-trigger.tsx:46`). Recolouring puts a gold
**action** directly above a gold **location indicator** in the same drawer — on KB
document routes via the file tree, **and on `/dashboard/settings`** via
`settings-shell.tsx:110`, which is the very route the gold assertion runs on. In
dark theme the two tokens are `#c9a962` (`-fg`) and `#d4b36a` (`-text`) —
near-identical (`app/globals.css:58-60`). It also promotes the back that jumps
**two** levels out (`→/dashboard`) above the natural one-level-up
(`→/dashboard/kb`, `components/kb/kb-content-header.tsx:76-93`).

`ux-design-lead` (F5), measured against `app/globals.css`: at `text-sm` (14px) on
the drawer surface, light-theme `-fg` `#9c7a2e` on `#f4eedf` is **3.49:1 — below
WCAG AA 4.5:1**. Dark passes at 8.25:1. `-text` `#7a5e1f` passes at **5.25:1**.
This is pre-existing (the band ships the same token at the same size), so B
propagates it rather than creating it — but the acceptance criterion that asserts
*equality with the band* is structurally incapable of catching it, which is why the
plan adds a standalone light-theme contrast report.

`cpo` argued the opposite: gold restores band-level **rank parity**, and
`text-soleur-text-muted` is the token used for non-interactive secondary text, so on
a drawer with no hover state position becomes the only "this is tappable" cue.

**Resolution and fallback.** Ship the operator's `-fg` as asked. Record that a
single token change to **`text-soleur-accent-gold-text`** would satisfy the
operator's *intent* (gold, band-level rank) **and** clear AA **and** resolve the
adjacency — i.e. the fallback is strictly better rather than merely different. The
device check decides.

**Deferred, with the tracker corrected.** CPO initially asked to sweep
`components/kb/kb-mobile-page-header.tsx:40` (same `href`, same
`aria-label="Back to menu"`, a third colour) for rank parity, then withdrew:
`app/(dashboard)/layout.tsx:228-238` records that the drawer's back **always
co-renders** with it and stays in the a11y tree even while the drawer is closed, so
a screen-reader user already hears two identically-named links to the same
destination. The open question is not *what colour* but *whether that renderer
should exist*. Routed to **#7201**, which already owns the back census and the
inert-drawer fix — not to the C follow-up.

---

## DC-3 — Premises corrected during research

Not challenges to a *direction*, but claims in the brief that research falsified.
Recorded so the corrections are auditable rather than silent. Every one of these was
verified against the code before being acted on.

1. **"Every unit test in this repo mocks the breakpoint hook."** 14 of ~1091 test
   files reference `useIsMobile`/`useMediaQuery`, and only **5** render the
   dashboard layout. The conclusion (unit coverage cannot prove this fix) stands,
   and the repo states the operative version itself at
   `apps/web-platform/e2e/nav-states-shell.e2e.ts:1049-1051`. The sharper hazard is
   that the stubs are **query-blind** (`matches: false` regardless of query), so a
   new mobile assertion would pass **vacuously**.

2. **"Local `bun run dev` is broken, so rely on … the e2e suite."** The e2e suite
   depends on the thing declared broken — `apps/web-platform/playwright.config.ts:67`
   and `:80` both run `npm run dev`. The cause is that Next writes
   `.next/package.json` = `{"type":"commonjs"}` during `hot-reloader.start()`,
   potentially after the custom server has already loaded the instrumentation hook,
   while the package declares `"type": "module"`. That is why it is host- and
   `.next`-state dependent, and why CI's `e2e` job is green on a cold checkout.
   **Open issue #3562 has tracked this since 2026-06-19.** The plan folds in a
   one-line `dev`-script fix and closes it.

3. **Issue C's mechanism.** The issue attributes the mobile KB squeeze to
   `kb-mobile-layout.tsx` rendering `KbDocShell` and `KbChatSidebar` as flex-row
   siblings. They are siblings in source, but `components/ui/sheet.tsx:131` is
   `createPortal(panel, document.body)` on mobile, so it emits no in-flow DOM and
   cannot split the width. The operator's actual symptom is
   `components/kb/c4-workspace.tsx:96` — a horizontal `Group` with a default-open
   right `Panel` and **no breakpoint branch at all**. A fix aimed at the file the
   issue names would change nothing the operator can see.

4. **"The existing guard should be simplified"** — see DC-1.

5. **The plan's own v1/v2 sequencing rationale was wrong.** It argued C was
   theoretical until A merged, because a phone user could not reach a document.
   `spec-flow-analyzer` showed that on a populated mobile KB landing
   `treeHost === "content"` and the browse tree renders in the content column,
   pinned green at `e2e/nav-states-shell.e2e.ts:1105-1124` (#7186, merged the same
   day). **C's damage is live now**, which is why the two C *defaults* were folded
   into PR 1 rather than deferred with the structural half.

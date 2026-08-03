---
title: "fix(kb): mobile drill-in navigation — the single file tree relocates by breakpoint"
date: 2026-08-03
issue: 7186
branch: feat-one-shot-7186-kb-mobile-drill-in-nav
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-158 (provisional ordinal — re-verify at /ship)
related_adrs: [ADR-047, ADR-049, ADR-067]
related_prs: [4810, 4871, 4911, 4915, 6874, 6915, 6917]
milestone: "Phase 4: Validate + Scale"
---

# fix(kb): mobile drill-in navigation for the Knowledge Base 🐛

`Closes #7186`

## Overview

On a phone (viewport `< 768px`), opening **Knowledge Base** shows a content pane with no
document and no way to browse in place. Since PR #4810 (ADR-047, the single nav rail) the KB
file tree is portaled into the hamburger drawer, so `/dashboard/kb` renders nothing in the
content column until a file is already selected. The mobile polish pass (#6917) added a
**stopgap only** — an empty state in `components/kb/kb-doc-shell.tsx` ("Open a file to see it
here" + a "Browse files" button dispatching `RAIL_EXPAND_EVENT`). That removed the blank-pane
confusion; it did not give the KB a navigation model. This is the third pass on this surface
(#6915 and #6917 were both stopgaps) — the repeat is itself the signal.

This plan ships the real fix: a **list → detail drill-in on mobile**, built on the route split
that already exists.

### The shape

There is exactly one `FileTree` browse surface in the app today (`KbSidebarShell`, portaled into
the rail's secondary slot). This plan does **not** add a second one. It makes the *destination*
of that one surface a function of a single boolean, `useKbLayoutState().isDesktop`:

| Viewport | Route | Where the ONE tree mounts | Drawer's secondary slot |
|---|---|---|---|
| `>= 768px` | any | rail secondary slot (portal) — **unchanged** | the tree (as today) |
| `< 768px` | `/dashboard/kb` | **content column** — the browse view | a "Browse files" row (a link) |
| `< 768px` | `/dashboard/kb/<path>` | not mounted (a document is open) | a "Browse files" row (a link) |

**The mobile browse view owns all of its own states.** Today `fullWidth = loading || error ||
(!loading && !hasTreeContent)` (`kb/layout.tsx:37`) is computed *before* the layout branch and
bypasses both layouts — so a naive browse panel would only ever render the populated state, and
a mobile user with an empty, loading, or errored tree would see a chromeless state with no
search and, critically, **no "Sync now"** (the Fix A self-recovery valve, which today lives only
inside the closed drawer at `kb-sidebar-shell.tsx:159`). So on mobile at the landing route the
browse chrome renders **always**, and loading / 503 / 404 / unknown / empty / populated render
*inside* it, above a pinned `KbSyncStatus` footer. Desktop's `fullWidth` behaviour is untouched.

**Back-navigation from a document already works.** `components/kb/kb-content-header.tsx:36-53`
renders an `md:hidden` back chevron ("Back to file tree") linking to `/dashboard/kb`. Today it
lands on the stopgap empty state; after this change it lands on the browse view. No new code.

### Why this shape and not the obvious alternatives

- **NOT a CSS `hidden md:flex` / `md:hidden` dual-render.** ADR-047 rejects it ("jsdom can't
  distinguish `display:none`, and a hidden-but-mounted secondary nav re-creates the double-mount
  hazard"), and it has already shipped and regressed once: PR #6874's initial commit mounted
  both the desktop 7-column board and `MobileBoard`, duplicating every `IssueCard`, breaking
  **12 tests** in `workstream-board.test.tsx` with "Found multiple elements" *and* running the
  hidden board's `sessionStorage` effect on desktop. **Precise statement of the constraint:** no
  CSS dual-render of the same tree component — use a JS viewport branch. (See the Research
  Reconciliation row on what ADR-047's single-mount *test* actually covers.)
- **NOT a new breakpoint hook.** `useKbLayoutState` already owns the KB's only breakpoint
  authority. A second authority can disagree with the first, and that is how two trees mount.
- **NOT a bottom-sheet file picker over the document.** That is the current drawer model with
  nicer chrome: browse state gets no URL, is not deep-linkable, and "KB opens on nothing"
  returns whenever there is no last document. It also contradicts the single recorded
  taste-profile entry (`dashboard / workstream-inline-crud-optimistic` — in-content and inline
  over sibling/modal patterns).
- **NOT a portal-destination swap** (one element re-parented between two containers). React
  remounts on container change anyway, so there is no state continuity to gain — and when a
  document is open on mobile there is no content-column slot, so the target would be null and
  the drawer would go empty again (the #6917 bug, inverted).
- **NOT moving `RailSlotPortal` inside the layout components** to get a single `isDesktop` read.
  The portal sits *outside* the `fullWidth` gate at `kb/layout.tsx:57-59` deliberately; moving
  it changes what is reachable in the empty/error states.
- **Per-directory routing is deferred, not rejected** — see Non-Goals #1 for the corrected
  reasoning.

## Research Reconciliation — Spec vs. Codebase

Every row below was verified against the working tree. Four of these corrected a claim that
appeared in the issue, in a domain review, or in an earlier draft of this plan.

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "the tree is portaled from `app/(dashboard)/kb/layout.tsx`" (issue body) | Path is `app/(dashboard)/dashboard/kb/layout.tsx` — extra `dashboard/` segment. Portal at `:57-59`. | Corrected path used throughout. |
| **"`app/(dashboard)/layout.tsx` suppresses the band's back in the KB doc view"** (earlier draft of this plan, and the comment at `kb-layout.tsx:39-43`) | **FALSE.** `const inKbDocView = isKbDocView(pathname)` at `layout.tsx:229` is computed and **never used** — a dead variable. The mobile band at `:404-409` is `suppressBack suppressSectionTitle` **unconditionally**, and it lives *inside* the drawer. So on the mobile KB landing there is today **no reachable in-page back at all** — only `drawer-back-to-menu` behind the hamburger. | Design decision DD1 (below) resolves who owns back on the browse view. The dead variable is removed or wired in Phase 3. |
| **"`/dashboard/kb/<dir>` renders a directory as a file"** (earlier draft; also asserted by spec-flow) | **FALSE for ordinary directory names.** `getKbExtension("engineering")` returns `""` (`lastDot <= 0`), and `isMarkdownKbPath` returns true for `""` — so a directory takes the *markdown* branch → `/api/kb/content/<dir>` → 404 → `clearKbPath(); router.replace("/dashboard/kb")`. A silent bounce to the landing, not a mis-render. **TRUE only for a dotted directory name** (`docs.v2` → ext `.v2` → the FilePreview branch). Separately: **no directory URL is reachable from the UI** — directories are `<button onClick={toggle}>`, only files are `<Link>` (`file-tree.tsx`). | Non-Goals #1 rewritten: per-directory routing is *additive with zero regression surface*, and deferring it leaves **no user-reachable hole**. The dotted-directory edge case gets its own tracking issue. |
| "ADR-047 forbids a second KB browse component" | Over-read. ADR-047 line 52 scopes the hard single-mount invariant to `OrgSwitcherContainer` + `LiveRepoBadge`, and `test/nav-single-mount.test.ts` asserts only those two. The binding constraint is the **rejected alternative** at line 80 — CSS-hiding the same nav. | Constraint restated as "no CSS dual-render of the same tree; use a JS viewport branch" so the implementer does not design around a rule that does not exist. The one-tree guarantee is still enforced, by the gate + the runtime tests. |
| "Use the `use-is-mobile.ts` pattern **or** the `useMediaQuery` gate the Workstream board uses" | KB already uses the second: `hooks/use-kb-layout-state.tsx:73`. **Nine** test files mock `@/hooks/use-media-query`. | Keep `useMediaQuery`; add a defensive seed. Decision D1. |
| "happy-dom has no media queries, so both trees mount" | Precise: happy-dom applies no *CSS* media queries. It **does** provide `window.matchMedia` — **measured in this repo**: `typeof window.matchMedia === "function"`, `innerWidth === 1024`, `min-768` → `true`, `max-767` → `false`, MQL has a real `addEventListener`. | A JS gate is testable; a CSS gate is not. Recorded as measured, not assumed. |
| `test/kb-sidebar-collapse.test.tsx` is a mobile contract | It mocks `useMediaQuery: () => false`, but that value is **incidental** — it avoids the unmocked `react-resizable-panels` of the desktop layout. Its product assertion is the ADR-047 rail contract. | Phase 4.1 splits it into a desktop arm (re-asserting every ADR-047 contract) and a mobile arm. No product assertion weakened. |
| `segment-to-drill-level.ts` already has a drill concept | Different axis: `segmentToDrillLevel` is *rail* drill and collapses landing + doc into one `"kb"` level. `isKbDocView` is the depth-within-section predicate. | Reuse `isKbDocView`; introduce no new drill vocabulary. |
| `nav-drill-authority.test.ts` is a style guard | A **build-failing static guard**: any file but `hooks/segment-to-drill-level.ts` matching `.startsWith("/dashboard/(kb\|settings\|chat)")` fails. Trailing-slash form excluded. | AC10. Neither new component needs `pathname` — `isContentView` is already in the hook. |
| Learning `2026-06-03-…-usemediaquery` — "stayed false under SSR hydration despite matchMedia true" | Verified: that was an `applyRailWidth = kbExpanded && isDesktop` **first-interactive-frame** inline-style gate in `app/(dashboard)/layout.tsx`. That call site **no longer exists** (`hooks/use-rail-width.ts` and `components/dashboard/rail-resize-handle.tsx` contain no `useMediaQuery`/`matchMedia`). Mechanism never established, so not disproved. | Three-layer closure in D1 — seed, zero-deploy prod check, and the ADR-049 e2e gate (AC7). |
| "Local `bun run dev` is broken (Sentry instrumentation ESM error)" | Not re-verified; nothing in this plan depends on a dev server. | Verification is `tsc` + vitest + ADR-049 e2e + prod device mode. |

> No `spec.md` exists for this branch — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Premise Validation

- `#7186` — `gh issue view 7186`: **OPEN**, `type/bug`, `priority/p2-medium`, `domain/engineering`,
  **no milestone**. Premise holds; not closed by a merged PR.
- `ADR-047-nav-context-band-outside-swap.md` exists, `status: active`. This plan adopts none of
  its rejected alternatives.
- Highest existing ADR ordinal: **ADR-157** → next free **ADR-158** (provisional; `adr-ordinals`
  is not a required check, so `/ship` re-verifies against `origin/main`).
- Prior-art commits verified by `git log`: `7dc1a355c` (#4810), `099ab2e90` (#6874 + its
  `useMediaQuery` review fix), `6eecc26de` (#6915, first deferral statement), `b470cc2ca`
  (#6917, the stopgap being replaced).
- Live milestone check (`gh api repos/:owner/:repo/milestones`): `Phase 4: Validate + Scale`,
  `Phase 5: Desktop Native App (Browser Automation)`, `Post-MVP / Later`. **Phase 1
  "Close the Loop (Mobile-First, PWA)" is closed** while mobile-first demonstrably is not —
  see Compliance Notes.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --limit 200` and matched every path in
`## Files to Edit` / `## Files to Create` against the issue bodies. **None.**

## User-Brand Impact

**If this lands broken, the user experiences:** the Knowledge Base — the artifact the brand
guide names as the moat ("your company's institutional memory") — is unusable. Two concrete
failure artifacts: (a) on a phone, `/dashboard/kb` renders a blank content column with no tree
and a drawer holding one dead link; (b) on desktop, a stale or inverted `isDesktop` moves the
file tree **out of the persistent rail into the content column**, so the daily-driver desktop KB
loses its navigation and its resizable chat splitter in one step.

**If this leaks, the user's data is exposed via:** nothing. This moves an already-authorized
client component between two DOM positions inside the same authenticated layout. No new route,
API surface, persistence, or third-party call; the same single `/api/kb/tree` SWR fetch serves
the one tree wherever it mounts.

**Brand-survival threshold:** `single-user incident` — confirmed by CPO review, neither raised
nor lowered. Supporting: it is a first-contact surface; the failure mode directly falsifies the
one positioning clause the brand-guide validation review mandated ("delivery-agnostic:
accessible from any device"); and this is the **third** pass on this surface after two stopgaps.
Not higher: no data loss, no PII, no auth boundary, no irreversible action — navigational only.

Consequences honoured: CPO sign-off at plan time (Domain Review), `user-impact-reviewer` at
review time, the escalated plan-review panel, `gdpr-gate` run rather than assumed, and
`deepen-plan` before `/work`. **Also honoured:** at this threshold a scope-out justified by
"the next-most-likely entry is not covered" is an anti-pattern — which is why **search-state
persistence is in scope** (it is a coverage hole on the primary mobile find path), while
per-directory routing is safely deferred (no directory URL is reachable from the UI, so
deferring leaves no user-reachable hole).

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-158` — "The KB file tree mounts by breakpoint: nav rail on desktop, content column
on mobile."** In-scope task of THIS plan (Phase 5), per `wg-architecture-decision-is-a-plan-deliverable`.

Decision to record:
1. The KB's single browse surface has exactly one mount site at any instant, selected by the
   single `useKbLayoutState().isDesktop` boolean. A CSS dual-render of the tree is prohibited;
   the mobile drawer receives a link, never a second tree.
2. **The generalisable rule** (CPO): *a drilled section whose secondary nav is hierarchical and
   unbounded renders in-content on mobile; a flat, bounded secondary nav stays in the drawer.*
   KB is the only segment with a user-grown hierarchy — Settings is ~a dozen flat tabs,
   Conversations is a flat list. Naming the rule stops the next segment relitigating it.
3. `RailSlotPortal` returns `null` until `railSlotEl` is set by a ref callback, so the
   portal-side breakpoint read is never rendered server-side. This is load-bearing and currently
   undocumented.

Alternatives to record: CSS dual-render (rejected — ADR-047 already rejects it and #6874 proved
it); a second breakpoint hook (rejected — two authorities can disagree, and it silently bypasses
9 test mocks); portal-destination swap (rejected — no continuity gained, null target when a
document is open); bottom-sheet picker (rejected — no URL, not deep-linkable, contradicts the
taste profile); per-directory routing (deferred, not rejected — see Non-Goals #1).

**Amend `ADR-047`:** Decision 2's "drilled sections lift their secondary nav into the rail via a
React portal" holds **at `md+`**; below `md` a hierarchical secondary nav renders in the content
column and the rail slot receives a link. Add ADR-158 to `related_adrs`. Do not touch its
rejected-alternatives table — this plan honours it.

Ordinal caveat: 158 is provisional. If renumbered at `/ship`, **sweep the whole artifact set in
the same edit** — `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-7186-kb-mobile-drill-in-nav/`
plus this plan body and AC12 — so no AC verifies a nonexistent file.

### C4 views

**No C4 impact.** Cited against all three model files, not a keyword grep:

- `spec.c4` (54 lines, read in full): 5 element kinds — `actor`, `system`, `container`,
  `database`, `component`; tags `external`, `selfhosted`. No UI-composition kind exists.
- `views.c4` (62 lines, read in full): exactly three views — `context` (L1),
  `containers of platform` (L2), `components of platform.plugin` (L3). **The only L3 view is
  over the Soleur *plugin*, not the web app.** The web UI's finest granularity anywhere in the
  model is the container `platform.webapp.dashboard` ("Conversation UI, knowledge base viewer,
  session management"). A nav-rail-vs-content-column distinction is one level below anything the
  model represents.
- `model.c4` (594 lines, grepped for `knowledge|kb|nav|rail|tree|mobile|file`): the only `kb`
  element is `platform.plugin.kb = database "Knowledge Base"` plus its edges (`hooks -> kb`,
  `api -> kb`, `skills -> kb`, `agents -> kb`). None is touched.

Completeness enumeration:
- **(a) external human actors** — `founder`, `emailSender`, `betaContact`, `contributor`. None
  added; none gains or loses access. `founder` already reaches `platform.webapp.dashboard`.
- **(b) external systems / vendors** — none added.
- **(c) containers / data stores touched** — none. The same `swrKeys.kbTree()` fetch serves the
  one tree at either mount site.
- **(d) actor↔surface access relationships** — unchanged. Same routes, auth, authorization
  grain; no sharing/ownership change; no element description falsified.

No `.c4` edit, therefore **no** `scripts/regenerate-c4-model.sh` run and `model.likec4.json`
unchanged.

## Observability

The changed surface is client-side React under `app/`, `components/`, `hooks/` — outside the
Phase-2.9 mandatory trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
`plugins/*/scripts/`), introducing no infrastructure. Declared anyway, because a navigation
surface that fails silently is indistinguishable from a working one.

```yaml
liveness_signal:
  what: the ADR-049 headless-Chromium assertion in nav-states-shell.e2e.ts — at 1280px
        kb-rail-tree present AND kb-browse-tree absent; at 390px the inverse (exactly one,
        asserted in both directions)
  cadence: every PR (e2e job) and every merge to main
  alert_target: the PR check itself (red = blocked merge)
  configured_in: apps/web-platform/e2e/nav-states-shell.e2e.ts
error_reporting:
  destination: Sentry — the existing KbErrorBoundary plus
               reportSilentFallback(err, { feature: "kb-tree", op: "fetch-tree" })
               at hooks/use-kb-layout-state.tsx:95,119; NEW sinks added by this plan for the
               two currently-silent failures below
  fail_loud: yes — a tree-fetch throw surfaces as WorkspaceNotReady / NoProjectState /
             UnknownError, never a silent blank
failure_modes:
  - mode: two trees mount at once (the #6874 dual-mount class)
    detection: test/kb-layout.test.tsx exactly-one assertion at BOTH mocked viewports AND
               across a mock flip (the transition, not just the endpoints), plus the static
               importer guard in test/nav-single-mount.test.ts
    alert_route: red CI check
  - mode: zero trees mount (both branches false / stale isDesktop)
    detection: the same assertion tests length === 1, never <= 1
    alert_route: red CI check
  - mode: isDesktop stale-false on a real desktop browser (the 2026-06-03 hydration class) —
          invisible to happy-dom, which has no hydration and no CSS
    detection: the 1280px arm of the e2e assertion (real Chromium)
    alert_route: red CI check
  - mode: "Sync now" fails silently — KbSyncStatus accepts onError (kb-sync-status.tsx:36) but
          NEITHER caller passes it (kb-sidebar-shell.tsx:160, kb-content-header.tsx:105), so a
          non-2xx or network throw just flips the label back. This plan pins that control in
          the browse view as THE mobile recovery valve, so the silence becomes load-bearing.
    detection: wire onError -> inline dismissible error row + retry + aria-live, and mirror via
               reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry)
    alert_route: Sentry + visible in-product error row
  - mode: search failure renders the PREVIOUS query's results labelled with the NEW query —
          search-overlay.tsx:25 only setResults on res.ok, :29 swallows the catch, :33 sets
          searched regardless
    detection: clear results on failure, render an error row, mirror the catch via
               reportSilentFallback
    alert_route: Sentry + visible in-product error row
  - mode: drawer "Browse files" row is a dead tap on /dashboard/kb (auto-close fires on
          [pathname] only, layout.tsx:232-234)
    detection: test asserting the row closes the drawer on the browse route
    alert_route: red CI check
logs:
  where: Sentry (client), via KbErrorBoundary + reportSilentFallback — no new sink
  retention: existing Sentry retention, unchanged
discoverability_test:
  command: >-
    cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-layout.test.tsx
    test/kb-sidebar-collapse.test.tsx test/kb-browse-view.test.tsx
    test/kb-sync-status.test.tsx test/components/kb/kb-reconnect-banner.test.tsx
    test/nav-single-mount.test.ts
  expected_output: all suites pass; the single-tree assertion reports length 1 at both
                   viewports and across the transition
```

No `ssh` appears in any verification path.

## Encryption Posture

Not applicable — no persistent data store and no new cross-component or network connection.
Phase 2.11 detection (`.tf`, `supabase/migrations/*.sql`, `cloud-init*`, `docker-compose*`)
matches nothing in the file lists.

## GDPR / Compliance

Run, not assumed (required at this threshold). **Fast pass:** no schema, migration, auth flow,
API route, or `.sql` file is touched; no new processing activity, no LLM or external call, no
new distribution surface, no change to what data is read or displayed. None of the four
expansion triggers (a)–(d) fire. Advisory only; no Critical findings expected. Re-run
`/soleur:gdpr-gate` against the actual diff at `/work` time.

## Infrastructure (IaC)

Not applicable. No server, service, cron, secret, vendor account, DNS record, or firewall rule.
Pure code change against an already-provisioned surface.

## Hypotheses

Not a network/SSH-connectivity issue; no trigger pattern from the network-outage checklist
matches. Skipped.

---

## Key Decisions

### D1 — Keep `useMediaQuery` as the KB's single breakpoint authority, seeded desktop-first

`hooks/use-kb-layout-state.tsx:73` keeps calling `useMediaQuery`. The only change is a new
**optional second argument** on the hook.

**One boolean, therefore no disagreement.** Every new mount site reads the same
`state.isDesktop`, produced by one `useMediaQuery` call. The rail gate and the content gate flip
together in the same render. That is the property "exactly one tree mounts" actually rests on;
the tests protect it, they do not create it.

**Why it is safe — two independent reasons, both verified.**
1. `isDesktop` is never consumed on a first-paint render: `use-kb-layout-state.tsx:140` sets
   `loading = treeData === undefined && …`, the SWR fetch has no `fallbackData`/SSR provider, and
   `kb/layout.tsx:37` computes `fullWidth` from it. Server and first client paint both render a
   skeleton. This is the identical precondition documented verbatim on the Workstream board gate
   (`components/workstream/workstream-board.tsx:108-116`).
2. `RailSlotPortal` returns `null` until `railSlotEl` is set, and `railSlotEl` is a
   `useState(null)` filled by a **ref callback** (`app/(dashboard)/layout.tsx:161`, `:624`) —
   null on the server *and* on the hydration render. So the portal-side read is never rendered
   server-side either. **Write this as a comment at the new gate:** if anyone ever makes the rail
   slot SSR-resolvable, this gate silently acquires a hydration mismatch.

**Defensive seed — convert the dangerous failure into the harmless one.** The stale-boolean
class is asymmetric here:

| stale value | consequence |
|---|---|
| `false` on desktop | the tree leaves the rail entirely — severe, every desktop user |
| `true` on mobile | desktop layout for one frame on a phone, self-corrects on the effect — cosmetic |

Widen the signature to `useMediaQuery(query: string, initial = false)` (the no-`window` branch
returns `initial`) and call it as `useMediaQuery("(min-width: 768px)", true)`. The default
preserves today's behaviour for the three other consumers (`components/ui/sheet.tsx:33`,
`components/ui/responsive-modal.tsx:56`, `components/workstream/workstream-board.tsx:116`) and
for `test/use-media-query.test.tsx`. All nine KB mocks are `useMediaQuery: () => <const>`, which
ignore arguments — **zero test churn**. ~3 lines.

**Why `useIsMobile` would be actively worse.** Nine test files mock `@/hooks/use-media-query`
(`kb-layout-panels`, `kb-sidebar-collapse`, `kb-layout-chat-close-on-switch`,
`kb-layout-thread-info-prefetch`, and five `kb-chat-sidebar-*`). Switching does **not** crash
(measured: happy-dom has `matchMedia`) — it does something worse: all nine mocks are silently
ignored, `max-767` returns `false` at happy-dom's 1024px, and several suites flip which branch
they exercise **without failing**. A silent branch flip in the suite meant to guard this change
is unacceptable.

**Residual risk, closed in three layers.** (i) the seed above; (ii) **a zero-deploy prod check
(Phase 0.5)** — `workstream-board.tsx` already gates on a raw `useMediaQuery` in exactly this
post-fetch position and is live; if its 7-column desktop branch renders at desktop width on
`app.soleur.ai` today, the hook hydrates correctly in that position. (A direct probe of KB's own
`isDesktop` is *not* available — you cannot read a hook from a console, and the 2026-06-03 probe
only worked because it dumped a `data-` attribute, which here would mean shipping code first.)
(iii) **the real gate — ADR-049 headless Chromium at both viewports on every PR** (AC7).

### D2 — Extract the tree body; keep the wrappers thin

`KbSidebarShell` mixes three concerns: the rail-collapsed icon branch, the `kb-rail-tree`
identity, and the tree body (search + scrollport + `FileTree`/empty + sync footer + the
`useNavResume` scroll-restore effect). Only the third is shared.

Extract it into `components/kb/kb-tree-panel.tsx`. `KbSidebarShell` keeps the collapsed branch,
the `kb-rail-tree` wrapper, and `useRailCollapsed()`. `KbBrowseView` is the mobile
content-column host. **Carry `data-tour-id="action:kb-tree"` into `KbTreePanel`**, not the rail
wrapper — `components/tour/tour-steps.ts:126` targets it, and it must follow the tree to
whichever host mounts it.

Scroll/expanded state: `expanded` is already hoisted to `use-kb-layout-state.tsx:75` (one
instance in context, shared through the portal — unaffected). Only `readScrollTop`/`writeScrollTop`
is per-wrapper; move that effect into `KbTreePanel` so both hosts get it and **do not add a
second sessionStorage key**. Since exactly one host mounts, there is no write race.

### D3 — The drawer gets a link, and the link must close the drawer

`app/(dashboard)/layout.tsx:232-234` auto-closes the drawer on `[pathname]` change **only**. A
`<Link href="/dashboard/kb">` tapped while already on `/dashboard/kb` produces no pathname
change, so the drawer stays open and nothing visibly happens — worse than a no-op, because this
is the drawer's only KB row. Rail-slot children have no drawer setter (`RailSlotContext` is
`HTMLElement | null`).

Fix: add a symmetric **`RAIL_CLOSE_EVENT`** beside `RAIL_EXPAND_EVENT`
(`components/dashboard/rail-slot.tsx:26`) with a listener in the dashboard layout, and have the
row close the drawer unconditionally before routing. Also give it `aria-current="page"` + the
active treatment on the browse route so it reads "you are here".

Rejected: hiding the row when already on `/dashboard/kb` — that leaves the drawer's KB section
blank, re-creating the "collapsed rail looked empty/broken" bug that `kb-sidebar-shell.tsx:36`
documents fixing.

### D4 — One PR, two clearly separated commits

The CTO recommended two PRs: a pure extraction, then the behaviour change — the value being that
at the extraction point **every existing test passes unmodified**, which is the proof the
extraction is faithful. That proof property is preserved by a commit boundary, so this ships as
**one PR with two commits**, and AC14 asserts the property at the first commit. Single PR because
the behaviour change is atomic: gating the portal without the browse view leaves mobile with no
tree at all, and mounting the browse view without gating the portal is the dual-mount regression.

### DD1 — Who owns "back" on the mobile browse view (design decision — operator gate)

The `.pen` gives the browse view a header with a back arrow to `/dashboard` ("the back arrow
always means up one level"). The shipped `#4915` contract, asserted in `test/kb-layout.test.tsx`,
says the KB **landing** header *omits* the back "because the persistent band owns it".

**That contract's premise is factually false on mobile** (see Research Reconciliation): the band
is unconditionally `suppressBack` and lives inside the drawer, so the mobile landing has no
reachable back without opening the hamburger. The wireframe fixes a real gap.

- **Option (a), recommended:** follow the wireframe — the browse header carries the back arrow.
  Updating the `#4915` assertion is then a **correction of a false premise**, not a weakening,
  and must be justified as such in the PR body.
- **Option (b):** keep the contract — title only, back stays behind the hamburger.

**This is the single most important item for the Phase 0.4 operator sign-off.** Do not pick it
unilaterally.

---

## Implementation Phases

### Phase 0 — Wireframe + operator sign-off gate 🚧 BLOCKING

**No product code before this phase closes** (`wg-ui-feature-requires-pen-wireframe`).

0.1 ✅ **Done.** `knowledge-base/product/design/navigation/kb-mobile-drill-in-nav.pen`
(136 KB) plus 8 frames exported as direct children of `navigation/screenshots/`, numbered
`29-`…`36-` (continuing the existing `01-`…`28-` sequence from #4911). Committed in `15ac70b19`
— an uncommitted `.pen` is at risk from the destructive-open bug (#3274). The pre-existing
`kb-mobile-nav-redesign-wireframes.pen` was **not** opened.

0.2 **Required additions before sign-off** (CPO condition 3 + constitution line 272):
- browse-view **error** frames (503 workspace-not-ready / 404 no-project / unknown + retry) —
  frames 30 and 31 cover empty and loading, error is missing;
- a **tablet frame at exactly 768px**, the switch point.

0.3 **Open design questions to put in front of the operator** — do not resolve unilaterally:
- **DD1** — who owns back on the browse view (recommended: option (a), the wireframe).
- **Doc-header action budget.** The `.pen` doc frame shows `[← | breadcrumb | chat]`; the shipped
  `KbContentHeader` also renders Download, `KbSyncStatus`, and `SharePopover`. Four actions do
  not fit 375px, but silently dropping Share is a capability regression and Download is the
  **only** way to consume a non-markdown attachment. Name the replacement (overflow menu /
  bottom sheet) or keep them.
- **Global top bar on KB routes.** The browse frame puts the hamburger on the right with no
  palette trigger; the global bar (`layout.tsx:320`) is hamburger-left + palette-right. If the
  global bar is suppressed on KB routes, the mobile ⌘K trigger (shipped #6903 — the only
  non-keyboard palette entry) disappears there. Confirm it is **not** suppressed.
- **Corner radius.** `brand-guide.md` states "Sharp (0px border-radius)… No rounded corners";
  the frames use 8–10px to match the shipped surface and the eight sibling wireframes in this
  folder. Either the guide or the surface is stale — flag for resolution, do not silently pick.

0.4 **Operator sign-off gate.** `xdg-open knowledge-base/product/design/navigation/screenshots/`
and stop. Operator-attended: ask for explicit approval before Phase 1. Headless: record
`wireframes ready for async review at <dir>`, surface the gate and the 0.3 questions in the PR
body, and **do not mark the PR ready** until the operator has signed off. On approval:
`bash plugins/soleur/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md kb aesthetic-direction kb-mobile-drill-in "$(date -u +%F)"`.

0.5 **Zero-deploy hydration sanity check (D1 layer ii).** Open `https://app.soleur.ai/dashboard/workstream`
at desktop width and confirm the 7-column board renders (not `MobileBoard`). Five minutes, no
deploy. If it fails, stop and re-plan around a CSS-var / container-query approach.

0.6 Assign #7186 to the `Phase 4: Validate + Scale` milestone (`wg-every-feature-listed-in-a-roadmap-phase`).

### Phase 1 — RED: the failing guards (`cq-write-failing-tests-before`)

1.1 `test/kb-layout.test.tsx` — parameterise the existing "does not render FileTree twice at root
path" case over both viewports using a settable `mockIsDesktop`
(the pattern at `test/kb-layout-panels.test.tsx:15-17`). Assert
`getAllByRole("navigation", { name: /knowledge base file tree/i })` has length **exactly 1** in
each arm, that the desktop arm's tree is inside `rail-secondary-slot` and the mobile arm's is
not — **and re-render across a mock flip (desktop → mobile and back), asserting exactly one
through the transition.** A double mount appears at the swap, not at either endpoint.

1.2 `test/kb-browse-view.test.tsx` (new) — mobile browse view renders header + search + tree +
pinned sync footer; renders its **own** loading / empty / 503 / 404 / unknown states in place
(not the bypassing `fullWidth` chrome); renders no rail-collapsed affordance; the drawer's
"Browse files" row links to `/dashboard/kb`, is `aria-current="page"` on that route, and closes
the drawer on tap in both cases.

1.3 `test/nav-single-mount.test.ts` — add a `CASES` entry asserting
`@/components/kb/kb-tree-panel` is imported by exactly
`["components/kb/kb-browse-view.tsx", "components/kb/kb-sidebar-shell.tsx"]`, and one for
`@/components/kb/file-tree` (verify whether `components/kb/index.ts` re-exports it before
writing the expected array). **Comment honestly:** an exact-importer allowlist proves "only these
two modules may import it", which is strictly *weaker* than single-mount — two allowlisted
modules could both mount. The mutual-exclusion guarantee comes from the single boolean (D1) and
is verified by 1.1 and 1.4, not by this static guard.

1.4 `e2e/nav-states-shell.e2e.ts` — extend the existing authenticated blocks
(`DESKTOP` at `:419`, `MOBILE` at `:911`; `kbRailTree` locator at `:403`):
- 1280×800: `kb-rail-tree` attached, `kb-browse-tree` **not** attached;
- 390×844: `kb-browse-tree` attached, `kb-rail-tree` **not** attached;
- 390×844 round trip: tap a file row → document → tap "Back to file tree" → browse view
  restored with **no** full page load;
- 768×1024 (the switch point): assert whichever side the operator's DD1/wireframe review fixes.

1.5 `test/kb-sync-status.test.tsx` — a failing sync renders a dismissible error row with retry
and announces via `aria-live`; the failure mirrors to Sentry.

1.6 `test/search-overlay.test.tsx` — a failed search clears stale results, renders an error row,
and mirrors the swallowed `catch` to Sentry; the query survives navigating to a document and back.

Run all of the above; confirm they fail for the intended reason, not an import error.

### Phase 2 — GREEN commit 1: pure extraction, zero behaviour change

2.1 Create `components/kb/kb-tree-panel.tsx` — move verbatim from `kb-sidebar-shell.tsx`: the
`useKb()` reads, `isEmpty`, the `useNavResume` scroll persist/restore effect and its
`MAX_SCROLL_RESTORE_FRAMES` cap, `SearchOverlay`, the `kb-tree-scrollport` div, the
`RailEmptyState`/`FileTree` branch, the `KbSyncStatus` footer, and `data-tour-id="action:kb-tree"`.

2.2 Reduce `components/kb/kb-sidebar-shell.tsx` to the rail wrapper: `data-testid="kb-rail-tree"`
+ `useRailCollapsed()` branch (collapsed icon column unchanged, including its
`RAIL_EXPAND_EVENT` dispatch and `kb-rail-collapsed-*` test ids) + `<KbTreePanel/>`.

2.3 **Commit boundary.** At this commit `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
is clean and **every existing test passes with zero test-file edits**. That unmodified-green run
is the proof the extraction is faithful (AC14) — do not fold behaviour into this commit.

### Phase 3 — GREEN commit 2: the breakpoint swap

3.1 `hooks/use-media-query.ts` — add the optional `initial` parameter (D1).
`hooks/use-kb-layout-state.tsx:73` → `useMediaQuery("(min-width: 768px)", true)`.

3.2 `app/(dashboard)/dashboard/kb/layout.tsx`:
- portal content becomes a **single ternary** on the one boolean, so the branches cannot both
  evaluate: `<RailSlotPortal>{isDesktop ? <KbSidebarShell/> : <KbRailBrowseLink/>}</RailSlotPortal>`,
  with the D1 reason-2 comment attached;
- the mobile landing owns its own states: compute `const mobileBrowse = !isDesktop && !isContentView`
  and render the browse chrome whenever `fullWidth || mobileBrowse`, with the populated branch
  rendering `<KbBrowseView/>` in the body. Desktop's `fullWidth` path is byte-for-byte unchanged
  (`mobileBrowse` is always false when `isDesktop`);
- remove or wire the dead `inKbDocView` at `app/(dashboard)/layout.tsx:229` and delete the
  comment asserting a suppression that does not happen;
- apply the operator's DD1 decision to the browse header.

3.3 Create `components/kb/kb-browse-view.tsx` — `data-testid="kb-browse-tree"`, full-height flex
column, `<KbTreePanel/>` **wrapped in `KbErrorBoundary`** (today the boundary wraps only
`KbDocShell`'s children at `kb-doc-shell.tsx:21`; a `FileTree` throw would otherwise white-screen
the whole content column with no recovery — do not inherit that gap on new surface).

3.4 Create `components/kb/kb-rail-browse-link.tsx` per D3 — `min-h-[44px]` row, "Browse files",
closes the drawer via `RAIL_CLOSE_EVENT`, `aria-current="page"` on the browse route. Derive
state from props/context, **never** a bare `pathname.startsWith("/dashboard/kb")` (AC10).

3.5 `components/dashboard/rail-slot.tsx` — export `RAIL_CLOSE_EVENT`;
`app/(dashboard)/layout.tsx` — add the listener beside the existing `RAIL_EXPAND_EVENT` one at
`:246-263`.

3.6 `components/kb/kb-mobile-layout.tsx` — the content column is now always the document shell
(the landing is handled in 3.2). Update the ADR-047 comment at `:30-33`, which currently asserts
the opposite ("The doc always fills the content area here").

3.7 `components/kb/kb-doc-shell.tsx` — delete the `md:hidden` stopgap block (`:32-48`) and its
`RAIL_EXPAND_EVENT` import. With the browse view in place, `isContentView === false` is only
reachable from `KbDesktopLayout`. Keep `DesktopPlaceholder` and `KbErrorBoundary` untouched.

3.8 Wire the two silent failures (in scope because this plan makes both load-bearing on mobile):
- pass `onError` from both `KbSyncStatus` callers → inline dismissible error row + retry +
  `aria-live`, mirrored via `reportSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`);
- `components/kb/search-overlay.tsx` — clear stale results on non-ok, render an error row,
  mirror the swallowed `catch`, and **lift the query into `useKbLayoutState`** so it survives
  browse → doc → back (CPO condition 2 — the coverage hole on the primary mobile find path).

3.9 Confirm the `RAIL_EXPAND_EVENT` census stays coherent: remaining dispatchers are
`kb-sidebar-shell.tsx` (collapsed rail, desktop-only) and `components/tour/tour-provider.tsx`;
the sole listener stays `app/(dashboard)/layout.tsx:246-263` with its mobile-gated
`setDrawerOpen(true)`. Do **not** remove the event.

3.10 Export the new components from `components/kb/index.ts`.

### Phase 4 — Reconcile the affected existing tests

Each item is an **intentional, enumerated** change. No product assertion is weakened.

4.1 `test/kb-sidebar-collapse.test.tsx` — split into a **desktop** arm (`mockIsDesktop = true`,
with the `react-resizable-panels` mock copied from `kb-layout-panels.test.tsx:39-56`)
re-asserting every existing ADR-047 rail contract — portals into the slot, no in-shell collapse
button, `kb-rail-empty` CTA, renders nothing without a slot, collapsed icon-only affordance with
the tree DOM-removed, collapsed "Browse files" dispatches `RAIL_EXPAND_EVENT` — and a **mobile**
arm asserting the slot receives `KbRailBrowseLink` (not a tree) and the content column receives
`kb-browse-tree`.

4.2 `test/kb-layout.test.tsx` — the `#4915` landing-header case changes only if the operator
chooses DD1 option (a). If so, the PR body must state that the original assertion encoded a
false premise (the band does not own back on mobile) and is being corrected.

4.3 `test/components/kb/kb-reconnect-banner.test.tsx` — parameterised over
`KbDesktopLayout`/`KbMobileLayout` and mocks `KbDocShell` wholesale. Pin its `usePathname` mock
to a document route so the mobile arm still exercises the banner, or add a browse-route arm.

4.4 `test/kb-tree-scroll-resume.test.tsx` — the scrollport moved into `KbTreePanel`. Confirm the
`kb-tree-scrollport` id and the rAF-coalesced persist/restore are unchanged; add a mobile arm.
Note the known limitation: restore is one-shot via `restoredRef`, so a second breakpoint crossing
does not restore — record it as a Non-Goal rather than silently shipping it.

4.5 `test/kb-layout-panels.test.tsx`, `test/kb-layout-chat-close-on-switch.test.tsx`,
`test/kb-layout-thread-info-prefetch.test.tsx`, the five `kb-chat-sidebar-*` suites — all mock
`useMediaQuery` explicitly and should be unaffected. **Run them; do not assume.**

4.6 `test/nav-rail-drill.test.tsx`, `test/workspace-context-band.test.tsx` — one-back-per-state
and band assertions stay green. `test/components/workstream/workstream-board.test.tsx` is the
dual-mount canary from #6874 — run it explicitly.

4.7 `test/light-theme-tokenization.test.tsx` — scans KB components for hard-coded colours. Grep
`app/globals.css` for every `soleur-*` token before use: a wrong token is a **silent no-op**, no
`tsc` error, no test failure.

### Phase 5 — ADR + docs

5.1 Write `ADR-158-kb-file-tree-mounts-by-breakpoint.md` with the three decision clauses and the
five alternatives above.
5.2 Amend `ADR-047-nav-context-band-outside-swap.md`: the `md+` qualifier on Decision 2, the
hierarchical-vs-flat rule, `related_adrs += ADR-158`.
5.3 No `.c4` edit → no `regenerate-c4-model.sh`, no `model.likec4.json` change.

### Phase 6 — Verification

6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
(**Not** `npm run -w apps/web-platform typecheck`: the repo root declares no `workspaces` field.)

6.2 Targeted:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-layout.test.tsx test/kb-sidebar-collapse.test.tsx test/kb-browse-view.test.tsx test/kb-tree-scroll-resume.test.tsx test/kb-layout-panels.test.tsx test/kb-sync-status.test.tsx test/search-overlay.test.tsx test/components/kb/kb-reconnect-banner.test.tsx test/nav-single-mount.test.ts test/nav-drill-authority.test.ts test/nav-rail-drill.test.tsx test/components/workstream/workstream-board.test.tsx`

6.3 Full suite via `test-all.sh`. **Read the per-suite lines, not the summary count** — `N-1/N`
means a suite failed, and `[FAIL] <suite> (0ms)` means a whole sub-suite crashed. That is exactly
how the #6874 dual-mount reached `/ship`.

6.4 `/soleur:qa` — the ADR-049 headless-Chromium `nav-states` gate. Mandatory: the diff touches
`app/(dashboard)/**` and a `layout.tsx`, and it is the only gate that sees real CSS and real
hydration.

6.5 Prod device-mode spot check on `https://app.soleur.ai` after deploy (local `bun run dev` is
broken on this host). Capture desktop, **tablet at exactly 768px**, and mobile (constitution
line 272).

---

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/components/kb/kb-tree-panel.tsx` | Shared tree body — search + scrollport + FileTree/empty + sync footer + scroll resume + tour id |
| `apps/web-platform/components/kb/kb-browse-view.tsx` | Mobile content-column browse view (`kb-browse-tree`), inside `KbErrorBoundary` |
| `apps/web-platform/components/kb/kb-rail-browse-link.tsx` | Mobile drawer "Browse files" row — a link that closes the drawer, never a tree |
| `apps/web-platform/test/kb-browse-view.test.tsx` | Browse view states + drawer-link behaviour |
| `apps/web-platform/test/search-overlay.test.tsx` | **New** — no suite exists today (`ls` verified). Failure clears stale results + mirrors to Sentry; query survives browse → doc → back |
| `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-mounts-by-breakpoint.md` | The decision record |
| `knowledge-base/product/design/navigation/kb-mobile-drill-in-nav.pen` | ✅ committed (`15ac70b19`) |
| `knowledge-base/product/design/navigation/screenshots/29-…36-*.png` | ✅ committed; `37-`+ for the Phase 0.2 additions |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | Breakpoint-gated portal ternary; `mobileBrowse` chrome owning its own states; DD1 header |
| `apps/web-platform/app/(dashboard)/layout.tsx` | `RAIL_CLOSE_EVENT` listener; remove/wire the dead `inKbDocView` (`:229`) and its false comment |
| `apps/web-platform/components/dashboard/rail-slot.tsx` | Export `RAIL_CLOSE_EVENT` |
| `apps/web-platform/components/kb/kb-sidebar-shell.tsx` | Reduce to the rail wrapper + collapsed branch; delegate to `KbTreePanel` |
| `apps/web-platform/components/kb/kb-mobile-layout.tsx` | Always the document shell; correct the ADR-047 comment (`:30-33`) |
| `apps/web-platform/components/kb/kb-doc-shell.tsx` | Delete the unreachable `md:hidden` stopgap (`:32-48`) + its `RAIL_EXPAND_EVENT` import |
| `apps/web-platform/components/kb/kb-sync-status.tsx` (callers) | Pass `onError` → error row + retry + `aria-live` + Sentry mirror |
| `apps/web-platform/components/kb/search-overlay.tsx` | Clear stale results on failure; error row; mirror the swallowed catch; lift the query |
| `apps/web-platform/components/kb/index.ts` | Export the three new components |
| `apps/web-platform/hooks/use-media-query.ts` | Optional `initial` parameter (default `false`) |
| `apps/web-platform/hooks/use-kb-layout-state.tsx` | Seed `true`; own the persisted search query |
| `apps/web-platform/test/kb-layout.test.tsx` | Two-viewport + transition single-tree assertion; DD1-dependent `#4915` correction |
| `apps/web-platform/test/kb-sidebar-collapse.test.tsx` | Desktop (ADR-047 contract) + mobile arms |
| `apps/web-platform/test/kb-tree-scroll-resume.test.tsx` | Mobile arm |
| `apps/web-platform/test/kb-sync-status.test.tsx` | Failure path coverage |
| `apps/web-platform/test/components/kb/kb-reconnect-banner.test.tsx` | Pin/extend the mobile arm |
| `apps/web-platform/test/nav-single-mount.test.ts` | Importer allowlist + the honest comment |
| `apps/web-platform/e2e/nav-states-shell.e2e.ts` | Two-viewport mount assertions, 768px switch point, drill-in round trip |
| `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md` | `md+` qualifier; hierarchical-vs-flat rule; `related_adrs` |

**Not edited (deliberately):** `components/kb/file-tree.tsx`, `components/kb/kb-content-header.tsx`
(its back chevron already does the right thing), `components/kb/kb-desktop-layout.tsx`,
`hooks/use-is-mobile.ts`, `hooks/segment-to-drill-level.ts`.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — On a phone viewport, `/dashboard/kb` renders the file tree in the content column
  (`kb-browse-tree` present, containing a `role="navigation"` named /knowledge base file tree/),
  verified at the 390px e2e arm.
- **AC2** — **Exactly one** file-tree instance mounts: `getAllByRole(…)` length **=== 1** (never
  `<= 1`) at both mocked viewports **and across a desktop↔mobile mock flip**.
- **AC3** — Desktop KB behaviour unchanged: at `mockIsDesktop = true` the tree is inside
  `rail-secondary-slot`, no in-shell collapse button, the collapsed icon affordance still
  DOM-removes the tree, and `kb-layout-panels.test.tsx` panel counts/sizes are untouched.
- **AC4** — Back from a document returns to the browse view without a full reload (e2e round
  trip), and the in-app chevron and the OS back button reach the same place — the PR states
  which mechanism (`push` vs `replace`/`router.back()`) was chosen.
- **AC5** — Exactly one back affordance renders per mobile state, **including the browse view**,
  per the operator's DD1 decision. `test/nav-rail-drill.test.tsx` stays green.
- **AC6** — The mobile drawer on a KB route contains the workspace switcher, "Back to menu", and
  a "Browse files" row — and **no** `role="navigation"` named /knowledge base file tree/.
- **AC7** — The ADR-049 e2e gate asserts, in real Chromium: 1280×800 → `kb-rail-tree` attached
  AND `kb-browse-tree` absent; 390×844 → the inverse. A real assertion, not a screenshot diff.
  This is the empirical closure of the stale-`isDesktop` risk.
- **AC8** — `test/nav-single-mount.test.ts` asserts `kb-tree-panel`'s importer set exactly, with
  the comment recording that this is weaker than single-mount and naming what does guarantee it.
- **AC9** — Tapping "Browse files" while already on `/dashboard/kb` **closes the drawer**; the
  row carries `aria-current="page"` there.
- **AC10** — No new bare `pathname.startsWith("/dashboard/kb")`.
  `test/nav-drill-authority.test.ts` passes unmodified.
- **AC11** — The mobile browse view renders its own loading, empty, 503, 404, and unknown states
  in place, each with a pinned "Sync now" footer reachable **without** opening the drawer.
- **AC12** — A failed "Sync now" and a failed search each render a visible dismissible error row
  with retry, announce via `aria-live`, and mirror to Sentry. The search query survives
  browse → document → back.
- **AC13** — `tsc --noEmit` exits 0 and the full `test-all.sh` run shows **no** non-`[ok]` suite
  line (verified by reading per-suite lines, not the summary count).
- **AC14** — At the Phase-2 commit, **every existing test passes with zero test-file edits** —
  the proof the extraction is faithful. The PR body enumerates every existing test changed in
  Phase 4 and why each change is mechanical or a false-premise correction.
- **AC15** — `ADR-158-*.md` exists and `ADR-047-*.md` carries the `md+` qualifier, the
  hierarchical-vs-flat rule, and the `related_adrs` entry. Swept if the ordinal is renumbered.
- **AC16** — `kb-mobile-drill-in-nav.pen` is committed with its PNGs as direct children of
  `navigation/screenshots/`, numbered from `29-`, including the Phase 0.2 browse-error and
  768px-tablet frames, and not gitignored.
- **AC17** — `/soleur:qa` (ADR-049 nav-states gate) is green.
- **AC18** — #7186 is assigned to the `Phase 4: Validate + Scale` milestone.

### Post-merge (operator)

- **AC19** — Prod device-mode check on `https://app.soleur.ai` after deploy at desktop, 768px,
  and mobile. *Automation: attempt via Playwright MCP against the prod URL with the operator
  session; `automation-status: UNVERIFIED` — /work MUST run a Playwright attempt before any
  operator handoff. AC7 already covers both viewports in CI against a real browser, so this is a
  post-deploy confirmation, not the primary gate.*
- **AC20** — Design sign-off recorded in the taste profile (Phase 0.4). *Automation: not feasible
  because design approval is a subjective human judgement, not an API-readable signal.*

## Non-Goals / Out of Scope

Each gets a tracking issue filed in the same session (`wg-when-deferring-a-capability-create-a`).

1. **Per-directory routing / folder drill-in.** Tapping a folder still expands it inline.
   **Corrected reasoning:** this is *not blocked* — `isMarkdownKbPath` returns true for an empty
   extension, so a directory URL 404s and bounces to the landing rather than mis-rendering, and
   **no directory URL is reachable from the UI** (directories are buttons, only files are links).
   Adding directory routes is purely additive with zero regression surface, and deferring leaves
   no user-reachable hole. Do not hard-code `/dashboard/kb` as the only browse URL, so this slots
   in later as a follow-up rather than a rewrite.
2. **The dotted-directory edge case** — `docs.v2` takes the binary branch and 404s there instead.
   Pre-existing, unreachable from the UI.
3. **"Recently updated" landing strip.** `TreeNode.modifiedAt` is already on the `/api/kb/tree`
   wire, and the CPO argues it measures the roadmap's actual Phase-4 validation signal
   (return-to-artifact) better than a tree does. Real value, but an enhancement rather than a
   coverage hole — search covers *find*. Track it.
4. **`isContentView` trailing-slash normalisation.** `use-kb-layout-state.tsx:217` is a strict
   `pathname !== "/dashboard/kb"` while `deriveContextPathFromPathname` (`:41-44`) normalises and
   `isKbDocView("/dashboard/kb/")` is `true` — three components disagree about which screen you
   are on. Pre-existing; normalising changes desktop behaviour.
5. **Document-route loading/error branches render no header, therefore no back**
   (`[...path]/page.tsx:130`, `:161`), and `UnknownError` has no retry. A genuine dead end on a
   phone, but pre-existing and in a different component tree. **High-priority follow-up** — file
   it as `priority/p2-medium` at minimum, and note in the PR body that this plan does not fix it.
6. **Scroll restore is one-shot** (`restoredRef`), so a *second* breakpoint crossing does not
   restore tree scroll. Focus is not re-homed across the swap either.
7. **History-backed chat sheet / drawer.** Neither pushes a history entry, so Android
   hardware-back from an open sheet navigates the route away. Pattern exists elsewhere
   (`crm-surface.tsx:46`, `workstream-board.tsx:134`).
8. **The closed drawer is not `inert`/`aria-hidden`** (`layout.tsx:368` only translates it
   off-screen), so its contents stay in the tab order. Pre-existing; now more visible because the
   drawer holds a KB affordance.
9. **Two different empty-state CTAs** for one condition — `EmptyState` → "Open a Chat",
   `RailEmptyState` → "Connect a repo". Reconcile separately.
10. **`kb/loading.tsx` renders a document skeleton**, so a cold mobile KB open flashes a document
    skeleton before resolving to a file list.
11. **Settings and Conversations mobile secondary nav** keep their drawer-hosted rails —
    justified by the ADR-158 hierarchical-vs-flat rule, not an oversight.
12. **Migrating the KB gate to `useIsMobile`** — deferred (D1). Re-evaluation trigger: the AC7
    e2e arm going red, or the nine `use-media-query` mocks being consolidated into a shared helper.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Dual mount (the #6874 class) reaches `main` | Medium — it has happened, and review + compound both missed it | Single ternary on one boolean (branches cannot co-evaluate) + AC2 equality assertion **including the transition** + AC8 static guard + AC7 real-browser assertion + running `workstream-board.test.tsx` as the canary |
| `isDesktop` stale-false on desktop under React 19 hydration | Low, not disproved | Three layers: desktop-first seed (D1), the zero-deploy Workstream prod check (Phase 0.5), and AC7 real Chromium at 1280px |
| Scope creep — spec-flow surfaced 6 P1s and 5 P2s, most pre-existing | **High** | Only defects this change makes load-bearing are in scope (sync silence, search silence + persistence, drawer dead tap, browse-view states). Everything else is an enumerated Non-Goal with a tracking issue |
| A modified existing test silently weakens its assertion | Medium | AC14 — the Phase-2 commit must be unmodified-green, and the PR body enumerates every Phase-4 change |
| DD1 decided unilaterally, contradicting the operator's design intent | Medium | Phase 0.3/0.4 — DD1 is the headline sign-off question; the plan recommends but does not decide |
| Zero trees mount (both branches false) | Low | AC2 asserts `=== 1`, not `<= 1` |
| A new component uses a nonexistent `soleur-*` token (silent no-op) | Medium | Phase 4.7 — grep `app/globals.css` before use |
| ADR ordinal collision | Medium — has happened twice in one pipeline | `/ship` ordinal gate + the documented artifact-set sweep |
| Destructive row actions (delete/rename) become full-width and always-visible on touch (`globals.css:261` forces `opacity: 1` under `(hover: none)`), one mis-tap from the row's navigate target, no undo | Medium | Verify ≥44px separation in the browse view; if it fails, swipe-reveal or an overflow menu on coarse pointers — decide at the Phase 0.4 gate |

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** the "one boolean, two mutually exclusive mount sites" shape is architecturally
sound (**LOW** risk) and no materially simpler shape exists — portal-destination swap and
route-based browse were both examined and rejected with reasons (folded into "Why this shape").
The hydration analysis was judged correct and **strengthened** with a second independent reason
(`RailSlotPortal` is null until a ref callback fires), now recorded in ADR-158 and as a code
comment. `useMediaQuery` risk **MEDIUM, reducible to LOW** via the `initial` seed parameter
(D1) plus the ADR-049 mobile assertion — the prod probe was demoted from gate to sanity check
because a hook value cannot be read from a console without shipping code first. Eight
previously-unnamed risks returned; six are folded in (R1 drawer dead-end → D3; R2 lost
empty-tree recovery valve → the browse view owning its own states; R3 `KbErrorBoundary` gap →
Phase 3.3; R5 orphaned `data-tour-id` → D2; R7 static-guard honesty → Phase 1.3; R8 transition
coverage → AC2), and two were resolved as non-issues (R4 `expanded` is already hoisted; R6
`nav-drill-authority` needs no `pathname` in the new components). Phasing: recommended two PRs;
adopted as one PR with a proof-carrying commit boundary (D4, AC14). No capability gaps.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `## Files to Create` contains
`components/kb/*.tsx`)
**Decision:** reviewed
**Agents invoked:** ux-design-lead, cpo, spec-flow-analyzer
**Skipped specialists:** none — no domain leader recommended a copywriter (the only new string
is a "Browse files" label already shipped in the collapsed rail)
**Pencil available:** yes

#### Findings

- **`ux-design-lead`** — delivered `kb-mobile-drill-in-nav.pen` (136 KB) + 8 frames
  (`29-`…`36-`), committed in `15ac70b19`. Raised two flags now in Phase 0.3: the brand guide's
  0px-radius rule conflicts with the shipped 8–10px surface and the eight sibling wireframes; and
  a single coherent variant was produced rather than a 3-way fan-out, because the brief fixed
  model, frames, platform, fidelity and visual language, leaving no meaningful aesthetic axis.
  Its frame-07 implementation note — tree state must live above the route boundary or the back
  tap refetches and reads *slower* than the drawer it replaces — is satisfied: `expanded` is
  already hoisted to `useKbLayoutState`, which does not remount across routes in the segment.
- **`cpo`** — **signs off conditionally** on four conditions, all now met: (1) correct the two
  false premises (per-directory routing is not blocked; ADR-047's single-mount test covers only
  the identity components) — both corrected in Research Reconciliation; (2) bring search-state
  persistence in scope — done (Phase 3.8), because at `single-user incident` a scope-out
  justified by "the next-most-likely entry is not covered" is an anti-pattern and search is the
  primary mobile find path; (3) specify browse-view empty/error/loading in the `.pen` before code
  — Phase 0.2; (4) record the in-content-vs-drawer rule in an ADR-047 amendment — Phase 5.2.
  Confirms the `single-user incident` threshold. Confirms the IA choice (list→detail) while
  rejecting the bottom-sheet alternative as contradicting the sole taste-profile entry, and
  judges the Settings/Conversations consistency risk **justified** — KB is the only drilled
  segment whose secondary nav is hierarchical and unbounded, i.e. the only one where the
  secondary nav *is* the content.
- **`spec-flow-analyzer`** — mapped 7 mobile screens + 12 states and returned 3 P0s, 9 P1s and
  5 P2s. **P0-1** (the browse view could never render an error or empty state because `fullWidth`
  pre-empts it, stranding a user with no "Sync now") reshaped the core design — the browse view
  now owns its own states. **P0-3** (drawer dead tap) → D3. **P0-2** (document loading/error
  branches render no back at all) is real and verified but pre-existing in a different component
  tree → Non-Goal #5 with a high-priority follow-up. Its P1-3 finding that `inKbDocView` is a
  dead variable was **independently verified and corrected a false premise in this plan's own
  earlier draft**. One of its findings (P1-2, directory paths render a broken FilePreview) was
  **checked and found wrong** for ordinary directory names — see Research Reconciliation.

## Test Scenarios

1. Mobile, populated tree, browse route — tree in the content column; drawer holds a link;
   exactly one tree.
2. Mobile, document route — document renders; exactly one back per DD1; drawer link present.
3. Mobile round trip — browse → file → back, expanded folders + scroll + **search query**
   preserved, no full reload.
4. Mobile, each non-populated state — loading / 503 / 404 / unknown / empty each render inside
   the browse chrome with a reachable "Sync now".
5. Desktop, populated — tree in the rail slot, chat splitter intact, no `kb-browse-tree`.
6. Desktop, collapsed rail — icon affordance, tree DOM-removed, `RAIL_EXPAND_EVENT` dispatched.
7. Both viewports **and the transition** — exactly one tree, asserted `=== 1`.
8. Real browser at 1280 / 768 / 390 — mount placement (AC7).
9. Failure paths — sync error and search error each render a retryable row and hit Sentry.
10. Dual-mount canary — `workstream-board.test.tsx` green.

## Compliance Notes

- **`wg-every-feature-listed-in-a-roadmap-phase` — gap found.** #7186 has no milestone, and
  neither did #6903, #6915, or #6917: four mobile-revision issues shipped or shipping outside any
  phase, while **Phase 1 "Close the Loop (Mobile-First, PWA)" is closed with 0 open**. Phase 0.6
  assigns #7186 to Phase 4; the Phase-1 annotation is a separate roadmap task.
- **Roadmap staleness (non-blocking, not this plan's job):** `knowledge-base/product/roadmap.md`
  "Current State" is dated 2026-05-25 and reports Phase 4 at 56 open / 179 closed; the live
  milestone API says 77 / 193, and Post-MVP is 957 open against the roadmap's 710. Trust the API;
  file a roadmap-refresh task.
- **Constitution line 272** — screenshots at desktop, tablet, and mobile before shipping.
  **Tablet must be exactly 768px**, the switch point (Phase 6.5, AC19).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6. This one is filled.
- **`bun test` does not work in this package** — `apps/web-platform/bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]`. Use `./node_modules/.bin/vitest run <path>`.
- **`npm run -w apps/web-platform <script>` fails** — the repo root declares no `workspaces`
  field. Use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **Test paths must match the vitest project globs**: `test/**/*.test.tsx` → happy-dom,
  `test/**/*.test.ts` + `lib/**/*.test.ts` → node. A co-located `components/**/*.test.tsx` is
  silently never run; a DOM-dependent test **must** be `.tsx`.
- **happy-dom provides `matchMedia`** (measured: function, `innerWidth` 1024, `min-768` true,
  real `addEventListener`) but applies **no CSS**. So a JS breakpoint gate is testable and a CSS
  one is not — and a hook swap that bypasses existing mocks fails *silently*, not loudly.
- **A wrong Tailwind `soleur-*` token is a silent no-op** — no `tsc` error, no test failure.
  Grep `app/globals.css` first.
- **Never read the full-suite summary count as a pass signal.** `N-1/N` means a suite failed;
  `[FAIL] <suite> (0ms)` means a sub-suite crashed. This is exactly how #6874 reached `/ship`.
- **Do not open `navigation/kb-mobile-nav-redesign-wireframes.pen`** — the Pencil adapter can
  wipe valid `.pen` files on open (#3274). This plan's `.pen` is already committed.
- **Screenshot numbering is shared per domain folder.** `navigation/screenshots/` holds
  `01-`…`36-`; Phase 0.2 additions start at `37-`. PNGs must be **direct children** — nested
  paths are gitignored (`.gitignore:70`) and fail to commit silently.
- **A comment asserting an invariant is not the invariant.** `kb-layout.tsx:39-43` and
  `layout.tsx:229` both describe a doc-view back-suppression that the code does not perform
  (`inKbDocView` is dead). Two agents and one draft of this plan inherited that fiction from the
  comment. Verify wiring, not prose.

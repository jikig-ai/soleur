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
plan_revision: v3 (post deepen-plan — see Plan Review Revisions and Deepen-Plan Revisions)
---

# fix(kb): mobile drill-in navigation for the Knowledge Base 🐛

`Closes #7186`

## Enhancement Summary

**Deepened on:** 2026-08-03 · **Revision:** v3 · **Sections enhanced:** 12
**Lenses applied (10):** CTO · CPO · spec-flow-analyzer · kieran-rails-reviewer ·
code-simplicity-reviewer · scoped strong-model advisor *(v2)* — then learnings-researcher ·
architecture-strategist · test-design-reviewer · framework-docs-researcher *(v3)*

### Key improvements
1. **A single derived `treeHost` value** replaces two conditions in two files that happened to
   agree (D5). Exactly one host in every reachable cell, as a property of one value rather than of
   an 8-cell test matrix.
2. **A silent capability deletion caught and reversed.** v2's shape left the mobile document route
   with no tree anywhere — removing the only in-KB escape from the two document states that render
   no header at all, while the plan asserted "no capability change". D5 keeps the drawer tree there.
3. **Two ACs that were false on a correct implementation, fixed** — AC2 demanded `=== 1` in a cell
   whose correct count was 0, and AC6 was vacuous because the suite it named never renders `KbLayout`.
4. **Host asserted by containment, not by a testid the component emits about itself** — the v2
   form would have agreed with the bug it was written to catch.
5. **All six framework claims verified against installed versions** (React 19.1, Next 15.5,
   Playwright 1.58) — including the one the plan *rejects* acting on: no documented mechanism exists
   for the stale-`useMediaQuery` class, confirming the decision to close it empirically instead.

### New considerations discovered
- The drawer can empty itself mid-fetch on the mobile landing when `treeHost` flips — which is the
  concrete functional argument for the drawer row the operator is being asked about (DC2).
- The search query has a better home than the 382-line layout hook: `useNavResume` already owns its
  two siblings, and using it removes a `tsc`-only trap and a fixture edit.
- The collapsed-rail state is localStorage-persisted and breakpoint-agnostic, so a desktop-collapsed
  user opens the mobile drawer to a branch that renders neither the empty-tree CTA nor "Sync now" —
  pre-existing, but this plan promotes that path to the named recovery valve.
- `production` hydration does **not** reconcile className mismatches, so a mismatch introduced into
  the `fullWidth` block would be invisible in prod and self-correcting in dev.

## Overview

On a phone (`< 768px`), opening **Knowledge Base** shows a content pane with no document and no
way to browse in place. Since PR #4810 (ADR-047, the single nav rail) the KB file tree is
portaled into the hamburger drawer, so `/dashboard/kb` renders nothing in the content column
until a file is already selected. The mobile polish pass (#6917) added a **stopgap only** — an
empty state in `components/kb/kb-doc-shell.tsx` ("Open a file to see it here" + a "Browse files"
button dispatching `RAIL_EXPAND_EVENT`). That removed the blank-pane confusion; it did not give
the KB a navigation model. This is the third pass on this surface (#6915 and #6917 were both
stopgaps) — the repeat is itself the signal.

The fix is a **list → detail drill-in on mobile**, built entirely on state that already exists.

### The shape

There is exactly one `FileTree` browse surface in the app (`KbSidebarShell`). This plan does not
add a second one — it makes that one surface's **host** a function of state the KB layout already
computes:

| Viewport | State | Where the ONE tree mounts | Content column |
|---|---|---|---|
| `>= 768px` | any | rail secondary slot (portal) | **unchanged** |
| `< 768px` | `fullWidth` (loading / 503 / 404 / unknown / empty) | rail slot — **unchanged, still in the drawer** | the existing `fullWidth` state bodies — **unchanged** |
| `< 768px` | populated, at `/dashboard/kb` | **content column** — the browse view | the tree |
| `< 768px` | populated, at `/dashboard/kb/<path>` | rail slot — **unchanged, still in the drawer** | the document |

**One derived value selects the host** (`treeHost`, D5). The table above is not enforced by two
independent conditions that happen to agree — it is a single `"rail" | "content"` value computed
once in `useKbLayoutState` and consumed by both call sites. The content column hosts the tree only
on a mobile, populated, landing render; **every other cell hosts it in the rail**, including the
mobile document route, so the drawer keeps the tree exactly as it does today.

Three properties fall out of that table, and they are what make this change small and safe:

1. **The `fullWidth` block is untouched.** Loading, 503, 404, unknown and empty already render a
   `md:hidden` mobile header plus the right state body, and on mobile the drawer still holds the
   real `KbSidebarShell` in those states — so the empty-tree CTA ("Connect a repo or add docs")
   and the "Sync now" self-recovery valve stay exactly as reachable as they are today. No new
   states to design, no new error UI, no second sync control.
2. **No viewport-derived value ever reaches a first-paint render.** `loading` starts true, so
   `fullWidth` short-circuits before the `isDesktop` branch is evaluated; and `RailSlotPortal`
   returns `null` until its container is set by a ref callback, so the portal side is not
   server-rendered either. That is why **`useMediaQuery` is not modified at all** — see D1.
3. **Back-navigation already works.** `components/kb/kb-content-header.tsx:36-44` renders an
   `md:hidden` back chevron ("Back to file tree") to `/dashboard/kb`. Today it lands on the
   stopgap; after this change it lands on the browse view. No new code.

The whole product change is: one prop on `KbSidebarShell`, one condition on the portal, one
branch in `KbMobileLayout`, deleting the stopgap, lifting the search query so it survives the
drill-in, and correcting two comments that describe behaviour the code does not perform.

### Why this shape and not the alternatives

- **NOT a CSS `hidden md:flex` / `md:hidden` dual-render of the tree.** ADR-047 rejects it
  ("jsdom can't distinguish `display:none`, and a hidden-but-mounted secondary nav re-creates the
  double-mount hazard"), and it shipped and regressed once: PR #6874's initial commit mounted both
  the desktop 7-column board and `MobileBoard`, duplicating every `IssueCard`, breaking **12
  tests** with "Found multiple elements" *and* running the hidden board's `sessionStorage` effect
  on desktop. **Precise constraint:** no CSS dual-render of the same tree component — use a JS
  branch. (CSS remains correct for non-duplicating chrome; the existing `md:hidden` header is
  fine and stays.)
- **NOT a new breakpoint hook or a second render-time `matchMedia` read.** The KB has one
  breakpoint authority; a second can disagree with the first, and that is how two trees mount.
- **NOT a bottom-sheet file picker over the document** — the current drawer model with nicer
  chrome: no URL, not deep-linkable, and "KB opens on nothing" returns whenever there is no last
  document. It also contradicts the single recorded taste-profile entry
  (`dashboard / workstream-inline-crud-optimistic` — in-content and inline over sibling/modal).
- **NOT a portal-destination swap.** React remounts on container change, so no continuity is
  gained — and with a document open on mobile there is no content-column slot, so the target
  would be null and the drawer would go empty again (the #6917 bug, inverted).
- **Per-directory routing is deferred, not rejected** — Non-Goals #1 has the corrected reasoning.

> No `spec.md` exists for this branch — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Plan Review Revisions (v1 → v2)

v1 was reviewed by CTO, CPO, spec-flow-analyzer, Kieran, code-simplicity, and a scoped
strong-model advisor. Six findings changed the design; recording them so the reasoning is not
re-litigated at `/work`.

| # | Finding | Source | Resolution |
|---|---|---|---|
| R1 | **v1's hydration-safety argument died the moment v1's own Phase 3.2 existed.** v1 introduced mobile-only chrome (a pinned sync footer, a DD1 back arrow) into the `fullWidth` block, gated on a JS boolean — consumed *during* `loading`, i.e. exactly the first-paint render v1 argued was safe. Server would emit desktop chrome, mobile hydration would emit different chrome: a React 19 mismatch on the most common first-paint state, on the surface this plan exists to fix. | Kieran P0-1 | **v2 does not touch the `fullWidth` block at all.** On mobile in those states the drawer keeps the real `KbSidebarShell`, so the sync/empty-CTA valve is as reachable as today with zero new chrome. The safety argument is restored intact — and is now structural, not argued. |
| R2 | **`useMediaQuery(query, initial)` was a provable no-op on the client** (`initial` is returned only on the `typeof window === "undefined"` branch; the `useState` initializer reads real `matchMedia` on the hydration render), so it could only change SSR output — and seeding `true` would have *created* R1's mismatch. Defending a never-established mechanism with a no-op is speculative complexity. | code-simplicity #4, Kieran P0-1 | **`hooks/use-media-query.ts` is not modified.** The advisor's `useSyncExternalStore` rewrite is also dropped: it changes `getServerSnapshot` for three other consumers to defend the same unestablished mechanism. AC7 (real Chromium at both viewports) is the actual closure and is kept. |
| R3 | **`KbTreePanel` extraction was a file move where a prop would do.** `KbSidebarShell` differs between hosts in exactly two ways: `data-testid` and `useRailCollapsed()`. | code-simplicity #1 | One optional prop (D2). This also dissolves the orphaned `data-tour-id` problem for free (Kieran P1-4) — the id never moves — and removes Phase 2, the two-commit protocol, the static importer guard, and two ACs. |
| R4 | **The drawer "Browse files" dead tap was created by v1, not pre-existing** — v1 added a link to the route you are already on, then added a new window event to fix it. | code-simplicity #2 | `RAIL_CLOSE_EVENT`, `kb-rail-browse-link.tsx`, and the extra layout listener are all cut (D3). |
| R5 | **The sync-error and search-error rows were scope creep wearing a threshold justification.** Both code paths are untouched by this diff and fail identically on desktop today. The `single-user incident` anti-pattern covers uncovered *entry paths into the capability being shipped*, not every latent defect in every imported component — v1's own Risks table rated scope creep High and then named these as the exception. | code-simplicity #3 | Cut, filed as `type/bug` follow-ups. **Search-query persistence is kept** — that one is a regression *this diff introduces* (the mobile host unmounts on navigation where the portal did not), so it is a no-regression obligation, not a feature. |
| R6 | **`kb-browse-tree` would only exist in the populated branch**, so v1's AC1/AC7/AC11 were false on a correct implementation whenever the tree was empty/errored — passing only by fixture accident (the e2e seeds a populated tree at `:292-298`, while the adjacent mobile test at `:948-953` seeds an **empty** one). | Kieran P0-2 | v2's state table makes the populated/non-populated split explicit, and every AC names which fixture it applies to. |

Also corrected from v1's own text: the e2e `DESKTOP` viewport is `1280×900` (`:383`), not
`1280×800`; the mobile `test.use` blocks are `:901` and `:912`; `KbSyncStatus` in the rail footer
is `kb-sidebar-shell.tsx:160`; `deriveContextPathFromPathname` is `use-kb-layout-state.tsx:40-46`.

## Deepen-Plan Revisions (v2 → v3)

Deepened by learnings-researcher, architecture-strategist, test-design-reviewer, and
framework-docs-researcher. All six framework claims v2 depends on were **verified against the
installed versions** (React ^19.1.0, Next ^15.5.21, Playwright ^1.58.2) — see Framework
Verification below. Seven findings changed the plan.

| # | Finding | Source | Resolution |
|---|---|---|---|
| R7 | **AC2 was false on a correct implementation.** At `{mobile, populated, /dashboard/kb/<path>}` v2's portal condition (`isDesktop \|\| fullWidth`) was `false` and `KbMobileLayout` rendered the doc shell — **zero** trees. v2's own state table and Test Scenario 2 said so, while AC2 demanded `=== 1` across all eight cells. This is the R6 defect class recurring on the *count* axis after R6 fixed it on the *fixture* axis. | architecture P0-1 **and** test-design Q1 (independently) | **D5** — a single derived `treeHost` value. Cell 7 becomes rail-hosted, so exactly one host holds in **all** cells and AC2 is literally true. AC2 is also restated as a per-cell host table, not a scalar. |
| R8 | **Cell 7 silently deleted a capability.** Today a mobile user on a document has the whole tree in the drawer — doc→doc is two taps, and it is the **only** in-KB escape from the two document states that render no header at all (`[...path]/page.tsx:130-140` loading, `:159-170` generic error; the `not-found` branch at `:142-157` *does* carry a back link, so v2's Non-Goals #6 was over-broad). v2 emptied that slot while asserting the diff was "two DOM positions" with no capability change. | architecture P0-2 | D5 restores the drawer tree on mobile document routes. Non-Goals #6 and the User-Brand Impact wording are corrected. |
| R9 | **The single-host property was emergent, not structural** — split across `isDesktop \|\| fullWidth` in one file and an `isContentView` branch reachable only under `!fullWidth && !isDesktop` in another, with no shared term. An 8-cell test matrix stood in for a guarantee. ADR-047 Decision 3 exists because a duplicated drill predicate is how drill state diverges. | architecture P0-3 | **D5** — `treeHost` derived once in `useKbLayoutState`, consumed by both call sites. ~6 lines; makes the invariant a property of one value. |
| R10 | **The search-query lift had a better home.** Widening `UseKbLayoutStateResult` (already a 382-line hook owning four unrelated concerns) breaks a typed literal at `tsc` time. But `useNavResume` already owns exactly this concern for the query's two siblings — `readExpanded`/`writeExpanded` and `readScrollTop`/`writeScrollTop`. | architecture P1-2 | Route the query through `useNavResume` instead. The `tsc` trap and the `kb-reconnect-banner.test.tsx` fixture edit both evaporate. |
| R11 | **Host asserted by a testid the component emits about its own placement is tautological.** If the implementer passes `host="content"` at the rail portal by mistake, the node renders *inside the rail slot* carrying `data-testid="kb-browse-tree"` and every testid-based assertion reports "it is in the browse host" — the test agrees with the bug. Separately, `kb-rail-tree` is attached even when the tree is DOM-removed (`kb-sidebar-shell.tsx:107` puts it outside the `collapsed ?` ternary — the file's own comment says so, and `e2e:604` asserts it attached alongside `kbLongFile` count 0), so v2's AC7 was green on a rail with no tree. | test-design Q2, Q6 | Host is asserted by **containment** (`toContainElement` / `secondarySlot(page).getByRole(...)`), and every host assertion names the `role="navigation"` node, never a wrapper testid alone. |
| R12 | **AC6 was vacuous.** `test/nav-rail-drill.test.tsx` renders `<DashboardLayout><div>content</div></DashboardLayout>` and never imports `KbLayout` — with no KB layout in the tree there is no portal source, so "the rail slot contains no KB tree" is true for *every* implementation, including one that mounts no tree at all. | test-design Q6 | Relocated to the browse test under `RailSlotHarness`, where a KB layout actually exists. |
| R13 | **AC3 was not machine-checkable and forbade correct refactors.** "`git diff` shows no hunk inside it" has no command and needs a human to eyeball a line range. | test-design Q6 | Replaced with the behavioural invariant it was proxying: render the `fullWidth` block at both `mockIsDesktop` values and assert identical `innerHTML`. That pins "no JS-gated DOM in the `fullWidth` block" — what D1 reason 1 actually requires — and survives refactoring. |

Four in-scope changes had **no** coverage in v2 and now do: the `host` guard against
`RailCollapsedProvider` leaking desktop collapsed state into the content column, the
`KbErrorBoundary` move, the stopgap deletion, and DD1's outcome. One phantom reconciliation was
deleted: v2's Phase 3.2 claimed the `#4915` landing-header case changes under DD1(a), but that
case uses `EMPTY_TREE_FETCH()` → `fullWidth` → a block DD1(a) is forbidden to touch, so the two
cannot meet (test-design Q4d).

### Framework Verification (installed versions, not memory)

| Claim | Verdict | Evidence |
|---|---|---|
| `createPortal` children read context from the **React** tree, not the DOM tree | **CONFIRMED** | React ^19.1.0 — react.dev/reference/react-dom/createPortal; the codebase already relies on it (`kb/layout.tsx:51-56`) |
| Passing a **different container** to `createPortal` recreates the portal content | **CONFIRMED** | React docs, verbatim: "Passing a different DOM node during an update will cause the portal content to be recreated." This is what makes the rejected portal-destination-swap design worthless |
| Conditionally returning `null` instead of calling `createPortal` is the sanctioned SSR-safe pattern | **CONFIRMED** | React's own error text instructs "Render them conditionally so that they only appear on the client render" |
| A ref-callback-filled container means the portal renders neither on the server nor on the hydration render | **CONFIRMED** | Ref callbacks fire after render; `railSlotEl` is `null` in both passes. D1 reason 2 holds |
| Next App Router **preserves** a segment layout across `/dashboard/kb` ↔ `/dashboard/kb/<path>` | **CONFIRMED** | Next ^15.5.21 — "On navigation, layouts preserve state, remain interactive, and do not rerender." Remount requires the segment itself or its dynamic params to change. This is what preserves `expanded` (and, after R10, the search query) |
| A documented React 19 mechanism by which `useState(() => matchMedia(q).matches)` + `useEffect` returns a **stale** client value | **NO EVIDENCE** | No upstream issue, changelog entry, or documented behaviour found. The 2026-06-03 learning's call site no longer exists. Confirms D1/R2: do not modify the hook; close the risk empirically via AC7 |
| Playwright `toBeAttached()` / `not.toBeAttached()` / `toHaveCount(0)` | **CONFIRMED** | Playwright ^1.58.2; `toBeAttached` since 1.33 and already used at `e2e:604` |

## Research Reconciliation — Spec vs. Codebase

Every row verified against the working tree. Four corrected a claim in the issue, a domain
review, or an earlier draft of this plan.

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "the tree is portaled from `app/(dashboard)/kb/layout.tsx`" (issue body) | Path is `app/(dashboard)/dashboard/kb/layout.tsx` — extra `dashboard/` segment. Portal at `:57-59`. | Corrected path used throughout. |
| **"`layout.tsx` suppresses the band's back in the KB doc view"** (v1 draft; also the comment at `kb/layout.tsx:39-43`) | **FALSE.** `const inKbDocView = isKbDocView(pathname)` at `app/(dashboard)/layout.tsx:229` is computed and **never used** — single grep hit, confirmed by two independent reviewers. The mobile band at `:403-410` is `suppressBack suppressSectionTitle` **unconditionally**, and lives *inside* the drawer. So the mobile KB landing has today **no reachable in-page back at all** — only `drawer-back-to-menu` behind the hamburger. | DD1 resolves who owns back on the browse view; the dead variable and its false comment are removed in Phase 2. |
| **"`/dashboard/kb/<dir>` renders a directory as a file"** (v1 draft; also spec-flow P1-2) | **FALSE for ordinary directory names.** `getKbExtension("engineering")` returns `""` (`lib/kb-extensions.ts:16`, `lastDot <= 0`) and `isMarkdownKbPath` returns true for `""` (`:20-23`) — so a directory takes the *markdown* branch → 404 → `clearKbPath(); router.replace("/dashboard/kb")`. A silent bounce, not a mis-render. **TRUE only for a dotted directory name** (`docs.v2` → `.v2` → FilePreview). Separately: **no directory URL is reachable from the UI** — directories are `<button onClick={toggle}>`, only files are `<Link>`. | Non-Goals #1 rewritten: per-directory routing is additive with zero regression surface, and deferring leaves **no user-reachable hole**. Dotted-directory edge case → Non-Goals #2. |
| "ADR-047 forbids a second KB browse component" | Over-read. ADR-047 line 52 scopes the hard single-mount invariant to `OrgSwitcherContainer` + `LiveRepoBadge`, and `test/nav-single-mount.test.ts` asserts only those two. The binding constraint is the **rejected alternative** at line 80 — CSS-hiding the same nav. | Constraint restated as "no CSS dual-render of the same tree; use a JS branch", so the implementer does not design around a rule that does not exist. |
| "Use `use-is-mobile.ts` **or** the `useMediaQuery` gate the Workstream board uses" | KB already uses the second (`hooks/use-kb-layout-state.tsx:73`). **Eight** test files mock `@/hooks/use-media-query`, all arity-0 arrows ignoring their arguments (`grep`-verified), plus `test/use-media-query.test.tsx` exercising the hook directly. | Keep `useMediaQuery` **unmodified** (D1). Switching to `useIsMobile` would silently bypass all eight mocks (it would not crash — happy-dom has `matchMedia` — it would flip branches without failing). |
| "happy-dom has no media queries, so both trees mount" | Precise: happy-dom applies no *CSS* media queries. It **does** provide `window.matchMedia` — **measured here**: `typeof === "function"`, `innerWidth === 1024`, `min-768` → `true`, `max-767` → `false`, real `addEventListener`. | A JS branch is testable; a CSS gate is not. Measured, not assumed. |
| `test/kb-sidebar-collapse.test.tsx`'s `useMediaQuery: () => false` exists to avoid unmocked `react-resizable-panels` (v1 draft) | **FALSE.** `test/kb-layout.test.tsx` mocks *neither* and renders `KbDesktopLayout` (which imports `Group`/`Panel`/`Separator` directly) at happy-dom's 1024px — 7/7 green. Real `react-resizable-panels` renders fine unmocked. | Phase 3.1's desktop-arm argument is re-derived from what the assertions actually cover, not from the false causal claim. |
| `segment-to-drill-level.ts` already has a drill concept | Different axis: `segmentToDrillLevel` is *rail* drill and collapses landing + doc into one `"kb"` level. `isKbDocView` is the depth-within-section predicate. | Reuse `isKbDocView`; no new drill vocabulary. |
| `nav-drill-authority.test.ts` is a style guard | A **build-failing static guard**: any file but `hooks/segment-to-drill-level.ts` matching `.startsWith("/dashboard/(kb\|settings\|chat)")` fails. | No new component needs `pathname` — `isContentView` is already in the hook. |
| Learning `2026-06-03-…-usemediaquery` — "stayed false at 1280px under React 19" | Verified: an `applyRailWidth = kbExpanded && isDesktop` **first-interactive-frame** inline-style gate in `app/(dashboard)/layout.tsx`. That call site **no longer exists**. Mechanism never established. | Not defended with a code change (R2). Closed empirically by AC7 (real Chromium, both viewports, every PR). |
| "Local `bun run dev` is broken" | Not re-verified; nothing here depends on a dev server. | Verification is `tsc` + vitest + ADR-049 e2e + prod device mode. |

## Premise Validation

- `#7186` — **OPEN**, `type/bug`, `priority/p2-medium`, `domain/engineering`, **no milestone**.
- `ADR-047` exists, `status: active`; this plan adopts none of its rejected alternatives.
- Highest existing ADR ordinal **157** → next free **158** (provisional; `/ship` re-verifies).
- Prior-art commits verified by `git log`: `7dc1a355c` (#4810), `099ab2e90` (#6874 + its
  `useMediaQuery` review fix), `6eecc26de` (#6915), `b470cc2ca` (#6917).
- Live milestones: `Phase 4: Validate + Scale`, `Phase 5`, `Post-MVP / Later`. **Phase 1
  "Close the Loop (Mobile-First, PWA)" is closed** while mobile-first demonstrably is not — see
  Compliance Notes.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200`, matched against every path in the
file lists. **None.**

## User-Brand Impact

**If this lands broken, the user experiences:** the Knowledge Base — the artifact the brand guide
names as the moat ("your company's institutional memory") — is unusable. Two concrete failure
artifacts: (a) on a phone, `/dashboard/kb` renders a blank content column; (b) on desktop, an
inverted or stale `isDesktop` moves the file tree **out of the persistent rail into the content
column**, so the daily-driver desktop KB loses its navigation and its resizable chat splitter in
one step.

**If this leaks, the user's data is exposed via:** nothing. This moves an already-authorized
client component between two DOM positions inside the same authenticated layout. No new route,
API surface, persistence, or third-party call; the same single `/api/kb/tree` SWR fetch serves the
one tree wherever it mounts.

**Brand-survival threshold:** `single-user incident` — confirmed by CPO, neither raised nor
lowered. First-contact surface; the failure mode directly falsifies the one positioning clause
the brand-guide validation review mandated ("delivery-agnostic: accessible from any device"); and
this is the **third** pass after two stopgaps. Not higher: no data loss, no PII, no auth boundary,
no irreversible action — navigational only.

Consequences honoured: CPO sign-off at plan time, `user-impact-reviewer` at review time, the
escalated review panel, `gdpr-gate` run rather than assumed, and `deepen-plan` before `/work`.
**Scope discipline under this threshold:** the anti-pattern it forbids is leaving an *entry path
into the shipped capability* uncovered — which is why search-query persistence is in scope (this
diff breaks it) while the pre-existing sync/search silent failures are not (untouched code paths,
identical on desktop today). Per-directory routing is likewise safe to defer: no directory URL is
reachable from the UI.

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-158` — "The KB file tree mounts by breakpoint: nav rail on desktop, content column
on mobile."** In-scope task of THIS plan (Phase 4), per `wg-architecture-decision-is-a-plan-deliverable`.

**Decision (one clause).** Written **without naming implementation variables** — an ADR that names
a local `const` is falsified by the next refactor (architecture P1-4):

> The KB's single browse surface has exactly one host at any instant. The rail slot hosts it,
> except on a below-`md` viewport at the KB landing with a populated tree, where the content column
> does. It is never mounted in both, and never CSS-hidden in one.

Cite today's expression (`treeHost`, D5) in **Consequences** as *the current implementation of* the
clause, alongside the two structural safety facts: no JS-gated DOM in the `fullWidth` block, and
`RailSlotPortal` returns `null` until its ref callback fires (`rail-slot.tsx:58-62`,
`layout.tsx:161`, `:624`).

**Alternatives Considered** — the two that were seriously weighed: the CSS `hidden md:flex` /
`md:hidden` dual-render (rejected — ADR-047 rejects it and #6874 proved the regression), and a
bottom-sheet file picker over the document (rejected — no URL, not deep-linkable, contradicts the
recorded taste profile).

Deliberately **not** recorded as a decision: a generalisable "hierarchical nav goes in-content,
flat nav stays in the drawer" rule. It has one known instance and one known counterexample
(Settings, Conversations); writing a rule for a future that does not exist yet is how you get a
constraint someone designs around in 2027. Non-Goals #10 states the observed fact without
elevating it to a rule.

**Amend `ADR-047` as a dated append-only `## Amendment` section** — following that file's own
precedent (it already carries a 2026-06-22 amendment) — and **do not edit Decision 2's sentence in
place**, or the record of what was decided in 2026-06 is erased. The v2 wording (`md+` qualifier)
was also simply wrong: the portal is live *below* `md` in every non-populated state, so the
breakpoint is not the discriminator. And "a section whose tree is not the primary content" was the
very generalisation this plan declines to record, in a vaguer form. Write the narrow clause:

> **Amendment 2026-08-03 (#7186):** Decision 2 stands unqualified as the default. One scoped
> exception (ADR-158): the KB's browse surface may render in the content column instead of the rail
> slot when — and only when — the content column has no document to display and the viewport is
> below `md`. It is never mounted in both hosts and never CSS-hidden in one. ADR-158 is the sole
> authority on that condition; this ADR does not restate it.

Add ADR-158 to `related_adrs`. Do not touch the rejected-alternatives table — the CSS-hide
rejection is exactly what this plan honours. Keeping the exception's definition in one place avoids
the split-authority failure ADR-047's own Decision 3 exists to prevent.

Ordinal caveat: 158 is provisional. If renumbered at `/ship`, **sweep the whole artifact set in
one edit** — `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-7186-kb-mobile-drill-in-nav/`
plus this body and AC8 — so no AC verifies a nonexistent file.

### C4 views

**No C4 impact.** Cited against all three model files, not a keyword grep:

- `spec.c4` (54 lines, read in full): 5 element kinds — `actor`, `system`, `container`,
  `database`, `component`; tags `external`, `selfhosted`. No UI-composition kind exists.
- `views.c4` (62 lines, read in full): exactly three views — `context` (L1),
  `containers of platform` (L2), `components of platform.plugin` (L3). **The only L3 view is over
  the Soleur *plugin*, not the web app.** The web UI's finest granularity anywhere in the model is
  the container `platform.webapp.dashboard` ("Conversation UI, knowledge base viewer, session
  management"). A rail-vs-content-column distinction is one level below anything modelled.
- `model.c4` (594 lines, grepped for `knowledge|kb|nav|rail|tree|mobile|file`): the only `kb`
  element is `platform.plugin.kb = database "Knowledge Base"` plus its edges (`hooks -> kb`,
  `api -> kb`, `skills -> kb`, `agents -> kb`). None is touched.

Completeness enumeration: **(a) external human actors** — `founder`, `emailSender`,
`betaContact`, `contributor`: none added, none gains or loses access. **(b) external systems /
vendors** — none added. **(c) containers / data stores** — none; the same `swrKeys.kbTree()` fetch
serves the one tree at either host. **(d) actor↔surface access relationships** — unchanged; same
routes, auth and authorization grain, no sharing/ownership change, no element description
falsified.

No `.c4` edit → **no** `scripts/regenerate-c4-model.sh` and `model.likec4.json` unchanged.

## Observability

The changed surface is client-side React under `app/`, `components/`, `hooks/` — outside the
Phase-2.9 mandatory trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
`plugins/*/scripts/`), introducing no infrastructure. Declared anyway, because a navigation
surface that fails silently is indistinguishable from a working one.

```yaml
liveness_signal:
  what: the ADR-049 headless-Chromium assertion in nav-states-shell.e2e.ts — at 1280x900
        kb-rail-tree attached AND kb-browse-tree absent; at 390x844 with a POPULATED tree the
        inverse; at 390x844 with an EMPTY tree kb-rail-tree attached and kb-browse-tree absent
  cadence: every PR (e2e job) and every merge to main
  alert_target: the PR check itself (red = blocked merge)
  configured_in: apps/web-platform/e2e/nav-states-shell.e2e.ts
error_reporting:
  destination: Sentry — the existing KbErrorBoundary plus
               reportSilentFallback(err, { feature "kb-tree", op "fetch-tree" })
               at hooks/use-kb-layout-state.tsx:95,119. No new sink; no new emit site.
  fail_loud: yes — a tree-fetch throw surfaces as WorkspaceNotReady / NoProjectState /
             UnknownError, never a silent blank
failure_modes:
  - mode: two trees mount at once (the #6874 dual-mount class)
    detection: the exactly-one assertion across both breakpoint values x both routes x both
               tree fixtures, plus across a desktop<->mobile mock flip
    alert_route: red CI check
  - mode: zero trees mount (both hosts skipped)
    detection: the same assertion tests length === 1, never <= 1
    alert_route: red CI check
  - mode: isDesktop wrong on a real desktop browser (the 2026-06-03 class) — invisible to
          happy-dom, which has no hydration and no CSS
    detection: the 1280x900 arm of the e2e assertion (real Chromium)
    alert_route: red CI check
  - mode: search query silently lost across the new browse -> doc -> back drill-in (a
          regression this diff would otherwise introduce, since the mobile host unmounts on
          navigation where the portal did not)
    detection: a test asserting the query survives the round trip
    alert_route: red CI check
logs:
  where: Sentry (client), via KbErrorBoundary + reportSilentFallback — unchanged
  retention: existing Sentry retention, unchanged
discoverability_test:
  command: >-
    cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-layout.test.tsx
    test/kb-mobile-browse.test.tsx test/kb-sidebar-collapse.test.tsx
    test/kb-tree-scroll-resume.test.tsx test/kb-layout-panels.test.tsx
    test/kb-layout-chat-close-on-switch.test.tsx test/kb-layout-thread-info-prefetch.test.tsx
    test/use-media-query.test.tsx test/light-theme-tokenization.test.tsx
    test/workspace-context-band.test.tsx test/nav-rail-drill.test.tsx
    test/nav-drill-authority.test.ts test/nav-single-mount.test.ts
    test/components/kb/kb-reconnect-banner.test.tsx
    test/components/workstream/workstream-board.test.tsx
  expected_output: "vitest reports `Test Files  N passed (N)` with zero failed files"
```

No `ssh` appears in any verification path. (The command above is the single canonical suite list —
Phase 5.2 references it rather than restating a divergent set.)

## Encryption Posture

Not applicable — no persistent data store and no new cross-component or network connection.
Phase 2.11 detection (`.tf`, `supabase/migrations/*.sql`, `cloud-init*`, `docker-compose*`)
matches nothing in the file lists.

## GDPR / Compliance

Run, not assumed (required at this threshold). **Fast pass:** no schema, migration, auth flow,
API route, or `.sql` file touched; no new processing activity, no LLM or external call, no new
distribution surface, no change to what data is read or displayed. None of the four expansion
triggers fire. Re-run `/soleur:gdpr-gate` against the actual diff at `/work` time.

## Infrastructure (IaC)

Not applicable. Pure code change against an already-provisioned surface.

## Hypotheses

Not a network/SSH issue; no trigger pattern from the network-outage checklist matches. Skipped.

---

## Key Decisions

### D1 — `hooks/use-media-query.ts` is not modified

**No `initial` parameter, no `useSyncExternalStore` rewrite, no `useIsMobile` swap.**

The v1 seed was a **provable no-op on the client**: `initial` would be returned only on the
`typeof window === "undefined"` branch, while the `useState` initializer synchronously reads
`window.matchMedia(query).matches` on the hydration render. It could therefore only change SSR
output — and seeding `true` would have *created* the mismatch it was meant to prevent, because
v1's own Phase 3.2 introduced mobile-only chrome consumed during `loading`. v2 removes that chrome
entirely, so there is nothing to seed against.

**Why raw `useMediaQuery` is safe here — two structural reasons, both verified, both preserved by
v2's shape:**
1. `isDesktop` is never consumed on a first-paint render. `use-kb-layout-state.tsx:140` sets
   `loading = treeData === undefined && …`, the SWR fetch has no `fallbackData`/SSR provider, and
   `kb/layout.tsx:37` computes `fullWidth` from it — so server and first client paint both render
   the `fullWidth` block, whose only breakpoint gating is CSS (`md:hidden`, `:72`). **v2 adds no
   JS-gated DOM to that block; that is the load-bearing constraint on the implementation.** This
   is the identical precondition documented verbatim on the Workstream board gate
   (`components/workstream/workstream-board.tsx:108-116`).
2. `RailSlotPortal` returns `null` until `railSlotEl` is set, and `railSlotEl` is a
   `useState(null)` filled by a **ref callback** (`app/(dashboard)/layout.tsx:161`, `:624`) — null
   on the server *and* on the hydration render. So the portal-side condition is not
   server-rendered either. **Write this as a comment at the portal**: if anyone ever makes the
   rail slot SSR-resolvable, this acquires a hydration mismatch.

Reason 1's guarantee is only as strong as "no JS-gated DOM in the `fullWidth` block". Phase 2 must
not add any, and AC3 pins it.

**Residual risk** — the 2026-06-03 stale-boolean class (different, now-removed call site;
mechanism never established) is closed **empirically, not by code**: AC7, real Chromium at both
viewports on every PR. happy-dom cannot see the class at all (no hydration, no CSS).

**Known second breakpoint read, and why it is safe:** `768` also appears as a bare literal in
`app/(dashboard)/layout.tsx:257` (inside the `RAIL_EXPAND_EVENT` handler) and `:281` (the drawer
auto-close on md-crossing). These are **event-time imperative reads**, not render-time gates — they
cannot disagree with `isDesktop` about what is *rendered*, only about what an event does. Leave
them; state the distinction in the ADR rather than extracting a shared constant this plan has no
other use for.

### D2 — One prop on `KbSidebarShell`, not a file extraction

`KbSidebarShell` differs between the two hosts in exactly two ways: `data-testid="kb-rail-tree"`
and `useRailCollapsed()`. That is a prop, not a new module. Take a **named host**, not a boolean —
`inRail={false}` is boolean-blind at the call site, and a named host composes directly with D5's
`treeHost` value:

```tsx
export function KbSidebarShell({ host = "rail" }: { host?: "rail" | "content" }) {
  // The rail's collapse axis is meaningless in the content column — and this guard cannot
  // be moved to the provider. RailCollapsedProvider wraps <main> as well as the rail
  // (layout.tsx:295-735) and MUST, because the portaled shell reads context through the
  // REACT tree — i.e. from kb/layout.tsx, which sits under <main> (rail-slot.tsx:36-45).
  // Narrowing the provider to the <aside> subtree would break ADR-047 Decision 2's
  // context-follows-the-React-tree guarantee. Consumer-side disambiguation is the only
  // available remedy, so this is a fix, not a workaround.
  const collapsed = useRailCollapsed() && host === "rail";
  …
  <div data-testid={host === "rail" ? "kb-rail-tree" : "kb-browse-tree"}
       data-tour-id="action:kb-tree" …>
```

Note for the test author: `data-testid="kb-rail-tree"` sits on the **outer wrapper, outside** the
`collapsed ?` ternary (`kb-sidebar-shell.tsx:107` — the file's own comment says the wrapper
"always renders to anchor present/absent assertions", and `e2e:604` asserts it attached while
`kbLongFile` count is 0). So *attached* ≠ *tree present*, and a testid the component emits about
its own placement cannot detect mis-placement. Every host assertion therefore names the
`role="navigation"` node and asserts **containment** (R11).

Four things this buys over v1's `KbTreePanel` extraction: no ~90-line file move; `data-tour-id`
never has to be "carried" anywhere, so the guided-tour anchor (`components/tour/tour-steps.ts:126`)
cannot be orphaned; no static importer guard whose own comment admits it does not prove the
property it is named after; and no two-commit "the extraction was faithful" protocol, because
nothing is extracted.

The `&& inRail` guard is not optional. `RailCollapsedProvider` wraps `<main>` as well as the rail
(`app/(dashboard)/layout.tsx:295`–`:735`), so a user who collapsed the desktop rail and then loads
on a phone would get the collapsed icon column rendered *in the content pane* without it.

`KbErrorBoundary` goes **inside** `KbSidebarShell` so both hosts inherit it — the rail tree has the
same gap today, and wrapping only the new host creates an asymmetry someone later "fixes" in the
wrong direction.

### D3 — The mobile rail slot renders nothing; no new event

On a KB route the drilled drawer already contains the workspace switcher and
`drawer-back-to-menu → /dashboard`, so it is not blank. And the browse view is *literally the
content directly behind the drawer* — a "Browse files" row's only job would be to close the drawer
that is covering it. v1 added that row, thereby creating a dead tap (the drawer auto-closes on
`[pathname]` only, `layout.tsx:232-234`), and then added a new window event to fix the problem it
had just created.

So: `{isDesktop || fullWidth ? <KbSidebarShell /> : null}` inside the one `RailSlotPortal`.
`RAIL_CLOSE_EVENT`, `kb-rail-browse-link.tsx`, and the extra layout listener are all cut.

**Known transition — the drawer can empty itself mid-fetch.** On mobile at `/dashboard/kb`,
`treeHost` flips over the fetch lifetime: `loading` → `"rail"` (tree in the drawer) → data lands
populated → `"content"` (tree in the content column, portal null). A user who opened the hamburger
*during* the fetch — which the #6917 stopgap explicitly trained them to do, and which is the only
nav on that screen — sees the drawer's tree vanish while the drawer is open, leaving the empty
secondary slot. The drawer auto-closes only on `[pathname]` (`layout.tsx:232-234`) and the pathname
did not change. On a warm `swrKeys.kbTree()` cache (ADR-067) the window is near-zero; on a cold
mobile load it is the length of the tree fetch. This is not the R4 dead tap re-litigated — that was
a self-created affordance; this is a state-transition reconciliation. It is named in Test Scenarios
and asserted in the e2e round trip.

**If the operator wants the wireframe's "Browse files" row** (frame 34 shows one), implement it in
`app/(dashboard)/layout.tsx` itself, where `setDrawerOpen` is already in scope (`:138`) and
`drill === "kb"` is already computed from `segmentToDrillLevel` (`:199`) — a static link with no
`KbContext` dependency has no reason to be portaled, and no new event is needed because the setter
is right there. **The transition above is the concrete functional argument for that row**: it is
what the drawer would show instead of an empty slot. That is a Phase 0.4 decision (DC2), not an
implementation default.

### D5 — One derived `treeHost` value, not two conditions that happen to agree

v2 selected the host with two expressions in two files sharing no term: `isDesktop || fullWidth`
at the portal, and an `isContentView` branch inside `KbMobileLayout` reachable only when
`!fullWidth && !isDesktop`. Mutual exclusion held only by a conjunction the code never stated, and
an 8-cell test matrix stood in for the guarantee. ADR-047's Decision 3 exists precisely because a
duplicated drill predicate is how drill state diverges — and it is enforced by a build-failing
guard. v2 reintroduced that shape one level down.

All three inputs already originate in `useKbLayoutState`. Name the value once:

```ts
// hooks/use-kb-layout-state.tsx — `fullWidth` moves here from kb/layout.tsx:37
const fullWidth = loading || !!error || !hasTreeContent;
const treeHost: "rail" | "content" =
  !isDesktop && !fullWidth && !isContentView ? "content" : "rail";
```

`kb/layout.tsx` renders `{treeHost === "rail" && <KbSidebarShell />}` inside the one
`RailSlotPortal`; `KbMobileLayout` renders `{treeHost === "content" ? <KbSidebarShell host="content" /> : <KbDocShell …/>}`.

Four consequences, all of which resolve findings rather than adding scope:
1. **Exactly one host in all 8 cells** — the mobile document route reverts to the rail, so AC2's
   `=== 1` becomes literally true instead of false at one cell (R7).
2. **The drawer keeps its tree on mobile document routes**, so the doc→doc path and the only
   in-KB escape from the two headerless document states survive untouched (R8).
3. The invariant becomes a property of **one value**, not of a test matrix (R9).
4. `fullWidth` — on which D1's entire hydration argument rests — is named in **one** place instead
   of recomputed in a layout file.

AC3 is unaffected: it pins the `fullWidth` **JSX block**, and the `const` moves out of that block
into the hook.

### DD1 — Who owns "back" on the mobile browse view (design decision — operator gate)

The `.pen` gives the browse view a header with a back arrow to `/dashboard` ("the back arrow always
means up one level"). The shipped `#4915` contract, asserted in `test/kb-layout.test.tsx`, says the
KB landing header *omits* the back "because the persistent band owns it".

**That contract's premise is factually false on mobile**: the band is unconditionally
`suppressBack` and lives inside the drawer, so the mobile landing has no reachable back without
opening the hamburger. The wireframe fixes a real gap.

- **Option (a), recommended:** follow the wireframe — the browse view carries the back arrow.
  Updating the `#4915` assertion is then a **correction of a false premise**, not a weakening.
- **Option (b):** keep the contract — no in-page back on the landing.

**Constraint on (a), and the reason this is a gate rather than a default:** the back arrow may be
added **only to the populated browse view**, never to the `fullWidth` block — putting it in the
shared block would reintroduce exactly the JS-gated first-paint DOM that D1 reason 1 forbids (R1).
It would also break `e2e/nav-states-shell.e2e.ts:948`, which asserts exactly one `/back to menu/i`
link on the mobile **empty**-tree landing; the populated-only placement leaves that assertion
untouched. Verify that when implementing (a).

**This is the headline item for the Phase 0.4 operator sign-off. Do not pick it unilaterally.**

---

## Implementation Phases

### Phase 0 — Wireframe + operator sign-off gate 🚧 BLOCKING

**No product code before this phase closes** (`wg-ui-feature-requires-pen-wireframe`).

0.1 ✅ **Done.** `knowledge-base/product/design/navigation/kb-mobile-drill-in-nav.pen` (136 KB)
plus 8 frames as direct children of `navigation/screenshots/`, numbered `29-`…`36-` (continuing
the existing `01-`…`28-` from #4911). Committed in `15ac70b19` — an uncommitted `.pen` is at risk
from the destructive-open bug (#3274). The pre-existing `kb-mobile-nav-redesign-wireframes.pen`
was **not** opened.

0.2 **One frame to add: the tablet at exactly 768px**, the switch point (constitution line 272).
*(v1 also required browse-view error frames; v2 does not need them — the mobile non-populated
states route through the existing, unchanged `fullWidth` block, so there is no new error UI to
design. See Plan Review Revisions R1.)*

0.3 **Open design questions for the operator — do not resolve unilaterally:**
- **DD1** — who owns back on the browse view (recommended: option (a), populated view only).
- **D3** — whether the drawer keeps a "Browse files" row at all (wireframe frame 34 shows one; the
  plan's default is an empty secondary slot, with the row available as a layout-local link).
- **Doc-header action budget.** The `.pen` doc frame shows `[← | breadcrumb | chat]`; the shipped
  `KbContentHeader` also renders Download, `KbSyncStatus`, and `SharePopover`. Four actions do not
  fit 375px, but silently dropping Share is a capability regression and Download is the **only**
  way to consume a non-markdown attachment. Name the replacement (overflow menu / bottom sheet) or
  keep them. *(No code in this plan changes that header — this is a wireframe-vs-shipped
  discrepancy to resolve before it becomes a follow-up.)*
- **Global top bar on KB routes.** The browse frame puts the hamburger on the right with no palette
  trigger; the global bar (`layout.tsx:320`) is hamburger-left + palette-right. If the global bar
  were suppressed on KB routes, the mobile ⌘K trigger (#6903, the only non-keyboard palette entry)
  would disappear there. Confirm it is **not** suppressed.
- **Corner radius.** `brand-guide.md` states "Sharp (0px border-radius)… No rounded corners"; the
  frames use 8–10px to match the shipped surface and the eight sibling wireframes in this folder.
  Either the guide or the surface is stale — flag for resolution, do not silently pick.

0.4 **Operator sign-off gate.** `xdg-open knowledge-base/product/design/navigation/screenshots/`
and stop. Operator-attended: ask for explicit approval before Phase 1. Headless: record
`wireframes ready for async review at <dir>`, surface the 0.3 questions in the PR body, and **do
not mark the PR ready** until the operator has signed off. On approval:
`bash plugins/soleur/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md kb aesthetic-direction kb-mobile-drill-in "$(date -u +%F)"`.

0.5 Assign #7186 to the `Phase 4: Validate + Scale` milestone
(`wg-every-feature-listed-in-a-roadmap-phase`).

### Phase 1 — RED: the invariant test first (`cq-write-failing-tests-before`)

The plan's justification for a JS branch is "a CSS gate is untestable, a JS branch is testable" —
that is only half true until the mobile branch is reachable in tests, because happy-dom pins
`matchMedia` at 1024px. The injection mechanism already exists and is proven in-repo: a settable
module mock (`vi.mock("@/hooks/use-media-query", () => ({ useMediaQuery: () => mockIsDesktop }))`,
`test/kb-layout-panels.test.tsx:15-17`). Land the invariant test before writing any component.

1.1 `test/kb-layout.test.tsx` — generalise the existing "does not render FileTree twice at root
path" case into an `it.each` **host table**, not a scalar count. Columns:
`(isDesktop, pathname, fixture, expectedHost)` with `expectedHost ∈ {"rail","content"}`. Under D5
every cell is exactly one tree, so the count assertion is `toHaveLength(1)` everywhere — but the
**host** is the invariant, and it is asserted by **containment**, never by a wrapper testid (R11):

```tsx
const nav = await screen.findByRole("navigation", { name: /knowledge base file tree/i });
const slot = screen.getByTestId("rail-slot-harness");
expectedHost === "rail" ? expect(slot).toContainElement(nav)
                        : expect(slot).not.toContainElement(nav);
```

Six cells, not eight — `{desktop, doc, empty}` and `{mobile, doc, empty}` are redundant with their
landing rows for the host invariant (the tree host does not depend on the route in a `fullWidth`
state), and each cell costs a full `KbLayout` render plus an SWR settle. Keep `{desktop, doc,
populated}` as a cheap content-column regression guard.

Plus a **desktop↔mobile flip**. Two implementer notes, both load-bearing:
- Drive the flip with RTL `rerender()` **on the same tree**. `unmount()` + a fresh `render()` makes
  the case tautologically green — a fresh render cannot have a stale portal, which is the only
  failure mode this case exists to catch.
- There is **no in-repo precedent for the flip**: `test/kb-layout-panels.test.tsx:14,90` and
  `test/kb-layout-chat-close-on-switch.test.tsx:27,102` both declare `mockIsDesktop` and reset it
  to `true` in `beforeEach`, and **neither ever sets it to `false`**. The precedent proves
  *injection*, not flipping. Write it deliberately, and reset `mockIsDesktop`/`mockPathname` in
  `beforeEach`.
- A synchronous ternary commits atomically, so the flip cannot observe a transient double mount —
  it is there to catch a **portal that fails to unmount**. Do not restate v1's incorrect rationale.

Before writing any assertion that depends on a branch firing, run the 30-second trace from
`knowledge-base/project/learnings/2026-05-07-test-assertion-must-verify-mock-activates-branch.md`:
confirm the mock value actually activates the target branch.

1.1b `test/kb-sidebar-shell-host.test.tsx` (new, component-level) — the single highest-value
addition from the test-design review, and the only RED for the `host` guard (whose v2 mitigation
was a code comment against a Medium-rated risk). Renders `KbSidebarShell` directly under
`RailSlotHarness`, three cases:
- `host="content"` → wrapper is `kb-browse-tree`;
- `host="content"` under `<RailSlotHarness collapsed>` → **still** renders `SearchOverlay` +
  `FileTree`, and does **not** render `kb-rail-collapsed-expand` (this is the
  `RailCollapsedProvider`-wraps-`<main>` leak: without the guard a user who collapsed the desktop
  rail and then opens on a phone gets a 56px two-icon strip as their entire browse view);
- default `host` → `kb-rail-tree`, collapse still honoured.

It also bisects the layout suite: a red cell in 1.2 otherwise has ~5 candidate causes.

1.2 `test/kb-mobile-browse.test.tsx` (new) — written against the **layout**
(`app/(dashboard)/dashboard/kb/layout.tsx`) with the mobile mock, **not** against a
not-yet-existing component, so it fails on a missing `kb-browse-tree` query rather than a module
resolution error. Cases:
- mobile + populated + landing → tree in the content column, rail slot holds no
  `role="navigation"` named /knowledge base file tree/ **(this is where AC6 lives — it is vacuous
  in `test/nav-rail-drill.test.tsx`, which never renders `KbLayout`, R12)**;
- mobile + populated + doc route → document in the content column, tree back in the rail slot;
- mobile + empty tree → the unchanged `fullWidth` body, tree in the rail slot;
- **the `fullWidth` block is viewport-invariant** — render it at `mockIsDesktop` true and false and
  assert identical `innerHTML`. This is the behavioural form of AC3 and pins D1 reason 1 (R13);
- **the deleted stopgap** — "Open a file to see it here" is absent, and `DesktopPlaceholder` still
  renders on the desktop landing (grep-verified: the stopgap block has **zero** references in
  `test/` or `e2e/` today, so deletion breaks nothing — and equally nothing asserts it is gone);
- **`KbErrorBoundary` coverage** — mock `@/components/kb/file-tree` to throw and assert the
  fallback renders at **both** hosts (symmetry is the stated justification for moving the boundary
  inside the shell; note `test/kb-sidebar-collapse.test.tsx` mocks `KbErrorBoundary` as a
  pass-through, so the existing suite is blind to this);
- **the search query survives landing → doc → landing.** Drive it by mutating `mockPathname` +
  `rerender()` on the **same** tree (a fresh `render()` is not what a client-side nav does and
  would pass for the wrong reason); mock `/api/kb/search` explicitly (the overlay has a 300ms
  debounce that re-arms on the restored query — an unmocked timer firing after teardown is exactly
  the cross-file leak `isolate: true` exists for); and assert on `findByDisplayValue`, not on
  results, or it becomes a network test;
- **DD1's outcome**, if the operator picks option (a): the populated browse view renders exactly
  one back affordance and it points at `/dashboard`.

1.3 `e2e/nav-states-shell.e2e.ts` — extend the existing authenticated describe blocks (verified:
`nav-states visual gate — desktop` at `:418` / `test.use({ viewport: DESKTOP })` at `:419`;
`nav-states visual gate — mobile` at `:911` / `:912`; `DESKTOP = { width: 1280, height: 900 }` at
`:383`, `MOBILE = { width: 390, height: 844 }` at `:384`; the `kbRailTree` locator at `:403` is
already asserted `toBeAttached()` at `:604`):
Assert the host by **containment against the real slot**, using the `secondarySlot(page)` locator
that already exists at `:400` — `kb-rail-tree` attached is NOT evidence the tree is present (the
wrapper renders unconditionally; `:604` asserts it attached while `kbLongFile` count is 0, R11):

```ts
const kbTree = (p: Page) => p.getByRole("navigation", { name: /knowledge base file tree/i });
```

- 1280×900, populated: `secondarySlot(page).locator(kbTree)` visible; `kb-browse-tree` count 0;
- 390×844, populated, landing: `kb-browse-tree` contains the tree; `secondarySlot` does not;
- 390×844, populated, **document route**: tree is back in `secondarySlot`; `kb-browse-tree` count 0
  (the D5 cell that keeps doc→doc working);
- 390×844, **empty** tree (the fixture already at `:948-953`): tree in `secondarySlot` — unchanged;
- 390×844 round trip: tap a file row → document → tap "Back to file tree" → browse view restored
  with **no** full page load. Use a **sentinel**, not a navigation-event listener:
  `await page.evaluate(() => { window.__kbNoReload = true })` before tapping, assert it is still
  `true` after tapping back. `page.on("framenavigated")` fires on same-document navigations in
  Chromium and would go red on a *correct* SPA transition. Prefer a web-first assertion on the
  row's interactivity over copying the `waitForTimeout(1500)` hydration sleep the neighbouring
  mobile block uses at `:911`;
- 390×844 **drawer-during-fetch**: open the hamburger while the tree is loading, let it resolve
  populated, assert the drawer does not present an empty secondary slot (D3's named transition);
- **768×1024 — UNCONDITIONAL.** v2 made this arm conditional on the DD1 outcome; that was wrong.
  Because every unit test mocks `useMediaQuery`, **no unit test ever exercises the string
  `(min-width: 768px)`** — a typo to `(min-width: 786px)` passes the entire matrix. This arm is the
  only guard on the breakpoint literal. `(min-width: 768px)` matches at exactly 768, so the
  expected result is the rail host, deterministically.

Run all three; confirm each fails on an assertion, not an import.

### Phase 2 — GREEN

2.0 `hooks/use-kb-layout-state.tsx` — derive `treeHost` per D5: move `fullWidth` in from
`kb/layout.tsx:37`, compute `treeHost: "rail" | "content"`, and export both. This is the change
that makes the single-host property structural.

2.1 `components/kb/kb-sidebar-shell.tsx` — add the optional `host?: "rail" | "content"` prop per
D2 (a named host, not a boolean): gate `useRailCollapsed()` with `&& host === "rail"` and carry the
"the provider cannot be narrowed without breaking ADR-047 Decision 2" comment, switch the wrapper
`data-testid`, keep `data-tour-id="action:kb-tree"` on that same wrapper, and move
`KbErrorBoundary` inside so both hosts inherit it.

2.2 `app/(dashboard)/dashboard/kb/layout.tsx` — the portal becomes a single condition on state the
file already computes, with the D1-reason-2 comment attached:

```tsx
<RailSlotPortal>{treeHost === "rail" ? <KbSidebarShell /> : null}</RailSlotPortal>
```

**Nothing else in this file changes.** The `fullWidth` block keeps its existing `md:hidden` header
and state bodies byte-for-byte — no sync footer, no back arrow, no JS-gated DOM (D1 reason 1, R1).

2.3 `components/kb/kb-mobile-layout.tsx` — branch the content column on the same one value:
`treeHost === "content" ? <KbSidebarShell host="content" /> : <KbDocShell isContentView>{children}</KbDocShell>`.
Update the ADR-047 comment at `:30-33`, which currently asserts the opposite ("The doc always fills
the content area here"). Apply the operator's DD1 outcome here — **populated view only**.

2.4 `components/kb/kb-doc-shell.tsx` — delete the `md:hidden` stopgap block (`:32-48`) and its
`RAIL_EXPAND_EVENT` import. With the browse view in place, `isContentView === false` is only
reachable from `KbDesktopLayout`. Keep `DesktopPlaceholder` untouched.

2.5 `app/(dashboard)/layout.tsx` — remove the dead `inKbDocView` at `:229` and the comment
asserting a doc-view back-suppression the code does not perform. If the operator chose the D3
"Browse files" row, add it here (setter and `drill` are already in scope) — not as a portaled
component.

2.6 `hooks/use-nav-resume.ts` + `components/kb/search-overlay.tsx` — persist the search query so it
survives the drill-in (the one regression this diff would otherwise introduce: the mobile host
unmounts on navigation where the portal did not). **Route it through `useNavResume`, not
`useKbLayoutState`** (R10): that hook already owns exactly this concern for the query's two
siblings — `readExpanded`/`writeExpanded` and `readScrollTop`/`writeScrollTop` — so the query is
the third member of an existing family rather than a fifth unrelated concern bolted onto a
382-line hook. Add `readSearchQuery`/`writeSearchQuery`; `SearchOverlay` seeds its `useState` from
it and writes on change.

Two consequences of choosing `useNavResume`: `UseKbLayoutStateResult` is **not** widened, so the
`tsc`-only trap at `test/components/kb/kb-reconnect-banner.test.tsx:51-75` and its fixture edit
both evaporate; and seeding is one frame late because `useNavResume` gates reads on `workspaceId`
— acceptable for a search input, and identical to how `expanded` already behaves. Reset the query
on workspace change so it does not leak between workspaces
(`knowledge-base/project/learnings/2026-04-17-kb-chat-stale-context-on-doc-switch.md`).

2.7 Confirm the `RAIL_EXPAND_EVENT` census stays coherent after 2.4: remaining dispatchers are
`kb-sidebar-shell.tsx` (collapsed rail, desktop-only) and `components/tour/tour-provider.tsx`; the
sole listener stays `app/(dashboard)/layout.tsx:246-263` with its mobile-gated `setDrawerOpen(true)`.
Do **not** remove the event.

### Phase 3 — Reconcile the affected existing tests

Each item is an **intentional, enumerated** change; no product assertion is weakened.

3.1 `test/kb-sidebar-collapse.test.tsx` — mocks `useMediaQuery: () => false`, so under v2 the KB
landing now renders the tree in the content column rather than the rail. Split into a **desktop**
arm (`mockIsDesktop = true`) re-asserting every existing ADR-047 rail contract — portals into the
slot, no in-shell collapse button, `kb-rail-empty` CTA, renders nothing without a slot, collapsed
icon-only affordance with the tree DOM-removed, collapsed "Browse files" dispatches
`RAIL_EXPAND_EVENT` — and a **mobile** arm asserting the empty-tree path still portals into the
rail. *(No `react-resizable-panels` mock is needed: `test/kb-layout.test.tsx` renders
`KbDesktopLayout` unmocked at 1024px and passes 7/7 — the v1 claim that the `false` mock existed to
dodge the panels was checked and is false.)*

3.2 `test/kb-layout.test.tsx` — the `#4915` landing-header case changes only if the operator picks
DD1 option (a). If so, the PR body must record that the original assertion encoded a false premise
(the band does not own back on mobile) and is being corrected.

3.3 `e2e/nav-states-shell.e2e.ts:948` — asserts exactly one `/back to menu/i` link on the mobile
**empty**-tree landing. Under v2 that page is unchanged, so it should stay green; if DD1(a) is
implemented anywhere other than the populated browse view, it goes red. Verify explicitly and
enumerate it in the PR body — it is the one e2e assertion DD1 can reach.

3.4 `test/components/kb/kb-reconnect-banner.test.tsx` — the typed `makeState()` literal must gain
the new search-query field (2.6). Also confirm the `KbMobileLayout` arm still exercises the banner
now that the content column branches on `isContentView`; pin its `usePathname` mock to a document
route, or add a landing-route arm.

3.5 `test/kb-tree-scroll-resume.test.tsx` — the scrollport is unchanged (no extraction), so this
should stay green; add a mobile arm for the content-column host. Known limitation, recorded rather
than silently shipped: restore is one-shot via `restoredRef` (`kb-sidebar-shell.tsx:47`), so a
second breakpoint crossing does not restore (Non-Goals #5).

### Phase 4 — ADR + docs

4.1 Write `ADR-158-kb-file-tree-host-is-a-derived-value.md` — one decision clause, two
seriously-weighed alternatives, and the two structural safety facts (no JS-gated DOM in the
`fullWidth` block; `RailSlotPortal` is null until its ref callback fires).
4.2 Amend `ADR-047`: the `md+` qualifier on Decision 2 and `related_adrs += ADR-158`.
4.3 No `.c4` edit → no `regenerate-c4-model.sh`, no `model.likec4.json` change.

### Phase 5 — Verification

5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
(**Not** `npm run -w apps/web-platform typecheck`: the repo root declares no `workspaces` field.)
This is the gate that catches 2.6's type widening.

5.2 Run the canonical suite list — the `discoverability_test.command` in `## Observability` above.
It is the single source of truth for which suites this change can reach; do not maintain a second
list here.

5.3 Full suite: `bash scripts/test-all.sh` (path `ls`-verified from the repo root — **not** under
`tests/scripts/`). **Read the per-suite lines, not the summary count** — `N-1/N` means a suite
failed and `[FAIL] <suite> (0ms)` means a whole sub-suite crashed. That is exactly how the #6874
dual-mount reached `/ship`.

5.4 `/soleur:qa` — the ADR-049 headless-Chromium `nav-states` gate. Mandatory: the diff touches
`app/(dashboard)/**` and a `layout.tsx`, and it is the only gate that sees real CSS and real
hydration.

5.5 Prod device-mode check on `https://app.soleur.ai` after deploy (local `bun run dev` is broken on
this host): desktop, **tablet at exactly 768px**, and mobile (constitution line 272).

---

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/test/kb-mobile-browse.test.tsx` | Mobile browse-view coverage, written against the layout |
| `apps/web-platform/test/kb-sidebar-shell-host.test.tsx` | Component-level `host` prop coverage — the RED for the `RailCollapsedProvider` leak, and the bisect for the layout suite |
| `knowledge-base/engineering/architecture/decisions/ADR-158-kb-file-tree-host-is-a-derived-value.md` | The decision record |
| `knowledge-base/product/design/navigation/screenshots/37-*.png` | The 768px tablet frame (Phase 0.2) |

*(`kb-mobile-drill-in-nav.pen` + frames `29-`…`36-` are already committed in `15ac70b19`.)*
**No new product component files** — v2 needs none (Plan Review Revisions R3/R4).

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/hooks/use-kb-layout-state.tsx` | **D5** — own `fullWidth` (moved in from the layout) and derive `treeHost: "rail" \| "content"` |
| `apps/web-platform/components/kb/kb-sidebar-shell.tsx` | Optional `host?: "rail" \| "content"`; `useRailCollapsed() && host === "rail"`; testid switch; `KbErrorBoundary` moved inside |
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | Portal condition `treeHost === "rail"` + the D1-reason-2 comment; `fullWidth` now read from the hook. **Nothing else.** |
| `apps/web-platform/components/kb/kb-mobile-layout.tsx` | Branch on `treeHost`; correct the ADR-047 comment (`:30-33`); DD1 header (populated view only) |
| `apps/web-platform/hooks/use-nav-resume.ts` | `readSearchQuery`/`writeSearchQuery` (2.6) |
| `apps/web-platform/components/kb/kb-doc-shell.tsx` | Delete the unreachable `md:hidden` stopgap (`:32-48`) + its `RAIL_EXPAND_EVENT` import |
| `apps/web-platform/app/(dashboard)/layout.tsx` | Remove the dead `inKbDocView` (`:229`) + its false comment; optional D3 row if the operator wants it |
| `apps/web-platform/components/kb/search-overlay.tsx` | Seed from / write to `useNavResume`; reset on workspace change |
| `apps/web-platform/test/kb-layout.test.tsx` | Six-cell host table + the `rerender()` flip (the `#4915` case needs **no** change — see Phase 3.2) |
| `apps/web-platform/test/kb-sidebar-collapse.test.tsx` | Desktop (ADR-047 contract) + mobile-empty arms |
| `apps/web-platform/test/kb-tree-scroll-resume.test.tsx` | Mobile arm |
| `apps/web-platform/test/components/kb/kb-reconnect-banner.test.tsx` | `makeState()` literal gains `treeHost`/`fullWidth`; arm pinning |
| `apps/web-platform/e2e/nav-states-shell.e2e.ts` | Both-viewport host assertions, empty-tree arm, 768px, drill-in round trip |
| `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md` | `md+` qualifier; `related_adrs` |

**Not edited (deliberately):** `hooks/use-media-query.ts` (D1 — the hook itself is untouched),
`hooks/use-is-mobile.ts`, `components/dashboard/rail-slot.tsx` (D3 — no new event),
`components/kb/file-tree.tsx`, `components/kb/kb-content-header.tsx` (its back chevron already does
the right thing), `components/kb/kb-desktop-layout.tsx`, `components/kb/kb-sync-status.tsx`,
`hooks/segment-to-drill-level.ts`, `components/kb/index.ts` (verified: it exports neither
`FileTree` nor `KbSidebarShell`, and v3 creates no new component, so the barrel needs no change).

## Acceptance Criteria

Eleven pre-merge criteria, each a checkable post-condition on file state, command output, or
observed behaviour. *(v1 had twenty; eleven were cut as ceremony — restating a phase instruction,
asserting that a test asserts something, or naming a precondition for opening any PR at all. v3
then split AC5 into two atomic criteria and added AC7b for the four changes v2 left uncovered.)*

### Pre-merge (PR)

- **AC1** — On a phone viewport **with a populated tree**, `/dashboard/kb` renders the tree in the
  content column (`kb-browse-tree` present, containing a `role="navigation"` named /knowledge base
  file tree/) and the rail secondary slot is empty. With an **empty** tree the same route is
  unchanged from today: the `fullWidth` body in the content column and `kb-rail-tree` in the rail.
- **AC2** — **Exactly one** file-tree instance mounts, **in the host named below**, in every cell.
  Asserted by **containment** of the `role="navigation"` node, never by a wrapper `data-testid`
  (`kb-rail-tree` renders even when the tree is DOM-removed):

  | viewport | route | fixture | expected host |
  |---|---|---|---|
  | desktop | landing | populated | rail |
  | desktop | doc | populated | rail |
  | desktop | landing | empty | rail |
  | mobile | landing | populated | **content** |
  | mobile | doc | populated | rail |
  | mobile | landing | empty | rail |

  Count is `1` in every row (that is what D5 buys), plus the desktop↔mobile flip via `rerender()`
  on the same tree. `{desktop, doc, empty}` and `{mobile, doc, empty}` are dropped as redundant
  with their landing rows.
- **AC3** — Desktop KB behaviour is unchanged, and the `fullWidth` block is **viewport-invariant**:
  rendered at `mockIsDesktop` true and false it produces identical `innerHTML`. That is the
  machine-checkable form of the D1-reason-1 guarantee ("no JS-gated DOM in the `fullWidth` block").
  *(v2 asserted "`git diff` shows no hunk inside it" — not machine-checkable, and it would fail a
  correct refactor. Keep the `git diff` read as a reviewer note, not an AC.)*
- **AC4** — Back from a document returns to the browse view without a full reload (e2e round trip).
- **AC5a** — The search query survives browse → document → back on mobile (driven by mutating the
  pathname and re-rendering the same tree, with `/api/kb/search` mocked, asserted on the input's
  display value).
- **AC5b** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 — the gate for
  2.0's `UseKbLayoutStateResult` widening, which fails typecheck without failing any test.
- **AC6** — On mobile with a populated tree, the rail secondary slot contains no `role="navigation"`
  named /knowledge base file tree/ — asserted in `test/kb-mobile-browse.test.tsx` under
  `RailSlotHarness`, where a `KbLayout` actually exists. *(v2 placed this in
  `test/nav-rail-drill.test.tsx`, which renders `<DashboardLayout><div>content</div></DashboardLayout>`
  and never imports `KbLayout` — with no portal source the assertion is vacuously true for every
  implementation, including one that mounts no tree at all. R12.)*
- **AC7** — The ADR-049 e2e gate asserts in real Chromium, by **containment in `secondarySlot`**
  (not by `kb-rail-tree` attachment, which is true even when the tree is DOM-removed): 1280×900
  populated → tree inside `secondarySlot`, `kb-browse-tree` count 0; 390×844 populated landing →
  the inverse; 390×844 populated **document route** → tree back inside `secondarySlot`; 390×844
  **empty** → tree inside `secondarySlot`; **768×1024 unconditionally** — the only test anywhere
  that exercises the real `(min-width: 768px)` literal, since every unit test mocks the hook. Real
  assertions, not a screenshot diff. This is the empirical closure of the stale-`isDesktop` risk.
- **AC7b** — The four changes v2 left uncovered are covered: the `host` guard (content-column host
  under a collapsed provider still renders the full tree, not the 56px icon strip), the
  `KbErrorBoundary` move (a throwing `FileTree` renders the fallback at **both** hosts), the
  stopgap deletion ("Open a file to see it here" absent, `DesktopPlaceholder` still rendering on
  the desktop landing), and — if the operator picks DD1(a) — exactly one back affordance on the
  populated browse view.
- **AC8** — `ADR-158-*.md` exists and `ADR-047-*.md` carries the `md+` qualifier and the
  `related_adrs` entry. Swept if the ordinal is renumbered.
- **AC9** — The PR body enumerates every existing test file changed in Phase 3 and, for each,
  whether the change is mechanical or a false-premise correction — including
  `e2e/nav-states-shell.e2e.ts:948` (the one e2e assertion DD1 can reach).

### Post-merge (operator)

- **AC10** — Prod device-mode check on `https://app.soleur.ai` at desktop, 768px, and mobile.
  *Automation: attempt via Playwright MCP against the prod URL with the operator session;
  `automation-status: UNVERIFIED` — /work MUST run a Playwright attempt before any operator handoff.
  AC7 already covers both viewports in CI against a real browser, so this is a post-deploy
  confirmation, not the primary gate.*
- **AC11** — Design sign-off recorded in the taste profile (Phase 0.4). *Automation: not feasible
  because design approval is a subjective human judgement, not an API-readable signal.*

## Non-Goals / Out of Scope

Each gets a tracking issue in the same session (`wg-when-deferring-a-capability-create-a`).

1. **Per-directory routing / folder drill-in.** Tapping a folder still expands inline.
   **Corrected reasoning:** not blocked — `isMarkdownKbPath` returns true for an empty extension, so
   a directory URL 404s and bounces to the landing rather than mis-rendering, and **no directory URL
   is reachable from the UI**. Additive with zero regression surface; deferring leaves no
   user-reachable hole. Do not hard-code `/dashboard/kb` as the only browse URL, so this slots in
   later rather than requiring a rewrite.
2. **Dotted-directory edge case** — `docs.v2` takes the binary branch and 404s there instead.
   Pre-existing, unreachable from the UI.
3. **"Sync now" fails silently** — `KbSyncStatus` accepts `onError` (`kb-sync-status.tsx:36`) but
   neither caller passes it (`kb-sidebar-shell.tsx:160`, `kb-content-header.tsx:105`). Pre-existing,
   identical on desktop, untouched by this diff. File as `type/bug`.
4. **Search failure shows the previous query's results under the new query's label** —
   `search-overlay.tsx:25` only `setResults` on `res.ok`, `:29` swallows the catch (violating
   `cq-silent-fallback-must-mirror-to-sentry`), `:33` sets `searched` regardless. Pre-existing and
   identical on desktop. File as `type/bug`.
5. **Scroll restore is one-shot** (`restoredRef`), so a second breakpoint crossing does not restore
   tree scroll; focus is not re-homed across the swap either.
6. **Two document states render no header, therefore no in-page back** — the loading branch
   (`[...path]/page.tsx:130-140`) and the generic `error` branch (`:159-170`), which also has no
   retry. **Corrected from v2, which was over-broad:** the `not-found` branch (`:142-157`) *does*
   carry a "Back to file tree" link, so it is not affected.
   **This stays a genuine Non-Goal only because of D5.** Under v2's shape the mobile document route
   had no tree anywhere, so this diff would have *deleted the mitigation* — the drawer tree is
   today the only in-KB escape from those two states — converting a latent dead end into a reachable
   one, and falsifying the "two DOM positions, no capability change" framing. D5 keeps the drawer
   tree on mobile document routes, so the states are left exactly as they are today.
   **Highest-priority follow-up** — file at `priority/p2-medium` or above and note in the PR body
   that this plan does not fix it.
7. **`isContentView` trailing-slash normalisation** — `use-kb-layout-state.tsx:217` is a strict
   `pathname !== "/dashboard/kb"` while `deriveContextPathFromPathname` (`:40-46`) normalises and
   `isKbDocView("/dashboard/kb/")` is `true`; three components disagree about which screen you are
   on. The **consequence changed class** under this plan — today a wrong `isContentView` at
   `/dashboard/kb/` swaps one placeholder for another; now it decides which host holds the tree.
   Risk stays low and the deferral stands **for a verified reason**: `next.config` sets no
   `trailingSlash`, so Next's default 308 normalises the URL before the layout ever sees it.
   Normalising the predicate itself would change desktop behaviour.
8. **History-backed chat sheet / drawer** — neither pushes a history entry, so Android
   hardware-back from an open sheet navigates the route away. Pattern exists elsewhere
   (`crm-surface.tsx:46`, `workstream-board.tsx:134`).
9. **The closed drawer is not `inert`/`aria-hidden`** (`layout.tsx:368` only translates it
   off-screen), so its contents stay in the tab order.
10. **Settings and Conversations keep their drawer-hosted rails.** Observed fact, not a rule — see
    the ADR section on why this is deliberately not generalised.
11. **Two different empty-state CTAs** for one condition (`EmptyState` → "Open a Chat",
    `RailEmptyState` → "Connect a repo").
12. **`kb/loading.tsx` renders a document skeleton**, so a cold mobile KB open flashes a document
    skeleton before resolving to a file list.
13. **"Recently updated" landing strip.** `TreeNode.modifiedAt` is already on the `/api/kb/tree`
    wire and the CPO argues it measures the roadmap's Phase-4 validation signal (return-to-artifact)
    better than a tree does. Real value, but an enhancement, not a coverage hole — search covers
    *find*.
14. **The collapsed drawer hides the recovery valve.** `collapsed` comes from
    `useSidebarCollapse("soleur:sidebar.main.collapsed")` (`layout.tsx:145`), which is
    **localStorage-persisted and breakpoint-agnostic** (`use-sidebar-collapse.ts:38-49`). A user who
    collapsed the desktop rail and later opens on a phone gets the collapsed branch inside the
    drawer (`kb-sidebar-shell.tsx:108-130`), which renders neither `RailEmptyState` nor
    `KbSyncStatus` — both live in the expanded branch (`:142-161`). Pre-existing and genuinely
    unchanged by this plan, so the R1 wording ("as reachable as they are today") is literally true —
    **but this plan promotes that drawer path from a redundant copy to the named recovery valve**,
    so it is worth an explicit check at Phase 5.5 / `/soleur:qa` (open prod mobile with
    `soleur:sidebar.main.collapsed=1` set) and a `type/bug` filing if it reproduces.
15. **The guided-tour anchor's reachability on mobile.** `tour-steps.ts:126-131` anchors
    `action:kb-tree` at `route: "/dashboard/kb"`; `tour-provider.tsx:82-94` dispatches
    `RAIL_EXPAND_EVENT` once at `startTour`, not per step, and the drawer auto-closes on the
    subsequent route change — so on mobile the anchor is spotlit inside a closed, off-screen drawer
    **today**. Under this plan the populated landing moves it into the content column (an
    improvement); the empty-tree state stays unchanged-broken. Net neutral-to-positive; recorded
    because D2's "the id never moves" is true of the attribute but says nothing about reachability,
    which does move — favourably.
16. **Touch-target audit of destructive row actions.** `app/globals.css:261-263` forces
    `.kb-tree-actions { opacity: 1 }` under `(hover: none)`; at full width, Delete sits closer to
    the row's navigate target than in a 224px rail, with no undo. Measure at the Phase-0.4 gate; any
    fix is a `file-tree.tsx` change and therefore its own issue.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Dual mount (the #6874 class) reaches `main` | Medium — it has happened, and review + compound both missed it | **Structurally impossible under D5** — one derived value cannot select two hosts. Backed by AC2's host table + AC7 real-browser containment assertions + running `workstream-board.test.tsx` as the canary |
| Implementation adds JS-gated DOM to the `fullWidth` block, reintroducing the v1 hydration mismatch | **Medium — the single most likely way to get v2 wrong** | AC3 requires the block byte-for-byte unchanged (`git diff` shows no hunk inside it); DD1's constraint puts the back arrow on the populated view only |
| `isDesktop` wrong on a real desktop browser | Low, mechanism never established | Closed empirically by AC7, not by a code change (D1/R2) |
| Scope re-creep at `/work` — the P1/P2 backlog surfaced by review is tempting and adjacent | **High** | Non-Goals #3, #4, #6 name the three most tempting with file:line and an explicit "file as `type/bug`". Only the search-query lift is in scope, and only because this diff breaks it |
| `RailCollapsedProvider` leaks the desktop collapsed state into the content-column host — the browse view becomes a 56px two-icon strip | Medium | The `&& host === "rail"` guard in D2, **plus a RED test** (`kb-sidebar-shell-host.test.tsx`, Phase 1.1b). v2 mitigated a Medium risk with a code comment; a comment is not a mitigation |
| The 2.0 type widening breaks `tsc` in a *test* file that no test run would surface | Medium | AC5b pairs it with `tsc --noEmit`; Phase 3.4 names the consumer (`kb-reconnect-banner.test.tsx:51-75`). Smaller than v2's, since 2.6 no longer widens the interface |
| The drawer empties itself mid-fetch on the mobile landing (`treeHost` flips rail→content when the tree resolves) | Medium | Named in D3, asserted in the e2e round trip, and the concrete functional argument for the DC2 "Browse files" row |
| An AC that is false on a correct implementation (the R6/R7 class — it has now recurred twice, on the fixture axis and the count axis) | **Medium** | AC2 is a per-cell host table, not a scalar; D5 makes every cell single-host so the count is uniform; two independent lenses re-derive the table before it is written |
| DD1 decided unilaterally against the operator's design intent | Medium | Phase 0.3/0.4 — DD1 and D3 are the headline sign-off questions |
| A new class uses a nonexistent `soleur-*` token (silent no-op) | Low (little new markup in v2) | Grep `app/globals.css` before use; `light-theme-tokenization.test.tsx` |
| ADR ordinal collision | Medium — twice in one pipeline before | `/ship` ordinal gate + the documented artifact-set sweep |

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** the "one boolean, mutually exclusive hosts" shape is architecturally sound (**LOW**
risk); no simpler shape exists — portal-destination swap and route-based browse were examined and
rejected with reasons. The hydration analysis was judged correct and **strengthened** with a second
independent reason (`RailSlotPortal` is null until a ref callback fires), now an ADR clause and a
code comment. Eight previously-unnamed risks returned; six are folded in (drawer dead-end → D3 cut
entirely; lost empty-tree recovery valve → the drawer keeps `KbSidebarShell` in `fullWidth` states;
`KbErrorBoundary` gap → moved inside the shell so both hosts inherit; orphaned `data-tour-id` →
dissolved by D2's one-prop route; static-guard honesty → the guard is cut with the extraction;
transition coverage → AC2), and two were non-issues (`expanded` is already hoisted; the new code
needs no `pathname`). Its two-PR phasing recommendation is **moot in v2** — with no extraction
there is nothing to prove faithful, so the commit protocol and its AC are gone. No capability gaps.

### Product/UX Gate

**Tier:** blocking (UI-surface change to a primary product surface)
**Decision:** reviewed
**Agents invoked:** ux-design-lead, cpo, spec-flow-analyzer, kieran-rails-reviewer,
code-simplicity-reviewer, scoped strong-model advisor, learnings-researcher,
architecture-strategist, test-design-reviewer, framework-docs-researcher
**Skipped specialists:** none — no domain leader recommended a copywriter (v2 adds no new copy at
all; the "Browse files" row that would have carried the only new string is cut)
**Pencil available:** yes

#### Findings

- **`ux-design-lead`** — delivered `kb-mobile-drill-in-nav.pen` (136 KB) + 8 frames, committed in
  `15ac70b19`. Two flags now in Phase 0.3: the brand guide's 0px-radius rule conflicts with the
  shipped 8–10px surface and the eight sibling wireframes; and a single coherent variant was
  produced rather than a 3-way fan-out because the brief fixed model, frames, platform, fidelity and
  visual language, leaving no meaningful aesthetic axis. Its frame-07 note — tree state must live
  above the route boundary or the back tap refetches and reads *slower* than the drawer it replaces
  — is satisfied: `expanded` is hoisted to `useKbLayoutState` (`:75`), which does not remount across
  routes in the segment. **The search query was the one piece of state that did not satisfy it —
  hence 2.6.**
- **`cpo`** — **signs off conditionally** on four conditions, all met: (1) correct two false
  premises (per-directory routing is not blocked; ADR-047's single-mount test covers only the
  identity components) — both in Research Reconciliation; (2) search-state persistence in scope —
  2.6; (3) browse-view empty/error/loading specified before code — **satisfied differently in v2**:
  those states route through the existing unchanged `fullWidth` block, so there is no new state to
  design (only the 768px frame remains, Phase 0.2); (4) record the in-content-vs-drawer rule in an
  ADR-047 amendment — Phase 4.2, recorded as a scoped qualifier rather than a generalised rule.
  Confirms the `single-user incident` threshold and the list→detail IA; rejects the bottom-sheet
  alternative as contradicting the sole taste-profile entry; judges the Settings/Conversations
  consistency risk **justified** — KB is the only drilled segment whose secondary nav *is* the
  content.
- **`spec-flow-analyzer`** — mapped 7 mobile screens + 12 states; 3 P0s, 9 P1s, 5 P2s. **P0-1** (the
  browse view could never render an error/empty state, stranding a user with no "Sync now") drove
  v1's redesign and is resolved differently and better in v2 — the drawer simply keeps the real
  shell in those states, so nothing is lost and nothing new is built. **P0-3** (drawer dead tap) is
  resolved by *not creating it* (D3). **P0-2** (document loading/error render no back) is real,
  verified, pre-existing → Non-Goals #6. Its P1-3 finding that `inKbDocView` is dead **independently
  corrected a false premise in this plan's own earlier draft**. One finding (P1-2, directory paths
  render a broken FilePreview) was **checked and found wrong** for ordinary directory names.
- **`kieran-rails-reviewer`** — verified most cited line numbers and confirmed D1's "zero test
  churn" claim, the two corrected false premises, and that no phase consumes a later phase's
  contract. Found the **P0 that reshaped v2**: v1's own Phase 3.2 falsified v1's hydration-safety
  argument, and the seed would have created the mismatch it was meant to prevent — with the tell
  that the existing chrome already solves this with `md:hidden` and v1 abandoned that mechanism
  without noticing. Also found that `kb-browse-tree` would exist only in the populated branch,
  making three v1 ACs pass by fixture accident; that the v1 unmodified-green proof was unrunnable
  under v1's own phase order; that a v1 RED test could only ever fail as an import error; that the
  2.6 type widening breaks a typed test literal at `tsc` (not test) time; and that the
  `kb-sidebar-collapse` mock rationale was false. All folded in.
- **`architecture-strategist`** (deepen) — enumerated the full 7-cell state space and found that
  two hosts can never both evaluate true (the hazard the plan spends most of its risk budget on is
  structurally impossible) but that **zero** hosts was reachable by design, which produced two P0s:
  an AC false on a correct implementation, and a silently deleted capability on the mobile document
  route. Its `treeHost` recommendation (D5) resolves both plus half of the drawer-transition
  finding. Also redirected the ADR-047 amendment to a dated append-only section with a scoped
  clause (the `md+` qualifier was falsified by the plan's own state table), stripped variable names
  out of the ADR-158 clause, and rehomed the search query to `useNavResume`. Confirmed ADR-047,
  principles-register, C4 and layering compliance.
- **`test-design-reviewer`** (deepen) — scored the v2 strategy **6.8/10 (C)**: A-grade reasoning
  (RED-before-GREEN with an explicit "fails on an assertion, not an import" gate; the role-based
  tree query) dragged down by two provably-wrong ACs and four uncovered in-scope changes. It
  independently re-derived the AC2 zero-tree cell, showed AC6 was vacuous, showed `kb-rail-tree`
  attachment is not evidence of a tree, and showed a testid-based host assertion agrees with the
  bug. Named three determinism vectors (the flip must `rerender()`, the "no full reload" predicate
  needs a sentinel, the search test needs `/api/kb/search` mocked) and one dead phase (3.2 was a
  phantom reconciliation).
- **`framework-docs-researcher`** (deepen) — verified all six load-bearing framework claims against
  installed versions; no refutations. See the Framework Verification table.
- **`learnings-researcher`** (deepen) — surfaced 9 applicable learnings; see Research Insights.
- **`code-simplicity-reviewer`** — measured the fix at ~60 lines of product code against ~400
  provisioned, and drove five cuts (extraction, drawer event, error rows, hook widening, blocking
  error frames) plus the AC reduction from 20 to 9. Its structural observations are recorded where
  they bind: `RailCollapsedProvider` wraps `<main>` (D2's `&& inRail`), and `768` appears as a bare
  literal in two event-time reads in `app/(dashboard)/layout.tsx` (D1's closing note).

## Test Scenarios

1. Mobile, populated, landing — tree in the content column, rail slot empty, exactly one tree.
2. Mobile, populated, document — document renders, **tree back in the rail/drawer** (D5), back
   chevron present. This is the cell that keeps doc→doc navigation and the only in-KB escape from
   the two headerless document states working.
3. Mobile round trip — landing → file → back, expanded folders + scroll + **search query**
   preserved, no full reload.
4. Mobile, empty tree — unchanged: `fullWidth` body in the content column, tree in the rail, "Sync
   now" and the connect CTA reachable in one hamburger tap.
5. Desktop, populated — tree in the rail slot, chat splitter intact, no `kb-browse-tree`.
6. Desktop, collapsed rail — icon affordance, tree DOM-removed, `RAIL_EXPAND_EVENT` dispatched.
7. The six-cell host table plus the `rerender()` flip — exactly one tree, correct host, asserted
   by containment.
7b. Mobile landing, drawer opened **during** the tree fetch → tree resolves populated → the drawer
   does not present an empty secondary slot (D3's named transition).
7c. Content-column host under a collapsed provider → full tree, not the 56px icon strip.
7d. A throwing `FileTree` → `KbErrorBoundary` fallback at **both** hosts.
8. Real browser at 1280×900 / 768 / 390×844, populated and empty — host placement (AC7).
9. Dual-mount canary — `workstream-board.test.tsx` green.

## Compliance Notes

- **`wg-every-feature-listed-in-a-roadmap-phase` — gap found.** #7186 has no milestone, and neither
  did #6903, #6915, or #6917: four mobile-revision issues shipped or shipping outside any phase,
  while **Phase 1 "Close the Loop (Mobile-First, PWA)" is closed with 0 open**. Phase 0.5 assigns
  #7186 to Phase 4; annotating Phase 1 is a separate roadmap task.
- **Roadmap staleness (non-blocking, not this plan's job):** `knowledge-base/product/roadmap.md`
  "Current State" is dated 2026-05-25 and reports Phase 4 at 56 open / 179 closed; the live milestone
  API says 77 / 193, and Post-MVP is 957 open against the roadmap's 710. Trust the API.
- **Constitution line 272** — screenshots at desktop, tablet, mobile before shipping. **Tablet must
  be exactly 768px**, the switch point (Phase 0.2, Phase 5.5, AC10).

## Research Insights

Institutional learnings consulted at deepen time. Each either **confirms** a decision (recorded so
it is not re-litigated) or **changes** one.

**Confirms D2 (one prop, no extraction):**
- `2026-06-22-collapsed-early-return-remounts-data-bearing-child-and-e2e-provenance-by-revert.md` —
  *"Reconcile-by-position: a conditional element swap around a data-bearing child is an unmount, not
  a re-render. To preserve a child's fetch/state across a UI-mode change, keep ONE instance at a
  stable position and branch className, never the element tree."*
- `ui-bugs/2026-04-16-react-effect-ordering-on-component-extraction.md` — *"Child effects fire
  before parent effects."* Extraction into a `KbTreePanel` would have re-ordered the scroll-restore
  and nav-resume effects relative to their parent; the prop route does not.
- `best-practices/2026-06-08-likec4-diagram-fullscreen-via-portal-overlay.md` — *"Re-parenting a
  single React subtree remounts it … React reconciles by tree position, not by element identity."*
  Independently confirms why the portal-destination-swap alternative buys nothing.

**Confirms D5 / the single-host gate:**
- `best-practices/2026-04-29-duplicate-component-mount-across-layouts.md` — *"two mount sites, one
  of them gated by composition condition. If a plan wants a component visible in two layouts,
  exactly one of those layouts is the 'owner' and the other must condition its mount on UI state
  plus segment."* D5 is that rule reduced to a single named value.

**Confirms D1 reason 1 and raises the stakes on AC3:**
- `ui-bugs/2026-05-06-react-18-production-hydration-skips-className-mismatches.md` — *"className
  mismatches are NOT reconciled in production builds. React logs a dev-only `console.error` and
  keeps the SSR DOM in place (no client re-render fires)."* A hydration mismatch introduced into
  the `fullWidth` block would therefore be **invisible in production** and self-correcting in dev —
  the worst possible signal profile, and precisely why AC3 pins viewport-invariance behaviourally.

**Changes Phase 1.1 and Phase 2.6:**
- `2026-05-07-test-assertion-must-verify-mock-activates-branch.md` — *"Before adding an assertion
  that depends on a conditional render branch firing, do a 30-second trace … Confirm the mock
  returns values that activate the target branch."* Folded into Phase 1.1 as an explicit step;
  load-bearing here because eight suites mock this exact hook and none of them currently flips it.
- `2026-04-17-kb-chat-stale-context-on-doc-switch.md` — *"When a feature is bound to a URL-derived
  key, the cheapest correctness guarantee is to unmount on key change rather than propagating reset
  logic through N layers of children."* The search query is bound to the **workspace**, not the
  document — so it must survive the drill-in (2.6) *and* reset on workspace change. Both are now
  specified.

**Confirms AC7's necessity:**
- `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md` — *"A silently-working fallback
  masked a dead primary for 14 days … Degraded-but-working is the state that kills you later."*
  A count-only assertion would stay green with the tree in the wrong host; only the host assertion
  fires. This is the same argument the test-design review reaches from the other direction.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
  This one is filled.
- **`bun test` does not work in this package** — `apps/web-platform/bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]`. Use `./node_modules/.bin/vitest run <path>`.
- **`npm run -w apps/web-platform <script>` fails** — the repo root declares no `workspaces` field.
  Use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **Test paths must match the vitest project globs**: `test/**/*.test.tsx` → happy-dom,
  `test/**/*.test.ts` + `lib/**/*.test.ts` → node. A co-located `components/**/*.test.tsx` is
  silently never run; a DOM-dependent test **must** be `.tsx`.
- **happy-dom provides `matchMedia`** (measured: function, `innerWidth` 1024, `min-768` true, real
  `addEventListener`) but applies **no CSS**. A JS branch is testable, a CSS one is not — and a hook
  swap that bypasses existing mocks fails *silently*, not loudly.
- **A RED test that imports a not-yet-created module fails as a resolution error, not an
  assertion.** Write new-surface tests against the composing layout, not the unwritten component.
- **A typed test literal can break `tsc` without breaking any test.**
  `test/components/kb/kb-reconnect-banner.test.tsx:51-75` constructs a full
  `UseKbLayoutStateResult`; widening that interface fails typecheck only.
- **A wrong Tailwind `soleur-*` token is a silent no-op** — no `tsc` error, no test failure. Grep
  `app/globals.css` first.
- **Never read the full-suite summary count as a pass signal.** `N-1/N` means a suite failed;
  `[FAIL] <suite> (0ms)` means a sub-suite crashed. This is exactly how #6874 reached `/ship`.
- **Do not open `navigation/kb-mobile-nav-redesign-wireframes.pen`** — the Pencil adapter can wipe
  valid `.pen` files on open (#3274). This plan's `.pen` is already committed.
- **Screenshot numbering is shared per domain folder.** `navigation/screenshots/` holds `01-`…`36-`;
  Phase 0.2 starts at `37-`. PNGs must be **direct children** — nested paths are gitignored
  (`.gitignore:70`) and fail to commit silently.
- **A comment asserting an invariant is not the invariant.** `kb/layout.tsx:39-43` and
  `app/(dashboard)/layout.tsx:229` both describe a doc-view back-suppression the code does not
  perform (`inKbDocView` is dead). Two agents and one draft of this plan inherited that fiction from
  the comment. Verify wiring, not prose.
- **A wrapper `data-testid` is not evidence the thing inside it rendered.** `kb-rail-tree` sits
  outside the `collapsed ?` ternary by design (`kb-sidebar-shell.tsx:107` — "the stable wrapper
  always renders to anchor present/absent assertions"), and `e2e:604` proves it by asserting the
  wrapper attached while the file row's count is 0. Assert the `role="navigation"` node.
- **An assertion can agree with the bug.** A testid the component emits to describe *its own
  placement* cannot detect mis-placement — pass the wrong host prop at the rail and the node renders
  inside the rail slot carrying the browse testid, and a testid-based host check reports success.
  Only containment against the real slot node can fail there.
- **A RED test driven by a module-level mock must be re-rendered, not re-mounted.** `unmount()` +
  a fresh `render()` makes a transition case tautologically green: a fresh render cannot have a
  stale portal, which is the only thing the case exists to catch.
- **A safety argument that rests on "no other code does X" is only as strong as the phase that might
  do X.** v1's hydration argument was correct about the codebase and falsified by v1's own
  implementation phase. When a plan argues safety from a precondition, name the phase that could
  break it and add an AC pinning it — here, AC3.

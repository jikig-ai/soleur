---
title: "feat: Direct keyboard shortcuts for command-palette destinations"
date: 2026-07-01
branch: feat-one-shot-palette-page-shortcuts
lane: cross-domain
type: feature
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [5636]
partially_addresses: ["#5637 (dedicated agent binding facet)", "brainstorm 2026-06-22 Open Question #1"]
---

# feat: Direct keyboard shortcuts for command-palette destinations ✨

## Enhancement Summary

**Deepened on:** 2026-07-01
**Agents:** spec-flow-analyzer (binding/collision flows), framework-docs-researcher (sequence
timing + WCAG 2.1.4 + cmdk hint rendering), code-simplicity-reviewer (YAGNI pass).

**Key improvements folded in:**
1. Bumped the sequence window to **1500 ms** (GitHub `hotkey`'s proven value; 1000 ms felt tight).
2. Confirmed **WCAG 2.1.4 DOES apply to two-key sequences** (they are not modifier-exempt) — the
   existing `shortcutsEnabled` turn-off is a valid, sufficient compliance path (W3C: turn-off OR
   remap OR focus-only; we have turn-off).
3. **Simplified per the YAGNI pass:** dropped the separate `NAV_SEQUENCES` table + bidirectional
   drift test in favor of a `seq` field on the existing `NAV_ITEMS`/`ADMIN_NAV_ITEMS` arrays
   (single-source by construction — drift structurally impossible, no test needed); relaxed the
   guarded-no-op to "Next.js dedupes a same-route push"; collapsed `resolveSequence`'s return to
   `CommandEffect | "arm" | null`.
4. Grounded `<kbd>`-pair hint rendering for sequences (`G` `I` as two `<kbd>`) vs a single glyph
   for chords, matching cmdk/Linear convention.
5. Kept (justified, not YAGNI): the `paletteOpen || helpOpen` modal guard (overlay has no focused
   input), resolver-level admin gating, no-new-dependency in-house buffer, `e.repeat` skip +
   focusin-clear (both industry-standard, one line each).

## Overview

The shipped command layer (`⌘K` palette + `?` overlay, PR #5633) makes every destination
reachable via **⌘K → type → Enter**. This feature adds **direct global shortcuts** so an
operator can jump straight to a destination without opening the palette, shows each key hint
inline in the palette, and lists them in the `?` overlay.

Destinations to bind (from the palette registry):

| Palette item | Group | Route | Requested binding |
|---|---|---|---|
| Ask an agent | Ask an agent | `/dashboard/chat/new` | `Ctrl+C` (conflicts — rebound, see §Binding Decision) |
| Dashboard | Navigation | `/dashboard` | dedicated |
| Inbox | Navigation | `/dashboard/inbox` | dedicated |
| Workstream | Navigation | `/dashboard/workstream` | dedicated |
| Knowledge Base | Navigation | `/dashboard/kb` | dedicated |
| Routines | Navigation | `/dashboard/routines` | dedicated |
| Analytics | Navigation (admin-only) | `/dashboard/admin/analytics` | dedicated |

**This feature realizes deferred issue #5636** ("two-key navigation sequences — G then I"),
whose re-evaluation criterion was *"Palette shipped and adopted; operators ask for faster nav
than ⌘K-then-type. Build through the existing registry, not a parallel handler."* The palette
shipped; this is that follow-up. It also resolves the parent brainstorm's Open Question #1
("should 'Ask an agent' get a dedicated direct binding") for the agent hero action.

Crucially: **the `G`-then-key nav-sequence design already exists in the shipped `#5633`
wireframe.** `help-overlay.tsx:5-7` documents it verbatim — *"the wireframe's `G`-then-I/K/R/D
nav sequences are NG2-deferred (#5636) and would document dead keys, so they are omitted."*
This plan un-defers exactly that design: build the sequences, then surface them in the overlay.

### Non-goals

- **Single-key unmodified verbs** (bare `c`=create etc., #5637) — still deferred; chat-typing
  collisions + no object model. This feature uses a `g`-**prefix**, never a bare letter.
- **Rebinding / remap UI** — WCAG 2.1.4 is satisfied by the existing turn-off toggle (§Legal).
- **Agent-invocable command surface** (#5638) — unchanged; the registry stays structured for it.
- **New Flagsmith flag** — the new shortcuts ride the existing `command-palette` `enabled` gate.
- **`tinykeys` or any new keyboard dependency** — the sequence buffer is ~30 lines in-house,
  matching the existing pure-matcher philosophy (and avoids the `cmdk` lockfile-sync pain from
  #5633; see §Sharp Edges).

## Binding Decision (documented per request)

The request said *"Ask an agent → Ctrl+C … Note: Ctrl+C is normally browser copy/interrupt — if
it conflicts, pick the closest non-conflicting binding and document the choice"* and left the six
nav bindings unspecified ("each get their own dedicated shortcut"). Here is the chosen scheme and
why.

### Why NOT modifier chords for the six nav items

Every mnemonic `Ctrl/⌘+<letter>` collides with a browser shortcut on at least one major browser,
and the `isEditable` guard cannot protect chords the browser handles before our listener:

| Candidate | Collision |
|---|---|
| Ctrl/⌘+D (Dashboard) | Bookmark this page (all browsers) |
| Ctrl/⌘+I (Inbox) | Firefox page-info / italic |
| Ctrl/⌘+K (KB) | already taken (palette) |
| Ctrl/⌘+R (Routines) | Reload page (all browsers) |
| Ctrl/⌘+1..6 (by index) | Switch to tab N (Chrome/Firefox) |
| Ctrl/⌘+J (agent, per brainstorm ⌘J idea) | Downloads (Chrome/Firefox, Win/Linux) |

This collision minefield is precisely why Linear/GitHub/Slack — and Soleur's own #5633
wireframe — use a **`g` "go-to" prefix** for navigation: `g` alone and each target letter alone
do nothing, so there is nothing to collide with, and the sequence is mnemonic ("**g**o to **d**ashboard").

### Chosen scheme

**Navigation — two-key `g`-then-letter sequences** (mnemonic; the wireframe's design):

| Sequence | Destination | Route | Gate |
|---|---|---|---|
| `g` `d` | Dashboard | `/dashboard` | always |
| `g` `i` | Inbox | `/dashboard/inbox` | always |
| `g` `w` | Workstream | `/dashboard/workstream` | always |
| `g` `k` | Knowledge Base | `/dashboard/kb` | always |
| `g` `r` | Routines | `/dashboard/routines` | always |
| `g` `a` | Analytics | `/dashboard/admin/analytics` | **admin only** |

**Ask an agent (hero action) — rebound from `Ctrl+C` to `g` `c`** ("go to chat"). Rationale:
`Ctrl+C` is a hard, non-negotiable conflict — copying a selection from non-editable page content
must keep working, and `isEditable` does NOT cover a text selection outside an input, so
intercepting `Ctrl+C` would silently break copy (a `single-user incident`-class trust erosion).
Folding the agent action into the same collision-free `g`-family keeps **one coherent, learnable,
WCAG-safe scheme** rather than a chord that works on some browsers and breaks on others. `c` =
**c**hat, closest surviving letter to the requested `Ctrl+C`.

**Open UX call for CPO sign-off (the one flagged decision).** spec-flow (G12) argues the agent
action is the *highest-value* shortcut and that `g c` semantically **demotes** it — it reframes
"start a new agent conversation" (a hero *verb*) as mere *navigation to a page*, and buries it in
the `g`-nav family. Linear reserves single-key `c` (create) precisely to give the hero verb
distinct weight. The counter-arguments for `g c`: (a) a browser-safe single chord does not exist
(`⌘J`=Downloads, `Ctrl+C`=copy, most `⌘+letter` are browser-claimed); (b) a bare single-key `c`
is exactly deferred #5637 (chat-typing collision surface + WCAG 2.1.4 single-char shortcut) and
re-opening it is out of scope; (c) one coherent `g`-family is more learnable than a mixed scheme.
**Recommendation: `g c`, grouped under "Ask an agent" (NOT "Navigation") in the overlay so it
reads as an action**, with the global hint shown as `G C` (not the palette-only `⌘↵`). If CPO
prefers hero-weight, the only defensible single-keystroke fallback is documented-and-accepted
`Ctrl+Shift+K` (browser-safe on Chrome; note Firefox uses it for the console) — awkward, hence
not recommended. This is the sole item requiring CPO sign-off before `/work`.

### Why this satisfies the request literally

- "Register these global shortcuts" → six nav sequences + `g c` in the one global listener.
- "Ask an agent → Ctrl+C … if it conflicts pick the closest non-conflicting binding and document"
  → Ctrl+C conflicts; `g c` is the closest coherent non-conflicting binding; documented here.
- "show the key hint next to each item in the command palette" → §FR3.
- "surface them in the ? keyboard-shortcuts overlay" → §FR4.

## User-Brand Impact

**If this lands broken, the user experiences:** a shortcut that navigates to the wrong page, or a
`g`-prefix that swallows the next keystroke inside chat/search, or a bound `Ctrl+C` that stops
copying selected text — on a keyboard surface the operator drives constantly.

**If this leaks, the user's data is exposed via:** N/A — no data surface; client-side navigation
only. The only "leak" vector is admin-gated `g a` navigating a non-admin toward an admin route
(mitigated: the sequence is inert for non-admins AND the route is server-guarded regardless).

**Brand-survival threshold:** single-user incident (inherited from the parent
`2026-06-22-keyboard-shortcuts` brainstorm, tagged user-brand-critical per #5175).

> CPO sign-off required at plan time before `/work` begins (the one open call is the hero-action
> binding: `g c` vs a chord — §Binding Decision). `user-impact-reviewer` runs at review time.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "Add global shortcuts" implies a new handler | One global listener already exists (`use-shortcuts.tsx`); `resolveShortcut` is a pure single-event matcher | Extend the ONE listener with a small `pendingPrefixRef` + a companion `resolveSequence`; no parallel handler, no new dep (honors #5636 criterion) |
| Nav commands carry a `keys` hint today | They do NOT — only the General group commands set `keys`; the Navigation group maps `NAV_ITEMS` without `keys` and `command-palette.tsx` does not render hints for the Navigation group | Add `keys` to the nav + ask commands AND render the hint in the Navigation + Ask groups |
| Ask-an-agent binding | Palette hero hint is `⌘↵` (Cmd+Enter, palette-open only); there is no global summon binding | Add a global `g c` summon + set the item's `keys` hint |
| A new flag is needed | Command layer already gated by `command-palette` (`enabled`) | Reuse `enabled`; no flag-create |
| Analytics is a normal nav item | It is `ADMIN_NAV_ITEMS`, admin-gated; `isAdmin` fetched via `/api/admin/check` and passed to the provider | `g a` reads `ctx.isAdmin`; inert + hidden from hints for non-admins |
| `?`/`g`-sequences risk WCAG 2.1.4 | Existing `shortcutsEnabled` localStorage turn-off gates the WHOLE listener | Sequences inherit the turn-off; WCAG exception (a) satisfied |

## Functional Requirements

- **FR1 — Sequence resolution.** A `g` keydown (when not suppressed) arms a pending "go-to"
  prefix for a short window (`SEQUENCE_WINDOW_MS = 1500` — GitHub `hotkey`'s proven value). A
  subsequent mapped letter within the window resolves to the destination `CommandEffect`
  (`navigate`/`openChat`) and clears the prefix. Any of: an unmapped key, a second `g`, `Escape`,
  or window expiry → clears the prefix with **no navigation** (no dead-key surprise). Two subtleties
  from the spec-flow pass (G2/G5), both industry-standard one-liners: (a) an **unmapped second key
  falls through** — it aborts the prefix but is NOT swallowed, so `g` then `⌘K` still opens the
  palette and `g` then `?` still opens help; (b) **auto-repeat is ignored** — `e.repeat === true`
  never arms/advances (MDN-standard). A `focusin` into an editable also clears any pending prefix
  (standard "don't trap the user" pattern; the 1500 ms window already bounds the stale-prefix
  worst case to a sub-second window, so this is cheap belt-and-suspenders, not load-bearing).
  Implemented as a DOM-free, unit-testable `resolveSequence(pending, event, ctx)` companion to
  `resolveShortcut` returning `CommandEffect | "arm" | null` (three outcomes: navigate / arm-prefix
  / clear), so both share the `isEditable` suppression and are tested without a DOM (matching
  `shortcuts-registry.test.ts`).
- **FR2 — Suppression parity.** Sequences obey the exact same guards as ⌘K/⌘B: suppressed while
  `isEditable(target)` (chat input, palette/overlay search), while `!shortcutsEnabled` (WCAG
  turn-off), and — for the *new nav/agent* bindings — while the `command-palette` flag is OFF
  (`enabled === false`). (⌘B stays flag-independent as today.)
- **FR3 — Palette key hints.** Each Navigation command and the Ask-an-agent hero item render their
  key hint inline via the existing `.cmdk-keys` slot already used by the General group. Sequences
  render as **two adjacent `<kbd>` elements** (`G` `D`) per cmdk/Linear convention; chords stay a
  single glyph. Admin-only `g a` hint renders only when `isAdmin` (buildCommands already omits the
  Analytics command for non-admins, so the hint is naturally absent).
- **FR4 — Help overlay rows.** The `?`/`⌘/` overlay lists the six nav sequences + the agent
  sequence (removing the `#5636`-deferred omission note in `help-overlay.tsx`), matching the
  committed wireframe `knowledge-base/product/design/command-palette/command-shortcuts-wireframes.pen`
  (the design of record from #5633). The admin-only Analytics row renders only when `isAdmin`. Rows
  keep the existing "selecting a row runs the shortcut" behavior (each new row's action navigates /
  opens chat via `runEffect`).
- **FR5 — Admin gating.** `g a` navigates only when `ctx.isAdmin`; for a non-admin it is a
  cleared prefix with no navigation, and neither the palette hint nor the overlay row appear.
- **FR6 — Idempotent navigation.** A nav sequence resolved while already on the target route is a
  harmless same-route `router.push` — Next.js App Router de-dupes it (no full reload). No explicit
  `pathname === href` guard is warranted (the YAGNI pass confirmed the loading-flash it would
  prevent is not reproducible for a static route); if one ever surfaces it is a one-line addition.
- **FR7 — Overlay/palette modal suppression.** Go-sequences are fully suppressed while
  `paletteOpen || helpOpen` (G6). The palette's search `Command.Input` already makes `isEditable`
  true (so `g d` types literally into the palette search), but the **help overlay's list has no
  focused input** — without an explicit `paletteOpen || helpOpen` guard, `g d` could navigate from
  underneath the open overlay, which is surprising. Treat both overlays as modal w.r.t. sequences.

## Technical Requirements / Implementation Phases

### Phase 0 — Preconditions (grep-verify before coding)
- Confirm `resolveShortcut`'s pure-matcher shape and that `ShortcutAction` is a string union
  (`use-shortcuts.tsx:67-93`) — the sequence resolver returns a `CommandEffect | null` instead of
  extending that union, so `navigate`/`openChat` flow through the existing `runEffect`.
- Confirm vitest include globs: node `test/**/*.test.ts` + jsdom `test/**/*.test.tsx`
  (`vitest.config.ts:44,64`). New unit tests → `test/shortcuts-registry.test.ts` (node); component
  tests → `test/command-palette.test.tsx` / `test/help-overlay.test.tsx` (jsdom).
- Confirm `isAdmin` reaches the provider (`layout.tsx:253` `isAdmin={isAdmin}`) and is in
  `ShortcutsContextValue` (`use-shortcuts.tsx:204`).

### Phase 1 — Registry: bindings + hints (`use-shortcuts.tsx`, `nav-items.ts`)
- Add a `seq` field (e.g. `"g d"`) directly to each entry in the existing `NAV_ITEMS` /
  `ADMIN_NAV_ITEMS` arrays (admin-ness is already implied by which array). `buildCommands` derives
  the `keys` hint from `seq` (`"g d"` → display `G` `D`), so palette hints, overlay rows, and the
  resolver **all read one field on one array** — single source by construction, no separate table,
  no drift test needed (YAGNI pass). Add `seq: "g c"` on the `ask-agent` action too — **show `G C`**
  as its hint (the global binding), since the current `⌘↵` only works with the palette already open.
- Add `resolveSequence(pending, e, ctx)` (pure, DOM-free) returning `CommandEffect | "arm" | null`:
  a matched second key → its `CommandEffect`; a bare `g` (not editable, not mid-sequence) → `"arm"`;
  any terminating non-match / `e.repeat` → `null`. Reuses `isEditable`; `g a` returns `null` unless
  `ctx.isAdmin`.

### Phase 2 — Listener: the sequence buffer (`ShortcutsProvider`, `use-shortcuts.tsx`)
- Add a `pendingPrefixRef` (`{ key: "g"; at: number } | null`) + window constant
  (`SEQUENCE_WINDOW_MS = 1500`) inside the ONE existing `keydown` handler. Order of checks (the
  pending-prefix check must PRECEDE the Escape drawer branch — G3): `shortcutsEnabled` → **if a
  prefix is pending: `Escape`/expiry/unmapped/editable clear it (and Escape is swallowed so it does
  NOT also run the `onEscape` drawer-close); a mapped key resolves** → else `Escape` drawer branch
  (unchanged) → `resolveShortcut` (chords, unchanged) → `resolveSequence` arm-on-`g` (only if
  `enabled` AND not `paletteOpen || helpOpen` — FR7 modal guard). The matched second key
  `preventDefault()`s and calls `runEffect(effect)` (admin-gated for `g a` via
  `stateRef.current.isAdmin` — thread `isAdmin` into `stateRef`).
- Prefix clears on: window expiry (checked on next keydown via `at` timestamp — no `setTimeout`
  needed, keeps the "read state via ref, never re-subscribe" TR2 invariant), unmapped key
  (fall-through, not swallowed), second `g`, `Escape` (swallowed), or focus-in-editable.
  Auto-repeat (`e.repeat`) never arms/advances. **No new listener; no re-subscription.**

### Phase 3 — Palette hints render (`command-palette.tsx`)
- Render `cmd.keys` for the Navigation group rows (mirror the General group's
  `{cmd.keys && <span className="cmdk-keys"> {cmd.keys}</span>}` at lines 332-343) and for the
  Ask-an-agent hero item. Non-admin: `buildCommands({isAdmin:false})` already omits the Analytics
  nav command, so its hint is naturally absent — assert this.

### Phase 4 — Help overlay rows (`help-overlay.tsx`)
- Extend `SHORTCUTS` with the six nav rows + the agent row, each carrying a new `HelpAction`
  variant that runs the corresponding `CommandEffect` via `runEffect`. Gate the Analytics row on
  `isAdmin` (read from `useShortcuts()`). Remove the `#5636`-deferred omission comment (lines 5-7).
- Keep WCAG note: rows are display + click launcher; the disable path is the Settings toggle.

### Phase 5 — Tests (write failing first — `cq-write-failing-tests-before`)
- `test/shortcuts-registry.test.ts` (node): `resolveSequence` truth table — `"arm"` on `g`;
  each mapped second key → correct effect; unmapped/second-`g`/`e.repeat` → `null`; `g a` gated by
  `ctx.isAdmin` (admin→navigate, non-admin→`null`). One structural assertion that `buildCommands`
  hints derive from the `seq` field on `NAV_ITEMS` (AC7 — single source).
- `test/command-palette.test.tsx` (jsdom): Navigation rows + Ask row show their `keys` hint;
  non-admin has no Analytics hint.
- `test/help-overlay.test.tsx` (jsdom): overlay lists the new rows; Analytics row present for
  admin, absent for non-admin; selecting a nav row calls the navigate effect.
- Integration (jsdom, existing provider harness): `g` then `d` navigates; `g` then Escape does
  not; `g` while focus in an input types literally; sequence no-ops when `shortcutsEnabled=false`
  and when `enabled=false`.

### Phase 6 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w …` — no root
  `workspaces`; per Sharp Edges).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/command-palette.test.tsx test/help-overlay.test.tsx`
  then the full suite.

## Files to Edit
- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — `resolveSequence`, sequence
  buffer in the listener, `keys` hints in `buildCommands`, thread `isAdmin` into `stateRef`.
- `apps/web-platform/components/command-palette/nav-items.ts` — add a `seq` field to the existing
  `NAV_ITEMS`/`ADMIN_NAV_ITEMS` entries + `seq` on the ask-agent action (single source; no new table).
- `apps/web-platform/components/command-palette/command-palette.tsx` — render nav + ask key hints.
- `apps/web-platform/components/command-palette/help-overlay.tsx` — new overlay rows + admin gate;
  remove the #5636-deferred omission comment.
- `apps/web-platform/test/shortcuts-registry.test.ts` — sequence resolver + hint-sync tests.
- `apps/web-platform/test/command-palette.test.tsx` — hint-render tests.
- `apps/web-platform/test/help-overlay.test.tsx` — overlay-row + admin-gate tests.

## Files to Create
- None (all changes extend existing command-layer files). New tests land in existing test files.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `resolveSequence` unit tests pass: `g` arms; `g d|i|w|k|r|c` → correct effect; `g a` →
  navigate iff `ctx.isAdmin`; unmapped/second-`g`/Escape/timeout/editable → null effect + cleared.
- **AC2** Integration: `g d` navigates to `/dashboard`; `g` then a 1.2 s pause then `d` does NOT
  navigate (window expired); `g` while focus in an `<input>` types `g` literally (no arm).
- **AC3** Sequences are inert when `shortcutsEnabled=false` (WCAG turn-off) AND when the
  `command-palette` flag `enabled=false`; ⌘B remains functional at `enabled=false` (unchanged).
- **AC4** Palette Navigation rows and the Ask-an-agent row render their key hint (`G D` … `G C`);
  non-admin render shows no Analytics row/hint. (jsdom render assertion on `.cmdk-keys`.)
- **AC5** `?`/`⌘/` overlay lists all six nav rows + the agent row; the Analytics row is present
  for `isAdmin=true`, absent for `isAdmin=false`; selecting a nav row invokes its navigate effect.
- **AC6** No new keyboard dependency added (`git diff package.json` shows no additions);
  `tsc --noEmit` clean; full web-platform vitest suite green.
- **AC7 (single source)** The `seq` field lives on the existing `NAV_ITEMS`/`ADMIN_NAV_ITEMS`
  arrays and the resolver, palette hints, and overlay rows all derive from it — a structural
  assertion (one test reads the arrays and confirms the resolver map + rendered hints match the
  `seq` values) rather than a separate table + bidirectional drift test.
- **AC8 (modal)** While `paletteOpen || helpOpen`, no go-sequence navigates (help overlay has no
  input, so this needs an explicit guard beyond `isEditable`).
- **AC9 (abort semantics)** `g` + Escape cancels the prefix and does NOT close the mobile drawer;
  `g` + an unmapped key aborts silently and that key still runs its own binding (`g` then `⌘K`
  opens the palette).
- **AC10 (editable audit)** All typing surfaces (chat composer, KB editor) satisfy `isEditable`
  (INPUT/TEXTAREA/SELECT/contentEditable). If any uses `role="textbox"` on a non-`contentEditable`
  node, extend the predicate before merge — a `g` armed outside it could otherwise navigate on the
  next letter typed there. (Bounded here since sequences require the `g` prefix first, but audit.)

### Post-merge (operator)
- None. No flag-create (rides existing `command-palette` flag), no migration, no infra. The change
  is client-only under `apps/web-platform/components/**` and deploys via the standard
  `web-platform-release.yml` container restart on merge to main.

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Engineering
**Status:** reviewed (inline — registry extension, no new substrate)
**Assessment:** Extend the ONE global listener with an in-house sequence buffer + a pure
`resolveSequence` companion; route through the existing serializable `CommandEffect`/`runEffect`
so the agent-native seam (#5638) is untouched. No new keyboard lib (avoids the #5633 lockfile-sync
pain). State read via the existing `stateRef` (no listener re-subscription, TR2 preserved).

### Legal
**Status:** reviewed (inline)
**Assessment:** WCAG 2.1.4 *Character Key Shortcuts* (Level A). Framework research confirms two-key
sequences (`g i`) **ARE in scope** for SC 2.1.4 (only modifier-key chords are exempt), so a
compliance path is required — one of turn-off / remap / focus-only (W3C). We satisfy **turn-off**:
the existing device-local `shortcutsEnabled` toggle gates the whole listener (default ON,
Settings → Keyboard shortcuts). CLO's hard requirement from #5637 (disable/remap/focus-only) is met
by that toggle + the `isEditable` focus guard. No new IP exposure (functional key bindings; no
Linear help-text/branding copied). No regulated-data surface.
Sources: W3C Understanding SC 2.1.4; GitHub `hotkey` (1500 ms sequence window).

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline) — references existing shipped wireframe
**Agents invoked:** spec-flow-analyzer (binding/collision flow analysis)
**Skipped specialists:** ux-design-lead — N/A: no new page/component/interactive surface is
created; the visual delta is (a) inline `.cmdk-keys` text hints on existing rows and (b) new rows
in the existing `?` overlay, both matching the **already-committed #5633 wireframe**
`knowledge-base/product/design/command-palette/command-shortcuts-wireframes.pen` (verified present
in `git ls-files`), whose `G`-then-I/K/R/D nav-sequence design this feature un-defers
(`help-overlay.tsx:5-7` documents that the overlay *omitted* those sequences pending #5636). No new
`.pen` required; that committed wireframe is the design of record.
**Pencil available:** N/A (no new UI surface)

#### Findings
See §Binding Decision (collision matrix) and the spec-flow gaps folded into FR1/FR5/FR7 + AC2/AC5.

## Architecture Decision (ADR/C4)

**No ADR.** This is a within-component extension of the existing command registry — no new
substrate, ownership/tenancy boundary, resolver/trust boundary, or ADR reversal.

**No C4 impact.** Verified against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): a grep for
`palette|keyboard|shortcut|command layer` returns zero — the client-side command layer is not a
C4 element, and this feature introduces **no** new external human actor (no new correspondent /
reviewer / recipient), **no** external system/vendor (no webhook/API/store), **no** container or
data store, and **no** actor↔surface access-relationship change (admin gating on `g a` is an
existing, already-modeled authz boundary — `/api/admin/check`, unchanged). Checked and
found-not-applicable; nothing to add or render.

## Observability

This is a **client-only** UI change (no `apps/*/server|src|infra` edits, no new runtime process),
so there is no server heartbeat to declare; the schema is filled honestly for the client surface —
CI is the regression liveness gate and the existing client-observability hook is the error channel.

```yaml
liveness_signal:
  what: the web-platform vitest suite exercising the shortcut resolver + palette/overlay render
        (test/shortcuts-registry.test.ts, test/command-palette.test.tsx, test/help-overlay.test.tsx)
  cadence: every CI run (per PR) and every deploy of apps/web-platform
  alert_target: CI red blocks the PR / release; visible in the GitHub Actions run + PR checks
  configured_in: apps/web-platform/vitest.config.ts + the web-platform CI workflow
error_reporting:
  destination: Sentry via the existing client hook reportSilentFallback (@/lib/client-observability)
               — reused, not extended (nav via router.push has no server error path)
  fail_loud: true (existing routine-run failures in command-palette.tsx:187 already mirror to Sentry
             with the fnId tag; this feature adds no new swallow-the-error path)
failure_modes:
  - mode: sequence resolves to the wrong route
    detection: resolveSequence unit tests assert exact effect per key (AC1); component nav test (AC5)
    alert_route: CI red (pre-merge)
  - mode: g-prefix leaks into typing (fires while focus is in chat/search)
    detection: isEditable-suppression unit + integration tests (AC2/FR2)
    alert_route: CI red (pre-merge)
  - mode: hint/resolver drift (a documented key does not match the live binding)
    detection: structurally prevented — hint + overlay + resolver all read the `seq` field on
               NAV_ITEMS (AC7 single-source assertion)
    alert_route: CI red (pre-merge)
  - mode: non-admin triggers admin g a
    detection: admin-gating unit + render tests (AC1/AC4/AC5); route is server-guarded regardless
    alert_route: CI red (pre-merge)
logs:
  where: browser console only in dev; no server logs (client-side navigation). Sentry captures any
         reused reportSilentFallback event as today.
  retention: Sentry default retention for the web-platform project (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/command-palette.test.tsx test/help-overlay.test.tsx"
  expected_output: all suites pass (0 failures) — the shortcut resolver, palette hints, and overlay
                   rows behave as specified; no ssh, no prod access required
```

## GDPR / Compliance

Skipped — no regulated-data surface (no schema/migration/auth flow/API route/`.sql`); no LLM
processing of session data; client keyboard bindings only.

## Infrastructure (IaC)

Skipped — no new server, service, secret, vendor, DNS, cert, or cron. Pure code change against an
already-provisioned surface (`apps/web-platform/components/**`).

## Open Code-Review Overlap

None. Ran `gh issue list --label code-review --state open` (200-limit) and `contains()`-matched
each edited file path against issue bodies — zero hits for `use-shortcuts.tsx`, `nav-items.ts`,
`command-palette.tsx`, `help-overlay.tsx`. No open scope-out touches this feature's files.

## Test Scenarios

1. `g` `d` → `/dashboard`; `g` `i` → `/dashboard/inbox`; … `g` `c` → `/dashboard/chat/new`.
2. `g` then 1.2 s then `d` → no nav (window expired).
3. `g` then `x` (unmapped) → prefix cleared, no nav; a later `g` `d` still works.
4. `g` then `Escape` → prefix cleared, no nav, no overlay side-effect.
5. Focus in chat input → `g` `d` types "gd" literally, no nav (isEditable).
6. Palette open, focus in search → `g` types literally into search (isEditable).
7. Non-admin `g` `a` → no nav; no Analytics palette hint; no Analytics overlay row.
8. Admin `g` `a` → `/dashboard/admin/analytics`; hint + overlay row present.
9. `shortcutsEnabled=false` → every sequence inert; ⌘B also inert (whole listener off).
10. `command-palette` flag OFF (`enabled=false`) → sequences inert; ⌘B still toggles (unchanged).
11. Already on `/dashboard`, press `g` `d` → harmless same-route `router.push` (Next.js de-dupes),
    no error. (No guard asserted — see FR6.)

## Research Insights

**Sequence timing (framework-docs):** GitHub's `hotkey` uses a **1500 ms** window between keys;
`keyboard-shortcut` defaults to 1000 ms (both configurable). 1500 ms is the more forgiving,
production-proven value → `SEQUENCE_WINDOW_MS = 1500`. When the first key arms, other single-key
shortcuts are blocked for the window (irrelevant here — we have no bare single-key bindings).
- github/hotkey · npm `keyboard-shortcut`

**WCAG 2.1.4 (framework-docs, load-bearing):** two-key `g i` sequences **are in scope** for SC
2.1.4 Level A — they are treated as character-key shortcuts (only modifier chords like `⌘K` are
exempt). Compliance requires **one** of: turn-off, remap, or focus-only. We ship **turn-off** via
the existing `shortcutsEnabled` toggle → compliant. (This closes the CLO hard requirement carried
on #5637.)
- W3C Understanding SC 2.1.4 · TestParty WCAG 2.1.4 (2025)

**Auto-repeat + focus (framework-docs):** ignore `e.repeat` at the top of the handler (MDN
`KeyboardEvent.repeat`); clear the pending prefix on `focusin` into an input to avoid trapping the
user mid-sequence. Both are one-liners and standard.

**cmdk hint rendering (framework-docs):** render each key as a `<kbd>`; a **sequence** = two
adjacent `<kbd>` (`G` `I`), a **chord** = a single glyph — matches cmdk's Linear example + shadcn
Command. The overlay already uses `<kbd className="cmdk-keys">`; the palette General group uses a
`<span className="cmdk-keys">` — reuse that slot, rendering two `<kbd>` for sequences.
- cmdk Linear example · shadcn/ui Command

**Simplicity pass (code-simplicity-reviewer):** for a 7-entry static keymap, a dedicated
`NAV_SEQUENCES` table + bidirectional drift test is over-built — a `seq` field on the existing nav
arrays makes drift structurally impossible. The guarded-no-op is defensive code for a
non-reproducible flash (Next.js already de-dupes). Both cut. Kept the modal guard, resolver-level
admin gating, and the no-new-dependency buffer as genuinely load-bearing.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, is `TBD`/placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6. This one is filled (threshold: single-user incident).
- **Do not add `tinykeys` or any keyboard dep.** #5636 *mentioned* `tinykeys`, but a ~30-line
  in-house prefix buffer fits the existing pure-matcher architecture and avoids the exact
  lockfile-sync failure that bit #5633 (`cmdk` added to `package.json`+`bun.lock` but not
  `package-lock.json` → CI `npm ci`/`lockfile-sync` failed). No new dep = no lockfile risk.
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`**, NOT
  `npm run -w apps/web-platform typecheck` (repo root declares no `workspaces`).
- **Tests must live in `apps/web-platform/test/`** to match vitest include globs
  (`test/**/*.test.ts` node, `test/**/*.test.tsx` jsdom) — a co-located `components/**/*.test.tsx`
  is silently never run.
- **Do not gate the sequence buffer on `setTimeout`.** Track the arm timestamp in the ref and
  check elapsed on the next keydown, preserving TR2 (one listener, never re-subscribes).
- **`Ctrl+C` must never be intercepted** — copying a non-editable selection is sacred and
  `isEditable` does not cover it. This is the core reason the hero action is rebound to `g c`.
- **Admin gating must be enforced in the resolver, not just the UI hint** — `g a` reads
  `ctx.isAdmin`; hiding the hint alone would still let a non-admin trigger the push (route is
  server-guarded, but the sequence should be a clean dead key for non-admins).

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Modifier chords per nav item (`⌘D`, `⌘I`, …) | Rejected | Browser-shortcut collisions (bookmark/reload/tab-switch); `isEditable` can't protect browser-handled chords |
| Keep `Ctrl+C` for Ask-an-agent | Rejected | Hard conflict with copy/SIGINT; breaks selection-copy (single-user-incident class) |
| `⌘J` for Ask-an-agent (brainstorm idea) | Rejected | Ctrl/⌘+J = Downloads (Chrome/Firefox, Win/Linux) |
| Dedicated chord for the hero action | Offered as CPO-signoff fallback | Ergonomically awkward (Ctrl+Shift+digit) or per-browser risky; `g c` recommended |
| Add `tinykeys` for sequences | Rejected | New dep + lockfile-sync risk; ~30-line in-house buffer suffices |
| Bare single-key nav (`d`,`i`,…) | Rejected | Chat-typing collisions + WCAG 2.1.4 (this is #5637, still deferred) |

## References
- `apps/web-platform/components/command-palette/use-shortcuts.tsx` (registry, listener, resolver)
- `apps/web-platform/components/command-palette/nav-items.ts` (nav source of truth)
- `apps/web-platform/components/command-palette/command-palette.tsx` (palette render, `.cmdk-keys`)
- `apps/web-platform/components/command-palette/help-overlay.tsx` (overlay; #5636 omission note)
- `apps/web-platform/app/(dashboard)/layout.tsx` (`ShortcutsProvider` wiring, `isAdmin`)
- `apps/web-platform/test/shortcuts-registry.test.ts`, `test/command-palette.test.tsx`, `test/help-overlay.test.tsx`
- Deferred issues: **#5636** (nav sequences — this closes it), #5637 (single-key verbs — stays deferred), #5638 (agent surface — unchanged)
- Parent brainstorm: `knowledge-base/project/brainstorms/2026-06-22-keyboard-shortcuts-brainstorm.md` (Open Question #1: dedicated agent binding)

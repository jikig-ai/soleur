---
title: "feat: Group Releases nav tab with Status & Settings (info/settings nav group)"
type: feat
date: 2026-07-07
branch: feat-one-shot-releases-info-tab-group
lane: single-domain
brand_survival_threshold: none
status: planned
---

# ✨ feat: Move "Releases" nav tab into the information/settings group

## Overview

The dashboard sidebar has two visually distinct nav groups:

1. **Primary action-tab group** (top of the rail, data-driven from `NAV_ITEMS`): Dashboard, Inbox, Workstream, Knowledge Base, Routines, **Releases**.
2. **Information/settings footer group** (bottom of the rail, hardcoded JSX below a top-border): user email, **Status** (external link → BetterUptime), **Settings**, Sign out, Theme toggle.

"Releases" is a **read-only informational feed** of shipped release notes — it is not a surface where the operator *does work*. It is the one item in the primary group that isn't an action destination, so it belongs in the information/settings footer group alongside Status and Settings.

**This change moves only the sidebar RENDER POSITION of Releases.** The route (`/dashboard/releases`), the page, the ⌘K command-palette entry, the `g l` go-to keyboard shortcut, and the `?` help-overlay row all stay exactly as they are.

### The critical constraint (why this isn't just "move a line")

`apps/web-platform/components/command-palette/nav-items.ts` → `NAV_ITEMS` is the **single source of truth for FOUR surfaces**:

1. the sidebar primary-nav render loop (`layout.tsx` ~L409–462),
2. the ⌘K command-palette registry (`use-shortcuts.tsx:301`),
3. the `g l` go-to shortcut resolver + `accel` map (`use-shortcuts.tsx:170, 231`),
4. the `?` help-overlay row (`help-overlay.tsx:61`).

If Releases is **removed** from `NAV_ITEMS`, three of its five entry points (palette, `g l`, help row) silently die. Therefore the Releases object **stays in `NAV_ITEMS` unchanged**; the sidebar primary-nav loop **filters it out** of its render, and the footer group renders it **explicitly** (the same pattern Status and Settings already use — they are hardcoded footer chrome, not `NAV_ITEMS` entries). This is the lowest-drift design: palette/shortcut/help auto-follow the untouched data source, and `shortcuts-registry.test.ts` (which iterates `NAV_ITEMS` generically) needs no change.

## User-Brand Impact

**If this lands broken, the user experiences:** a Releases link that is either missing from the sidebar entirely, duplicated (rendered in both the primary group and the footer), or shows no active-highlight when on `/dashboard/releases`. Worst realistic case: the `g l` shortcut / ⌘K palette entry regresses if `NAV_ITEMS` is edited instead of just the render.
**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is client-only sidebar chrome; no data, auth, network, or persistence surface is touched.
**Brand-survival threshold:** none — internal navigation chrome reposition; no sensitive path (no schema/migration/auth/API/`.sql`) in the diff, reason: single client render-position change to a nav link, fully reversible, no data or route impact.

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality | Plan response |
|---|---|---|
| "Reorder the dashboard navigation so Releases sits alongside Status and Settings" | Status & Settings are **not** in `NAV_ITEMS` — they are hardcoded footer JSX (`layout.tsx` L474–496). Releases **is** in `NAV_ITEMS` (L39) and renders via the primary loop. | Not a pure array reorder. Keep `NAV_ITEMS` intact (palette/shortcut source), filter Releases from the primary loop, and render it as explicit footer JSX mirroring the `settingsActive` pattern. |
| "It's an informational tab" | Releases route is a read-only GitHub-releases feed (`/dashboard/releases`, PR #5956/#5962). | Confirmed — grouping with Status (external status page) + Settings is IA-coherent. |
| Guided tour may target Releases | `tour-steps.ts` targets stop at `/dashboard/routines`; **no** step targets `/dashboard/releases`. | No tour breakage. Still add `data-tour-id="/dashboard/releases"` to the footer link to preserve the contract for future tour steps (cheap, harmless). |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Releases removed from primary nav render.** In the expanded sidebar, the primary action-tab list renders exactly: Dashboard, Inbox, Workstream, Knowledge Base, Routines (Releases no longer appears there). Verify: the primary loop iterates `navItems.filter((i) => i.href !== "/dashboard/releases")`.
- [ ] **AC2 — Releases renders once, in the footer info/settings group.** A Releases `<Link href={RELEASES_HREF}>` renders inside the footer chrome `<div>` (the `border-t` block, `layout.tsx` ~L464–512), positioned **first** in the footer action stack — order: email → **Releases** → Status → Settings → Sign out → Theme toggle. Because AC1 filters it from the primary loop and it is added exactly once here, it appears in exactly **one** sidebar location (verify by grep: the `/dashboard/releases` `<Link>` renders once in `layout.tsx`; the label/route still lives once in `nav-items.ts`).
- [ ] **AC3 — Active highlight works and matches its new neighbors.** On `/dashboard/releases` (and sub-routes like `/dashboard/releases/x`), the footer Releases link shows the **footer-neutral** active treatment (`bg-soleur-bg-surface-2 text-soleur-text-primary` + `aria-current="page"`) — the same active *className block* Settings uses, NOT the primary-nav gold treatment — so it reads as part of the info/settings group. **Derivation:** `const releasesActive = pathname.startsWith(RELEASES_HREF);`. NOTE: this is a direct `pathname` check, **not** a `drill`-state check — `/dashboard/releases` is not a drill segment (`DrillLevel` is only `"kb" | "settings" | "chat"`), so do **not** write `drill === "releases"` (that is a TypeScript error). Only the active className is shared with Settings; the derivation is not.
- [ ] **AC4 — Collapsed rail intact.** When the rail is collapsed, the footer Releases link renders icon-only using the directly-imported `RocketIcon` component (referenced directly like `SettingsIcon`, **not** via the `NAV_ICONS` map — that map is consumed only inside the primary loop) with `title={collapsed ? "Releases" : undefined}`, matching Status/Settings collapsed behavior. The footer block is **not** newly gated on `collapsed` (preserves the ADR-047 invariant that footer chrome mounts/unmounts on `drill === null` only, never on collapse).
- [ ] **AC5 — Palette + shortcut preserved (zero regression).** `NAV_ITEMS` is unchanged; ⌘K palette still lists "Releases", `g l` still navigates to `/dashboard/releases`, and the `?` help overlay still shows the `g l` row. `shortcuts-registry.test.ts` passes unchanged.
- [ ] **AC6 — `data-tour-id` for pattern consistency.** The footer Releases link carries `data-tour-id={RELEASES_HREF}` — matching how every primary-nav link derives `data-tour-id={item.href}`. (No tour step targets Releases today; this is for render-pattern consistency, not a hypothetical future tour. Cheap and harmless.)
- [ ] **AC7 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; the web-platform vitest suite passes (`./node_modules/.bin/vitest run`).
- [ ] **AC8 — Visual verification.** `/verify` (or Playwright) confirms the two nav groups render as designed in both expanded and collapsed states, matching the wireframe at `knowledge-base/product/design/dashboard/releases-nav-relocation.pen`.

## Files to Edit

- **`apps/web-platform/app/(dashboard)/layout.tsx`** — the only production code file changed:
  - Define a single route constant to avoid triplicating the string literal (the plan's thesis is "`NAV_ITEMS` is the source of truth", so pin the three new references to one local const): `const RELEASES_HREF = "/dashboard/releases";` near the top of the component. Use it in all three sites below. (A `NAV_ITEMS.find(i => i.label === "Releases")!.href` lookup is the alternative but adds a non-null-assertion + indirection for a route that will not move — the local const is the minimal pin; do not over-abstract.)
  - Add `releasesActive` derivation: `const releasesActive = pathname.startsWith(RELEASES_HREF);` (place near the existing `settingsActive` — but note `settingsActive` is a `drill === "settings"` check, NOT a pathname check; Releases has no drill level, so it uses `pathname.startsWith` directly. Do not write `drill === "releases"` — TS error).
  - Change the primary nav `.map` source from `navItems` to `navItems.filter((i) => i.href !== RELEASES_HREF)` so Releases is excluded from the action-tab loop. (Filter by `href`, not index; keep `ADMIN_NAV_ITEMS`/Analytics behavior unchanged.)
  - Insert a Releases `<Link>` as the **first** action in the footer chrome `<div>` (above the Status `<a>`), cloning the Settings `<Link>` markup: `href={RELEASES_HREF}`, a directly-referenced `<RocketIcon />` (the local component at ~L835, like `<SettingsIcon />` — not a `NAV_ICONS` lookup), `title={collapsed ? "Releases" : undefined}`, `aria-current={releasesActive ? "page" : undefined}`, `data-tour-id={RELEASES_HREF}`, and the neutral active/hover className block (identical to Settings, driven by `releasesActive`).
- **`apps/web-platform/components/command-palette/nav-items.ts`** — **NO CHANGE** (explicitly). Releases stays in `NAV_ITEMS` (L39) as the source of truth for the palette, `g l` shortcut, and help overlay. Documented here so a reviewer doesn't "helpfully" remove it.

## Files to Create

- `knowledge-base/product/design/dashboard/releases-nav-relocation.pen` — **already created** by the UX gate (before/after sidebar wireframe, 26,901 bytes). Commit with this feature.
- `knowledge-base/product/design/dashboard/screenshots/06-releases-nav-relocation-before-after.png` — wireframe render. Commit with this feature.

## Test Strategy

- **Palette/shortcut regression (existing):** `apps/web-platform/test/shortcuts-registry.test.ts` iterates `NAV_ITEMS` generically and must stay green with no edits — this is the guard that proves the `g l` / ⌘K entry for Releases survived. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts`.
- **Render position:** `layout.tsx` is a heavily provider-wrapped `"use client"` shell; a full mount test is high-effort / low-value for a render-position tweak. Primary verification is **`/verify` / Playwright visual** (AC9) across expanded + collapsed states, cross-checked against the `.pen`. If a lightweight sidebar render harness already exists at work time, add a focused assertion that the Releases `<Link>` is a descendant of the footer `border-t` container and absent from the primary `<nav>`; otherwise rely on typecheck + visual verification (do not build a new heavyweight harness for this).
- Full suite + typecheck per AC8.

## Observability

**N/A — client-only sidebar render reposition.** Phase 2.9 trigger paths (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) are **not** touched; the only code edit is `apps/web-platform/app/(dashboard)/layout.tsx` (a client React layout). No new error paths, no server code, no infrastructure, no failure modes to instrument. Discoverability of a broken render is the visual/Playwright check in AC9, not a runtime signal.

## Domain Review

**Domains relevant:** Product (UI-surface: sidebar nav chrome).

Non-Product domains (Legal, Finance, Marketing, Sales, Ops, Support, Engineering-Infra): **none relevant** — this is internal navigation chrome with no data, compliance, cost, distribution, or infra implications. One advisory note carried from CPO below.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `app/**/layout.tsx` + "nav rails / chrome" per `ui-surface-terms.md`)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** none — copywriter not needed (no copy changes; the "Releases" label is unchanged).
**Pencil available:** yes (`.pen` committed under `knowledge-base/product/design/dashboard/`)

#### Findings

- **ux-design-lead:** Produced `knowledge-base/product/design/dashboard/releases-nav-relocation.pen` — a before/after side-by-side of the expanded sidebar rail showing Releases relocating from the primary action group into the footer info/settings group (first footer action, rocket glyph). Screenshot `06-releases-nav-relocation-before-after.png`. *Note:* the wireframe rendered Releases with the gold active treatment purely as a **visual tracking aid** so the reviewer's eye follows the item across the before/after; the **plan prescribes the footer-neutral active treatment** (AC4) for group coherence with Status/Settings. This is the one intentional divergence from the wireframe.
- **spec-flow-analyzer:** Confirmed the four-surface data-model split is the crux. Recommended (adopted): keep Releases in `NAV_ITEMS` + filter from the primary loop (lowest drift); create `releasesActive` mirroring `settingsActive`; keep Releases a **flat root** palette command (rail-group ≠ palette-group, intentional — Releases is product content, not a setting); assign the collapsed icon + tooltip; add `data-tour-id`. All folded into ACs.
- **cpo:** **Proceed** — sound low-risk IA improvement; primary group becomes cleanly "action surfaces," Releases (read-only changelog) was the odd one out; matches SaaS convention (Linear/Vercel park changelog/status as meta chrome). Minor discoverability loss (footer is lower-salience) is mitigated by the retained ⌘K + `g l` access. **CMO note for future attention only (not a blocker):** if Releases is ever intended as a growth/retention "ship-velocity" signal, revisit its prominence post-beta — flagged, no decision needed now.

## Open Code-Review Overlap

- **#2193** — *refactor(billing): unify past_due and unpaid banners into shared component + extract useDismissiblePersistent* — touches `layout.tsx`. **Disposition: Acknowledge.** Disjoint concern (billing banner unification / `useDismissiblePersistent` extraction) from the nav-group reposition; no shared lines. Leave open; no fold-in.

## Institutional Learnings Applied

- `2026-07-01-global-go-sequences-must-suppress-under-any-app-modal.md` — the `g l` modal-suppression guard is untouched (we don't edit `nav-items.ts`); verify `g l` still suppresses under modals during `/verify`.
- `2026-06-22-collapsed-early-return-remounts-data-bearing-child-and-e2e-provenance-by-revert.md` (ADR-047) — do **not** newly gate the footer chrome block on `collapsed`; it mounts on `drill === null` only. (AC5.)
- `2026-07-02-platform-glyph-fix-must-sweep-all-render-sinks.md` — after the move, sweep that "Releases" renders once (footer) and its `g l` hint appears wherever it should (palette help), no orphaned/duplicated label.
- `2026-04-29-subagent-stale-file-read-in-worktree.md` — `NAV_ITEMS` feeds three sinks that auto-follow the data source; pass worktree-absolute paths to any subagent.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail `deepen-plan` Phase 4.6 — this plan fills it (threshold: none).
- **Do not remove Releases from `NAV_ITEMS`** — that silently kills the ⌘K entry, the `g l` shortcut, and the `?` help row. The move is a render-position change in `layout.tsx` only.
- **`settingsActive` is a drill check, not a pathname check.** It is `drill === "settings"`. Releases is **not** a drill segment (`DrillLevel = "kb" | "settings" | "chat"`), so its active state MUST use `pathname.startsWith(RELEASES_HREF)`. Writing `drill === "releases"` is a TypeScript error. Only the active *className* is shared with Settings, not the derivation. (AC3.)
- **Do not reuse the primary-nav gold active style in the footer** — use the neutral Settings active className so Releases reads as part of the info/settings group (AC3). The wireframe's gold is a tracking aid, not the target.
- **The footer references icons directly** (`<RocketIcon />`), not via the `NAV_ICONS` map — that map is consumed only inside the primary render loop. (AC4.)
- Filter the primary loop by `href` (via `RELEASES_HREF`), not by array index — `NAV_ITEMS` order/length is not pinned by tests, but an index filter would break if the array is reordered later.

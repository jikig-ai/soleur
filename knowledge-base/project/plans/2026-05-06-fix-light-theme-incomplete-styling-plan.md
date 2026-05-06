---
type: bug-fix
status: draft
created: 2026-05-06
deepened: 2026-05-06
branch: feat-one-shot-fix-light-theme-incomplete-styling
related_pr: "#3271"
related_issue: "#3232 (parent), follow-up TBD"
requires_cpo_signoff: false
---

# Fix Light Theme Incomplete Styling — Tokenize Remaining Web-Platform Surfaces

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Overview, Phase 1 (Mapping table), Phase 2 (Group F markdown-renderer + global-error guidance), Phase 3 (regression test design), Phase 4 (visual QA precedent), Risks (3 new), Sharp Edges (4 new), Research Insights (new section).

### Key Improvements

1. **Markdown-renderer is the highest-risk single file in the migration** — it controls every rendered chat message + KB doc, embeds amber link colors that need brand-token mapping (`text-soleur-accent-gold-fg`), and has 11 distinct color classes across `<h1>/<h2>/<h3>/<th>/<td>/<pre>/<code>/<blockquote>/<a>`. Promoted from Group F to its own dedicated review sub-step with both-themes manual verification on a long markdown reply.
2. **`app/global-error.tsx` rendering invariant pinned**: Next.js 15 mounts global-error inside its own `<html>` shell — `globals.css` IS imported on this route (it lives under `app/`), but the inline no-FOUC script is NOT, so `data-theme` is unset and `:root:not([data-theme])` resolves via `prefers-color-scheme`. Mapping to tokens is therefore **safe** but the section uses `:root:not([data-theme])` defaults, which means a dark-OS user sees Forge and a light-OS user sees Radiance — verify this rendering matches expectation.
3. **Tailwind v4 opacity-modifier compatibility verified**: `bg-soleur-bg-surface-2/60` and `border-soleur-border-default/50` are valid in Tailwind v4 — the `@theme` declaration shipped in PR #3271 wires CSS-variable-backed colors through the slash-modifier opacity pipeline (`color-mix(in oklch, var(--color-soleur-bg-surface-2) 60%, transparent)`). No need to add opacity-paired token variants.
4. **Brand-workshop UX-mockup-gate learning applies inversely**: PR #3271's predecessor session (`knowledge-base/project/learnings/best-practices/2026-05-05-brand-workshop-needs-ux-mockup-gate.md`) shipped the Radiance palette through brand-architect without rendering it on real surfaces. PR #3271 then validated the palette on credential surfaces only. **This PR is the missing surface validation** for chat / KB / dashboard / settings / connect-repo / share. The ux-design-lead Pencil iteration is NOT re-required — palette is locked; only application widens.
5. **Selected/emphasis state mapping needed**: dashboard page and chat-input use `border-amber-500/50` + `text-amber-500` for the selected pill state. Map to `border-soleur-border-emphasized` + `text-soleur-accent-gold-fg`; the gold-emphasis tokens are already in `globals.css` and shipped by PR #3271. Without this mapping, "selected" reads as muted gold on Radiance.

### New Considerations Discovered

- The migration covers 64 files / ~536 raw color lines. A multi-commit strategy (one commit per Group A–F) is preferable to a single mega-commit — each Group is independently reviewable, each commit can ship a screenshot pair, and `bisect` retains usefulness.
- The new regression-grep test (`light-theme-tokenization.test.tsx`) supersedes manual review for future drift. It is the load-bearing follow-up gate — without it, the next contributor adds a `bg-zinc-900` and Light mode silently regresses.
- `chat/leader-colors.ts` is OUT-OF-SCOPE but its consumers (`message-bubble.tsx`, `tool-use-chip.tsx`, `routed-leaders-strip.tsx`, `subagent-group.tsx`, `leader-avatar.tsx`) ARE in scope. The leader pink/blue/etc. literal classes in those consumer files must be left untouched while surrounding gray classes are tokenized — drift class: a careless rename touches `border-l-pink-500`.

## Overview

PR #3271 ("Light/Dark/System theme toggle + Light-mode tokenization for credential surfaces") shipped the theme toggle UI plus a CSS-variable-backed token system in `apps/web-platform/app/globals.css`, then tokenized only the credential / billing / concurrency / chat-rail surfaces (auth pages, billing, BYOK rotation, API-usage panel, upgrade-at-capacity, conversations rail). The user reports light mode "looks like you only did the background" — every other surface still ships hardcoded `bg-zinc-*` / `text-white` / `border-zinc-*` classes that do not respond to `data-theme="light"`.

Audit numbers (run 2026-05-06 against the current branch):

- **80 files** in `apps/web-platform/{app,components}` contain hardcoded gray/zinc/slate/neutral/stone backgrounds, text, or borders.
- **536 raw lines** of hardcoded color classes across those files.
- **Only 16 files** currently consume the `soleur-*` token namespace — those are the PR #3271 scope plus the new theme components.

This plan tokenizes the remaining 64 user-visible files using the same pattern PR #3271 established: drop hardcoded gray scales in favor of `bg-soleur-bg-*` / `text-soleur-text-*` / `border-soleur-border-*` Tailwind utilities, which resolve via CSS variables in `globals.css` and switch automatically on `<html data-theme="light">`.

**Goal:** Light mode renders all in-app surfaces (chat, KB browser, dashboard, settings, connect-repo, onboarding modals, share/error pages) with intentional Radiance-palette colors that match the brand-guide direction shipped in PR #3271, not just an inverted base background.

## Research Reconciliation — Spec vs. Codebase

| Claim from prompt / PR #3271 description | Codebase reality (2026-05-06) | Plan response |
|---|---|---|
| "PR #3271 only themed the background" | PR #3271 themed background **plus** 9 specific surfaces (auth × 4, billing, BYOK rotation, api-usage × 3, cancel-retention, upgrade-at-capacity, conversations-rail). Background-only was the *user-visible perception* — not literally what shipped. | Plan must scope to the **remaining** ~64 user-visible files, not re-tokenize what already shipped. Don't double-touch billing-section, conversations-rail, etc. |
| "Hardcoded `bg-zinc-*`, `bg-slate-*`, `text-white`" | Confirmed: 80 files, 536 lines. Includes `gray-`, `neutral-`, `stone-` variants too. The project uses all five Tailwind gray scales interchangeably. | Migration grep MUST cover all five (`zinc\|slate\|neutral\|gray\|stone`), not just the three named in the prompt. |
| "Apply the same semantic-token pattern from PR #3271" | Pattern is Tailwind v4 `@theme { --color-soleur-bg-*: var(--soleur-bg-*) }` declarations + `@custom-variant dark` pinned to `[data-theme="dark"]`. Migration is a class rename (`bg-zinc-900` → `bg-soleur-bg-base`), not a `dark:`-prefix retrofit. PR #3271 deliberately removed `dark:*` pairs in favor of the pinned variant. | Plan adopts the tokenized-class approach. Avoid introducing new `dark:bg-*` pairs — that contradicts the architecture. The single `dark:*` user (api-usage-section.tsx) is intentional and out of scope. |
| "Status colors (red/orange/green/blue) need theming" | Status colors are used for semantic purposes (errors, warnings, success). PR #3271 left these as-is (e.g., `bg-red-600`, `bg-orange-600`). | Out of scope for v1. Status colors are visually legible on both backgrounds; theming them adds risk without clear win. Track as deferred follow-up if visual QA flags contrast. |
| "Leader-color constants" (`apps/web-platform/components/chat/leader-colors.ts`) | Border/badge palette per domain leader (cmo→pink, cto→blue, etc.). Designed to be brand-recognizable across themes. | Out of scope. Domain identification > theme harmony. |

## User-Brand Impact

**If this lands broken, the user experiences:** Light mode toggle appears non-functional or chaotic — switching to Light flips the base background to ivory but leaves dark cards, dark sidebars, dark chat bubbles, and white-on-dark text floating on the new light surface. Multiple high-contrast inversions per screen. Reads as "the Light option is broken; the team didn't finish."
**If this leaks, the user's [data / workflow / money] is exposed via:** Not applicable — this is a pure visual/styling change. No new code paths handle credentials, payments, or user data.
**Brand-survival threshold:** none

This change carries no data-exposure or single-user-incident risk. It is a visual quality bar enforcement against a feature already shipped publicly.

## Research Insights

### Tailwind v4 + CSS-variable token mechanics (verified against repo state)

The token system established in `apps/web-platform/app/globals.css` (PR #3271) uses two layered mechanisms:

1. **`@theme` registration** turns `--color-soleur-*` CSS variables into Tailwind utility classes at compile time:
   ```css
   @theme {
     --color-soleur-bg-base: var(--soleur-bg-base);
     --color-soleur-text-primary: var(--soleur-text-primary);
     /* ...etc */
   }
   ```
   Result: `bg-soleur-bg-base`, `text-soleur-text-primary`, `border-soleur-border-default`, etc. resolve as standard Tailwind utilities.
2. **`@custom-variant dark`** is pinned to `[data-theme="dark"]` and `[data-theme="system"] @media (prefers-color-scheme: dark)`, so any `dark:*` class still works but is **not the migration target**. PR #3271 explicitly drops `dark:*` pairs in favor of single tokenized classes that respond automatically to the `data-theme` attribute change.

**Implication for this PR:** the migration is a 1:1 className rename, not a `light:`-prefix add. Reviewers expecting `dark:bg-zinc-950 light:bg-amber-50`-style pairs are wrong about the architecture; point them at `globals.css` and PR #3271's diff.

**Opacity modifier interaction:** Tailwind v4 implements `bg-color/N` via `color-mix(in oklch, <token> N%, transparent)`. CSS-variable-backed colors work natively — `bg-soleur-bg-surface-2/60` produces `color-mix(in oklch, var(--color-soleur-bg-surface-2) 60%, transparent)` and recomposes when the underlying variable changes on theme switch. No opacity-paired token additions required.

### Class-rename mapping (canonical reference)

Drop-in replacements for every hardcoded gray scale found in the audit. Two helpful sub-rules:

- **Page chrome / app shell backgrounds** (the biggest, outermost surface — modal overlay, dashboard outer, sheet desktop panel): `bg-zinc-950`, `bg-neutral-950` → `bg-soleur-bg-base`. Examples: `app/(dashboard)/layout.tsx`'s outer flex, `app/global-error.tsx`'s `<body>`.
- **Card / modal body / sidebar / topbar** (one elevation up): `bg-zinc-900`, `bg-neutral-900`, `bg-zinc-800` → `bg-soleur-bg-surface-1`. Examples: `billing-section.tsx` card, `conversations-rail.tsx`, sheet panels.
- **Hover / pressed / input field / chip / kbd** (two elevations up): `bg-zinc-800`, `bg-zinc-700`, `bg-neutral-700` → `bg-soleur-bg-surface-2`. Examples: `hover:bg-soleur-bg-surface-2`, `<kbd className="bg-soleur-bg-surface-2 ...">`.

Text:

- **Body emphasis / heading / value-text:** `text-white`, `text-zinc-50`, `text-zinc-100`, `text-zinc-200`, `text-neutral-100` → `text-soleur-text-primary`.
- **Body prose / labels:** `text-zinc-300`, `text-zinc-400`, `text-neutral-300`, `text-neutral-400`, `text-slate-300`, `text-slate-400` → `text-soleur-text-secondary`.
- **Muted / metadata / placeholder:** `text-zinc-500`, `text-zinc-600`, `text-neutral-500`, `text-stone-500`, `placeholder:text-zinc-500` → `text-soleur-text-muted` (and `placeholder:text-soleur-text-muted`).

Borders:

- **Default border:** `border-zinc-800`, `border-zinc-700`, `border-neutral-800`, `border-neutral-700`, `border-slate-700` → `border-soleur-border-default`.
- **Emphasis (selected / focused / brand-accent):** `border-amber-500`, `border-amber-500/50` → `border-soleur-border-emphasized` (drop the `/50` only if visual QA shows the new emphasized border is too strong; the Radiance emphasis token is `#9b8857`, similar visual weight to amber-500/50 on Forge).

Brand accents:

- **CTA fill button:** `bg-amber-500 text-black`, `bg-yellow-500 text-zinc-900` → `bg-soleur-accent-gold-fill text-soleur-text-on-accent`.
- **Gold link / accent label:** `text-amber-400`, `text-amber-500` → `text-soleur-accent-gold-fg`.
- **Gold link hover:** `hover:text-amber-300` → `hover:text-soleur-accent-gold-text`.

### Markdown-renderer color audit (`components/ui/markdown-renderer.tsx`)

This is the single highest-leverage file. It controls the rendered color of every chat message and every KB doc preview. The 11 color decisions in the current build:

| Element | Current class | Proposed mapping |
|---|---|---|
| `<h1>` | `text-white` | `text-soleur-text-primary` |
| `<h2>` | `text-white` | `text-soleur-text-primary` |
| `<h3>` | `text-neutral-200` | `text-soleur-text-primary` (heading hierarchy reads as primary on both themes; secondary makes h3 fade) |
| `<li>` | `text-neutral-200` | `text-soleur-text-secondary` |
| `<th>` | `border-neutral-700 bg-neutral-800/50 text-neutral-200` | `border-soleur-border-default bg-soleur-bg-surface-2/50 text-soleur-text-primary` |
| `<td>` | `border-neutral-700 text-neutral-300` | `border-soleur-border-default text-soleur-text-secondary` |
| `<pre>` (preWrap + non-wrap) | `bg-neutral-950 text-neutral-300` | `bg-soleur-bg-base text-soleur-text-secondary` (`pre` is intentionally darker than card surface — Forge stays dark, Radiance ivory base reads as a code-block recess) |
| `<code>` inline | `bg-neutral-800 text-amber-300` | `bg-soleur-bg-surface-2 text-soleur-accent-gold-fg` |
| `<a>` | `text-amber-400 hover:text-amber-300` | `text-soleur-accent-gold-fg hover:text-soleur-accent-gold-text` |
| `<strong>` | `text-white` | `text-soleur-text-primary` |
| `<blockquote>` | `border-neutral-600 text-neutral-400` | `border-soleur-border-default text-soleur-text-muted` |

Validation: render an existing chat conversation with at least one of every element above, screenshot Forge + Radiance, confirm contrast and visual hierarchy survive.

### Selected / emphasis state mapping (from dashboard + chat-input audit)

`apps/web-platform/app/(dashboard)/dashboard/page.tsx` and `chat-input.tsx` use a "pill-selected" pattern for prompt-mode toggle and routed-leader pills:

```tsx
// Before
className={isSelected
  ? "border-amber-500/50 bg-neutral-900 text-amber-500"
  : "border-neutral-700 bg-neutral-900 text-neutral-300"}

// After
className={isSelected
  ? "border-soleur-border-emphasized bg-soleur-bg-surface-1 text-soleur-accent-gold-fg"
  : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary"}
```

The `bg-neutral-900` background in BOTH selected and unselected branches is the same surface — it should map to the **same** token in both branches (`bg-soleur-bg-surface-1`). Only the border + text differ. Drift class: mapping selected to `surface-2` and unselected to `surface-1` would make the selected pill subtly raise off the row, which the original design did not do.

### `app/global-error.tsx` — Next.js 15 root-error rendering invariant

Next.js 15 docs (`next/app-router/error-handling`) confirm:

- `app/global-error.tsx` mounts when the root layout itself throws. It owns its own `<html>` and `<body>` because the root layout is unavailable.
- `app/globals.css` IS still loaded — the file is imported by `app/layout.tsx`'s static import chain that PostCSS/Tailwind compiles regardless of which route renders.
- The **inline `<NoFoucScript>` is NOT loaded** because it lives inside the failed root layout. `<html>` therefore has no `data-theme` attribute.
- Resolution: `:root:not([data-theme])` block in `globals.css` matches → `prefers-color-scheme` decides → dark-OS users see Forge, light-OS users see Radiance.

**Plan adjustment:** map `global-error.tsx` to `bg-soleur-bg-base text-soleur-text-primary` etc. — it WILL respond to OS preference correctly. Do NOT skip global-error in the migration. The previous draft's risk note ("if `globals.css` is unavailable") is mitigated.

### Vitest regression-test pattern (verified against repo precedent)

Repo precedent for grep-style tests:

- `apps/web-platform/test/theme-csp-regression.test.tsx` (PR #3271) — reads `app/layout.tsx`, asserts CSP/no-FOUC invariants via string match.
- `plugins/soleur/docs/scripts/screenshot-gate.mjs` — Eleventy critical-CSS screenshot gate (`cq-eleventy-critical-css-screenshot-gate`).

Implementation sketch for `apps/web-platform/test/light-theme-tokenization.test.tsx`:

```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..");

// Files that legitimately retain literal grays (status, leader identity, etc.).
// Each entry MUST cite a one-line reason in code comments.
const ALLOWLIST = new Set<string>([
  "components/chat/leader-colors.ts",       // Domain-leader identity palette (cross-theme).
  "components/chat/status-indicator.tsx",   // Status semantics (red/orange/green).
  // ...add as discovered during migration; reviewer reviews each entry.
]);

const SURFACE_GROUPS = [
  "app/(dashboard)/layout.tsx",
  "app/(dashboard)/dashboard/page.tsx",
  "app/global-error.tsx",
  "app/shared/[token]/page.tsx",
  "components/ui/markdown-renderer.tsx",
  "components/ui/sheet.tsx",
  "components/chat/chat-surface.tsx",
  "components/chat/message-bubble.tsx",
  "components/chat/interactive-prompt-card.tsx",
  "components/kb/file-tree.tsx",
  "components/settings/connected-services-content.tsx",
  "components/connect-repo/select-project-state.tsx",
  "components/dashboard/foundation-cards.tsx",
  "components/inbox/conversation-row.tsx",
  // Representative sampling — full list in the test.
];

const HARDCODED = /\b(?:bg|text|border)-(?:zinc|slate|neutral|stone|gray)-\d+|text-white\b/;
const TOKENIZED = /\bsoleur-(?:bg|text|border|accent)-/;

describe("light-theme tokenization", () => {
  for (const rel of SURFACE_GROUPS) {
    it(`${rel} contains no hardcoded gray classes`, () => {
      if (ALLOWLIST.has(rel)) return;
      const src = readFileSync(resolve(ROOT, rel), "utf8");
      expect(src).not.toMatch(HARDCODED);
    });
    it(`${rel} consumes Soleur tokens`, () => {
      const src = readFileSync(resolve(ROOT, rel), "utf8");
      expect(src).toMatch(TOKENIZED);
    });
  }
});
```

The test must run in `vitest` (not `vitest run --browser`), uses `node:fs`, and pins absolute paths via `path.resolve(__dirname, "..")` per the brittleness note.

### Visual QA cadence

PR #3271 captured 4 reference screenshots under `knowledge-base/product/design/theme-toggle/screenshots/` and the brand workshop UX-mockup-gate learning is the canonical reason this is required. This PR widens the same screenshot capture to 12 (6 groups × 2 themes) with the file-naming convention proposed in Phase 4.4.

If a Pencil MCP session is available at work-time, those screenshots can be taken inside Pencil for easier annotation; otherwise plain `--screenshot` Playwright captures suffice. Skipping screenshots would be a workflow regression.

## Implementation Phases

### Phase 1 — Migration Scaffolding

**Files to read (no edits):**

- `apps/web-platform/app/globals.css` — confirm token list, no schema changes needed.
- `apps/web-platform/components/settings/billing-section.tsx` — exemplar for surface-1 + accent CTA mapping.
- `apps/web-platform/components/chat/conversations-rail.tsx` — exemplar for navigation/list mapping.

**Deliverable:** A short mapping reference (kept in the PR description, not committed as a doc) that fixes the migration grammar:

| Tailwind class (deprecated in app surfaces) | Replace with |
|---|---|
| `bg-zinc-950`, `bg-neutral-950`, `bg-zinc-900` (page chrome) | `bg-soleur-bg-base` |
| `bg-zinc-900`, `bg-neutral-900`, `bg-zinc-800` (cards, modals, headers) | `bg-soleur-bg-surface-1` |
| `bg-zinc-800`, `bg-zinc-700` (elevated rows, hover, input, kbd) | `bg-soleur-bg-surface-2` |
| `bg-zinc-700/50`, `bg-zinc-800/60` opacity variants | `bg-soleur-bg-surface-2/60` (numeric opacity preserved) |
| `text-white`, `text-zinc-50`, `text-zinc-100`, `text-zinc-200` | `text-soleur-text-primary` |
| `text-zinc-300`, `text-zinc-400`, `text-slate-300`, `text-slate-400`, `text-neutral-400` | `text-soleur-text-secondary` |
| `text-zinc-500`, `text-zinc-600`, `text-neutral-500`, `text-stone-500` | `text-soleur-text-muted` |
| `border-zinc-800`, `border-zinc-700`, `border-neutral-800`, `border-slate-700` | `border-soleur-border-default` |
| `border-zinc-600`, `border-amber-500`-as-emphasis | `border-soleur-border-emphasized` (only for selected/focused emphasis) |
| `bg-amber-500` / `bg-yellow-500` (CTAs only) | `bg-soleur-accent-gold-fill` paired with `text-soleur-text-on-accent` |
| `text-amber-400`, `text-amber-500` (gold accent text/link) | `text-soleur-accent-gold-fg` (default), `hover:text-soleur-accent-gold-text` |

Status colors (`red-`, `orange-`, `green-`, `blue-`, `cyan-`, `pink-`, `violet-`, `emerald-`) remain literal — out of scope for this PR.

**Tasks:**

- [ ] 1.1 Re-read `globals.css` to confirm the token list (no schema additions in v1).
- [ ] 1.2 Confirm exemplar consistency (`billing-section.tsx` and `conversations-rail.tsx`) — note any drift from the mapping table above.
- [ ] 1.3 Run the audit grep one more time at start-of-work to confirm scope hasn't changed:
  ```bash
  rg -c '\b(bg|text|border)-(zinc|slate|neutral|stone|gray)-|text-white\b' apps/web-platform/{app,components}
  ```
  Record the file count as a baseline for the post-implementation check.

### Phase 2 — Surface-by-Surface Tokenization (parallel-ready)

Six surface groups. Each group is independent and can be migrated in any order. Within a group, files share visual context, so reviewing diffs together catches inconsistencies (a card uses `surface-1`, its hover row should use `surface-2`).

**Group A — Chat surface** (16 files; ~125 hardcoded color lines)

- [ ] `apps/web-platform/components/chat/chat-surface.tsx` (18 lines)
- [ ] `apps/web-platform/components/chat/interactive-prompt-card.tsx` (25 lines — heaviest in chat; many surface levels)
- [ ] `apps/web-platform/components/chat/message-bubble.tsx` (16 lines — verify `border-l-*` leader colors are NOT touched)
- [ ] `apps/web-platform/components/chat/chat-input.tsx` (10 lines)
- [ ] `apps/web-platform/components/chat/at-mention-dropdown.tsx` (9 lines)
- [ ] `apps/web-platform/components/chat/workflow-lifecycle-bar.tsx` (8 lines)
- [ ] `apps/web-platform/components/chat/subagent-group.tsx` (8 lines)
- [ ] `apps/web-platform/components/chat/notification-prompt.tsx` (8 lines)
- [ ] `apps/web-platform/components/chat/review-gate-card.tsx` (5 lines)
- [ ] `apps/web-platform/components/chat/pwa-install-banner.tsx` (5 lines)
- [ ] `apps/web-platform/components/chat/attachment-display.tsx` (5 lines)
- [ ] `apps/web-platform/components/chat/welcome-card.tsx` (4 lines)
- [ ] `apps/web-platform/components/chat/naming-nudge.tsx` (4 lines)
- [ ] `apps/web-platform/components/chat/kb-chat-content.tsx` (4 lines)
- [ ] `apps/web-platform/components/chat/tool-use-chip.tsx` (3 lines)
- [ ] `apps/web-platform/components/chat/routed-leaders-strip.tsx` (3 lines)
- [ ] **NOT touched (intentional):** `chat/leader-colors.ts` (domain identity palette), `chat/conversations-rail.tsx` (already tokenized), `chat/status-indicator.tsx` (status semantics), `chat/kb-chat-sidebar.tsx` (verify; if hardcoded, add to list).

**Group B — Knowledge-base browser** (17 files; ~74 hardcoded color lines)

- [ ] `apps/web-platform/components/kb/file-tree.tsx` (16)
- [ ] `apps/web-platform/components/kb/pdf-preview.tsx` (10)
- [ ] `apps/web-platform/components/kb/share-popover.tsx` (9)
- [ ] `apps/web-platform/components/kb/search-overlay.tsx` (8)
- [ ] `apps/web-platform/components/kb/kb-desktop-layout.tsx` (6)
- [ ] `apps/web-platform/components/kb/text-preview.tsx` (4)
- [ ] `apps/web-platform/components/kb/no-project-state.tsx` (4)
- [ ] `apps/web-platform/components/kb/file-preview.tsx` (4)
- [ ] `apps/web-platform/components/kb/empty-state.tsx` (4)
- [ ] `apps/web-platform/components/kb/download-preview.tsx` (4)
- [ ] `apps/web-platform/components/kb/workspace-not-ready.tsx` (3)
- [ ] `apps/web-platform/components/kb/selection-toolbar.tsx` (3)
- [ ] `apps/web-platform/components/kb/loading-skeleton.tsx` (3)
- [ ] `apps/web-platform/components/kb/kb-content-header.tsx` (3)
- [ ] `apps/web-platform/components/kb/desktop-placeholder.tsx` (3)
- [ ] `apps/web-platform/components/kb/kb-sidebar-shell.tsx` (2)
- [ ] `apps/web-platform/components/kb/kb-content-skeleton.tsx` (2)
- [ ] `apps/web-platform/components/kb/kb-breadcrumb.tsx` (2)
- [ ] `apps/web-platform/components/kb/unknown-error.tsx` (1)
- [ ] `apps/web-platform/components/kb/kb-mobile-layout.tsx` (1)
- [ ] `apps/web-platform/components/kb/kb-error-boundary.tsx` (1)
- [ ] `apps/web-platform/components/kb/kb-doc-shell.tsx` (verify count; appears in audit but not in top counts)
- [ ] `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` (3) — App Router page; also touch the layout sibling if it has hardcoded grays.

**Group C — Settings & account surfaces** (11 files; ~74 hardcoded color lines)

- [ ] `apps/web-platform/components/settings/connected-services-content.tsx` (15)
- [ ] `apps/web-platform/components/settings/settings-content.tsx` (13)
- [ ] `apps/web-platform/components/settings/team-settings.tsx` (8)
- [ ] `apps/web-platform/components/settings/settings-shell.tsx` (8)
- [ ] `apps/web-platform/components/settings/project-setup-card.tsx` (8)
- [ ] `apps/web-platform/components/settings/disconnect-repo-dialog.tsx` (7)
- [ ] `apps/web-platform/components/settings/delete-account-dialog.tsx` (6)
- [ ] **NOT touched:** `settings/billing-section.tsx`, `settings/api-usage-*.tsx`, `settings/cancel-retention-modal.tsx`, `settings/key-rotation-form.tsx` (already tokenized in PR #3271 — do not double-edit).

**Group D — Connect-repo / onboarding flow** (10 files; ~85 hardcoded color lines)

- [ ] `apps/web-platform/components/connect-repo/select-project-state.tsx` (16)
- [ ] `apps/web-platform/components/connect-repo/ready-state.tsx` (14)
- [ ] `apps/web-platform/components/connect-repo/create-project-state.tsx` (12)
- [ ] `apps/web-platform/components/connect-repo/github-redirect-state.tsx` (11)
- [ ] `apps/web-platform/components/connect-repo/choose-state.tsx` (10)
- [ ] `apps/web-platform/components/connect-repo/setting-up-state.tsx` (9)
- [ ] `apps/web-platform/components/connect-repo/github-resolve-state.tsx` (6)
- [ ] `apps/web-platform/components/connect-repo/failed-state.tsx` (6)
- [ ] `apps/web-platform/components/connect-repo/no-projects-state.tsx` (3)
- [ ] `apps/web-platform/components/connect-repo/interrupted-state.tsx` (2)
- [ ] `apps/web-platform/components/onboarding/naming-modal.tsx` (7)

**Group E — Dashboard, analytics, inbox, shared** (9 files; ~104 hardcoded color lines)

- [ ] `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (37 — heaviest single file in the audit)
- [ ] `apps/web-platform/components/analytics/analytics-dashboard.tsx` (28)
- [ ] `apps/web-platform/components/inbox/conversation-row.tsx` (14)
- [ ] `apps/web-platform/components/dashboard/foundation-cards.tsx` (4)
- [ ] `apps/web-platform/components/dashboard/foundation-section.tsx` (verify)
- [ ] `apps/web-platform/app/shared/[token]/page.tsx` (10) — public share page; visible to recipients without an account; light theme correctness matters most here.
- [ ] `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx` (6)
- [ ] `apps/web-platform/app/(dashboard)/layout.tsx` (5 — already partially tokenized, audit residual hardcoded classes; re-verify CTA buttons that still use `bg-orange-600 text-white` and `bg-red-600 text-white`)
- [ ] `apps/web-platform/components/concurrency/account-state-banner.tsx` (2)
- [ ] `apps/web-platform/components/shared/cta-banner.tsx` (3)

**Group F — UI primitives, error pages, auth helpers** (8 files; ~24 hardcoded color lines)

- [ ] `apps/web-platform/components/ui/markdown-renderer.tsx` (11) — **highest-leverage single file in this PR.** Prose colors render every chat message + KB doc preview. Use the Markdown-renderer color audit table in Research Insights as the canonical mapping. After migration: render an existing chat conversation containing all of `<h1>/<h2>/<h3>/<p>/<ul>/<table>/<pre>/<code>/<a>/<strong>/<blockquote>` and capture both-themes screenshots BEFORE moving on. Drift here is site-wide.
- [ ] `apps/web-platform/components/ui/sheet.tsx` (3) — modal/drawer overlay primitive.
- [ ] `apps/web-platform/components/ui/error-card.tsx` (3)
- [ ] `apps/web-platform/components/ui/outlined-button.tsx` (1)
- [ ] `apps/web-platform/components/ui/card.tsx` (1)
- [ ] `apps/web-platform/components/error-boundary-view.tsx` (3)
- [ ] `apps/web-platform/app/global-error.tsx` (3) — Next.js root error page. Verified in Research Insights: `globals.css` IS loaded; the no-FOUC inline script is NOT. `<html>` therefore has no `data-theme` and falls through to `:root:not([data-theme])` (OS-preference). Map to `bg-soleur-bg-base text-soleur-text-primary` and add an inline comment explaining the OS-follow behavior. Validate by force-throwing in the root layout and screenshotting in both Forge and Radiance OS modes.
- [ ] `apps/web-platform/components/leader-avatar.tsx` (1)
- [ ] `apps/web-platform/components/auth/oauth-buttons.tsx` (verify count) — auth pages already tokenized; if oauth buttons still ship raw classes, fold in.

### Phase 3 — Tests

PR #3271 added `theme-provider.test.tsx`, `theme-toggle.test.tsx`, `theme-csp-regression.test.tsx`, and `dynamic-theme-color.test.tsx`. The existing tests cover the toggle behavior + hydration but do not assert that surface components consume tokens.

**Test additions (new file):**

- [ ] `apps/web-platform/test/light-theme-tokenization.test.tsx` — a single-file regression harness that:
  1. Reads a representative file from each Group (A–F) via `fs.readFileSync` against absolute paths.
  2. Asserts each file contains zero matches of the deprecated grep:
     ```ts
     /\b(bg|text|border)-(zinc|slate|neutral|stone|gray)-\d+|text-white\b/
     ```
     except for an explicit allowlist (status-colored helpers, leader-colors.ts, chat/status-indicator.tsx, components that intentionally retain literal grays for status semantics).
  3. Asserts each file contains at least one `soleur-(bg|text|border|accent)-` token.

  Why a regression-grep test: TypeScript and Tailwind v4 don't catch hardcoded color drift; the only signal today is "looks wrong in Light mode," which requires manual visual QA. A grep test pins the pattern as a build-time invariant.

- [ ] No new tests are required for the Group A–F files individually — the regression-grep test covers them collectively. Existing component tests should not need updates because tokenized classes are still valid Tailwind utilities; rendered HTML changes only the className strings.

**Test invariants:**

- The test file must import absolute paths via `path.resolve(__dirname, '../components/...')` — relative `../../` traversal is brittle.
- The allowlist constant (status-color exempt files) lives at the top of the test file with an inline comment per entry explaining why.

### Phase 4 — Visual QA

Visual QA runs after the diff is staged but before merge. Two passes per group, one per theme.

- [ ] 4.1 `bun run dev` (or whichever script `apps/web-platform/package.json` exposes), open `http://localhost:3000`, log in.
- [ ] 4.2 For each Group A–F, navigate to a representative page in **Dark theme**, screenshot, then toggle to **Light theme**, screenshot. Compare:
  - Surface colors switch (no leftover dark cards on light backgrounds, no leftover light cards on dark backgrounds).
  - Text contrast holds (no `text-soleur-text-primary` rendering as off-white-on-ivory or near-black-on-near-black).
  - Borders are visible in both themes (no `border-soleur-border-default` becoming invisible).
  - Hover states (`hover:bg-soleur-bg-surface-2`) are visible.
- [ ] 4.3 Save screenshots under `knowledge-base/product/design/light-theme-completion/screenshots/{group-letter}-{theme}.png`.
- [ ] 4.4 If any contrast or hover issue surfaces, fix inline before merge.

**Out-of-band visual checks:**

- [ ] 4.5 The `app/global-error.tsx` route is hard to trigger naturally; verify by temporarily throwing in `app/layout.tsx`, screenshotting, then reverting. If global-error renders without `globals.css`, document why hardcoded colors are correct and add a Sharp Edges note.
- [ ] 4.6 The `app/shared/[token]/page.tsx` route is logged-out / shareable. Capture screenshots in both themes (default unauthenticated browser, no theme cookie set → renders System theme).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Audit grep `rg -c '\b(bg|text|border)-(zinc|slate|neutral|stone|gray)-|text-white\b' apps/web-platform/{app,components}` returns ≤ N files where N is the count of the documented allowlist (status-color carriers + leader-colors.ts + components with intentional literal grays). Allowlist enumerated in the new test file.
- [ ] Existing 16 already-tokenized files (PR #3271 scope) appear in `git diff main...HEAD --name-only` ONLY if they had residual hardcoded classes the audit caught — never as a refactor of correct code.
- [ ] `bun test apps/web-platform/test/` passes including the new `light-theme-tokenization.test.tsx`.
- [ ] `tsc --noEmit` clean.
- [ ] Visual QA screenshots committed under `knowledge-base/product/design/light-theme-completion/screenshots/` for all 6 groups × 2 themes (12 screenshots minimum).
- [ ] PR body uses `Closes #3232` only if the original issue specifically called for full-app tokenization; otherwise `Ref #3232` and link the new follow-up issue.
- [ ] No new `dark:*` Tailwind prefixes introduced (per PR #3271 architecture; `@custom-variant dark` does the work via tokens).

### Post-merge (operator)

- [ ] None. This is a CSS-class change with no migrations, deploys, or external service mutations.

## Risks

- **Token namespace gaps for status colors.** The current token system has no `--soleur-status-*` (red/orange/green/blue) variables. Components using semantic colors (`bg-red-600`, `text-orange-400`) keep the literal Tailwind classes. In Light mode these colors are slightly under-saturated against the ivory background. If visual QA flags low contrast, file a follow-up to add `--soleur-status-{danger,warning,success,info}` tokens — do NOT widen this PR.
- **Markdown renderer prose color drift.** `components/ui/markdown-renderer.tsx` controls the rendered color of every chat message and every KB doc. A sloppy mapping (e.g., body text → `text-soleur-text-muted` instead of `-secondary`) will fade content site-wide. Validate against an existing chat conversation with a long markdown reply.
- **Sheet / modal overlay opacity.** `components/ui/sheet.tsx` uses `bg-zinc-900/80` for the backdrop. The token system has no opacity-paired variant; mapping to `bg-soleur-bg-base/80` works but rendered alpha differs between themes (light alpha tint vs dark alpha tint). Visual QA must confirm modals still feel modal in Light mode (backdrop visibly recedes).
- **`global-error.tsx` follows OS preference, not user choice.** Verified via Next.js 15 docs: `globals.css` IS loaded on this route, but the no-FOUC inline script is NOT (it lives in the failed root layout). The `<html>` therefore has no `data-theme`, and `:root:not([data-theme])` resolves via `prefers-color-scheme`. Result: a Light-mode user with a dark OS sees the error page render in Forge — technically a divergence from the user's chosen theme. Acceptable for an error path that already represents a degraded state. Document inline as a comment.
- **Reviewer false-positive on test allowlist.** The regression-grep test allowlist will look like "we're suppressing the rule for some files." Document the per-file rationale in test comments so reviewers don't suspect drift suppression.
- **Selected-pill mapping inconsistency.** Two files (`dashboard/page.tsx`, `chat/chat-input.tsx`) use the `bg-neutral-900` shared-background pill pattern. If reviewer A maps both branches to `surface-1` and reviewer B maps the selected branch to `surface-2`, the pill rises subtly out of the row. Pin to `surface-1` for both branches, only border + text change.
- **Leader-colors consumer drift class.** `chat/leader-colors.ts` is out of scope (domain-identity palette), but its consumers (`message-bubble.tsx`, `tool-use-chip.tsx`, `routed-leaders-strip.tsx`, `subagent-group.tsx`, `leader-avatar.tsx`) ARE in scope. A grep-and-replace using a too-broad pattern (e.g., regex `border-l-(pink|blue|emerald|violet|orange|amber|slate|cyan|neutral)-`) would tokenize the leader pink/blue/etc. literal classes — defeating the cross-theme identity guarantee. Use surgical edits, not regex sweep.
- **Markdown-renderer `<pre>` darker-than-card invariant.** PR #3271 + Forge convention sets code blocks to `bg-neutral-950` — visibly darker than the surrounding `<div>` card. On Radiance, `bg-soleur-bg-base` (ivory `#fbf7ee`) is lighter than `bg-soleur-bg-surface-1` (`#f4eedf`), inverting the recess effect — code blocks "stick out" instead of "recess in." Visual QA must confirm this reads as intentional; if not, `<pre>` may need its own `--soleur-bg-code` token. Track as deferred follow-up.

## Sharp Edges

- The single existing `dark:*`-prefix consumer (`api-usage-section.tsx`) is intentional per PR #3271's architecture; do not retro-tokenize it in this PR.
- `chat/leader-colors.ts` exports literal `border-l-pink-500` etc. — these are domain-identity colors, not theme colors. Adding the file to this PR's diff is a workflow violation (out of scope, brand-recognizable across themes).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Section is filled (threshold: none) per the impact analysis above.
- When migrating opacity-modifier classes (`bg-zinc-800/60`), preserve the `/60` suffix on the new token (`bg-soleur-bg-surface-2/60`). Tailwind v4 handles opacity modifiers on CSS-variable-backed colors natively.
- The audit grep deliberately uses `\b(bg|text|border)-` rather than just `bg-`; subagents that "simplify" the regex will miss `text-zinc-400` (the most common offender, ~18 occurrences in `interactive-prompt-card.tsx` alone).
- Do NOT migrate marketing pages or the docs site (`plugins/soleur/docs/**`). Those have their own theming context and are out of scope for the web-platform light-theme fix.
- `app/shared/[token]/page.tsx` is the public share-link surface; its theme defaults to System. Confirm no logged-in-only assumptions (e.g., reading a theme cookie that requires auth) — if found, document expected unauth behavior in code comments.
- Per AGENTS.md `cq-write-failing-tests-before` (TDD), `light-theme-tokenization.test.tsx` MUST land in a commit BEFORE the surface migrations land — write the test first against the current state (which will fail on every Group A–F file), then migrate group-by-group, watching the failure list shrink.
- Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`, every Phase 2 file path was verified against `git ls-files apps/web-platform/components | grep` at plan time. `dashboard/foundation-section.tsx` and `auth/oauth-buttons.tsx` are listed as "verify count" and may have zero hardcoded grays — verify and remove from the diff if so, do not no-op edit.
- Tailwind v4 opacity modifiers (`/60`) on CSS-variable-backed tokens use `color-mix(in oklch, ...)` under the hood. Browsers without `color-mix` support (Safari < 16.2) fall back to fully-opaque. Soleur's browser support floor (Next 15 + React 19 implicit baseline) excludes this concern, but a dependency bump that adds an older-browser target needs a rebaseline.
- The migration is a 1:1 className rename, not a `light:`-prefix add. Reviewers expecting `dark:bg-zinc-950 light:bg-amber-50`-style pairs are wrong about the architecture; point them at `globals.css` and PR #3271's diff.
- Do NOT introduce new `dark:*` Tailwind prefixes during the migration. PR #3271 chose tokens + `@custom-variant dark`; new `dark:*` consumers contradict the architecture. The single existing consumer (`api-usage-section.tsx`) is intentional and OUT OF SCOPE.

## Domain Review

**Domains relevant:** Product/UX (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (auto-accepted in pipeline)
**Skipped specialists:** ux-design-lead (auto-accepted in pipeline; visual QA in Phase 4 covers screenshot validation)
**Pencil available:** N/A

#### Findings

This plan modifies **existing** UI surfaces (no new pages, no new modals, no new flows). It tokenizes color classes against the design system PR #3271 already validated (with ux-design-lead and screenshot iterations under `knowledge-base/product/design/theme-toggle/`). The visual contract is the Radiance palette already chosen and shipped. Phase 4 visual QA validates that the migration preserves brand-aligned color behavior — no new design surface to review.

Per the plan skill's pipeline-mode rule for ADVISORY tier, the gate auto-accepts and proceeds with documented visual-QA gating in Phase 4 instead of a fresh ux-design-lead Pencil session.

## Open Code-Review Overlap

None — this plan touches presentational `className` strings only. No open `code-review`-labeled issues match the planned file paths (would need to re-run `gh issue list --label code-review` if the audit window slips, but as of plan time there are no overlaps with chat/, kb/, settings/, connect-repo/, dashboard/, ui/ surface files).

## Test Scenarios

1. **Tokenization grep regression**: A file under `apps/web-platform/components/chat/` containing `bg-zinc-900` causes `light-theme-tokenization.test.tsx` to fail. (Add a temporary file in the test, assert the grep matches, then remove.)
2. **Theme toggle integration**: Existing `theme-provider.test.tsx` + `theme-toggle.test.tsx` continue to pass — the migration changes class names but not the toggle's stateful logic.
3. **Cold-render Light mode**: With `<html data-theme="light">` set by the no-FOUC script before React hydrates, every Group A–F surface renders ivory-base + Radiance accents (manual, captured as screenshots in Phase 4).
4. **Cold-render System mode → OS dark**: Default user (no theme cookie, OS in dark) renders Forge palette across all surfaces (no leftover light surfaces).
5. **Cold-render System mode → OS light**: Default user (no theme cookie, OS in light) renders Radiance palette across all surfaces.
6. **Live theme switch**: Toggle Forge → Radiance → System on the dashboard; every Group A–F surface visible at the time of toggle re-renders with the new palette without reload.

## Commit Strategy

Recommended: 8 commits on the feature branch.

1. `test: add light-theme tokenization regression harness` — `apps/web-platform/test/light-theme-tokenization.test.tsx` only. Test fails on current state (every Group A–F file). RED commit.
2. `fix(light-theme): tokenize chat surface` — Group A (16 files).
3. `fix(light-theme): tokenize KB browser surface` — Group B (~22 files).
4. `fix(light-theme): tokenize settings + onboarding surfaces` — Group C (7 files).
5. `fix(light-theme): tokenize connect-repo flow` — Group D (11 files).
6. `fix(light-theme): tokenize dashboard, analytics, inbox, share` — Group E (~9 files).
7. `fix(light-theme): tokenize UI primitives + global-error` — Group F (~8 files, includes the markdown-renderer dedicated review).
8. `docs: light-theme completion screenshots` — `knowledge-base/product/design/light-theme-completion/screenshots/*.png` (12 PNGs).

After commit 7, the regression test goes GREEN. Each Group commit can be independently reviewed and reverted; bisect retains usefulness.

## Files to Edit

See Phase 2 enumeration. Approximate count: 64 files modified, 1 test file created. Net diff is largely class-rename churn.

## Files to Create

- `apps/web-platform/test/light-theme-tokenization.test.tsx` — regression-grep harness with documented allowlist.
- `knowledge-base/product/design/light-theme-completion/screenshots/{a-chat,b-kb,c-settings,d-connect,e-dashboard,f-ui}-{forge,radiance}.png` — 12 screenshots captured during Phase 4 visual QA.

## Out of Scope (deferred)

- Status-color tokenization (`--soleur-status-{danger,warning,success,info}`). Track via follow-up issue if Phase 4 visual QA flags contrast.
- `chat/leader-colors.ts` palette refactor. Domain-identity colors are deliberately theme-stable; no action.
- Marketing site / Eleventy docs theming.
- Re-tokenizing the 16 files PR #3271 already shipped.
- Adding `dark:*` prefix-based variants. PR #3271 chose `@custom-variant dark` + tokens; do not contradict.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-06-fix-light-theme-incomplete-styling-plan.md. Branch: feat-one-shot-fix-light-theme-incomplete-styling. Worktree: .worktrees/feat-one-shot-fix-light-theme-incomplete-styling/. Issue: TBD (follow-up to #3232/#3271). Plan reviewed, implementation next.
```

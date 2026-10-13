# Brainstorm: Linear-style Keyboard Shortcuts for the Soleur Web App

**Date:** 2026-06-22
**Branch:** feat-web-app-shortcuts
**PR:** #5633 (draft)
**Lane:** cross-domain
**Status:** Brainstorm complete — ready for planning

## What We're Building

A keyboard-first **command layer** for the Soleur web app (`apps/web-platform`), inspired by how Linear manages its shortcuts. v1 scope is deliberately narrowed to the two highest-value, lowest-risk pieces of Linear's system:

1. **`⌘K` / `Ctrl+K` command palette** — a single, fuzzy-searchable surface to navigate anywhere and trigger the product's core verbs.
2. **`?` help overlay** — a searchable cheat-sheet of available shortcuts for discoverability.

Both render from **one central command registry** (single source of truth). The existing scattered `⌘B` sidebar-toggle binding migrates into the registry. The registry is *structured* to later expose its actions to agents ("anything a user can do, an agent can do"), but agent wiring is **out of scope for v1**.

### Palette contents (v1)

The palette must launch **dense** — a sparse palette reads as unfinished to the technical beachhead audience. v1 includes all four command categories:

- **Navigation** — jump to any sidebar destination: Dashboard, Inbox, Knowledge Base, Routines, Chat, Settings, Team, Billing, Audit (Analytics/Audit gated by admin as today).
- **KB doc search** — fuzzy-search and jump to any Knowledge Base document (makes the compounding KB moat instantly reachable).
- **Ask an agent / summon chat** — *hero action*; open/summon the agent chat from anywhere. The core verb of the product and what makes the palette feel agent-native rather than a Linear clone.
- **Trigger a workflow/routine** — fire or jump to an Inngest routine from the palette.

## Why This Approach

- **CPO guidance:** Soleur has **no issue-tracker object model**, so copying Linear's single-key issue verbs (`c`=create, `s`=status) would be cargo-culting. The transferable value is the **navigation/command layer** over a product with sidebar nav + KB + chat + dashboards. Chat is a primary surface, so **unmodified single keys collide with typing** — defer them.
- **CTO guidance:** A **central registry** is the only shape that keeps palette, help overlay, (and future agent surface) in sync. `cmdk` (Linear/Vercel's library) handles the palette UI; v1 needs only a small global listener for `⌘K` and `?`. `tinykeys` (for sequences) is deferred with the sequences themselves.
- **CLO guidance:** WCAG 2.1.4 *Character Key Shortcuts* (Level A) is the one compliance item — and choosing **no single-character shortcuts in v1 sidesteps it entirely**. The `?` overlay satisfies discoverability. IP risk of mimicking Linear's *scheme* is negligible (key bindings are functional, not copyrightable); do not copy Linear's help-text wording/branding.
- **YAGNI:** Approach A is barely more work than a bare palette but avoids duplicated command lists and earns the agent-native seam without over-building (Approach C).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| v1 shortcut scope | `⌘K` palette + `?` overlay only | Highest value, dodges chat collisions + WCAG 2.1.4 |
| Single-key verbs (Linear `c`/`s`/etc.) | **Deferred** | No issue object model; collide with chat typing |
| Nav sequences (`G` then `I`) | **Deferred** | Adds `tinykeys` + muscle-memory load; revisit after palette lands |
| Architecture | Central command registry → renders palette + overlay | Single source of truth; no list drift; agent-native-ready |
| Palette library | `cmdk` | Battle-tested (Linear/Vercel/Raycast), ~8KB, a11y built-in |
| Existing `⌘B` sidebar toggle | Migrate into registry | Avoid double-binds / collision; one listener |
| Agent action surface | **Deferred** (registry structured for it) | CPO: defer; YAGNI for a palette v1 |
| Hero action | "Ask an agent / summon chat" | Core product verb; makes palette agent-native |
| Visual design | Wireframe `⌘K` palette + `?` overlay (Phase 3.55) | UI feature — `.pen` wireframe required before build |

## Open Questions

1. **Summon binding:** `⌘K` opens the palette; should "Ask an agent" also get a dedicated direct binding (e.g. `⌘J`), or live only as a palette entry in v1? (Planning detail — decide at spec/plan time.)
2. **Palette ↔ existing modals:** the app uses custom portal modals (no Radix). Does the `cmdk` palette reuse the `Sheet` primitive's portal/escape handling, or stand alone? (Plan-time.)
3. **Recent-commands persistence:** localStorage-backed "recent commands float to top" — v1 or v1.1?
4. **Feature flag:** gate the palette behind a Flagsmith flag (e.g. `command-palette`) for a dev-cohort rollout? (Recommended; confirm at plan time.)

## User-Brand Impact

- **Artifact:** the `⌘K` command palette + `?` help overlay command layer in `apps/web-platform`.
- **Vector:** a shortcut/command that silently fails or mis-routes (e.g. "Trigger workflow" firing the wrong routine, or the palette swallowing keystrokes inside chat) — eroding trust in a surface the operator drives constantly.
- **Threshold:** `single-user incident`.

Tagged **user-brand-critical** (auto, per #5175). The derived plan inherits `Brand-survival threshold: single-user incident` unless overridden.

## Domain Assessments

**Assessed:** Product, Engineering, Legal

### Product

**Summary:** Partial fit — the navigation/command layer transfers, the issue-tracker single-key verbs do not. Lead with a dense `⌘K` palette (nav + KB docs + chat + "Ask an agent") and `?` overlay; defer single-key verbs (chat-typing collisions). The agent-summon action is the real differentiator that makes the palette feel native, not imitative. Recommends spec-flow-analyzer for the command inventory and ux-design-lead for the overlay before build.

### Engineering

**Summary:** Build a **central shortcut registry** as the single source of truth (`id`/`keys`/`label`/`group`/`when`/`run()`); `cmdk` renders the palette, the `?` overlay renders from the same table, and the existing `⌘B`/`Escape`/rail-arrow bindings migrate in to avoid double-fires. Client-only (SSR/hydration safe), respect input-focus guards (`chat-input`, `at-mention-dropdown` already own keys). The registry should double as the agent-invokable action surface — do not build a keystroke layer that bypasses the action layer. v1 = registry + palette + overlay + ~8–12 nav actions; defer rebinding, scoped maps, mobile.

### Legal

**Summary:** One real item — WCAG 2.1.4 *Character Key Shortcuts* (Level A): single-character shortcuts must be disable-able/remappable/focus-only. v1's no-single-key choice avoids it; if single keys are added later, the disable/remap requirement is a hard acceptance criterion. IP risk of mimicking Linear's binding scheme is negligible; avoid copying Linear's proprietary help text/branding. No other material legal exposure.

## Existing Infrastructure (repo research)

- **Stack:** Next.js 15.5 (App Router) / React 19 / TS 5.7 / Tailwind 4. State via React Context + custom hooks (Zustand barely used). Custom portal modals (`Sheet`, `TypedConfirmModal`) — **no Radix, no `cmdk`, no hotkey library installed.**
- **Existing scattered keydown handlers** (the collision surface to reconcile):
  - `app/(dashboard)/layout.tsx` — `⌘B`/`Ctrl+B` sidebar toggle; `Escape` closes mobile drawer. *(A code comment here already anticipates a "command palette" dispatcher.)*
  - `components/kb/selection-toolbar.tsx` — `⌘⇧L` quote selected KB text to chat.
  - `components/chat/chat-input.tsx`, `components/chat/at-mention-dropdown.tsx` — `Enter`/arrow keys (focus-conflict surfaces the registry guard must respect).
- **Nav destinations** (`NAV_ITEMS`): Dashboard, Inbox, Knowledge Base, Routines, Chat, Settings, Team, Billing, Audit, (Analytics — admin only).
- **Entry point for the global listener + provider:** `app/(dashboard)/layout.tsx`.

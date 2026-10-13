---
name: feat-web-app-shortcuts
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-22-keyboard-shortcuts-brainstorm.md
branch: feat-web-app-shortcuts
issue: 5635
pr: 5633
---

# Feature: Linear-style Command Palette (⌘K) + Help Overlay (?) for the Web App

## Problem Statement

The Soleur web app (`apps/web-platform`) has no keyboard-first command layer. Navigation
and core actions require mouse-driven sidebar clicks, and keyboard handling is scattered
across ad-hoc `useEffect(keydown)` listeners (`⌘B` sidebar toggle, `Escape` drawer,
`⌘⇧L` quote-to-chat) with no shared registry, no discoverability surface, and no collision
detection. A code comment in `app/(dashboard)/layout.tsx` already anticipates a "command
palette" dispatcher that was never built. For the technical beachhead audience (Claude Code
users who live in `⌘K` muscle memory), the absence of a palette reads as unfinished.

## Goals

- G1: Ship a `⌘K`/`Ctrl+K` command palette that lets the operator navigate anywhere and
  trigger the product's core verbs without the mouse.
- G2: Ship a `?` help overlay (searchable shortcut cheat-sheet) for discoverability.
- G3: Back both surfaces with a single central command registry (no duplicated command lists).
- G4: Launch the palette **dense** — Navigation + KB doc search + "Ask an agent" + Trigger
  workflow — so it never feels sparse/unfinished.
- G5: Migrate the existing `⌘B` sidebar toggle into the registry without double-firing.
- G6: Structure the registry so it can later expose actions to agents (agent-native seam),
  without wiring agents in v1.

## Non-Goals

- NG1: Single-key verbs (Linear `c`=create, `s`=status). No issue object model; collide with
  chat typing. Deferred — follow-up issue.
- NG2: Two-key navigation sequences (`G` then `I`). Deferred — follow-up issue.
- NG3: Wiring the registry to agents / MCP tools (Approach C). Deferred — follow-up issue.
- NG4: User-customizable rebinding, per-route scoped keymaps, mobile keyboard support.
- NG5: Replacing the existing custom modal primitives with Radix.

## Functional Requirements

### FR1: Command palette open/close

`⌘K` (macOS) / `Ctrl+K` (Win/Linux) opens the palette from any dashboard route; `Esc`
closes it. The trigger is suppressed while focus is in an input/textarea/contenteditable
(must not hijack browser/OS defaults or interfere with chat typing). Links to wireframe
`01-command-palette-cmdk.png`.

### FR2: Dense palette contents

Palette shows results grouped by category, in order: **Navigation** (Dashboard, Inbox,
Knowledge Base, Routines, Chat, Settings, Team, Billing, Audit — admin-gated items respect
existing visibility), **Ask an agent** (hero row — visually emphasized; summons/open chat),
**Knowledge Base** (fuzzy doc search), **Workflows** (trigger an Inngest routine). Fuzzy
search filters across all groups. Footer shows `↑↓ navigate · ↵ select · esc close`.

### FR3: Misfire-resistant workflow rows

"Trigger workflow" rows display disambiguating context (scope + last-run) and an explicit
named action ("Run routine"), per the brand-critical wireframe, so the operator never fires
the wrong routine.

### FR4: Help overlay

`?` opens a searchable help overlay listing available shortcuts grouped by category
(General: `⌘K`, `⌘B`, `?`, `Esc`; Navigation preview). `?` is suppressed while typing.
Links to wireframe `02-help-overlay-shortcuts.png`.

### FR5: Migrate existing ⌘B

The existing `⌘B`/`Ctrl+B` sidebar-toggle binding is re-expressed as a registry entry and
served by the single global listener — no duplicate handler, no double-fire.

## Technical Requirements

### TR1: Central command registry

One registry module is the single source of truth: each command is `{ id, label, group,
keys?, when?(ctx), run() }`. The palette (`cmdk`) and the `?` overlay both render from it.
Registry shape must permit a future agent-invokable surface (same `id` + `run()`), but v1
does not wire agents.

### TR2: Single global keyboard listener

One client-only `keydown` listener (mounted in `app/(dashboard)/layout.tsx` or a provider
beneath it) dispatches against the registry. Must guard on
`input`/`textarea`/`contenteditable` focus and respect components that own keys
(`chat-input.tsx`, `at-mention-dropdown.tsx`).

### TR3: Library + bundle

Use `cmdk` for the palette UI (a11y + fuzzy search built in). Reuse the existing portal/
`Sheet` escape-handling patterns where practical (no Radix). Keep the registry client-only;
never read `navigator.platform` during render (avoid SSR/hydration mismatch on the ⌘/Ctrl
glyph).

### TR4: WCAG 2.1.4 (Character Key Shortcuts)

v1 uses only modifier-based (`⌘K`) and `?` shortcuts — no single-character shortcuts — so
SC 2.1.4 (Level A) is satisfied by construction. Any future single-key verb MUST ship with a
disable/remap path as a hard acceptance criterion.

### TR5: Feature flag (recommended)

Gate the palette behind a Flagsmith runtime flag (e.g. `command-palette`) for a dev-cohort
rollout, consistent with existing `useFeatureFlag()` usage. Confirm at plan time.

## Open Questions (carry to plan)

- OQ1: Dedicated direct binding for "Ask an agent" (e.g. `⌘J`) vs. palette-entry only.
- OQ2: Recent-commands localStorage persistence in v1 or v1.1.
- OQ3: Palette portal — reuse `Sheet` primitive or standalone.

## Domain Review (carry-forward)

- **Product:** Lead with palette + overlay; the agent-summon hero action is the differentiator
  vs. an issue-tracker clone. Defer single-key verbs.
- **Engineering:** Central registry as single source of truth; migrate scattered bindings;
  client-only; the registry should double as the future agent action surface.
- **Legal:** WCAG 2.1.4 is the one compliance item — avoided in v1 by no-single-key choice;
  IP risk negligible (don't copy Linear help-text/branding).

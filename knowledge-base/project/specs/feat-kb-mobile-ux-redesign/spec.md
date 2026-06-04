---
feature: kb-mobile-ux-redesign
title: KB Workspace Chrome / Nav Redesign (D4 borderless polish + workspace logo)
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
branch: feat-kb-mobile-ux-redesign
pr: 4911
brainstorm: knowledge-base/project/brainstorms/2026-06-04-kb-chrome-nav-redesign-brainstorm.md
wireframes: knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen
---

# Spec: KB Workspace Chrome / Nav Redesign

## Problem Statement

The workspace chrome wrapping the Knowledge Base screen (mobile + desktop) reads as amateurish:
two competing back affordances (top chevron → file tree; "Back to menu" → /dashboard), a heavy
bordered **non-interactive** workspace card dominating the top (solo users can't even switch), a
page title buried 5th in the stack, borders/dividers used everywhere for grouping, and a cheap gold
square swatch standing in for workspace identity. Net effect: low trust, weak hierarchy, wasted
real estate.

## Goals

- G1: Replace the chrome with the styled **D4 "borderless elevation polish"** system (mobile + desktop), grouping via elevated surfaces not borders, with a prominent page title.
- G2: Replace the gold swatch with a **workspace logo** (monogram fallback now; upload later), using the **hybrid display rule**.
- G3: Reduce to **one back affordance per state** and **remove the global "Soleur" wordmark**.
- G4: Preserve all workspace-switch correctness (single-mount, confirm-then-switch, hard nav) — zero cross-tenant regression.
- G5: Build the chrome as a reusable primitive, adopted in KB first.

## Non-Goals

- NG1: Workspace **logo upload** capability (settings UI + storage + `logo_url` column + validation) — deferred follow-on slice.
- NG2: Rolling the reusable header to Chat/Settings/Dashboard in this PR (KB-first; generalize later).
- NG3: Changing the workspace switch grain or navigation model (no new ADR).

## Functional Requirements

- FR1: KB landing (with content) renders the D4 styled chrome: single back chevron, borderless elevated workspace identity row (logo + name + slug), bold "Knowledge Base" title, search field, borderless recent-docs list. → `screenshots/20-final-m1-kb-landing-content.png`
- FR2: KB empty state renders the same identity + title + a single gold "Open a Chat" primary action. → `screenshots/21-final-m2-kb-empty-gold-cta.png`
- FR3: Multi-org switch is a bottom-sheet (mobile) showing logo/monogram per row, active checkmarked, "you will switch context" confirm copy. → `screenshots/22-final-m3-switch-sheet-logo-rows.png`
- FR4: Desktop expanded sidebar shows logo + name switcher (no wordmark), de-boxed nav, gold only for active state; collapsed icon-rail shows logo-only identity. → `screenshots/23-final-desktop-expanded-sidebar.png`, `24-final-desktop-collapsed-rail.png`
- FR5: Workspace identity uses the **hybrid rule** — logo-only when a custom logo is set; logo + name for the monogram fallback; the selector always shows names. → `screenshots/18-logo-hybrid-rule-demo.png`
- FR6: Monogram fallback = rounded-square tile (surface-2 #1c1c1c, uppercase initial, weight 700) — explicitly NOT a gold square.
- FR7: The global "Soleur" wordmark (`app/(dashboard)/layout.tsx:283`) is removed.

## Technical Requirements

- TR1: The workspace switcher stays **mounted once** (ADR-047). New chrome composes around it / takes it as a slot; must pass `test/nav-single-mount.test.ts`.
- TR2: Preserve the confirm-then-switch flow verbatim: `set_current_workspace_id` RPC (migration 079, ADR-044) → `refreshSession()` JWT re-mint → **hard `window.location.assign("/dashboard")`** (no `router.push`).
- TR3: Back navigation = a shared **back slot** (href + aria-label props); KB supplies "back to file tree", section chrome supplies "back to menu". Don't collapse the destinations.
- TR4: Tokens only (`bg-soleur-*`, `text-soleur-*`, `@theme`); gold #c9a962 reserved for active-workspace identity + single primary action. No raw hex.
- TR5: Respect top safe-area inset on mobile; sidebar w-64 expanded / w-14 collapsed; band placement via CSS (`hidden md:block`) preserving first-frame paint; `pathname` passed in (no `usePathname` in the band).
- TR6: Keep / update `nav-chevron-alignment.test.tsx` and `e2e/nav-states-shell.e2e.ts`.

## Redline notes

See the UX lead's redlines in the brainstorm + `.pen` (token-per-element, spacing, monogram spec, safe-area). Active nav: gold @ ~9% alpha bg, cornerRadius 8. Identity tile: 34×34 mobile / 30×30 desktop / 32×32 collapsed.

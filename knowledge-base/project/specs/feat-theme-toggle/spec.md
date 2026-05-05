---
title: Theme toggle (light / dark / system)
status: draft
related_issue: 3232
related_pr: 3271
brainstorm: knowledge-base/project/brainstorms/2026-05-05-theme-toggle-brainstorm.md
user_brand_critical: true
brand_survival_threshold: single-user incident
---

# Theme Toggle — Spec

## Problem Statement

`app.soleur.ai` is currently dark-only by construction (`apps/web-platform/app/layout.tsx` hardcodes `bg-neutral-950 text-neutral-100`, `viewport.themeColor: "#0a0a0a"`). The Solar Radiance light palette landed in #3233 and is now production-approved, but no toggle exists for users to switch into it. ~115 TSX files use hardcoded dark utility classes; ~65 of those need tokenization to support a working light mode.

## Goals

- G1. Provide a visible control on the main app page that switches between **Forge (dark)**, **Radiance (light)**, and **System**.
- G2. Render the chosen theme on first paint with no FOUC.
- G3. Persist the user's choice across sessions.
- G4. Update the existing CSP-nonce-protected `<head>` without breaking the nonce policy.
- G5. Keep persistence per-user with zero cross-tenant leak surface.

## Non-Goals

- Custom user-defined palettes.
- Per-route theme overrides.
- Animated theme transitions beyond the default CSS variable swap.
- Theme toggle on the Eleventy marketing/docs site.

## Functional Requirements

- **FR1.** Toggle UI is reachable from the dashboard's main page (exact placement: header right, decided at design time).
- **FR2.** Three options: Forge / Radiance / System. Selecting System follows `prefers-color-scheme` and reacts to OS-level changes live.
- **FR3.** Selection persists across reloads and across browser tabs of the same origin (storage event listener).
- **FR4.** First paint matches the persisted choice — no flash from default → user choice.
- **FR5.** `viewport.themeColor` updates dynamically to match the active theme so mobile browser chrome matches.

## Technical Requirements

- **TR1. Tokenization.** Replace hardcoded `bg-neutral-950` / `text-neutral-100` and similar in component files with semantic CSS variables backed by both palettes. Sequencing (single PR vs phased) decided at plan time.
- **TR2. ThemeProvider.** Add a provider (custom or `next-themes` if compatible with current Next.js / CSP setup) that exposes `{theme, resolvedTheme, setTheme}` and persists to localStorage by default.
- **TR3. No-FOUC inline script.** A `<script>` in `<head>` reads the persisted choice and sets `<html data-theme>` before paint. Script MUST consume the existing CSP nonce from `apps/web-platform/app/layout.tsx`.
- **TR4. Persistence.** Default to **localStorage** (zero cross-tenant surface). DB-column persistence is out of scope unless cross-device sync is an explicit requirement at plan time, in which case `data-integrity-guardian` + `security-sentinel` review is mandatory before merge.
- **TR5. Dynamic `themeColor`.** Replace static `viewport.themeColor` with an effect that swaps a `<meta name="theme-color">` tag based on resolved theme.
- **TR6. CSP regression test.** Plan must include a CSP test verifying the no-FOUC inline script does not break the nonce policy on `/`, `/auth/*`, and any payment surface.

## User-Brand Impact

**Threshold: `single-user incident`** (carried forward from brainstorm).

- **Cross-tenant leak vector.** Persistence layer choice — localStorage is preferred precisely because it has no cross-tenant surface. Any DB-backed approach must be fronted by `security-sentinel` + `data-integrity-guardian` review.
- **CSP regression vector.** No-FOUC inline script in `<head>` could break CSP nonce policy app-wide if implemented without nonce passthrough. CSP test required in plan.
- **Sign-off:** CPO + CLO + CTO + `user-impact-reviewer` at plan ready.

## UI Specification (founder-approved, design pass 2026-05-05)

Initial mockups produced via Pencil MCP (`apps/web-platform/design/exports/theme-toggle-{forge,radiance}.png`). Founder reviewed both palettes and approved placement. Iteration request captured below; the iteration .pen was destroyed by a Pencil MCP silent-drop incident (#3274) before re-export, so the iteration is captured here in writing rather than as a fresh mockup. The original PNGs remain valid for placement and segment treatment; only labels/visibility differ.

**Placement.** Sidebar footer of the dashboard, directly above the email + Sign-out row. Anchored under a `THEME` ALL-CAPS label (Inter 10/600 letter-spacing 2, tertiary text). Total wrap height ≈70px; does not push the email row off-screen at the existing sidebar height.

**Control.** 3-way segmented control, equal-width thirds, 32px tall, sharp corners (0px radius — brand "architectural precision"). 1px outer gold-grey border. Sized to fill the 192px sidebar interior.

**Segments.** Three segments, icons-only by default — **NO visible text labels.**

| Order | Label (tooltip + aria-label) | Icon (Lucide) |
|---|---|---|
| 1 | **Dark** | `flame` |
| 2 | **Light** | `sun` |
| 3 | **System** | `monitor` |

**States.** Inactive segment: transparent over toggle background, muted icon color (Forge `#6A6A6A` / Radiance `#6F6353`). Active segment: next surface tint fill (Forge `#1C1C1C` / Radiance `#EDE4CC`), 1px gold stroke (Forge `#C9A962` / Radiance `#9B8857`), gold icon.

**Hover.** Show the label as a tooltip chip above the segment. Style matches the active-segment treatment: 1px gold stroke, surface tint background, primary text color. Use the platform-native `<button title>` only as a fallback for non-pointer devices; the visible chip is the primary affordance.

**Accessibility.** Each segment is a `<button>` with `aria-pressed` reflecting active state and `aria-label` set to the full label ("Dark theme", "Light theme", "Follow system theme"). The chosen theme name announces via `aria-live` polite when changed.

## Acceptance Criteria

Inherited from issue #3232 + the UI spec above:

- [ ] CSS theme tokens introduced; hardcoded `bg-neutral-950` / `text-neutral-100` replaced with semantic tokens (scope decided at plan time).
- [ ] `ThemeProvider` (or equivalent) added; respects `prefers-color-scheme` for "System" and reacts to live OS-level changes.
- [ ] Persistence: localStorage by default. DB only with `security-sentinel` + `data-integrity-guardian` review.
- [ ] No-FOUC inline script added (CSP-nonce-compatible) — verified on `/`, `/auth/*`, payment surfaces.
- [ ] `viewport.themeColor` updated dynamically per resolved theme.
- [ ] 3-way segmented control rendered in sidebar footer with the three segments in order Dark / Light / System (no visible labels, hover tooltips show labels).
- [ ] Lucide icons (`flame`, `sun`, `monitor`) at 12px inside 32px-tall segments.
- [ ] aria-pressed + aria-label on each segment; aria-live announce on change.
- [ ] CSP regression test passes.
- [ ] `user-impact-reviewer` signs off.

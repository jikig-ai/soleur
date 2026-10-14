---
date: 2026-06-04
topic: KB workspace chrome / nav redesign (mobile + desktop)
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
branch: feat-kb-mobile-ux-redesign
pr: 4911
---

# Brainstorm: Knowledge Base Workspace Chrome / Nav Redesign

## What We're Building

A redesign of the workspace **chrome** (header + workspace switcher + back navigation) that
wraps the Knowledge Base screen, applied to KB first but built as a **reusable system** for all
dashboard screens (mobile + desktop). The current screen reads as amateurish: two competing back
affordances, a heavy bordered non-interactive switcher card dominating the top, a buried page
title, borders/dividers everywhere, and a cheap gold square swatch for workspace identity.

**Chosen direction: D4 — "borderless elevation polish"** (the simplest / KISS option), styled to
production quality. Plus a **new settable workspace logo** (replacing the swatch) and **removal of
the global "Soleur" wordmark**.

**Visual design (wireframes):** `knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen`
- Final styled comps: `screenshots/20-final-m1-kb-landing-content.png`, `21-final-m2-kb-empty-gold-cta.png`,
  `22-final-m3-switch-sheet-logo-rows.png`, `23-final-desktop-expanded-sidebar.png`, `24-final-desktop-collapsed-rail.png`
- Explorations (4 directions): `08`–`13` (mobile), `14`–`17` (desktop), `18` (hybrid-logo rule), `19` (logo-upload stub, follow-on)

## Why This Approach

The user explicitly rejected D1 (unified app bar) as "too cluttered" and chose D4 — the lowest-risk,
minimal-restructuring option that keeps today's element order but de-boxes everything, swaps the
swatch for a logo, drops the redundant back link, and promotes the title. It is the most KISS
direction, has the smallest engineering diff, and still fixes all four problems. Research
(Notion/Slack/Linear/Apple HIG/Mintlify/Radix/Geist) confirms borderless, elevation-led dark UI +
single back affordance + disciplined accent is the "senior" pattern.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Direction = D4** (borderless elevation polish), styled to hi-fi | User picked it over D1 ("too cluttered"); simplest/KISS, smallest eng diff |
| 2 | **Settable workspace logo** replaces the gold square swatch | Swatch looks cheap; logo is the identity upgrade |
| 3 | **Hybrid identity display** | Logo-only when a custom logo is set; logo + name for monogram fallback; name always in the selector |
| 4 | **Monogram fallback** = tasteful rounded-square tile (surface-2, NOT a gold square) | New/unlogo'd workspaces need an unmistakable, non-ugly default |
| 5 | **Expanded rail/header = logo + name; collapsed rail = logo-only** | At-a-glance tenant clarity when space allows; minimalism when collapsed |
| 6 | **Remove the global "Soleur" wordmark** from chrome (`app/(dashboard)/layout.tsx:283`) | KISS, real-estate win; PWA icon already carries brand |
| 7 | **One back affordance per state** | Unify the *primitive* (back slot), not the *destination* — KB pop-to-tree vs section exit stay distinct under the hood |
| 8 | **Ship monogram now, logo-upload feature later** | Monogram is an instant upgrade; upload UI + storage is a separate follow-on slice |
| 9 | **Visual design** | `.pen` wireframes committed under `knowledge-base/product/design/navigation/` |

## Non-Goals / Deferred

- **Workspace logo UPLOAD capability** (settings UI + Supabase storage + image validation + `logo_url` data field) — deferred to a follow-on slice; this redesign ships the monogram fallback only. (Tracking issue created.)
- D1 / D2 / D3 directions (explored, not chosen — retained in the `.pen` for reference).
- Rolling the reusable header to Chat/Settings/Dashboard — do KB first, generalize only when each screen has a concrete need (CTO: reject big-bang refactor).

## Open Questions

1. Does the workspace `logo_url` live on the `workspaces` table or a related `organizations` row? (workspace-grain per ADR-044 — confirm at plan time.)
2. Exact monogram color/derivation when no logo (neutral surface-2 vs name-hashed tint).
3. Whether the desktop collapsed-rail logo-only state needs a hover tooltip with the name (a11y).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(Engineering + Product spawned; others n/a for client-side chrome.)

### Product (CPO)
**Summary:** Four core problems = double-back, non-interactive boxed card, buried title, redundant
chrome. Recommended a unified app bar (D1); user chose D4. Hard success criterion: a non-technical
user can instantly name which workspace they're in and find the one way back, with no element that
looks interactive but isn't. Cross-tenant ambiguity is the brand-survival risk — resting state must
show identity, never hide it behind a tap.

### Engineering (CTO)
**Summary:** Do NOT fully merge the two back affordances — expose a back *slot* (href + aria-label),
each screen supplies its own target. Workspace switcher is mounted ONCE (ADR-047 single-mount;
`nav-single-mount.test.ts`) — the new chrome composes *around* it, never re-mounts it. Preserve the
confirm-then-switch flow verbatim: `set_current_workspace_id` RPC (migration 079, ADR-044) →
`refreshSession()` JWT re-mint → **hard `window.location.assign("/dashboard")`** (a soft
`router.push` serves stale RSC = cross-tenant leak). Ship KB-first incrementally; reject big-bang
all-screens refactor. No new ADR needed unless the switch grain or nav model changes.

## Capability Gaps

- **Workspace logo data + storage is net-new.** Evidence: `git grep -niE "logo|avatar|icon" --
  supabase/migrations/*` and `components/dashboard/*`, `app/api/workspace/*` returned no
  workspace/organization logo column — identity is the gold swatch only
  (`org-switcher.tsx:118` `bg-soleur-accent-gold-fg/60`). The upload feature (deferred) will need a
  `logo_url` column + Supabase storage bucket + validation + the monogram fallback.

## User-Brand Impact

- **Artifact:** the workspace identity element in the chrome (logo/monogram + name).
- **Vector:** if the redesign makes the active workspace ambiguous (esp. logo-only with a generic
  monogram), a user could read/edit the **wrong tenant's** knowledge base — a cross-tenant trust breach.
- **Threshold:** single-user incident. Mitigation baked into the design: hybrid rule keeps the name
  visible whenever identity is only a monogram; the switch is a confirm-then-switch flow with a hard
  navigation (CTO constraint) so a switched context never serves stale cross-tenant data.

## Session Errors

1. **Pencil `open_document` is destructive on this existing `.pen` (#3274).** The first open silently
   rewrote the on-disk file and loaded zero nodes; a second open wiped it to a 40-byte stub. Recovery:
   `git checkout` (the file was committed). **Workaround that worked:** golden-copy +
   `open_document(filePath=<canonical>, inputPath=<golden-copy>)`, then verify post-save byte size ≥ prior.
   Worth filing/heal under #3274 if not already tracked.

## Inspiration (cited)

- Linear redesign (elevation/opacity not borders): https://linear.app/now/how-we-redesigned-the-linear-ui
- Dark-mode systems guide: https://muz.li/blog/dark-mode-design-systems-a-complete-guide-to-patterns-tokens-and-hierarchy/
- Apple HIG Navigation Bars (single back, large title): https://developer.apple.com/design/human-interface-guidelines/components/navigation-and-search/navigation-bars
- Back Button UX: https://smart-interface-design-patterns.com/articles/back-button-ux/ · https://baymard.com/blog/back-button-expectations
- Notion mobile workspace switcher: https://www.notion.com/help/workspaces-on-mobile
- Radix dark mode / Geist colors: https://www.radix-ui.com/themes/docs/theme/dark-mode · https://vercel.com/geist/colors
- Mintlify mobile nav: https://www.mintlify.com/docs/organize/navigation

---
feature: kb-mobile-ux-redesign
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-04-feat-kb-workspace-chrome-nav-redesign-plan.md
issue: 4915
deferred: [4916, 4917]
---

# Tasks: KB Workspace Chrome / Nav Redesign (D4)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm 4 swatch sites, wordmark site, 3 back-affordance sites, named tests exist (done in research)
- [ ] 0.2 Run ADR-049 `e2e/nav-states-shell.e2e.ts` for a green baseline before edits
- [ ] 0.3 Read `components/leader-avatar.tsx` (size-map + img-error fallback) as tile model

## Phase 1 — Workspace identity monogram tile
- [x] 1.1 Create `components/dashboard/workspace-identity-tile.tsx` (pure presentational, props `{name, size}`, monogram on fixed non-gold token, no `variant`, no img branch)
- [x] 1.2 Create `test/workspace-identity-tile.test.tsx` (single-initial derivation, never gold, not-imported guard) — 6/6 green
- [ ] 1.3 Replace swatch at `org-switcher.tsx:87` (solo), `:118` (multi trigger)
- [ ] 1.4 Replace swatch at `org-switcher.tsx:160` (dropdown row) — preserve current vs non-current fill
- [ ] 1.5 Thread active workspace `name` into the collapsed band; replace swatch at `workspace-context-band.tsx:95`; replace static `title="Active workspace"` (:94) with full name
- [ ] 1.6 Verify `nav-single-mount.test.ts` still green (tile imports neither container nor badge)

## Phase 2 — Borderless de-box + wordmark removal + solo/multi affordance
- [ ] 2.1 De-box switcher trigger (`org-switcher.tsx:114,139,154`), outer container wrapper (`org-switcher-container.tsx:132`), band shell (`workspace-context-band.tsx:79,169`) → surface-1 elevation
- [ ] 2.2 Do NOT touch confirm dialog border (`org-switcher-container.tsx:144`) or button handlers (:154-167,187-201); retain confirm/retry gold (:157,190)
- [ ] 2.3 Solo = flat (no caret); multi = caret + pressable; keep `workspace-identity-static` testid/text
- [ ] 2.4 Remove `<span>Soleur</span>` (`app/(dashboard)/layout.tsx:288-292`), keep flex row + sibling buttons, stays render-conditional (`drill === null`)
- [ ] 2.5 Update wordmark tests: `nav-rail-drill.test.tsx:94/133`; `nav-states-shell.e2e.ts:369/391/479` (don't touch `"Soleur Workspace"` assertions)
- [ ] 2.6 Preserve width-clamp classes (`w-full min-w-0`, `shrink-0`) + padding ownership

## Phase 3 — Suppress duplicate back in doc view
- [ ] 3.1 Suppress band "Back to menu" in mobile doc view via explicit prop from `(dashboard)/layout.tsx` OR mobile-placement scoping — NO parallel pathname check in band (ADR-047 AC4c)
- [ ] 3.2 Keep band back glyph distinct from collapse chevron (`nav-chevron-alignment.test.tsx:83/92`)
- [ ] 3.3 Add test: exactly one back control per state (doc view = file-tree back only)

## Phase 4 — Page-body chrome for fullWidth states + title ownership
- [ ] 4.1 Add page-body "Knowledge Base" title + mobile back to the single `kb/layout.tsx` fullWidth wrapper (do NOT re-mount identity band)
- [ ] 4.2 Ensure exactly one "Knowledge Base" title on mobile (no band/page double-render)

## Phase 5 — Visual regression gate + test reconciliation
- [ ] 5.1 Extend `e2e/nav-states-shell.e2e.ts`: mock app routes (`/api/workspace/active-repo`, `/list-memberships`); assert content testids + `scrollWidth-clientWidth<=1` at `md:w-56`/`md:w-14`; identity present every drill state; collapsed monogram non-gold + name tooltip
- [ ] 5.2 Reconcile vitest suites green: `nav-single-mount`, `nav-chevron-alignment`, `nav-rail-drill`, `org-switcher`, `workspace-context-band`, `workspace-identity-tile`
- [ ] 5.3 `tsc --noEmit` clean; run e2e via Playwright (excluded from vitest)
- [ ] 5.4 PR body: `Closes #4915`; reference #4916, #4917

## Out of scope (tracked)
- #4916 — workspace logo UPLOAD (settings + storage + logo_url + gdpr-gate)
- #4917 — switch-failure tenant divergence (switch state machine — untouched here)

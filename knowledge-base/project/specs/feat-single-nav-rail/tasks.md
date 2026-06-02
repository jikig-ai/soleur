---
feature: feat-single-nav-rail
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-single-nav-rail-drill-in-plan.md
issue: 4813
---

# Tasks: Single Nav Rail — Drill-In Replacement

TDD; failing tests first. 4 phases (atomic single-PR). Runner: `./node_modules/.bin/vitest run`.

## Phase 0 — Pre-flight (no code)
- [ ] 0.1 Confirm Node ≥22.9.0 (✓ v22.22.1) + Pencil connected (✓; wireframes done).
- [ ] 0.2 Re-grep the 4 ⌘B owners, the `!collapsed` switcher/badge gate, and the 3 localStorage keys (main/settings/chat); re-grep the test list (Kieran P1-1).

## Phase A — Brand-safety payload (context band + single ⌘B owner + safe switch)
- [ ] A.1 RED: `workspace-context-band.test.tsx` — identity (name+repo) in DOM on a **drilled** route (`/dashboard/settings/members`); back chevron synchronous; never gated on `collapsed`.
- [ ] A.2 GREEN: create `components/dashboard/workspace-context-band.tsx`, mounted in `(dashboard)/layout.tsx` OUTSIDE the swap region; relocate `OrgSwitcherContainer` (interactive chip, solo one-render-path) + `LiveRepoBadge`. Net-new = back chevron + section label + shell only.
- [ ] A.3 RED+GREEN single-mount (AC4b): grep/import test that `OrgSwitcherContainer`+`LiveRepoBadge` render in exactly one module.
- [ ] A.4 Safe switch (AC2): `org-switcher-container.tsx:94` `reload()` → `window.location.assign("/dashboard")`; update `org-switcher-container.test.tsx` confirm + retry paths.
- [ ] A.5 Single ⌘B owner (AC5): remove the 4 per-route guards; one handler; jsdom (one handler toggles) + Playwright (one rail across KB/Settings/Chat).

## Phase B — URL-derived drill + lift secondary navs
- [ ] B.1 RED: `nav-rail-drill.test.tsx` — main nav on `/dashboard` AND `/dashboard/admin/analytics`; secondary slot on `kb|settings|chat`; back hidden on non-drill; stable nav-hook mock refs.
- [ ] B.2 GREEN: pure `segment-to-drill-level.ts` (typed allowlist); route ALL `startsWith` literals through it (AC4c grep test); reuse `translate-x` slide + `ChevronLeftIcon`.
- [ ] B.3 Lift KB tree / Settings sub-nav / Conversations rail into the swap slot, keyed by segment. **DELETE `chat/layout.tsx:67-72` aside** (keep banner resolution); AC4d: one `conversations-rail` node on `/dashboard/chat` md+.
- [ ] B.4 Strip redundant `mx-auto max-w-*`/`px/py` from lifted child pages; ref-guard relocated reset effects.
- [ ] B.5 Collapse-key unification: one key + one-time cleanup of the 3 orphans; KB stays ephemeral (documented).

## Phase C — Empty states, mobile band, instrumentation
- [ ] C.1 Generic labeled empty-state CTA for empty Conversations + empty KB rails (AC6) — never blank.
- [ ] C.2 Mobile top-bar context band replacing the static "Soleur" span (`layout.tsx:216-218`); one band component via `variant` prop.
- [ ] C.3 AC11 (pre-merge): wrong-workspace action-time instrumentation on invite / API-key-share / scope-grant.

## Phase D — ADR + test rework
- [ ] D.1 ADR-047 "context band + switcher outside the swap region"; cite AP-011.
- [ ] D.2 Rework the ~17 test files; no jsdom layout assertions; both-toggle-state alignment; `WEBPLAT_TEST_USE_FORKS=1` to triage kb-chat-sidebar flakes.
- [ ] D.3 `tsc --noEmit` clean (AC8); reference wireframes in spec FRs (AC9).

## Exit
- [ ] CPO sign-off confirmed (single-user-incident threshold).
- [ ] `user-impact-reviewer` at PR review.

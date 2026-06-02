---
feature: feat-single-nav-rail
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-single-nav-rail-drill-in-plan.md
issue: 4813
---

# Tasks: Single Nav Rail — Drill-In Replacement

TDD; failing tests first. 4 phases (atomic single-PR). Runner: `./node_modules/.bin/vitest run`.

## Phase 0 — Pre-flight (no code)
- [x] 0.1 Confirm Node ≥22.9.0 (✓ v22.22.1) + Pencil connected (✓; wireframes done).
- [x] 0.2 Re-grep the 4 ⌘B owners, the `!collapsed` switcher/badge gate, and the 3 localStorage keys (main/settings/chat); re-grep the test list (Kieran P1-1). (Branch rebased onto origin/main first — layout.tsx had landed sibling edits.)

## Phase A — Brand-safety payload (context band + single ⌘B owner + safe switch)
- [x] A.1 RED: `workspace-context-band.test.tsx` — identity (name+repo) in DOM on a **drilled** route (`/dashboard/settings/members`); back chevron synchronous; never gated on `collapsed`.
- [x] A.2 GREEN: create `components/dashboard/workspace-context-band.tsx`, mounted in `(dashboard)/layout.tsx` OUTSIDE the swap region; relocate `OrgSwitcherContainer` (interactive chip, solo one-render-path) + `LiveRepoBadge`. Net-new = back chevron + section label + shell only.
- [x] A.3 RED+GREEN single-mount (AC4b): grep/import test that `OrgSwitcherContainer`+`LiveRepoBadge` render in exactly one module. (`nav-single-mount.test.ts`)
- [x] A.4 Safe switch (AC2): `org-switcher-container.tsx` `reload()` → `window.location.assign("/dashboard")`; update `org-switcher-container.test.tsx` confirm + retry paths.
- [x] A.5 Single ⌘B owner (AC5): remove the 4 per-route guards; one handler; jsdom (one handler toggles across KB/Settings/Chat). Playwright across sections → AC10 walkthrough.

## Phase B — URL-derived drill + lift secondary navs
- [x] B.1 RED: `nav-rail-drill.test.tsx` — main nav on `/dashboard` AND `/dashboard/admin/analytics`; secondary slot on `kb|settings|chat`; back hidden on non-drill; stable nav-hook mock refs.
- [x] B.2 GREEN: pure `segment-to-drill-level.ts` (typed allowlist); route ALL `startsWith` literals through it (AC4c grep test `nav-drill-authority.test.ts`); reuse `ChevronLeftIcon`.
- [x] B.3 Lift KB tree / Settings sub-nav / Conversations rail into the swap slot via a portal (`rail-slot.tsx`). **DELETED `chat/layout.tsx` aside** (kept banner resolution); AC4d: one `conversations-rail` node.
- [x] B.4 Strip redundant `mx-auto max-w-*`/`px/py` from lifted shells; reset-effect ref-guards unchanged (no relocated reset effect needed).
- [x] B.5 Collapse-key unification: main key retained as the unified key + one-time cleanup of the orphaned settings + chat-rail keys; KB stays ephemeral (documented in `use-sidebar-collapse.ts`).

## Phase C — Empty states, mobile band, instrumentation
- [x] C.1 Generic labeled empty-state CTA (`RailEmptyState`) for empty Conversations + empty KB rails (AC6) — never blank.
- [x] C.2 Mobile top-bar context band replacing the static "Soleur" span; one band component via `variant` prop; single-mount via `useMediaQuery`.
- [x] C.3 AC11 (pre-merge): wrong-workspace action-time instrumentation (`emitWorkspaceActionContext`) on invite / API-key-share / scope-grant.

## Phase D — ADR + test rework
- [x] D.1 ADR-047 "context band + switcher outside the swap region"; cite AP-011.
- [x] D.2 Reworked the test files to the slot model; deleted obsolete aside-CSS-contract + drawer-mount tests; no jsdom layout assertions.
- [x] D.3 `tsc --noEmit` clean (AC8); wireframes referenced in spec FRs (AC9).

## Exit
- [x] CPO sign-off confirmed (single-user-incident threshold) — cleared 2026-06-02 (3 conditions, all in-plan).
- [ ] `user-impact-reviewer` at PR review.

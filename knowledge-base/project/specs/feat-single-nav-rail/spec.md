---
title: Single Nav Rail — Drill-In Replacement with Persistent Workspace Context
feature: feat-single-nav-rail
date: 2026-06-02
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-02-single-nav-rail-brainstorm.md
related_issues: [4813, 2343]
supersedes_model: "collapsible-sidebars (#2342, shipped)"
---

# Spec: Single Nav Rail

## Problem Statement

The web-platform shows two side-by-side sidebars on KB, Settings, and Chat: a persistent
primary nav rail plus a per-route secondary rail (KB file tree / Settings sub-nav /
Conversations rail). Two rails consume horizontal space that should go to content
(conversations, chat-on-PDF, KB doc reading), and the prior collapsible model (#2342)
only partially fixes this — it requires a manual collapse and, worse, *unmounts* the
workspace switcher and "Working on: repo" badge when collapsed, so a wrong-workspace
action is already possible today.

## Goals

- G1. Collapse the two rails into one: the section's secondary nav **replaces** the
  primary nav in the same rail, with a back chevron returning to main nav.
- G2. A **persistent context band** (`[‹ back] · workspace avatar/name · "Working on: repo" ·
  section title`) stays visible in EVERY drill state — never hidden.
- G3. Reclaim the secondary rail's width (~w-48 to w-72) for content on KB, Settings, Chat.
- G4. Preserve browser back/forward and deep-linkability of every nav state.
- G5. Eliminate the existing wrong-workspace exposure (switcher unmount on collapse).

## Non-Goals

- NG1. No drill-in for Dashboard / Analytics (no secondary rail to replace).
- NG2. No data-model, auth, RLS, or storage change — pure front-end navigation restructure.
- NG3. No section-switcher control in the context band (sibling switch = back-then-forward,
  per operator decision). May be revisited post-launch if instrumentation shows orientation pain.
- NG4. No icon-rail-collapse hybrid (Approach B rejected in favor of A).

## Functional Requirements

- FR1. **Drill-in replace.** On navigating into KB / Settings / Chat, the rail renders that
  section's secondary nav in place of the primary nav. (Surfaces: `kb/layout.tsx`,
  `settings/layout.tsx` → `settings-shell.tsx`, `chat/layout.tsx` → ConversationsRail.)
- FR2. **Back affordance.** A back chevron in the context band returns to the main nav
  (`router.push` to the parent segment).
- FR3. **Persistent context band.** Workspace avatar/name + "Working on: repo" + section
  title render in all drill states. Mounted OUTSIDE the swap region (see TR1).
- FR4. **URL-derived drill level.** Drill state is derived from the route segment, not local
  React state and not the collapse hook.
- FR5. **Sibling switching.** Switching KB→Settings is back-then-forward (no in-band switcher).
- FR6. **Unified ⌘B/Ctrl+B.** Consolidate the three route-guarded shortcut handlers
  (`layout.tsx`, `settings-shell.tsx`, `use-kb-layout-state.tsx`) into one rail owner.
- FR7. **GDPR controls reachable.** Settings entry stays visible in main nav; account-deletion
  and DSAR export remain reachable via Settings drill-in (CLO requirement).
- FR8. **Mobile.** Reuse / generalize the existing `kb-mobile-layout.tsx` drill-in pattern;
  keep the mobile drawer behavior coherent with the desktop model.

## Technical Requirements

- TR1. **Brand-safety invariant (load-bearing).** `OrgSwitcherContainer` + `LiveRepoBadge`
  must mount in the always-mounted `(dashboard)/layout.tsx` route-group layout, ABOVE the
  swap region, so they survive every drill state by construction. Recorded as an ADR.
- TR2. **Reuse the `translate-x` drawer-slide primitive** (`layout.tsx:238-239`) and inline
  `ChevronLeftIcon` for the primary↔secondary slide; do not introduce a second animation system.
- TR3. **Route-group ownership.** Either lift active-section rendering into the shared layout
  conditionally on segment, OR invert rail ownership so one component swaps children. Choose
  the lower-risk shape at plan time (CTO leans toward the shared-layout conditional render).
- TR4. **Route manifest (#2343).** Land a minimal segment→drill-level map in the shape #2343
  will adopt, or sequence #2343 first. Decide at plan time.
- TR5. **Test rework (~15 files).** `dashboard-layout-*`, `kb-layout*`, `settings-sidebar-collapse`,
  `kb-sidebar-transition`, `use-sidebar-collapse`. `dashboard-layout-sidebar-settings.test.tsx`
  will break outright (Settings footer-link assertion). Write/adjust failing tests first.
- TR6. **Solo-user context band.** Decide whether the band shows workspace name for solo users
  (`memberships.length <= 1`, where the switcher self-hides) — orientation value vs. switcher parity.

## Acceptance Criteria (from CPO)

- AC1. Zero wrong-workspace destructive actions — instrument workspace-context-at-action-time
  on invite / key-share / scope-grant.
- AC2. Task resumption: users return to the same KB doc / PDF-chat position after navigating away.
- AC3. Time-to-find Settings/KB does not regress vs. today (moderated test, 3–5 non-technical users).
- AC4. Content-area width on KB/Settings/Chat measurably increases when the secondary nav is active.

## Open Questions (resolve in plan)

1. Solo-user context-band behavior (TR6).
2. `LiveRepoBadge` poll/subscription survives relocation (brainstorm OQ2).
3. Chat: drilling replaces primary nav with Conversations list — confirm desired.
4. Route-manifest sequencing vs. #2343 (TR4).

## Visual Design

ux-design-lead wireframes (drill states, context band, collapsed workspace identity) are
a prerequisite — first plan step. No `.pen` artifact exists yet (Capability Gap #1).

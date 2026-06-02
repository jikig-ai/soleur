---
title: Single Nav Rail — Drill-In Replacement with Persistent Workspace Context
date: 2026-06-02
topic: single-nav-rail
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
related_issues: [4813, 4810, 2343]
supersedes_model: collapsible-sidebars (#2342, shipped)
---

# Brainstorm: Single Nav Rail — Drill-In Replacement

## What We're Building

Collapse Soleur's **two side-by-side sidebars** into **one nav rail**. Today the persistent primary rail (workspace switcher, "Working on: repo", theme toggle, Dashboard / Knowledge Base / Analytics, footer: email / Status / Settings / Sign out) sits next to a secondary rail (KB file tree, Settings sub-nav, or the Chat conversations rail). The new model: clicking a section makes its **secondary nav replace the primary nav in the same rail**, with a back chevron to return — reclaiming the second rail's width (~w-48 to w-72) for content: conversations, chat-on-PDF, KB doc reading.

A **slim persistent context band** stays pinned at the top of the rail in every drill state: `[‹ back] · workspace avatar/name · "Working on: repo" · section title`. This band is the wrong-workspace circuit breaker.

**Approach:** A — Drill-in replace + persistent context band. Drill level is **URL-derived** (the route segment already encodes it). Sibling-section switching is **back-then-forward** (return to main nav, then pick the sibling). Applies uniformly to KB, Settings, and Chat — all three already have a secondary rail.

## Why This Approach

- **It matches the operator's mental model** ("one rail, secondary replaces primary, back returns") and delivers the maximum content-width win, which the already-shipped *collapsible* model (#2342) only partially achieves (user must manually collapse, and collapse *unmounts* the workspace context).
- **The persistent context band fixes an existing latent bug, not just a regression.** CPO verified that `OrgSwitcherContainer` + `LiveRepoBadge` already unmount when the primary rail is collapsed (`layout.tsx:281-290`, gated on `!collapsed`) — so a wrong-workspace action is *already* possible today. Pinning workspace identity in the band closes that hole.
- **Low architectural risk via URL-derived drill state** (CTO). Browser back/forward and shareable URLs work for free; the switcher mounts in the always-mounted route-group layout *above* the swap region, so it survives every drill state by construction.
- **The pattern is already proven in our own codebase.** `kb-mobile-layout.tsx` already does single-column drill-in (tree at `/dashboard/kb`, replaced by content on a file route via `isContentView`). Desktop drill-in generalizes a pattern that ships today on mobile.
- **CPO dissent acknowledged:** CPO recommended icon-rail-collapse (Approach B) for non-technical discoverability, citing orientation cost. Operator chose A; the persistent context band + prominent back affordance answer the biggest part of that concern. The orientation cost (sibling switch = back-then-forward) is accepted as a deliberate trade for the cleaner single rail. Acceptance instrumentation (below) will catch it if it bites.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Interaction model | Drill-in replace (secondary replaces primary in one rail) | Operator's vision; max content width; supersedes collapse-in-place model |
| Persistent context band | Always-visible `[‹ back · workspace · repo · section]` pinned atop the rail in every drill state | Brand-critical: workspace identity must never disappear (wrong-workspace circuit breaker); also fixes existing collapse-unmount bug |
| Drill-state source | URL/route segment (`/dashboard` vs `/kb` vs `/settings` vs `/chat`) | CTO: free back/forward + deep-linking; no new local state; don't reuse collapse hook (orthogonal concern) |
| Switcher placement | Mounts in always-mounted `(dashboard)/layout.tsx`, OUTSIDE the swap region | CTO load-bearing rule: prevents switcher unmounting on drill |
| Sibling-section switching | Back-then-forward (return to main nav, then pick sibling) | Operator choice; simplest; one extra tap accepted |
| Scope | KB + Settings + Chat | All three already have a secondary rail; uniform model |
| Transition primitive | Reuse existing `translate-x` drawer-slide (`layout.tsx:238-239`) + inline `ChevronLeftIcon` | No new animation system (CTO/research) |
| ⌘B / Ctrl+B shortcut | Consolidate the 3 separate route-guarded handlers into one rail owner | Research: shortcut implemented 3× today (layout, settings, kb) |
| GDPR controls reachability | Account-deletion + DSAR export stay behind Settings drill-in | CLO: Art. 12(2)/17/20 require *accessible*, not N-click; Settings entry must stay visible in main nav |
| Architecture Decision Record | Capture "switcher renders outside the swap region" as an ADR | CTO: durable brand-safety invariant worth recording |
| Visual design | ux-design-lead wireframes drill states + context band BEFORE build | CPO + CTO: lock context-header placement before rail refactor |

### Concrete layout sketch (desktop)

```
TODAY (two rails):                          PROPOSED (one rail, drilled into KB):
┌──────────┬──────────┬─────────────┐       ┌──────────┬───────────────────────────┐
│ Soleur   │ KB       │             │       │ ‹ Soleur Workspace · jikig/soleur │  ← persistent context band
│ ◐ theme  │ search.. │             │       │   Knowledge Base                  │
│ [WS ▾]   │ ▸ eng    │  content    │       ├──────────┼───────────────────────────┤
│ Working: │ ▸ finance│  (narrow)   │  →    │ search.. │                           │
│ Dashboard│ ▸ legal  │             │       │ ▸ eng    │   content (WIDE)          │
│ KB       │ ...      │             │       │ ▸ finance│                           │
│ Analytics│          │             │       │ ▸ legal  │                           │
│ ────     │          │             │       │ ...      │                           │
│ Settings │          │             │       │          │                           │
└──────────┴──────────┴─────────────┘       └──────────┴───────────────────────────┘
   w-56       w-48/72                          (rail = single column; ~w-48/72 reclaimed for content)
```

## Open Questions

1. **Solo-user concentration.** CPO flagged: `OrgSwitcherContainer` self-hides for solo users (`memberships.length <= 1`). So the wrong-workspace risk is concentrated entirely in multi-org/team accounts. Does the context band still show workspace name for solo users (orientation value) or stay hidden (matching switcher)? Decide in plan.
2. **`LiveRepoBadge` poll behavior** must survive relocation into the context band — confirm the poll/subscription isn't tied to its current mount position.
3. **Chat secondary = Conversations rail.** Drilling into Chat replaces primary nav with the conversations list. Confirm this is the desired "win real estate for conversations" behavior (vs. keeping conversations always visible).
4. **KB chat / PDF panel** is a resizable react-resizable-panels Panel (22–40%) *inside* the KB layout. Widening it comes from reclaiming the KB tree rail via drill-in — confirm no separate work needed.
5. **Shared route manifest (#2343, OPEN).** CTO: the segment→drill-level map is the natural home for #2343. Land a minimal segment-map helper in the shape #2343 will adopt, or sequence #2343 first? Decide in plan.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Recommends icon-rail-collapse (hybrid) over full drill-in for non-technical users on orientation/discoverability grounds; full drill-in trades a real-estate win for navigation-depth cost. Verified the wrong-workspace risk is *already live* (switcher unmounts on collapse). Operator overrode toward full drill-in (Approach A) with the persistent context band as mitigation. CPO's acceptance signals adopted: zero wrong-workspace destructive actions, task-resumption (no place-loss), no regression in time-to-find Settings/KB, measurable content-width gain.

### Engineering (CTO)

**Summary:** Feasibility HIGH, risk MEDIUM concentrated in workspace context. Recommended shape: URL-derived drill level (not local state, not the collapse hook); switcher mounts in always-mounted route-group layout above the swap region (survives drill by construction); reuse `translate-x` slide primitive; ~15 test files to rework (days). Most likely failure: a fast "stateful rail swaps contents" implementation lets the switcher ride inside the swapped body and vanish on drill — prevent with the structural rule above. Interacts with OPEN #2343 (route manifest). Recommends an ADR.

### Legal (CLO)

**Summary:** LOW legal surface; no consent/disclosure/data-model change, GDPR gate not triggered. Account-deletion (`delete-account-dialog.tsx`) + DSAR export (`dsar-export-job-list.tsx`) live in the Settings sub-nav being drilled into — fine, since Art. 12(2)/17/20 require *accessible*, not within N clicks, provided the Settings entry stays visible in main nav. Only real ask: active-workspace identity must remain unambiguous on any pane that mutates membership, grants, or shares PII (Members, Scope Grants, Integrations) — satisfied by the context band.

## Capability Gaps

| Gap | Domain | Why needed (evidence) |
|---|---|---|
| Wireframes for drill states + persistent context band + collapsed workspace identity | Product (ux-design-lead) | CPO + CTO: context-header placement must be locked before the rail refactor. No `.pen` artifact exists for this; interaction-design decision, not a roadmap one. |
| Per-route state-machine for drill + context-band persistence across route changes | Product (spec-flow-analyzer) | CPO: KB/Settings/Chat have secondary rails; Dashboard/Analytics do not — flow differs per route; needs explicit mapping. Confirmed via research: secondary rails only at `kb/layout.tsx`, `settings/layout.tsx`, `chat/layout.tsx`. |
| Shared route manifest (segment → drill-level) | Engineering | Pre-existing OPEN issue #2343; CTO: ad-hoc segment map now creates a second source of route truth #2343 must reconcile. Decide sequencing in plan. |

## User-Brand Impact

**Artifact:** the workspace switcher (`OrgSwitcherContainer`) + "Working on: repo" badge (`LiveRepoBadge`), currently mounted only in the primary rail (`layout.tsx:281-290`).

**Vector:** if a drill-in hides the active-workspace identity, a non-technical user could perform a destructive/PII action — invite a member, share an API key, edit Scope Grants, edit KB docs — against the **wrong workspace**, an unauthorized-disclosure pattern (CLO-confirmed). The risk is *already partially live* today because the switcher unmounts on rail collapse.

**Threshold:** single-user incident. One wrong-workspace action (e.g. inviting an outside party into the wrong tenant, or exposing teammate PII) is brand-damaging.

**Mitigation (load-bearing):** persistent context band showing workspace avatar/name + active repo in EVERY nav/drill state; switcher mounts outside the swap region in the always-mounted route-group layout. Captured as a planned ADR.

## Next Steps

1. ux-design-lead wireframes (capability gap #1) — first plan step.
2. Spec via `skill: soleur:plan`; decide Open Questions #1 and #5 in the plan, not at implementation time.
3. Create/record the ADR for the "switcher outside swap region" invariant.

---
title: "An RBAC 'same access' report is often UI-visibility, not privilege escalation — diagnose the server boundary first"
date: 2026-06-01
category: bug-fixes
module: apps/web-platform/components/settings
tags: [rbac, authorization, ui-gating, defense-in-depth, settings, workspace]
pr: 4763
---

# Learning: An RBAC "Member has the same access as Owner" report is often UI-only

## Problem

Operator reported that a workspace **Member** (`jean.deruelle@gmail.com`) appeared to
have the same access as the **Owner** (`ops@jikigai.com`), "especially in Settings."
The instinct on an RBAC report is to assume privilege escalation and start hardening
the authorization model (routes, RLS, RPCs).

## Solution

**Diagnose the server boundary BEFORE touching the auth model.** Grep the API routes
and RPCs the surface calls and confirm whether they already gate on role. In this case
every workspace-scoped mutation already enforced `role === "owner"` server-side:

- `app/api/workspace/{invite-member,remove-member,transfer-ownership,cancel-invite}/route.ts`
  each `return 403 not_owner` for a non-owner caller, and the RPCs re-check ownership.

So a Member's attempt was already rejected with `403 not_owner` — **not** escalation.
The actual defect was **UI-only**: two owner-only controls rendered to all roles,
contradicting the page's own `isOwner` convention:

1. The "+ Invite member" button (`invite-member-action.tsx`) took no `isOwner` prop.
2. The per-row kebab in `team-membership-list.tsx` gated only on `!isCurrentUser`, not
   `isOwner`, so Members saw a "Remove member" item.

The fix threaded the already-computed `isOwner` (single source in `team/page.tsx`) into
those two controls (`showActions = !isCurrentUser && isOwner`; `if (!isOwner) return null`),
mirroring the existing `pending-invites-list.tsx` / `delegation-toggle.tsx` precedents.
**Server 403 gates were retained verbatim as defense-in-depth** — the UI gate is
cosmetic alignment, never the boundary.

## Key Insight

A "role X can do Y" report is a claim about *observed UI affordances*, which is a
**superset** of what the server permits. Confirm the server boundary first:

- If the server already 403s the action → the bug is UI-visibility. Fix = thread the
  existing role flag to the unguarded control. Do **not** weaken or rewrite the auth model.
- The real regression to fear is **over-gating** (hiding a control from a legitimate
  Owner), not under-gating — pin it with an `isOwner={true}` positive-control test.
- Also confirm the role union is closed (`"owner" | "member"` here, backed by a DB CHECK
  constraint) so `role === "owner"` is exhaustive — a future third role would need revisiting.

## Session Errors

1. **Task tool unavailable inside the planning subagent** (forwarded from session-state.md)
   — Recovery: substituted deterministic grep/Read probes for research/plan-review fan-out;
   ran deepen halt gates directly. Prevention: known environment constraint; plan flagged
   `requires_cpo_signoff: true` so the skipped multi-agent plan-review was surfaced, and the
   post-implementation 7-agent review compensated.
2. **Planning subagent's first `Write` resolved to the bare-root mirror** (forwarded) —
   Recovery: corrected to the explicit worktree path. Prevention: already covered by the
   CWD-verification step-0 in the one-shot planning-subagent contract.
3. **`vitest --project component` exited 127 from the worktree root** — the Bash tool
   persists CWD across calls, and a prior `cd <worktree-root> && git diff` left CWD above
   `apps/web-platform`. Recovery: re-ran with explicit `cd <abs-path> && …`. Prevention:
   already documented in work SKILL.md ("chain `cd <worktree-abs-path> && <cmd>` in a single
   Bash call") — one-off, no new rule needed.

## Tags
category: bug-fixes
module: apps/web-platform/components/settings

---
title: "Member-side BYOK delegation consumption must resolve the ACTIVE workspace, not MIN(created_at)"
date: 2026-06-02
category: bug-fixes
module: apps/web-platform/server/byok-resolver.ts
tags: [byok, delegations, workspace-resolution, cross-tenant, adr-044, multi-agent-review]
pr: 4767
issues: [4767, 4761]
---

# Learning: member delegation consumption resolved the wrong workspace, keeping the keyless banner up

## Problem

After an owner shared a BYOK key with a member (PR #4761 fixed the owner-side
`grant_byok_delegation` write, so a `byok_delegations` row existed with
`grantee_user_id = member`, `workspace_id = shared workspace`), the member
STILL saw the dashboard keyless "joiner" banner ("tasks need an API key … add
your own"), and runtime task leases failed with `MissingByokKeyError`.

## Root cause

The member-side resolvers in `apps/web-platform/server/byok-resolver.ts`
(`resolveByokDelegationContext` → `userHasEffectiveByokKey` /
`userHasPendingByokDelegation`, AND the runtime `resolveKeyOwnerThenLease`)
derived the delegation's workspace via `getDefaultWorkspaceForUser`, which is
`MIN(workspaces.created_at)` = the member's **oldest** workspace. An invited
member who already had a solo account holds two `workspace_members` rows; the
delegation lives in the **shared** workspace the owner granted into, but
`MIN(created_at)` resolves the member's pre-existing **solo** workspace. So
`resolve_byok_key_owner(member, solo_ws)` and the `byok_delegations` SELECT
filtered on `workspace_id = solo_ws` found no row → `hasEffectiveKey:false`,
`pendingDelegation:false` → joiner banner.

## Solution

Swap `getDefaultWorkspaceForUser` → `resolveCurrentWorkspaceId` (the canonical
ADR-044 active-workspace resolver already used by `current-repo-url.ts`,
`resolve-installation-id.ts`, `insert-draft-card.ts`, `resolveActiveWorkspaceKbRoot`)
in the single shared chokepoint so all three consumers move atomically.
`accept-invite` sets `current_workspace_id` to the shared workspace, so an
accepted member resolves the workspace the delegation lives in. The resolver
fails closed to the caller's own solo workspace (never a sibling), preserving
the cross-tenant invariant.

## Key Insight

1. **Trace the ACTUAL producer; the consumers move together.** The symptom is a
   banner string, but fixing only the banner path (`resolveByokDelegationContext`)
   would leave `resolveKeyOwnerThenLease` looking in the solo workspace → the
   banner vanishes but task runs still fail (a worse state). Enumerate every
   consumer of the wrong derivation before coding. A grep audit also surfaced a
   **third** site the plan flagged for audit: `chat/layout.tsx` hardcoded
   `workspaceId = user.id` (the solo workspace) before `resolveGranteeDelegation`.

2. **Prefer the canonical resolver over a new query.** `resolveCurrentWorkspaceId`
   already encodes the fail-closed-to-solo (never-a-sibling) invariant. A
   workspace-agnostic `WHERE grantee = caller` lookup would widen the read
   surface and break tenant scoping. The cross-tenant backstop is defense in
   depth: even a wrong workspace can't leak a sibling's delegation because
   `resolve_byok_key_owner` AND `resolveGranteeDelegation` both also filter
   `grantee_user_id = caller`.

3. **No-throw vs throw is a fail-direction change to verify per consumer.**
   `getDefaultWorkspaceForUser` threw on integrity violation; `resolveCurrentWorkspaceId`
   Sentry-mirrors then returns the solo `userId`. The runtime lease's try/catch
   becomes a defensive guard (it still fires on a transport-level promise
   rejection — say "does not throw on a handled query error", not "never throws").

## Session Errors

1. **Bare-repo command failure on resume.** — Recovery: `git worktree list` →
   `cd .worktrees/<branch>`. The first `git status`/`git branch` ran from the
   `core.bare=true` primary dir (exit 128; `git branch` returned `main`; the
   untracked plan-file Read came back empty because it lives in the worktree).
   — Prevention: on a resume prompt that names a branch + worktree-based work,
   run `git worktree list` and cd into the matching worktree BEFORE any
   git/file inspection. (Hook `hr-when-in-a-worktree-never-read-from-bare`
   covers the inverse direction; the resume-orientation gap is the new wrinkle.)

2. **Concurrent review-agent working-tree contamination.** — Recovery:
   post-review `git status` + `git diff HEAD -- <file>` confirmed a clean tree
   matching the correct committed HEAD. — `test-design-reviewer` reverted
   `byok-resolver.ts` to its pre-fix state to empirically verify RED while
   `data-integrity-guardian` + `architecture-strategist` read the same shared
   worktree concurrently; both reported the transient revert as a HIGH/blocking
   "uncommitted working-tree" finding (an external linter also touched the file
   mid-review). The committed HEAD was correct the whole time. — Prevention:
   when `/review` fans out a mutating agent (test-design verifies RED by editing
   source) alongside file-reading agents on one shared worktree, verify
   `git diff HEAD` is empty post-review before trusting any "working-tree
   revert" finding. Routed to the `review` skill Sharp Edges.

3. **`gh pr view --json merged` field quirk (forwarded from session-state.md).**
   — `merged` vs `mergedAt` during the plan phase; premise validated regardless.
   — One-off; no workflow change warranted.

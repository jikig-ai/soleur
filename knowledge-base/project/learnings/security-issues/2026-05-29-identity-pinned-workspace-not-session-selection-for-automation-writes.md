---
title: Automation/headless writes must pin workspace by identity, not session-selection
date: 2026-05-29
category: security-issues
module: web-platform/messages
issue: 4579
pr: 4580
tags: [rls, multi-tenant, cross-tenant, workspace, supabase, cron, idor, gdpr, art-17]
---

# Learning: identity-pinned workspace for automation writes (not `resolveCurrentWorkspaceId`)

## Problem

The KB-drift walker (an HMAC-signed cron) persists draft action cards into the
workspace-scoped `messages` table, attributed to a fixed operator founder. The
plan (and spec FR3) prescribed resolving the target workspace via
`resolveCurrentWorkspaceId(founderId, tenant)`.

`resolveCurrentWorkspaceId` returns `user_session_state.current_workspace_id` —
the **last workspace the user SELECTED in the UI** (written by
`set_current_workspace_id`, which accepts any workspace the user is a *member*
of). For an interactive user that is correct. For an **identity-attributed
headless/automation write** it is a cross-tenant-leak vector: if the operator
founder is ever a member of a shared/team workspace and their stale selection
points there, every nightly digest lands in that **team's** Today queue — and
the `is_workspace_member(workspace_id, auth.uid())` RLS INSERT policy **passes**,
because the operator legitimately IS a member. RLS is membership-checked, not
solo-ownership-checked, so it is structurally incapable of catching this.

## Solution

Pin the workspace by **identity**, not session-selection. For a solo founder the
solo workspace id equals the user id (ADR-038 N2: `workspaces.id = <user id>`),
so the headless write sets:

```ts
const tenant = await getFreshTenantClient(founderId); // mints role=authenticated, sub=founderId
const workspace_id = founderId;                       // solo-pin — NOT resolveCurrentWorkspaceId
```

RLS (`is_workspace_member(founderId, founderId)`) then becomes defense-in-depth,
not the sole guard. Verified against live prod: the operator founder has exactly
one membership (to its solo workspace) and `is_workspace_member(founderId,
founderId) = true`.

## Key Insight

`resolveCurrentWorkspaceId` answers "where is the user looking right now?", not
"who owns this data?". Any **identity-attributed write that is not driven by a
live interactive session** (cron, webhook, Inngest function, internal ingest
route) must resolve the workspace from the trusted identity, never from
session-selection state — and must never trust RLS membership as the
cross-tenant guard, because a legitimate multi-membership user passes it. The
unit test that proves this asserts `workspace_id === founderId` AND that
`resolveCurrentWorkspaceId` is never called.

**Corollary (GDPR Art. 17):** a discriminator CHECK that admits a draft-card row
must be `user_id`-free. Conversation-less cards are erased by
`messages.user_id REFERENCES auth.users ON DELETE CASCADE` (mig 046) on
account-delete — NOT by mig 068's in-place nulling, which only matches
attachment-bearing rows in a cross-user conversation. A `user_id`-anchored
branch would abort erasure with 23514 only if a future migration converted that
FK to `ON DELETE SET NULL`; keeping the branch user_id-free is the cheap
defensive choice. Verify a function's match condition for the specific row class
before citing its behavior in a load-bearing comment.

## Session Errors

1. **Agent types `repo-research-analyst` / `learnings-researcher` not found.** The Agent tool requires fully-qualified namespaced names. — Recovery: re-spawned as `soleur:engineering:research:repo-research-analyst` / `…:learnings-researcher`. — Prevention: copy the exact `subagent_type` from the Agent tool's available-agents list; soleur agents are namespaced `soleur:<domain>:<subdomain>:<name>`.
2. **`Edit` failed "File has not been read yet"** after viewing the file via Bash `cat -n`. — Recovery: used the Read tool, then Edit. — Prevention: a Bash view does not satisfy the Edit precondition; Read (the tool) before Edit even if already seen via Bash.
3. **Phase 0 prod probe errored: `column w.owner_user_id does not exist`.** Assumed `workspaces.owner_user_id`; the solo invariant is `workspaces.id = founderId` and `owner_user_id` lives on `organizations`. — Recovery: re-probed `information_schema.columns` for the `workspaces` shape, then queried `workspaces.id = founderId`. — Prevention: probe the table's actual columns (or read the CREATE TABLE migration) before writing a query against an assumed column.
4. **`vitest` EXIT=127 from wrong CWD.** The Bash tool does not persist `cd` across calls; the runner lives at `apps/web-platform/node_modules/.bin`. — Recovery: chained `cd apps/web-platform && ./node_modules/.bin/vitest …`. — Prevention: chain `cd <abs-path> && <cmd>` in one Bash call (existing work-skill rule).
5. **Push rejected (non-fast-forward).** A `git rebase origin/main` rewrote the SHAs of commits already pushed to the feature branch. — Recovery: confirmed the remote-only commits were just pre-rebase dupes of my own work (subject-level diff), then `git push --force-with-lease`. — Prevention: when rebasing a branch whose commits are already pushed, expect a force-with-lease; verify remote-only subjects match local before forcing.
6. **`github-on-event` test asserted `.code === '08006'` on the thrown error**, which broke after the refactor routed the insert through `insertDraftCard` (which re-throws a wrapped `Error` carrying the code in its message). — Recovery: changed the assertion to `rejects.toThrow(/08006/)`. — Prevention: when a refactor moves error handling into a helper that re-throws a wrapped Error, sweep existing tests asserting the original error's `.code`/shape and update to the new throw contract.
7. **Migration comment asserted a false mechanism** ("mig 068 anonymization nulls `user_id` on cards"). 068 only matches attachment-bearing rows in a cross-user conversation. — Recovery (caught by data-integrity-guardian review): corrected the comment to the real path (`ON DELETE CASCADE` erases conversation-less cards). — Prevention: before citing a function's behavior on a row class in a load-bearing comment, read the function's WHERE/match condition for that class.

## Tags
category: security-issues
module: web-platform/messages

---
title: "Dev Supabase now auto-creates the solo workspace on createUser; integration-test teardown must use anonymise_* RPCs (WORM)"
date: 2026-06-02
category: integration-issues
tags: [supabase, integration-test, workspace, worm, teardown, concurrency-slots]
related_prs: [4791]
related_issues: [4798]
related_migrations: [053, 059, 063, 087, 093]
---

# Learning: Dev Supabase auto-creates the solo workspace; integration teardown needs anonymise_* RPCs

## Problem

While writing a real-dev-Supabase integration test for the `acquire_conversation_slot`
4-arg fix (Sentry 23502, PR #4791), two schema-evolution facts broke the test
setup/teardown — both contradicting older in-repo comments:

1. **The mig-053 header comment is stale.** It states `handle_new_user` (mig 001)
   "does NOT touch organizations / workspaces / workspace_members" and that the TS
   signup fallback creates them. A later trigger now **auto-creates the solo
   organization + solo workspace (`workspaces.id = user.id`, ADR-038 N2) +
   owner membership + a `workspace_member_actions` WORM audit row** on a raw
   `service.auth.admin.createUser(...)`. A test `beforeAll` that synthesizes the
   solo workspace itself hits `23505 duplicate key value violates
   "workspaces_pkey"`.

2. **`deleteUser` teardown is blocked by an append-only WORM audit row.**
   `workspace_member_actions.{target_user_id, actor_user_id}` are `ON DELETE
   RESTRICT` FKs to `public.users`, and the table has a WORM trigger
   (`workspace_member_actions_no_mutate`) that rejects DELETE with `P0001`. So:
   - A direct `DELETE FROM workspace_member_actions` → `P0001` (WORM).
   - A direct `DELETE FROM workspace_members` → fires the audit trigger, which
     **re-creates** a `workspace_member_actions` row referencing the user → the
     subsequent `auth.users` delete stays FK-blocked (`23503`).

## Solution

For integration tests against dev that create a synthetic user:

- **Do NOT recreate the solo org/workspace/membership.** The new-user trigger
  already made them. Read the trigger-created workspace's `organization_id`
  (`select organization_id from workspaces where id = user.id`) and create only
  the *additional* fixtures you need (e.g. a distinct team workspace — a bare
  `workspaces` row suffices; `acquire_conversation_slot` is SECURITY DEFINER and
  only needs the FK target to exist, no membership row).

- **Teardown order (to let `deleteUser` succeed):**
  1. delete `user_concurrency_slots` / `conversations` by `user_id`
  2. `rpc("anonymise_workspace_members", { p_user_id })` — DELETEs membership
     with `SET LOCAL app.worm_bypass` so the audit trigger is suppressed
  3. `rpc("anonymise_workspace_member_actions", { p_user_id })` — NULLs the
     existing audit row's `actor/target_user_id` (mig 087, worm-bypass)
  4. delete the workspaces you created + the solo workspace (`id = user.id`)
  5. delete `organizations` by `owner_user_id`
  6. `auth.admin.deleteUser(user.id)`
  - Make `deleteUser` best-effort (warn, not throw) so a future trigger-added
    RESTRICT FK does not fail the whole suite on a teardown-only gap.

## Key Insight

In-repo comments about trigger behavior rot as migrations land. When an
integration test depends on what a DB trigger does on insert/delete, **verify the
live behavior empirically** (a `23505` on a "fresh" insert is the tell that a
trigger already populated the row) rather than trusting a header comment from the
migration that first introduced the trigger. Full user deletion on this schema is
a 12-step anonymise orchestration (`account-delete.ts`); tests that only need a
clean teardown can call the two `anonymise_*` RPCs that cover the rows the
new-user trigger creates.

See [[2026-05-22-tenant-integration-runtime-failures-post-mig-059]] for the
sibling NOT-NULL-vs-un-reissued-RPC class this fix belongs to.

## Session Errors

1. **Bash CWD reset after `bun add pg` in /tmp** — `bun add` reset the shell CWD;
   a later `cd apps/web-platform` failed (`No such file or directory`).
   **Recovery:** re-`cd` from the worktree root in the same call.
   **Prevention:** always `cd <worktree-abs-path> && <cmd>` in one Bash call;
   never rely on CWD persisting across tool calls (already a known rule — the
   `bun add` side-effect is the new wrinkle).
2. **Stale mig-053 comment → double-created solo workspace (`23505`).**
   **Recovery:** read the trigger-created workspace's org; create only the team
   workspace. **Prevention:** this learning.
3. **`deleteUser` blocked by WORM RESTRICT FK; two failed cleanup attempts.**
   **Recovery:** `anonymise_workspace_members` + `anonymise_workspace_member_actions`
   in that order before `deleteUser`. **Prevention:** this learning.
4. **New `getUserWorkspace` fail-loud guard broke 6 unit tests** that never seeded
   a workspace binding. **Recovery:** `setUserWorkspace("user-1","user-1")` in
   `beforeEach`. **Prevention:** when adding a fail-loud precondition to a
   server handler, grep the handler's existing test files for the entry path and
   seed the new precondition in their setup in the same change.
5. **AC8 contract-pair target was already dead** (stale `conversation-archive-release-slot`
   suite). **Recovery:** updated the helper for contract-alignment + filed #4798
   for the pre-existing staleness. **Prevention:** when a plan's contract-pair
   sweep names a file, run that file's suite against the real backend first to
   confirm it is live before assuming the one-line update makes it pass.
6. **Plan "File modified since read"** — a checkbox-marking script touched the plan
   between read and edit. **Recovery:** re-read before edit. **Prevention:** batch
   programmatic file mutations before manual edits, or re-read after any script
   that rewrites the file.

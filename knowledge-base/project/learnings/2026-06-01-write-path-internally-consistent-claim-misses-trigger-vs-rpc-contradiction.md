---
title: '"DB write path is internally consistent" misses BEFORE-trigger-vs-RPC contradictions — reproduce against the live DB'
date: 2026-06-01
category: database-issues
module: workspace-invitations
tags: [postgres, trigger, security-definer-rpc, root-cause, immutability, supabase, invite]
pr: 4745
---

# Learning: a plan's "write path is internally consistent end-to-end" claim missed a trigger-vs-RPC self-contradiction

## Problem

Every workspace-invite acceptance failed in prod with the generic UI error
"Something went wrong. Please try again." The accept flow is
`invite-actions.tsx → POST /api/workspace/accept-invite → acceptWorkspaceInvitation → accept_workspace_invitation RPC`.

The plan (after `/plan` + `/deepen-plan`) concluded the **migration source was
internally consistent end-to-end** and pinned the root cause on **live prod
schema/grant drift** (migration 085 not applied / lost `GRANT EXECUTE` / divergent
live RPC body — the classic 42703/42501 class). All three drift hypotheses were
**wrong**: read-only prod introspection confirmed 085 was applied, the RPC body
matched source byte-for-byte, the columns existed, and `service_role` had EXECUTE.

## Root cause

A self-contradiction **within migration 075 itself** (not drift):

1. `create_workspace_invitation` sets `workspace_invitations.attestation_id` at
   **creation** time (the inviter's attestation) — every invitation row has a
   non-NULL `attestation_id` from creation.
2. The `workspace_invitations_no_mutate` BEFORE-UPDATE trigger (075:144-148)
   raises `P0001 "attestation_id is immutable once set"` when
   `OLD.attestation_id IS NOT NULL AND NEW.attestation_id IS DISTINCT FROM OLD`.
3. `accept_workspace_invitation` did `UPDATE ... SET accepted_at = now(),
   attestation_id = <new acceptance attestation>` — re-pointing an
   already-non-NULL column → trips the trigger → **every accept failed
   deterministically** since 075 shipped.

The static per-function review missed it because each function looks correct in
isolation; the contradiction lives in the **interaction** between the create
RPC, the immutability trigger, and the accept RPC's `SET` list.

## Solution

Migration 090 (`CREATE OR REPLACE`, same `(uuid,uuid)` signature, rolling-deploy
safe) drops the `attestation_id` reassignment from accept's UPDATE — `SET
accepted_at = now()` only. The invitation keeps its creation attestation
(lineage); the acceptance attestation links only from `workspace_members`
(the membership-consent record). The trigger permits `accepted_at` NULL→NOT-NULL
(075:117), so the reduced UPDATE is allowed.

Also restored the 076 `not_intended_invitee` identity-binding check that 085 had
silently dropped, and added Sentry mirroring + reason-code copy mapping so the
next occurrence of this class is diagnosable instead of dark.

## Key Insight

**When a plan claims a DB write path is "internally consistent end-to-end,"
treat it as a hypothesis to falsify against the live DB, not a fact.** Two
concrete gates:

1. **Trigger-vs-RPC cross-check.** For every table an RPC writes, read every
   `BEFORE INSERT/UPDATE` trigger on that table and intersect the trigger's
   immutability/guard arms against the RPC's `SET`/column list. A column the
   trigger freezes that the RPC reassigns is a guaranteed runtime failure that
   no per-function read and no `tsc` will catch. Static "each function is fine"
   is insufficient when a trigger constrains what the function may write.
2. **Reproduce before remediating.** A read-only schema/grant introspection
   confirms-or-kills the drift hypotheses cheaply; a `BEGIN; SELECT rpc(...);
   ROLLBACK;` against the real failing row captures the actual SQLSTATE +
   message in seconds and is non-destructive. Both are far cheaper than shipping
   a speculative migration. Here the rolled-back repro turned a wrong "it's
   drift" plan into the exact `P0001 attestation_id is immutable` cause, and the
   same rolled-back transaction proved the fix unblocked the real prod invite.

Corollary: when re-issuing a `CREATE OR REPLACE` function body, diff it against
**every** prior definition (075 → 076 → 085), not just the latest — 085 silently
dropped 076's identity-binding check, a regression that rode forward invisibly.

## Session Errors

1. **Plan root-cause wrong (drift vs trigger contradiction).** Recovery:
   read-only prod introspection + rolled-back RPC repro found the real cause.
   Prevention: trigger-vs-RPC cross-check + live-DB repro before trusting an
   "internally consistent" claim (this learning).
2. **Plan missed the 076 identity-binding regression** dropped by 085. Recovery:
   data-integrity-guardian caught it at review; restored into 090. Prevention:
   diff a re-issued function body against all prior definitions, not just the
   previous one.
3. **Secret leak into transcript** — `doppler secrets get DATABASE_URL_POOLER |
   sed 's|postgres://...|'` used the wrong scheme (`postgresql://`), printing full
   connection strings with passwords. Recovery: stopped reprinting. Prevention:
   never echo connection strings; extract only host/ref with a verified filter,
   or compare refs via `SUPABASE_PROJECT_REF` (no embedded credential).
4. **Integration-test ordering hazard (caught pre-run)** — the identity
   negative-test first re-invited an already-accepted member (→
   `invitee_already_member`). Recovery: switched to a fresh synthetic email.
   Prevention: sibling integration tests sharing a `beforeAll` fixture must not
   depend on state a prior test mutated.
5. **Edit mismatch** on `invite-reason-messages.ts` (misremembered exact
   docstring text). Recovery: re-read + matched exact. Prevention: re-read prose
   written earlier in a long session before editing.
6. **Planning-subagent self-corrections (forwarded)** — a Write to the bare-root
   checkout was blocked by the worktree guard (redirected to worktree); two
   recalled learning-file citations didn't exist (replaced). Already handled.

## Tags
category: database-issues
module: workspace-invitations

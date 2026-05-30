# Learning: harden every consumer of a token/id-gated state, not just the read path

## Problem

feat-cancel-pending-invite (#4634) added owner-side soft-revoke of pending workspace
invites. The plan hardened `lookup_invitation_by_token` to return `reason:'revoked'`
and reasoned (in session-state) that "FR4 needs no accept-page edit" because the
token landing page renders a generic message on any `!result.ok`. That reasoning was
**incomplete**: the token landing page is the *presentation* gate, but the *mutation*
gate is a separate RPC (`accept_workspace_invitation`) reachable directly via
`POST /api/workspace/accept-invite` with the raw `invitationId`. The accept RPC only
checked `accepted_at`/`declined_at`/`expires_at` — never `revoked_at`. A raw-token
holder could therefore accept a **cancelled** invite and join the workspace, silently
defeating the feature's core guarantee ("a revoked invite's token can no longer be
accepted").

Two orthogonal review agents (architecture-strategist + pattern-recognition-specialist)
independently surfaced this as P1. Plan-time review and the per-AC grep gates missed it
because both looked only at the named read path.

## Solution

Re-issued `accept_workspace_invitation` in migration 085 with an `IF v_inv.revoked_at
IS NOT NULL THEN RETURN {ok:false, reason:'revoked'}` arm (after the declined check),
restored the 075 body in the down migration **before** the `DROP COLUMN`, mapped
`revoked` → 409 in the accept-invite route, and added an accept-after-revoke assertion
to the integration test.

## Key Insight

When you add a state column (`revoked_at`) that must gate access, grep for **every**
function/route/query that reads the gated entity by id or token — the presentation
read (`lookup_*`) and the mutation write (`accept_*`/`apply_*`/`consume_*`) are
usually distinct code paths reachable independently. Hardening one without the other
leaves a direct-API bypass that the UI hides. The cheapest gate: `git grep -n
'<entity>_id\|FROM <table>' apps/` and classify each hit as read-only vs
state-mutating; every mutating consumer needs the new gate.

## Session Errors

1. **Stale migration number in plan (083 vs 085).** Plan said next was 083; `origin/main`
   already had 083/084 merged after the worktree was cut. — Recovery: rebased onto
   origin/main, renumbered to 085. — **Prevention:** derive the next migration number
   from `git ls-tree origin/main -- apps/web-platform/supabase/migrations/`, never the
   bare-root/local index (which lags origin/main in this bare-repo setup).
2. **Plan prescribed a co-located component test path that vitest never discovers.**
   `components/settings/*.test.tsx` is invisible to `vitest.config.ts` (component project
   `include: ["test/**/*.test.tsx"]`). — Recovery: moved to `test/components/settings/`.
   — **Prevention:** verify any prescribed test path against the project's vitest
   `include` globs before writing the file.
3. **`accept_workspace_invitation` missed the `revoked_at` gate** (the P1 above). —
   Recovery: review-caught, fixed inline. — **Prevention:** the Key Insight above.
4. **`migration-rpc-grants.test.ts` false-positive on the WORM trigger fn.** Its regex
   misattributes a non-`SECURITY DEFINER` fn to the following fn's `SECURITY DEFINER`,
   demanding a REVOKE for it. — Recovery: re-asserted `REVOKE ALL ON FUNCTION
   workspace_invitations_no_mutate() ...` matching 075. — **Prevention:** when
   re-issuing via `CREATE OR REPLACE` a WORM/trigger fn that precedes a DEFINER fn in
   the same migration file, carry its REVOKE line forward.

## Tags
category: integration-issues
module: workspace-invitations

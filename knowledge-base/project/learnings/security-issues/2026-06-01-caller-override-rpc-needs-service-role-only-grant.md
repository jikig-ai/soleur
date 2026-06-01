# Learning: a SECURITY DEFINER caller-override param is ONLY safe behind a service_role-only grant

## Problem

Migration 091 added `rename_organization`, an owner-gated SECURITY DEFINER RPC. The
TS wrapper invokes it via `createServiceClient()` (service-role key), under which
`auth.uid()` is NULL — so a pure `auth.uid()` owner-gate (the mig 075
`transfer_workspace_ownership` shape) would `RAISE 28000` on every call. To make
the gate work, the RPC was given a caller-override parameter:

```sql
CREATE OR REPLACE FUNCTION public.rename_organization(
  p_organization_id uuid, p_name text, p_caller_user_id uuid DEFAULT NULL
) ... AS $$
  v_caller := COALESCE(p_caller_user_id, auth.uid());
  -- owner-gate on v_caller ...
$$;
GRANT EXECUTE ON FUNCTION public.rename_organization(uuid, text, uuid) TO authenticated;  -- BUG
```

This shipped through plan + work + the migration's own 16-test shape suite, all
green. **security-sentinel caught it at review as a P1:** because the override is
client-supplied AND `authenticated` could reach the RPC via PostgREST
(`POST /rest/v1/rpc/rename_organization`), any logged-in user could forge
`p_caller_user_id = <victim owner uuid>` and rename any organization — bypassing
the route's entire CSRF/flag/owner-check defense stack. Victim owner uuids are
discoverable via the peer-visible `workspace_members` select.

## Solution

Grant the RPC to `service_role` **only** (REVOKE from authenticated), mirroring
`accept_workspace_invitation` (mig 076/085) — the precedent the override pattern
was actually copied from:

```sql
REVOKE ALL ON FUNCTION public.rename_organization(uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rename_organization(uuid, text, uuid)
  TO service_role;
```

The sole caller is the trusted server wrapper (`createServiceClient()`), which
forwards the route's verified `getUser()` id. `authenticated`/`anon` can no longer
reach the forgeable override. A regression guard was added to the migration shape
test (`not.toMatch(/GRANT ... rename_organization ... TO authenticated/)`) and a
CI verify sentinel (`has_function_privilege('authenticated', ...) = false`).

## Key Insight

There are exactly two safe SECURITY DEFINER owner-gate shapes in this codebase, and
they form one rule, not a menu:

| Shape | Caller identity | Grant | Why safe |
|---|---|---|---|
| `transfer_workspace_ownership` (075) | pure `auth.uid()` (non-forgeable) | `TO authenticated` | the JWT `sub` cannot be forged |
| `accept_workspace_invitation` (076/085), `rename_organization` (091) | `COALESCE(p_caller_user_id, auth.uid())` (forgeable) | `TO service_role` only | the override is unreachable except via the trusted service-role server layer |

**The invariant: a function that accepts a forgeable caller-override param MUST be
service_role-only.** Mixing the override param (from one precedent) with
`GRANT TO authenticated` (from the other) is a privilege-escalation primitive. When
copying a SECURITY DEFINER precedent, copy BOTH halves — the identity source AND the
grant scope are a matched pair.

Corollary surfaced in the same review: `transfer_workspace_ownership` itself may be
latently broken — pure `auth.uid()` under its service-role wrapper means
`auth.uid()` is NULL → 28000 on every call. Filed as #4765 for verification (the
reason 091 correctly diverged from the 075 shape).

## Tags
category: security-issues
module: apps/web-platform/supabase/migrations

## Session Errors

1. **P1 owner-gate bypass self-introduced** (forgeable override + `GRANT TO authenticated`) — Recovery: grant to `service_role` only + regression test + verify sentinel. Prevention: when adopting a caller-override SECURITY DEFINER pattern, copy the grant scope from the SAME precedent as the param, never mix.
2. **Bash CWD drift across calls** — the harness persists shell CWD; it flipped between worktree root and `apps/web-platform`, causing `apps/web-platform/apps/web-platform/` path errors and missing `./node_modules/.bin/vitest`. Recovery: re-anchor. Prevention: prefix every Bash call with an absolute `cd <worktree>/apps/web-platform &&`.
3. **tsc errors after rename refactor** (missed `trimmed`→`validated.trimmed` in the route success return; untyped fetch mock zero-arg tuple) — Recovery: fix references + type the mock signature. Prevention: run pinned `./node_modules/.bin/tsc --noEmit` after every rename/extract refactor (the gate caught it pre-commit).
4. **psql unavailable locally** — QA DB-verify could not run directly. Recovery: graceful degradation to the CI verify sentinel (the no-eyeball automated mechanism). Not a defect; no prevention needed.

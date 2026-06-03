---
category: bug-fixes
module: web-platform/api/workspace/delegations
tags: [supabase, postgrest, rpc, byok-delegations, silent-failure, named-arguments]
---

# Learning: PostgREST `rpc()` named-arg mismatch fails resolution → 400 → silent client revert

## Problem

The "Share a key" toggle on Settings → Members → Team did nothing when an org owner
clicked it: the toggle flipped back to off, no delegation was created, no error shown.

`POST /api/workspace/delegations` called the SECURITY DEFINER RPC `grant_byok_delegation`
with named arguments that did not match migration 064's signature, and omitted a required
one:

```ts
// broken
service.rpc("grant_byok_delegation", {
  p_grantor_user_id, p_grantee_user_id, p_workspace_id,
  p_daily_cap_cents,        // RPC expects p_daily_usd_cap_cents
  p_hourly_cap_cents,       // RPC expects p_hourly_usd_cap_cents
  p_created_by_user_id,     // RPC expects p_actor_user_id
  // MISSING: p_expires_at (required, no DEFAULT)
});
```

## Root cause

PostgREST resolves `rpc()` calls by the **set of supplied argument names**. A name set
that doesn't match any function overload fails to resolve (PGRST202 "Could not find the
function … in the schema cache"). The route mapped that error to HTTP 400, and the client
(`delegation-toggle.tsx`) only flipped state `if (res.ok)` — so on a 400 it did nothing and
never reset, producing the silent "click does nothing" revert.

Two compounding silencers:
- `tsc` cannot catch it — supabase-js `.rpc(name, params)` takes an untyped params object.
- The client swallowed the non-OK response with no error path.

## Solution

1. **Caller-only fix.** Align the route's named args to the canonical 7-arg 064 contract,
   already proven by `scripts/byok-grant.ts:173-180`: `p_daily_usd_cap_cents`,
   `p_hourly_usd_cap_cents` (defaulting to the daily cap — the RPC rejects NULL hourly with
   `22003` and the UI exposes only a daily stepper), `p_expires_at: null` (never expires),
   `p_actor_user_id: user.id`. No migration/schema/RPC change.
2. **Pin the contract in a test.** New `test/api-delegation-grant-route.test.ts` asserts
   `toHaveBeenCalledWith` the exact 7-key arg object + negative `not.toHaveProperty` on the
   three broken legacy names. Confirmed RED against the broken route, GREEN after.
3. **Stop the silent swallow.** `delegation-toggle.tsx` `handleToggle` now surfaces non-OK
   responses AND a thrown `fetch` (offline/DNS/TLS) via `console.error` + `window.alert`,
   matching `team-membership-list.tsx`'s remove-member pattern.

## Key Insight

A `.rpc()` call against an untyped supabase client is an **unchecked stringly-typed contract**
across the TS↔Postgres boundary — same class as untyped `.select()` against a nonexistent
column (`2026-06-01-untyped-supabase-select-nonexistent-column-ships-green.md`). When you add
or edit a route `.rpc()` call, pin the exact arg-name set in a `toHaveBeenCalledWith` test and
cross-check it against the migration body and any proven sibling caller — neither `tsc` nor a
select-arg-discarding mock will catch a name drift, and a client that only acts on `res.ok`
turns the resulting 400 into an invisible no-op.

Corollary: any client write handler whose only success path is `if (res.ok)` MUST have an
`else` AND a `catch` — a thrown fetch bypasses the `!res.ok` branch entirely.

## Session Errors

1. **Bash CWD drift** — `cd apps/web-platform` returned `No such file or directory` because
   the Bash tool's working directory had already moved into `apps/web-platform` from a prior
   call (CWD persists across Bash tool calls; shell state like env vars does not).
   **Recovery:** re-ran the command from the already-correct CWD; no work lost.
   **Prevention:** already covered by the work skill's guidance to chain `cd <worktree-abs> &&
   <cmd>` in a single Bash call with absolute paths rather than relying on prior CWD. One-off;
   no new rule warranted.

## Tags
category: bug-fixes
module: web-platform/api/workspace/delegations

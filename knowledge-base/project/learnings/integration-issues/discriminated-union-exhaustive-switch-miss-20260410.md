---
module: WebSocket Protocol
date: 2026-04-10
problem_type: integration_issue
component: tooling
symptoms:
  - "TypeScript compile error after adding variant to discriminated union"
  - "Exhaustive switch in ws-handler.ts not updated for new usage_update type"
  - "SECURITY DEFINER function callable by any authenticated user via PostgREST"
root_cause: incomplete_setup
resolution_type: code_fix
severity: high
tags: [typescript, discriminated-union, exhaustive-switch, security-definer, supabase, rpc]
---

# Learning: Check all type consumers when modifying discriminated unions

## Problem

When adding a `usage_update` variant to the `WSMessage` discriminated union in `lib/types.ts`, the exhaustive type switch in `ws-handler.ts` was not updated. This would have caused a TypeScript compilation failure (`Type '{ type: "usage_update"; ... }' is not assignable to type 'never'`). The bug was caught by the security-sentinel review agent, not during implementation.

Additionally, the `increment_conversation_cost` SQL function was created with `SECURITY DEFINER` but without `REVOKE`/`GRANT` statements. By default in Supabase, all functions are executable by `authenticated` and `anon` roles via PostgREST, meaning any authenticated user could call the RPC on any conversation — including other users' conversations — with arbitrary values including negative deltas.

## Root Cause

1. **Union type consumers not audited:** Adding a variant to a TypeScript discriminated union requires updating ALL `switch` statements that exhaustively match on it. The agent-runner, ws-client, and ws-handler all switch on `WSMessage.type`, but only the first two were updated.

2. **Supabase default permissions:** PostgreSQL functions default to `EXECUTE` granted to `PUBLIC`. In Supabase, this maps to `anon` and `authenticated` roles. `SECURITY DEFINER` compounds the risk by running as the function owner (bypassing RLS).

## Solution

### Union type changes

After modifying any discriminated union, grep for exhaustive switches:

```bash
grep -rn "const _exhaustive: never" apps/web-platform/
```

This finds all exhaustive type narrowing patterns that will break if a new variant is unhandled.

### SECURITY DEFINER functions

Always pair with access restriction:

```sql
CREATE OR REPLACE FUNCTION my_rpc(...) RETURNS VOID AS $$
BEGIN
  -- validation
  IF delta < 0 THEN RAISE EXCEPTION 'must be non-negative'; END IF;
  -- logic
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

-- Restrict to service_role only
REVOKE EXECUTE ON FUNCTION my_rpc(...) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION my_rpc(...) FROM authenticated;
REVOKE EXECUTE ON FUNCTION my_rpc(...) FROM anon;
GRANT EXECUTE ON FUNCTION my_rpc(...) TO service_role;
```

## Key Insight

When modifying a shared type (union, enum, interface), the implementation site is only one consumer. Every file that switches, maps, or narrows on that type must be updated. The TypeScript compiler catches exhaustive switches, but only if you compile before committing. Review agents catch what local testing misses when the compile step is skipped.

For Supabase RPC functions, the secure-by-default assumption is wrong: functions are public by default. `SECURITY DEFINER` + no `REVOKE` = any authenticated user can escalate privileges.

## Session Errors

1. **Missed ws-handler.ts exhaustive switch** — Added `usage_update` to WSMessage union without grepping for exhaustive switches. Recovery: caught by security-sentinel review agent, fixed immediately. **Prevention:** After modifying any discriminated union type, grep for `const _exhaustive: never` across the codebase before committing.

2. **SECURITY DEFINER without access control** — Created RPC function without REVOKE/GRANT. Recovery: caught by data-integrity-guardian and security-sentinel, fixed by adding REVOKE from PUBLIC/authenticated/anon and GRANT to service_role only. **Prevention:** Add a checklist item to the migration template: every SECURITY DEFINER function must include REVOKE/GRANT.

3. **Missing NOT NULL on financial columns** — Created nullable columns with DEFAULT 0, allowing potential NULL arithmetic propagation (`NULL + N = NULL`). Recovery: added NOT NULL constraints in review fix. **Prevention:** Default to NOT NULL for numeric columns unless there is an explicit reason for nullability.

4. **Awaited non-critical RPC in hot path** — Used `await` on a fire-and-forget telemetry call, adding 20-80ms latency per turn completion. Recovery: converted to `.then()` pattern. **Prevention:** Before awaiting any new async call, ask: "Does the caller need the result?" If not, fire-and-forget with `.then()` error logging.

5. **Null dereference on nullable column** — Called `.toUpperCase()` on `domain_leader` which is nullable since migration 010. Recovery: added optional chaining with fallback. **Prevention:** When consuming database columns in frontend code, check the migration history for nullability — TypeScript types may not reflect database reality.

## Prevention

- Grep for exhaustive switches (`const _exhaustive: never`) after modifying any discriminated union
- Every Supabase `SECURITY DEFINER` function must include `REVOKE` from PUBLIC/authenticated/anon and explicit `GRANT` to the intended role
- Add `NOT NULL` and `CHECK` constraints to financial/numeric columns by default
- Classify async operations as blocking vs. telemetry — only `await` blocking operations

## Tags

category: integration-issues
module: WebSocket Protocol

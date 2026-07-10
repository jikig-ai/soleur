---
title: Supabase default privileges leave residual anon/authenticated EXECUTE grants that `revoke ... from public` never removes
date: 2026-07-10
category: security-issues
tags: [supabase, rls, security-definer, grants, rls-fuzz]
issues: [6256, 6306]
---

## Pattern

A migration that intends "service-role-only" access to a `SECURITY DEFINER`
function by doing:

```sql
revoke all on function public.<fn>(...) from public;
grant execute on function public.<fn>(...) to service_role;
```

is **insufficient**. Supabase configures DEFAULT PRIVILEGES so every new function
in `public` is granted EXECUTE to `anon`, `authenticated`, AND `service_role` at
`CREATE` time. `revoke ... from public` removes only the PUBLIC grant — the
**explicit** `anon`/`authenticated` grants survive. Live `proacl` shows
`{...,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`.

If the function also trusts a caller-supplied tenancy param (`p_user_id`,
`p_workspace_id`) without re-deriving `auth.uid()` authorization, ANY authenticated
(often anon) user can invoke it cross-tenant — a bypass invisible to base-table
RLS (the definer rights bypass RLS on the underlying tables).

## Detection & fix

- Detection: the runtime RLS-fuzz harness (#6256, ADR-111) RPC dimension drives
  every `SECURITY DEFINER` + authenticated-EXECUTE fn with tenant-B claims +
  tenant-A params; a clean return / non-empty result = a bypass. `find_stuck_
  active_conversations` + `acquire/release/touch_conversation_slot` were found
  this way (#6306).
- Fix: `revoke execute on function public.<fn>(...) from anon, authenticated;`
  and add a `verify/NNN_*.sql` sentinel asserting
  `has_function_privilege('authenticated', ...) = false`.
- Audit the whole class: any definer fn whose migration granted `service_role`
  only (never `authenticated`) yet `has_function_privilege('authenticated', …)`
  is true is a candidate.

## Harness false-green classes fixed at review (same PR)

- RPC `any-throw = denied` masks signature drift (42883) / validation-before-auth
  → SQLSTATE-classify: denial = only {42501, P0001, P0002}.
- Getter attacks whose default value equals the denial sentinel (null/false) →
  poison the seed (truthy values) + add an RPC positive control.
- Predicate-based table enumerator (`is_workspace_member` literal) misses tables
  isolated by a different predicate → enumerate the broader `workspace_id`/
  `message_id` surface, require target-or-excluded-with-rationale.

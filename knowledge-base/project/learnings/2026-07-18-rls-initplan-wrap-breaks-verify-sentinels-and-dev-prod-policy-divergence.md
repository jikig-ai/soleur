---
title: An RLS auth_rls_initplan wrap breaks exact-string verify/ sentinels AND needs IF-EXISTS for dev/prod policy divergence
date: 2026-07-18
category: database-issues
module: apps/web-platform/supabase/migrations, apps/web-platform/supabase/verify
tags: [supabase, rls, migration, auth_rls_initplan, verify-migrations, dev-prod-divergence]
issue: null
pr: 6663
---

## Problem

A semantics-preserving RLS optimization — wrapping `auth.uid()` → `(select auth.uid())` in
`WITH CHECK`/`USING` for InitPlan hoisting (migration 134 of PR #6663) — passed the full local
suite, 8-agent review, and preflight, but produced **two distinct post-merge failures** that only
surfaced against the live dev and prod databases:

1. **`verify-migrations` FAILED (release workflow, gated `deploy=skipped`).**
   `verify/129_rls_write_check_workspace_member.sql` (the #6334 sentinel) asserts
   `with_check ILIKE '%user_id = auth.uid()%'`. Wrapping the owner-binding made pg_policies deparse it
   as `user_id = ( SELECT auth.uid() AS uid)`, so the exact-substring match no longer hit — even
   though the security-critical `is_workspace_member(...)` conjunct SURVIVED the wrap (verified
   live-present on prod). The sentinel spelling was stale, not the policy.

2. **Migration 134 apply FAILED on dev (`tenant-integration`):**
   `policy "conversations_owner_delete" for table "conversations" does not exist`. The policy NAMES
   were sourced from PROD's live `pg_policies`, but dev and prod are DISTINCT Supabase projects
   (`hr-dev-prd-distinct-supabase-projects`) whose RLS state had DIVERGED — `conversations_owner_delete`
   exists on prod but not on the CI dev DB (075 creates it; no forward migration drops it; dev drifted
   out-of-band). `ALTER POLICY` has no `IF EXISTS`, so a single absent policy aborts the whole migration.

## Solution

- **Guard every `ALTER POLICY` with a `pg_policies` existence check** so the migration applies across
  divergent projects: `DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND
  tablename=... AND policyname=...) THEN ALTER POLICY ...; END IF; END $$;`. Where the policy is absent,
  the wrap no-ops (a perf optimization has nothing to optimize); where present, it wraps as intended.
  On prod all targets exist so every wrap applies.
- **Make the paired verify sentinel wrap-tolerant.** Replace the exact `ILIKE '%user_id = auth.uid()%'`
  with a regex that matches BOTH forms while preserving the anti-false-green prefix:
  `with_check ~* 'user_id = \(? *(select +)?auth\.uid\(\)'`. Verify the fixed sentinel against **live
  prod** (`/database/query`, read-only) before shipping — all checks must return `bad=0`.

## Key Insight

**A migration that changes an RLS policy's DEPARSED EXPRESSION (an initplan wrap, a predicate rewrite,
a role/qual edit) has TWO blast radii beyond the policy itself, both invisible to the local test
suite:** (a) every `apps/web-platform/supabase/verify/*.sql` sentinel that STRING-MATCHES that policy's
`qual`/`with_check` breaks — sweep `git grep -l "<policyname>" apps/web-platform/supabase/verify/`
and update each to match the new deparse (or make it wrap-tolerant); and (b) the migration must be
robust to dev/prod policy-set divergence — `ALTER POLICY` on a name sourced from ONE project's live
catalog fails on the other, so guard with `pg_policies IF EXISTS`. Neither is caught by tsc, the
vitest suite, or the migration-shape lints — only by `verify-migrations` (against prod) and
`tenant-integration` (against dev), i.e. POST-MERGE. The review-time defense is to grep `verify/` for
the touched policy names and to default RLS `ALTER POLICY` migrations to `IF EXISTS` guards.

## Session Errors

- **`verify-migrations` failed post-merge** (RLS-wrap broke `verify/129`'s exact string-match). Recovery:
  wrap-tolerant regex, verified live-prod `bad=0`, hotfix PR #6671. **Prevention:** when a migration edits
  an RLS policy expression, `git grep -l "<policyname>" apps/web-platform/supabase/verify/` and update
  each stale sentinel in the SAME PR.
- **Migration 134 apply failed on dev** (conversations_owner_delete absent — dev/prod RLS divergence).
  Recovery: `pg_policies IF EXISTS` guard on all 18 ALTERs. **Prevention:** default RLS `ALTER POLICY`
  migrations to existence-guarded `DO` blocks; policy names sourced from one project's live catalog are
  not guaranteed present in the other.
- **ADR-ordinal collision** — a sibling landed `ADR-123-web-host-private-nic` during the ~90-min pipeline;
  the Phase-7 BEHIND auto-sync pulled it in. Recovery: renumbered ours 123→124 + swept feature-scoped
  refs. **Prevention:** already covered by the ship ADR-ordinal gate + Phase-7 re-check; fired as designed.
- **Transient `canary_sandbox_failed` deploy flake** — first deploy failed with `reason=canary_sandbox_failed`
  while `sandbox_canary.verdict=pass` + container_exit_code 0 + prod /health 200; re-run succeeded.
  **Prevention:** a contradictory canary verdict (top-level failed, sub-verdict pass) with a healthy
  container is a deploy-verification flake — re-run once before treating it as a code regression.

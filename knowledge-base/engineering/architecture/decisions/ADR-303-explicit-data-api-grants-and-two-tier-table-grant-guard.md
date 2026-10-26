---
title: Explicit per-relation Data API grants + two-tier table-grant guard (live-catalog gate authoritative, PR-diff lint subordinate)
status: accepted
date: 2026-10-26
amends: none
supersedes: none
related: [4027, 4647, 6340]
related_adrs: [ADR-111, ADR-112, ADR-153]
brand_survival_threshold: single-user incident
---

# ADR-303: Explicit per-relation Data API grants and the two-tier table-grant guard

## Context

On 2026-10-30 Supabase stopped auto-granting Data API access (PostgREST /
supabase-js / GraphQL) to new tables in the `public` schema of existing projects
(changelog 45329). Relations created after the flip — and every relation on an
environment built by replaying the migration corpus (new projects, preview
branches, `supabase db reset`, the rls-authz-fuzz stack) — return 42501
permission-denied to `anon`/`authenticated`/`service_role` unless a migration
grants them explicitly.

This repo's corpus had partial, inconsistent coverage: 42 up-migrations create
tables but only 14 carried api-role grants, because Supabase's platform defaults
had been silently materializing them. Effective privileges also compose
defaults + GRANT + REVOKE and are not reconstructable from migration source
text.

## Decision

1. **Explicit per-relation grants are the convention.** Every `public`-schema
   Data-API-reachable relation (table, view, materialized view, sequence)
   carries its api-role `GRANT`s in the migration that creates it, or a
   `soleur:no-data-api:` sentinel with a reason. A `REVOKE`-free snapshot
   migration (`174_api_data_grants_snapshot.sql`, generated from the live prd
   catalog via `scripts/dump-api-grants.ts`) backfills the existing corpus so a
   fresh replay reproduces prd's effective posture exactly — no widening, no
   narrowing.
2. **Two-tier guard, mirroring ADR-112's split:** the *authoritative* tier is a
   live-catalog runtime gate (`test/rls-fuzz/rls-grants.integration.test.ts` +
   the `table-grants.ts` classification registry) asserting
   `has_table_privilege`/`has_column_privilege`/`has_sequence_privilege` state
   with catalog⇔registry parity on the fuzz stack; the *subordinate* tier is a
   PR-diff static lint (`scripts/lint-migration-api-grants.sh --from-pr-diff`
   in `tenant-integration.yml`) that fails fast pre-DB.
3. **Local-stack parity via `supabase-local.sh` post-start normalize**, not the
   `[api] auto_expose_new_tables` config key: that key was added by
   `supabase/cli#5239` (merged 2026-05-26) and does not exist on pinned CLI
   2.84.2 (2026-03-25). All local+CI starts funnel through the wrapper, so one
   normalize step models the post-flip world. **On any future bump to CLI
   >=v2.116.0 the swap to `[api] auto_expose_new_tables = false` becomes
   REQUIRED** — per #6337, unset re-enables auto-expose there; the declarative
   key then replaces the normalize step.
4. **`ALTER DEFAULT PRIVILEGES … GRANT` to restore auto-expose is rejected**:
   it re-opens the exact over-exposure Supabase is closing (every internal
   table becomes API-granted under RLS), contradicts #4027's narrowing
   direction, and ADR-112 established that a mis-scoped ADP under
   `supabase_admin` is a silent no-op (the #6340 live probe auto-closed stale
   2026-10-10 and never ran — no validated ADP path exists).

## Consequences

- prd is unchanged by construction: 174 re-declares already-effective
  privileges (`verify/174` asserts effective-vs-expected post-apply).
- A future create-table migration without grants fails in CI before merge —
  statically (lint) and at runtime (fuzz gate on a defaults-off stack).
- Per-relation narrowing of default-era grants (e.g. `users` carrying
  table-level UPDATE despite 006's column-split intent) is deferred to a
  follow-up issue paired with #4027 — narrowing under a remediation banner is
  the #4647 silent-failure class and changes prd behavior.
- The `.down.sql` for 174 is a documented no-op: REVOKE cannot distinguish
  grant provenance and would strip default-era effective access on prd.

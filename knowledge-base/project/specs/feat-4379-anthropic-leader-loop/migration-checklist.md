---
title: "Migration 069 apply + verify (PR-B)"
date: 2026-05-25
issue: 4379
migration: 069_action_sends_leader_loop.sql
env: dev
---

# Migration 069 apply checklist — dev Supabase

Renumbered from `067_action_sends_leader_loop.sql` (plan-time ordinal) after the Phase 8.1 collision check revealed `origin/main` had already taken 067 (`067_workspace_member_revocation_lookup.sql`) and 068 (`068_jti_deny_rls_predicate_and_revoke_rpc.sql`) between plan authorship and /work resume.

## Pre-apply collision check

```
$ git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | \
    awk '{print $4}' | grep -oE '^apps/web-platform/supabase/migrations/[0-9]{3}' | sort -u | tail -3
apps/web-platform/supabase/migrations/063
apps/web-platform/supabase/migrations/064 (× 5 — same-window sibling PRs)
apps/web-platform/supabase/migrations/065
apps/web-platform/supabase/migrations/066
apps/web-platform/supabase/migrations/067  ← collides
apps/web-platform/supabase/migrations/068  ← collides
```

Next free ordinal: **069**.

## Apply path (per hr-dev-prd-distinct-supabase-projects fallback chain)

Supabase MCP unavailable in this session → fell through to Doppler `DATABASE_URL_POOLER` (dev) → rewrote `:6543/` (transaction-mode) to `:5432/` (session-mode) to admit multi-statement DDL.

```
$ doppler run -p soleur -c dev -- bun /tmp/apply_mig069.mjs
content_sha: 81c21eb1be3abfc2377855d4bea0631e559d47e6
Applied 069_action_sends_leader_loop.sql successfully
```

The apply script writes the migration body + `INSERT INTO public._schema_migrations (filename, content_sha) VALUES (...)` in the same transaction (matches `apps/web-platform/scripts/run-migrations.sh` convention).

## Post-apply schema verification

```
$ doppler run -p soleur -c dev -- bun /tmp/verify_mig069.mjs
New columns:
  cancellation_requested_at      timestamp with time zone  nullable=YES
  current_turn                   smallint                  nullable=YES
  current_turn_started_at        timestamp with time zone  nullable=YES
  prompt_version                 text                      nullable=YES
  reversal_handles               jsonb                     nullable=YES
  undone_at                      timestamp with time zone  nullable=YES

_schema_migrations row: {
  filename: "069_action_sends_leader_loop.sql",
  content_sha: "81c21eb1be3abfc2377855d4bea0631e559d47e6",
}
```

All 6 columns present, all nullable, types match AC3 spec. Tracker row written with `content_sha = git hash-object <file>`.

## PostgREST cache reload

Deferred — PostgREST polls schema every ~10 min, and `NOTIFY pgrst, 'reload schema'` over a `:5432` pooler connection does NOT reach PostgREST's `LISTEN` (PgBouncer multiplex). Natural poll cycle catches the new columns within 10 min; no operator action required.

## Static-shape test

`apps/web-platform/test/supabase-migrations/069-action-sends-leader-loop.test.ts` — 13 tests, all pass (read SQL as text + assert AC3 shape).

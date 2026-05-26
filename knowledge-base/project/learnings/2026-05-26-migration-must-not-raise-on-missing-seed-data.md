---
title: "Migrations must degrade gracefully when seed-data rows are absent"
date: 2026-05-26
type: learning
pr: 4463
tags: [migration, ci, tenant-integration, bot-fixture, seed-data]
---

# Migrations must degrade gracefully when seed-data rows are absent

## Problem

Migration `071_ux_audit_artifacts_bucket.sql` used `RAISE EXCEPTION` when
`ux-audit-bot@example.test` was not found in `auth.users`. This caused the
`tenant-integration` CI workflow to fail on EVERY PR that touched migrations,
because the CI env applies migrations to dev-Supabase where the bot user
may not have been seeded yet.

The failure blocked the merge of unrelated PRs and was a recurring source
of CI red across the team.

## Solution

1. Changed `RAISE EXCEPTION` to `RAISE NOTICE` + `RETURN` — the bucket
   still creates (self-contained DDL), the RLS policy is deferred until
   the bot user is seeded.
2. Added a `Seed bot fixtures (pre-migration)` step to
   `tenant-integration.yml` that runs `bot-fixture.ts seed` before
   migration apply (with graceful fallback on failure).

## Key Insight

Migrations must be self-contained or degrade gracefully. A migration that
`RAISE EXCEPTION` on missing seed data is a CI landmine — it blocks ALL
subsequent migrations for ALL PRs, not just the one that introduced the
dependency.

**Rule:** When a migration references rows from `auth.users` or any seed-
populated table, use `RAISE NOTICE` + `RETURN` (skip the dependent DDL)
instead of `RAISE EXCEPTION`. Document the deferred dependency in the
migration header. The CI workflow seeds fixtures before apply, but the
migration must not hard-fail if the seed hasn't run.

## Prevention

- Plan-time: `/soleur:plan` should flag any migration that contains
  `RAISE EXCEPTION` + `auth.users` lookup as a seed-dependency risk
- CI: `tenant-integration.yml` now seeds bot fixtures before migration apply
- Migration authoring: use `RAISE NOTICE` + `RETURN` for graceful skip

---
date: 2026-05-06
category: best-practices
tags: planning, code-review-overlap, supabase, multi-env, management-api
source_session: feat-supabase-disk-io-budget plan-stage compound
related_pr: 3356
related_issue: 3358
---

# Learning: Verify cross-env state before treating an open issue as a plan blocker

## Problem

During Phase 1.7.5 of the plan skill (open code-review issue overlap check), the `feat-supabase-disk-io-budget` plan flagged issue **#3370** ("Dev Supabase `_schema_migrations` drifts — 034/035 applied untracked, 036 unapplied") as a candidate blocker. The issue's framing strongly implied that any new migration would fail when `run-migrations.sh` re-applied the un-tracked 034 (publication membership exists → idempotent guards probably hold) and especially 035 (CREATE INDEX without `IF NOT EXISTS` → would error on duplicate index).

The default temptation was to fold #3370's reconciliation into this PR (`INSERT INTO _schema_migrations ... ON CONFLICT DO NOTHING` for 034 + 035 + 036) so the new migration 038/039 could land cleanly. That would have crossed scope, made the PR larger, and triggered the cross-cutting-refactor scope-out criterion.

## Solution

Query the cross-env state directly before treating the issue as a constraint. The Supabase Management API exposes `_schema_migrations` via the `/database/query` endpoint:

```bash
SUPA_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
REF=ifsccnjhymdmidffkzhl
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  "https://api.supabase.com/v1/projects/$REF/database/query" \
  -d '{"query": "SELECT filename, applied_at FROM public._schema_migrations ORDER BY applied_at DESC LIMIT 12"}'
```

Result: prod's `_schema_migrations` was clean — 034 / 035 / 036 / 037 all tracked, applied chronologically. The drift was **dev-only**. The plan could mention #3370 as a developer-ergonomics risk (Risks #1) without folding in any reconciliation. The PR scope stayed at 2 migrations + 1 test file.

## Key Insight

Many "drift" issues are env-specific. The cost of a 30-second Management API call is trivial compared to the cost of unnecessarily expanding PR scope. **Default rule:** when an open issue is flagged as a possible blocker for a plan, query the production-side state directly via the relevant Management API or Doppler before treating the issue as a constraint. If prod is clean, the issue is dev-ergonomics and can be acknowledged in Risks without fold-in.

This generalizes beyond Supabase to any vendor with a read-only management API (Cloudflare zone state, Stripe product state, GitHub repo state, etc.). The pattern composes with `hr-exhaust-all-automated-options-before` — Doppler-stored access token + REST is already the priority-1 path.

## When this applies

- Plan-stage Phase 1.7.5 returns an overlap on a "drift" / "tracking" / "consistency" / "out-of-band-applied" issue.
- The issue's body says "future X is unsafe" but the unsafe condition depends on env state.
- The cost of fold-in is meaningful (extra migration body, extra reviewer surface) AND the cost of API verification is trivial (single curl).

## Tags

category: best-practices
module: plan-skill
vendor: supabase, cloudflare, stripe, github
relates: hr-exhaust-all-automated-options-before, plan-skill Phase 1.7.5

---
lane: procedural
plan: knowledge-base/project/plans/2026-06-14-fix-supabase-disk-io-github-events-retention-window-plan.md
issue: 5225
migration: 103
---

# Tasks — fix Supabase Disk-IO: processed_github_events retention 90d → 7d

Plan: `knowledge-base/project/plans/2026-06-14-fix-supabase-disk-io-github-events-retention-window-plan.md`

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 Re-confirm migration 103 is free on origin/main:
  `git fetch origin main -q && git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/ | grep -oE '10[0-9]_' | sort -u` → must show `100_ 101_ 102_`, NOT `103_`.
- [x] 0.2 Re-confirm `received_at` + `processed_github_events_received_at_idx` exist (`052_multi_source_dedup.sql:128,136`); `created_at` does NOT exist.
- [x] 0.3 Re-confirm no WORM trigger on `processed_github_events` (the 052 WORM trigger is on `audit_github_token_use`).

## Phase 1 — Migration 103 (RED test first)

- [x] 1.1 Write `apps/web-platform/test/supabase-migrations/103-github-events-retention-7day.test.ts` mirroring `094-dedup-retention.test.ts` (stripComments + regex). Assertions (7):
  1. `cron.unschedule('processed_github_events_retention')` guard present
  2. `cron.schedule('processed_github_events_retention', '0 4 * * *', …)`
  3. scheduled DELETE uses `received_at` + `interval '7 days'` (NOT 90)
  4. one-time top-level `DELETE FROM public.processed_github_events WHERE received_at < … interval '7 days'`
  5. does NOT reference `created_at`
  6. down restores `interval '90 days'`
  7. up contains `COMMENT ON TABLE public.processed_github_events` that does NOT mention "partition rotation"
  Run it RED (file not yet created): `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/103-github-events-retention-7day.test.ts`
- [x] 1.2 Write `apps/web-platform/supabase/migrations/103_github_events_retention_7day.sql`:
  - `DO $cron_block$ … cron.unschedule guard … cron.schedule('…', '0 4 * * *', $$DELETE … received_at < now() - interval '7 days'$$) … EXCEPTION WHEN duplicate_object THEN NULL; END $cron_block$;` — mirror 094 dollar-quoting exactly.
  - One-time top-level `DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days';`
  - `COMMENT ON TABLE public.processed_github_events IS …` correcting the stale 052 "partition rotation" claim → actual mechanism (daily pg_cron 7-day sweep; 3-day github.com redelivery horizon; service-role-only).
  - Header comment: 3-day GitHub horizon + 24h Inngest layer + `--single-transaction` note + plan path.
- [x] 1.3 Write `apps/web-platform/supabase/migrations/103_github_events_retention_7day.down.sql`:
  - Restore the 90-day schedule (same idempotent shape, `interval '90 days'`); lossy (no row restore).
  - Header warning: down re-arms the bloat / recreates #5225 — framework-reversibility only, never an incident rollback.
- [x] 1.4 Run the shape-test GREEN.

## Phase 2 — Monitor message clarity (no test edit)

- [x] 2.1 Edit `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts` — widen the dedup-over-ceiling reason string to name both modes (sweep stopped OR window too long). Keep `${table}=` interpolation so `processed_github_events` stays in the reason.
- [x] 2.2 Confirm no test edit needed: `./node_modules/.bin/vitest run test/server/inngest/cron-supabase-disk-io.test.ts` stays GREEN (asserts `/processed_github_events/`, not the literal).

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/103-github-events-retention-7day.test.ts test/server/inngest/cron-supabase-disk-io.test.ts` — all GREEN.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.

## Phase 4 — Ship

- [ ] 4.1 PR body uses **`Ref #5225`** (NOT `Closes`) — ops-only-prod-write; issue closes post-merge after recovery.
- [ ] 4.2 Pre-merge ACs in plan satisfied.

## Phase 5 — Post-merge (operator — automated; no dashboard eyeballing)

- [ ] 5.1 Migration applies automatically via `web-platform-release.yml` migrate job on merge.
- [ ] 5.2 Immediately after deploy, via Management API (read-only; token from `doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain`, REF=ifsccnjhymdmidffkzhl, POST `/v1/projects/$REF/database/query`):
  - `SELECT count(*) FROM public.processed_github_events;` → PASS if ≤ 40,000.
  - `SELECT schedule, command FROM cron.job WHERE jobname='processed_github_events_retention';` → PASS if command contains `interval '7 days'` and schedule `'0 4 * * *'`.
- [ ] 5.3 ~3 days later: re-query `disk_io_pressure_signal()` RPC → PASS if `cache_hit_pct ≥ 98` AND row count stable/declining < 100k.
- [ ] 5.4 `gh issue close 5225` only after 5.3 verdict passes (or confirm the monitor auto-closed it on recovery), with the API verdict output as the comment.

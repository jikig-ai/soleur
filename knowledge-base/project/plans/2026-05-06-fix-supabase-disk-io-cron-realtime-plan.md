---
date: 2026-05-06
type: fix
issue: 3358
draft_pr: 3356
branch: feat-supabase-disk-io-budget
worktree: .worktrees/feat-supabase-disk-io-budget
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: ops-only-prod-write
---

# Plan: Reduce Supabase Prod Disk IO via cron cadence + Realtime publication audit

## Summary

Two surgical migrations to stop prod Supabase Disk IO Budget depletion before it causes a brand-visible outage:

1. **Migration 038** — change pg_cron `user_concurrency_slots_sweep` cadence from `* * * * *` (1,440 runs/day) to `*/15 * * * *` (96 runs/day) via `cron.unschedule` + `cron.schedule` (the existing migration 029 pattern). Saves ~5,400 cron-internal writes/day.
2. **Migration 039** — drop `public.messages` from the `supabase_realtime` publication added in migration 034. Confirmed zero production subscribers (only 16 hits in code for messages-table Realtime, all in `*test*` files; the only real-time consumer in `apps/web-platform/hooks/use-conversations.ts:238` subscribes to `conversations` only).

No code changes outside `apps/web-platform/supabase/migrations/` and the parallel test files. `use-conversations.ts` is not touched. No new compute add-on. No Terraform changes.

## Context

- **Source brainstorm:** `knowledge-base/project/brainstorms/2026-05-06-supabase-disk-io-budget-brainstorm.md`
- **Source spec:** `knowledge-base/project/specs/feat-supabase-disk-io-budget/spec.md`
- **Live diagnostics (2026-05-06):** Realtime WAL parser is the #1 query (1.12M ms / 219K calls / 325M block hits, 100% cache hit) — structural ~100ms WAL polling, not user-driven. pg_cron `job_run_details` plumbing is the #2-#4 cluster (~63K writes / 14d). Active user data is tiny: 58 conversations, 126 messages, 0 live concurrency slots. The IO is structural, not user-driven.
- **Tier:** prod is on default Micro (87 MB/s baseline disk IO, no compute add-on selected — only custom_domain). Not changing in this PR.
- **Compliance gates verified:** `hr-dev-prd-distinct-supabase-projects` PASS (dev `mlwiodleouzwniehynfz` ≠ prd `ifsccnjhymdmidffkzhl`).

## User-Brand Impact

Carried forward from brainstorm Phase 0.1 (operator answered "all of them" to the framing question).

**If this lands broken, the user experiences:** every authenticated session backed by prod Supabase — chat history, conversation state, billing-tied API keys. Specific failure modes: (a) dashboard live conversation list stops refreshing if migration 039 accidentally drops `conversations` instead of `messages`, (b) stuck-active conversations linger longer than they should if the cron cadence change cross-impacts the stuck-active reaper (verified: NO cross-impact, see Research Reconciliation), (c) a botched ALTER PUBLICATION leaves the publication in an undefined state and breaks all Realtime subscribers.

**If this leaks, the user's data is exposed via:** the publication change is operationally adjacent to RLS-bypass surface (publications affect what the Realtime broker reads from WAL, not what RLS allows users to subscribe to). No new RLS or SECURITY DEFINER surface introduced.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be invoked at review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Goal

Move prod Supabase IO consumption comfortably under the Micro baseline (87 MB/s) without a compute add-on upgrade, and prove the savings via before/after `pg_stat_statements` captured through the Supabase Management API.

## Research Reconciliation — Spec vs Codebase

| Spec claim | Reality (verified 2026-05-06) | Plan response |
|---|---|---|
| FR1 cadence: `*/5` or `*/15`, plan picks. | At current scale: 0 live slots, 38 deletes / 14 days = 2.7 deletes/day. The 120s `last_heartbeat_at` freshness threshold is independent of sweep cadence. | Pick `*/15 * * * *`. 15-min cleanup latency ≪ heartbeat freshness window. |
| FR2 outcome: keep / scope / replace, plan picks. | `apps/web-platform/hooks/use-conversations.ts:227-323` subscribes to `conversations` (channel A) and `users` (channel B). **Zero production subscribers to `public.messages`** (16 grep hits, all `*test*` files). | **Drop `public.messages` from publication**, keep `public.conversations`. Smallest possible diff with biggest WAL benefit. No `use-conversations.ts` edit needed. |
| TR1 reversible: cron change must be reversible. | `cron.alter_job(jobid, schedule := ...)` requires bigint jobid (no name overload — confirmed via pg_cron docs). Migration 029 created job by name (`user_concurrency_slots_sweep`). | Use `cron.unschedule(name)` + `cron.schedule(name, ...)` (the same pattern migration 029 uses). Rollback is symmetric. |
| Spec implies cron migration alone may need test guard. | Test convention is `apps/web-platform/test/supabase-migrations/036-release-slot-on-archive.test.ts`: `readFileSync` + comment-strip + regex. | Mimic this pattern for both 038 and 039. |
| Brainstorm noted `pg_cron job_run_details` is a top write contributor (~63K writes / 14d). | Each cron job invocation produces 3 plumbing writes regardless of work. Slowing cadence is the controllable lever (we cannot disable `pg_cron.log_run` on Supabase Cloud). | Cadence change is the only lever. Do NOT add a separate retention DELETE on `cron.job_run_details` — that adds writes. |
| Brainstorm noted dev `_schema_migrations` drift (issue #3370). | **Verified 2026-05-06: prd `_schema_migrations` is clean** — 037 / 036 / 035 / 034 all tracked. Drift is dev-only. | No prod risk. Add a Risks entry for dev developer ergonomics; do not fold in #3370 reconciliation. |

## Implementation Phases

### Phase 1: Migration 038 — slow `user_concurrency_slots_sweep` to `*/15 * * * *`

Create `apps/web-platform/supabase/migrations/038_slow_user_concurrency_slots_sweep.sql`:

```sql
-- 038_slow_user_concurrency_slots_sweep.sql
--
-- Reduce the pg_cron sweep on public.user_concurrency_slots from once-per-
-- minute to once-per-15-minutes. The 120-second `last_heartbeat_at`
-- freshness threshold (declared in 029) is independent of sweep cadence;
-- this migration only changes how often dead rows are physically reaped.
--
-- At current scale (38 deletes across 14+ days, 0 live slots in steady
-- state) the per-minute cadence was producing ~5,760 cron-internal writes
-- per day to cron.job_run_details for ~3 useful deletes per day. Slowing
-- to 15 minutes drops cron-internal writes to ~384/day with no functional
-- impact on stuck-active recovery (handled separately by migration 037's
-- find_stuck_active_conversations RPC + agent-runner.ts:522 setInterval).
--
-- See: knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md
-- See: knowledge-base/project/learnings/2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md
-- Issue: #3358

DO $$
BEGIN
  -- Idempotent guard: only act if the named job exists.
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;

  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '*/15 * * * *',
    $sweep$
      delete from public.user_concurrency_slots
      where last_heartbeat_at < now() - interval '120 seconds';
    $sweep$
  );
END $$;
```

### Phase 2: Migration 039 — drop `public.messages` from `supabase_realtime` publication

Create `apps/web-platform/supabase/migrations/039_drop_messages_from_realtime_publication.sql`:

```sql
-- 039_drop_messages_from_realtime_publication.sql
--
-- Remove public.messages from the supabase_realtime publication added by
-- migration 034. The Realtime WAL parser is the dominant disk IO consumer
-- on prod (1.12M ms / 219K calls / 325M block hits in the captured window),
-- driven by ~10 polls/sec regardless of user activity.
--
-- Confirmed via repo grep that no production code subscribes to
-- public.messages via Realtime — all 16 hits across apps/web-platform are
-- in *test* files (mock builders). The only production Realtime consumer
-- is apps/web-platform/hooks/use-conversations.ts:238, which subscribes
-- to public.conversations (kept in the publication).
--
-- public.conversations remains in the publication. This migration only
-- narrows the WAL fan-out, not the live-update surface of the dashboard.
--
-- Rollback: re-add via `ALTER PUBLICATION supabase_realtime ADD TABLE
-- public.messages;` (idempotent guard pattern from migration 034).
--
-- See: knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md
-- Issue: #3358

DO $$
BEGIN
  -- Idempotent guard: only act if messages is currently in the publication.
  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.messages;
  END IF;
END $$;
```

### Phase 3: Tests — combined file-parse content guard

One test file covering both migrations, mirroring the `apps/web-platform/test/supabase-migrations/036-release-slot-on-archive.test.ts` pattern (readFileSync + line-comment strip + regex). Per AGENTS.md `cq-write-failing-tests-before`, tests pin the SQL contract without requiring a live DB.

Create `apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

describe("migration 038_slow_user_concurrency_slots_sweep", () => {
  const executable = stripComments(
    readFileSync(path.join(MIG_DIR, "038_slow_user_concurrency_slots_sweep.sql"), "utf8"),
  );

  it("unschedules the existing job by name (idempotent guard)", () => {
    expect(executable).toMatch(/cron\.unschedule\s*\(\s*'user_concurrency_slots_sweep'\s*\)/i);
  });

  it("re-schedules at 15-minute cadence", () => {
    expect(executable).toMatch(
      /cron\.schedule\s*\(\s*'user_concurrency_slots_sweep'\s*,\s*'\*\/15\s+\*\s+\*\s+\*\s+\*'/i,
    );
  });

  // Kieran #5: pin the DELETE predicate byte-shape so a future edit cannot
  // change the load-bearing freshness condition while still passing the
  // schedule + threshold assertions above.
  it("preserves the DELETE predicate body unchanged from migration 029", () => {
    expect(executable).toMatch(
      /delete\s+from\s+public\.user_concurrency_slots\s+where\s+last_heartbeat_at\s*<\s*now\(\)\s*-\s*interval\s+'120\s+seconds'/i,
    );
  });
});

describe("migration 039_drop_messages_from_realtime_publication", () => {
  const executable = stripComments(
    readFileSync(path.join(MIG_DIR, "039_drop_messages_from_realtime_publication.sql"), "utf8"),
  );

  it("drops public.messages from supabase_realtime", () => {
    expect(executable).toMatch(
      /ALTER\s+PUBLICATION\s+supabase_realtime\s+DROP\s+TABLE\s+public\.messages/i,
    );
  });

  it("does NOT drop public.conversations (must remain in publication)", () => {
    expect(executable).not.toMatch(
      /ALTER\s+PUBLICATION\s+supabase_realtime\s+DROP\s+TABLE\s+public\.conversations/i,
    );
  });

  it("guards on publication membership before dropping (idempotent)", () => {
    expect(executable).toMatch(/pg_publication_tables/i);
    expect(executable).toMatch(/IF\s+EXISTS\s*\(/i);
  });
});
```

### Phase 4: PR description prep — before/after diagnostics

Capture before-numbers from prd via Supabase Management API and paste into PR description before marking ready. Reusable script:

```bash
SUPA_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
REF=ifsccnjhymdmidffkzhl
QPATH="https://api.supabase.com/v1/projects/$REF/database/query"

# Top 10 by total exec time
Q='SELECT round(total_exec_time::numeric, 1) AS total_ms, calls, round(mean_exec_time::numeric, 2) AS mean_ms, shared_blks_read, shared_blks_hit, left(query, 200) AS query FROM pg_stat_statements WHERE query NOT ILIKE '\''%pg_stat_statements%'\'' ORDER BY total_exec_time DESC LIMIT 10'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

# Top tables by write churn
Q='SELECT schemaname, relname, n_tup_ins+n_tup_upd+n_tup_del AS churn FROM pg_stat_user_tables WHERE schemaname IN ('\''public'\'','\''cron'\'') ORDER BY churn DESC LIMIT 10'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

# Disk IO usage trend (last 7 days, hourly)
curl -sS -H "Authorization: Bearer $SUPA_TOKEN" "https://api.supabase.com/v1/projects/$REF/health"
```

After post-merge migrate, run `pg_stat_statements_reset()` once via Management API, wait 24h, capture again, paste deltas to PR description.

## Files to Create

- `apps/web-platform/supabase/migrations/038_slow_user_concurrency_slots_sweep.sql`
- `apps/web-platform/supabase/migrations/039_drop_messages_from_realtime_publication.sql`
- `apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts`

## Files to Edit

**None** — research collapsed lever (b) to a publication-only change; `use-conversations.ts` is untouched.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/supabase/migrations/038_slow_user_concurrency_slots_sweep.sql` exists with a `*/15 * * * *` schedule and the `cron.unschedule` + `cron.schedule` pattern wrapped in a `DO $$ ... END $$` idempotent guard against `cron.job.jobname`.
- [x] `apps/web-platform/supabase/migrations/039_drop_messages_from_realtime_publication.sql` exists with `ALTER PUBLICATION supabase_realtime DROP TABLE public.messages;` wrapped in a `DO $$ ... END $$` idempotent guard against `pg_publication_tables`.
- [x] `apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts` passes (`bun test apps/web-platform/test/supabase-migrations`).
- [x] `bun run typecheck` green (`bun run lint` requires interactive ESLint setup; not a configured gate in this app).
- [x] **Cron job-name uniqueness:** `grep -r "user_concurrency_slots_sweep" apps/web-platform/supabase/migrations/` returns ONLY migrations 029 and 038 (guards against silent rename drift in sibling migrations that would double-schedule).
- [ ] PR description includes:
  - Before-snapshot of `pg_stat_statements` top 10 + `pg_stat_user_tables` write counts on prd, captured 2026-05-06 (already in the brainstorm — paste).
  - Roll-back plan (see Roll-back section below).
  - `Ref #3358` (NOT `Closes #3358` — closure is post-merge once the 7-day verification is green; this is `classification: ops-only-prod-write` per the plan-skill Sharp Edge).
- [ ] `semver:patch` label on PR.
- [ ] CPO sign-off on the User-Brand Impact section (recorded in PR comment).
- [ ] `user-impact-reviewer` passes at review time.

### Post-merge (operator)

- [ ] `web-platform-release.yml` `migrate` job green; both 038 and 039 applied to prd. Verify behavior (not bookkeeping):
  - `cron.job` shows `user_concurrency_slots_sweep` with `*/15 * * * *`: `SELECT jobname, schedule FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep';`
  - `pg_publication_tables` shows `public.conversations` PRESENT and `public.messages` ABSENT: `SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime' ORDER BY tablename;`
- [ ] Run `SELECT pg_stat_statements_reset();` via Management API immediately after migrate completes.
- [ ] 30 minutes later: smoke-test the dashboard chat surface — open two browser tabs, send a message in tab A, verify tab A shows the message immediately AND tab B's conversation list AND message body updates within ~2 seconds (the conversation-row-driven refresh path is the one doing the work; this confirms the kept `conversations` channel is sufficient and the dropped `messages` publication was unneeded).
- [ ] 24 hours later: re-pull `pg_stat_statements` top 10 and the Disk IO Budget gauge. Append to PR description as the after-snapshot. Realtime WAL parser per-call cost should drop; cron-plumbing writes should drop ~93%.
- [ ] **7 days later:** confirm Disk IO Budget gauge is *recovering* (climbing back toward full), not just *stable*. Burst credit accumulates over ~7 days on Micro tier; 24h shows rate-of-burn, not budget recovery.
- [ ] `gh issue close 3358` only after the 7-day verification passes and a brief comment summarizing the deltas is posted.

## Roll-back

**Forward-only rollback** (preferred, ~5 minutes via Management API):

```sql
-- Revert 038: restore per-minute cadence.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;
  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '* * * * *',
    $sweep$
      delete from public.user_concurrency_slots
      where last_heartbeat_at < now() - interval '120 seconds';
    $sweep$
  );
END $$;

-- Revert 039: re-add messages to the publication.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;
```

**PR-revert rollback** (if forward-only is insufficient): `gh pr revert 3356` opens a revert PR. The revert ships migrations 040 + 041 with the bodies above.

## Risks

1. **Dev `_schema_migrations` drift (issue #3370).** Dev has 034 / 035 applied untracked, 036 unapplied. When a developer runs `apps/web-platform/scripts/run-migrations.sh` on dev to test 038 + 039, the runner will attempt 034 (idempotent — should succeed and get tracked), 035 (no `IF NOT EXISTS` on its CREATE INDEX — may fail), 036 (will apply normally), then 038 + 039. **Mitigation:** developer reconciles dev manually before running the full chain (`INSERT INTO public._schema_migrations (filename) VALUES ('034_*.sql'), ('035_*.sql') ON CONFLICT DO NOTHING;`). Alternatively, apply 038 + 039 to dev directly via Management API and `INSERT` into `_schema_migrations` (the same out-of-band path that produced the existing drift). Prod is unaffected — verified clean tracking through 037.

2. **Realtime broker behavior on `ALTER PUBLICATION ... DROP TABLE`.** The Supabase Realtime broker reads from logical replication slots backed by the publication. Existing client subscriptions to `public.conversations` should be unaffected. However, any client that has a stale `messages`-table subscription (from a previous deploy or a test environment) will silently stop receiving events after migration 039 applies — they will not error, just go quiet. **Mitigation:** confirmed via grep that no production code subscribes to `messages`. Smoke-test in pre-merge dev verification covers this.

3. **`cron.unschedule` + `cron.schedule` is not transactional with respect to inflight ticks.** pg_cron's launcher reads schedules via a background process and does NOT participate in our migration's transaction; the launcher may cache the prior schedule for up to ~1s after our DELETE on `cron.job`. Worst case: one missed sweep tick at the cadence boundary, OR one extra sweep tick at the old cadence between our `unschedule` and `schedule` calls. **Mitigation:** none needed. The DELETE predicate is idempotent (deleting zero stale rows is fine), and one missed/extra tick has zero user-visible impact at current row counts.

4. **`pg_cron job_run_details` is not truncated.** Slowing the cron cadence reduces NEW writes to `job_run_details`, but the existing ~63K rows from the 14-day window are not truncated. Supabase's pg_cron extension does not auto-vacuum `cron.*` tables aggressively. **Mitigation:** none in this PR. If `cron.job_run_details` ever becomes a space concern, a separate migration can add a per-week retention policy. Tracked-but-deferred — call out in compound's learning, NOT a separate issue (table size is currently negligible).

5. **Realtime broker may briefly renegotiate the logical replication slot when the publication changes.** Subscribers may see a brief disconnect+reconnect at the moment 039 applies. At current concurrency (small operator + handful of test sessions) this is invisible. At >1k concurrent connections we'd schedule a maintenance window; not relevant today. **Mitigation:** none needed at current scale; flag in compound for future scaling.

## Test Strategy

- **Vitest content-guard tests** (Phase 3 above) pin the SQL contract: cadence, table membership, idempotent guards, no accidental `conversations` drop. These run in CI on every PR.
- **No live-DB tests** (the harness has no migrate-then-query flow for `cron.*` and the publication). Live verification happens post-merge via Management API queries (already specified in Acceptance Criteria → Post-merge).
- **Dashboard smoke-test** post-merge confirms `use-conversations.ts` Realtime path still works after the publication narrows.
- **Type-check / lint** are necessary but insufficient — they cannot catch a wrong cadence string or a wrong table name. The Vitest pattern is the load-bearing gate.

## Open Code-Review Overlap

Adjacent open issues reviewed: **#3372** (120s threshold tautological — independent), **#3370** (dev `_schema_migrations` drift — prod is clean; captured in Risks #1), **#3220** (postmerge trigger verification — N/A, no triggers here), **#3374** (slot_reclaimed WS frame — unrelated), **#3219** (inactivity-sweep slot leak — different sweep path), **#3221** (nightly cron CI — unrelated). All **acknowledge**, none require fold-in, none block merge.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Operations (carried forward from brainstorm Phase 0.5).

- **Engineering (CTO):** diagnose-first; no new SECURITY DEFINER surface; SECDEF `pg_temp` gaps in 017/027 deferred to #3361.
- **Product (CPO):** threshold = `single-user incident`; instrument-before-remediating respected via before-snapshot AC; sign-off required at plan time.
- **Legal (CLO):** zero subprocessor surface; no RLS or SECDEF; hard line — no PII in PR-description query output (Management API queries above expose only normalized query text + column names).
- **Operations (COO):** optimize-only = $0 incremental; Supabase Terraform gap (#3359) and tripwire compute bump (#3360) deferred.

**Product/UX Gate:** ADVISORY tier (no new pages / components). Auto-accepted (pipeline). No fresh ux-design-lead invocation. The publication narrowing has zero user-facing surface today; any future feature needing `messages`-table Realtime would re-add it.

## Dependencies

None new. Uses only existing infrastructure: pg_cron extension (already enabled), Supabase Realtime publication (already exists from migration 034), `apps/web-platform/scripts/run-migrations.sh` (already wired in `web-platform-release.yml`), Vitest (already configured with the migration-test convention from PR #036 and PR #2817).

## Sharp Edges

- `classification: ops-only-prod-write` — PR body uses `Ref #3358`, NOT `Closes #3358`. Issue closure is a post-merge step after the 7-day verification passes (per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`: `Closes` auto-closes at merge before remediation runs).
- Do NOT attempt to run `pg_stat_statements_reset()` from a migration file. The reset belongs to the operator's post-apply step via Management API. Putting it in the migration would reset stats every time someone re-runs migrations on a fresh dev project.
- The Realtime broker's logical replication slot reads ALL WAL regardless of which tables are in the publication; the publication only filters what it FORWARDS to subscribers. WAL emission volume is therefore not reduced by 039 — only the per-record routing cost in the Realtime broker. The IO budget impact is real but smaller than reducing total WAL would be.

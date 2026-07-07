---
title: "fix(db): stop autovacuum thrash on tiny hot-update tables (residual Supabase Disk IO drain)"
date: 2026-07-07
type: fix
lane: single-domain
brand_survival_threshold: none
related_issues: [5739, 3358, 5736]
status: draft
---

# fix(db): stop autovacuum thrash on tiny hot-update tables (residual Supabase Disk IO drain)

🐛 **Type:** bug fix / performance / infrastructure tuning
**Prod target:** `soleur-web-platform` (ref `ifsccnjhymdmidffkzhl`, Micro / 1 GB RAM, eu-west-1)
**Lineage:** third remediation in the prod Disk IO Budget line — #3358 (migrations 038/039: slowed the pg_cron sweep, dropped `public.messages` from Realtime) → #5736 (migration 114: WAL-concentration monitor; webhook-dedup fix crushed statement WAL from ~12 GB/day to ~17 MB/day) → **this PR** (residual driver: autovacuum thrash).

## Overview

After the June 2026 webhook-dedup fix (merged 2026-06-30), statement-attributed WAL on prod is only ~17 MB/day — the WAL problem is solved. The **residual** Disk IO Budget drain is now **autovacuum thrash**: Postgres' default autovacuum trigger (`autovacuum_vacuum_threshold = 50` + `autovacuum_vacuum_scale_factor = 0.2`) fires after only ~50 updates on a tiny table, so six 0–16-row hot-update tables are being fully vacuumed 50–142×/week. Each vacuum reads the table + **all** its indexes, writes WAL, and fsyncs — a fixed per-vacuum IOPS cost that, multiplied across six thrashing tables, is what now drains the Micro-instance budget.

**Measured (pg_stat_all_tables + pg_stat_statements, 7-day window, `stats_reset` 2026-06-30 12:40 UTC, as of 2026-07-07):**

| table | schema | live rows | updates/7d | autovacuums/7d | write source |
|---|---|---|---|---|---|
| `user_concurrency_slots` | public (ours) | 0 | 6,836 | 142 | `touch_conversation_slot` heartbeat |
| `mint_rate_window` | public (ours) | 7 | 2,613 (100% HOT) | 50 | runtime JWT mint rate-limiter |
| `runtime_mint_intent` | public (ours) | 7 | 2,528 (100% HOT) | 49 | runtime JWT mint intent marker |
| `auth.users` | auth (Supabase) | 16 | 11,737 | 108 | sign-in churn |
| `auth.one_time_tokens` | auth (Supabase) | 5 | ~2.8k ins+del | 53 | OTP lifecycle |
| `realtime.subscription` | realtime (Supabase) | 0 | ~2.7k ins+del | 48 | Realtime subs |

**The fix:** set per-table autovacuum storage parameters on the **public-schema tables we own** so they vacuum far less often, and set `fillfactor = 70` so updates stay HOT (in-page) and index bloat stays bounded as more dead tuples accumulate between vacuums. Because these tables stay tiny (0–16 live rows) and their updates are overwhelmingly HOT, letting dead tuples accumulate to a threshold of ~1,000 (vs the default ~50) before vacuuming is safe and cuts vacuum frequency ~15–20×. `auth.*` and `realtime.*` are Supabase-managed (GoTrue / Realtime) and MUST NOT be `ALTER`ed here — their write-churn reduction is tracked separately by open issue #5739.

### Central engineering argument (challenge to the "reduce write frequency" sub-goal)

The task framing lists two levers: (1) autovacuum tuning, and (2) reducing redundant writes in our code. **Lever 1 is the complete fix; lever 2 is not cheap-and-safe here and is deliberately scoped out** (see Alternatives + Non-Goals). Rationale:

- The **writes** are no longer the problem — statement WAL is already ~17 MB/day. The problem is the **vacuums those writes trigger**. Fixing the vacuum trigger (lever 1) addresses the actual IOPS driver directly and completely; halving the write count (lever 2) only halves an input that is already small, while the fixed per-vacuum overhead is what dominates.
- The mint-path writes (`runtime_mint_intent`, `mint_rate_window`) are **1:1 with JWT mints**, which are **already coalesced** by the tenant-client cache at `TTL/4` (≤24 mints/hr/founder, `lib/supabase/tenant.ts:794-800`). Reducing them further means widening the cache reuse window from `TTL/4` back toward `TTL/2` — which **reverses a deliberate Resolution C (#3363) security tightening**, so it is neither cheap nor safe and belongs with #5739, not here.
- The heartbeat write (`user_concurrency_slots`) is driven by the **30 s WS ping** (`ws-handler.ts:2947`), not by message volume. Widening it (e.g. 30 s → 45 s) tightens the margin against the 120 s sweep freshness threshold for a ~1.5× write reduction the migration already dwarfs ~20×. Optional and low-value; see Non-Goals.

## Research Reconciliation — Task Framing vs. Codebase

| Task framing claim | Codebase reality | Plan response |
|---|---|---|
| `user_concurrency_slots` driven by `touch_conversation_slot` RPC **"on every message"** | RPC fires from the **30 s WS heartbeat ping** (`ws-handler.ts:2933-2953`), not per message; comment at `029:169-172` confirms "once per 30s per live session" | Corrected in Overview. Write source is liveness heartbeat; message volume is irrelevant. Does not change the fix (autovacuum tuning is agnostic to write source). |
| Reduce mint writes by debounce/coalesce | Mints already coalesced at `TTL/4` cache (`tenant.ts:794`); the `TTL/4` value is a deliberate #3363 security tightening from `TTL/2` | Scoped out — reducing further reverses a security decision; defer to #5739. |
| "six thrashing tables" | 3 are public/ours (fixable here); 3 are `auth.*` / `realtime.*` (Supabase-managed, out of scope) | Migration touches only the 3 owned tables; Phase 0 discovery query surfaces any additional owned tables. |
| Fix = one migration under `apps/web-platform/supabase/migrations/` | Confirmed: migrations deploy via `web-platform-release.yml#migrate` → `scripts/run-migrations.sh` on merge to main; tests are file-parse shape tests (`test/supabase-migrations/*.test.ts`). No autovacuum/fillfactor prior art exists — novel but standard Postgres DDL. Next number is **123**. | Migration `123_tame_autovacuum_on_tiny_hot_tables.sql` + `.down.sql` + shape test. |

**Premise validation (Phase 0.6):** #5739 is **OPEN** (`perf(db): reduce Supabase Auth write churn … investigate JWT/session lifetimes`, p3-low) — confirmed still-live; this PR complements it and must NOT touch JWT/session lifetime. #3358 and #5736 are the merged prior remediations (migrations 038/039, 114 present on disk). No stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** at worst, bounded table bloat on a handful of tiny internal tables (a few extra 8 KB pages) — no user-facing surface. A pathologically-high threshold on a table that later grows could delay analyze/vacuum, but all three targets are structurally tiny (0–16 live rows) and self-limited by their own sweep/TTL logic. If the optional heartbeat-interval change were mis-tuned (scoped out here), a live session's slot could be reaped early → the next message triggers a re-acquire (already self-healed by `ws-handler-cap-hit-self-heal`).
**If this leaks, the user's data is exposed via:** N/A — the migration sets storage parameters only; it adds no columns, touches no row data, and changes no RLS/grants.
**Brand-survival threshold:** none — infrastructure tuning, reversible, no data surface.
**threshold: none, reason:** migration sets `reloptions` (autovacuum params + fillfactor) on 3 internal tiny tables; no new PII, columns, RLS, grants, or data movement, so no single- or aggregate-user exposure vector exists.

## Implementation Phases

### Phase 0 — Live read-only discovery (confirm targets + surface siblings)

Read-only, against prod ref `ifsccnjhymdmidffkzhl` via `mcp__plugin_supabase_supabase__execute_sql` (or the curl recipe in the 2026-05-06 learning). No writes.

1. Snapshot the current thrash + **pin the post-deploy verification baseline** (autovacuum_count is cumulative — capture it now):
   ```sql
   SELECT schemaname, relname, n_live_tup, n_tup_upd, n_dead_tup,
          autovacuum_count, last_autovacuum
   FROM pg_stat_all_tables
   WHERE schemaname = 'public'
   ORDER BY autovacuum_count DESC
   LIMIT 25;
   ```
2. **Decision rule for the ALTER list:** include every `public`-schema table with `autovacuum_count ≥ 20` (over the current window) AND `n_live_tup ≤ 100`. This confirms the three named tables and surfaces any additional owned tiny hot-update table (candidates to check by name: `worktree_write_lease` (116), `routine_run_progress` (120), `runtime_cost_state` (046), `byok_cap_trip*` (121), `inbox_item` (122), `workflow_state` (032)). Do NOT include any `auth.*` / `realtime.*` / `cron.*` table.
3. Read the current `reloptions` so the `.down.sql` restores true prior state (almost certainly NULL = defaults):
   ```sql
   SELECT relname, reloptions FROM pg_class
   WHERE relname IN ('user_concurrency_slots','mint_rate_window','runtime_mint_intent');
   ```
4. Record the baseline row set into the PR/spec so the Follow-Through probe (Phase 3) can diff against it.

### Phase 1 — Migration `123_tame_autovacuum_on_tiny_hot_tables.sql`

Create `apps/web-platform/supabase/migrations/123_tame_autovacuum_on_tiny_hot_tables.sql` and its `.down.sql`. Header comment must cite: the residual-thrash diagnosis, the #3358/#5736 lineage, the 2026-05-06 learning, #5739 as the related (out-of-scope) auth-churn tracker, and the "no CONCURRENTLY" note (not needed — `ALTER TABLE … SET (…)` is fast transactional DDL, safe inside Supabase's per-migration txn).

For each confirmed owned table (the three named + any Phase-0 additions):
```sql
ALTER TABLE public.user_concurrency_slots SET (
  autovacuum_vacuum_threshold    = 1000,  -- was default 50
  autovacuum_vacuum_scale_factor = 0,     -- remove the %-of-rows term (meaningless at 0–16 rows)
  autovacuum_analyze_threshold   = 1000,  -- stop analyze thrash too (stable plan on a tiny table)
  autovacuum_analyze_scale_factor= 0,
  fillfactor                     = 70     -- leave 30% page free for HOT updates under the higher dead-tuple ceiling
);
-- …repeat for mint_rate_window, runtime_mint_intent, + any Phase-0 additions…
```
- **Why `threshold = 1000`, `scale_factor = 0`:** vacuum fires deterministically every ~1,000 dead tuples. Projected frequency: `user_concurrency_slots` 6,836/1,000 ≈ **7/wk** (was 142); mint tables ~2,600/1,000 ≈ **2–3/wk** (was 49–50). ~15–20× reduction. `500`–`2000` is the acceptable band (task-specified); `1000` is the uniform middle. deepen-plan/review may adjust per-table.
- **Why `fillfactor = 70`:** raising the dead-tuple ceiling means up to ~1,000 dead row-versions accumulate between vacuums; `fillfactor 70` keeps free space on the (few) pages so the 100%-HOT mint-table updates stay HOT and do not spill into new heap pages or bloat the PK/unique indexes. Applies to future page writes only — no rewrite needed; these hot tables rewrite their pages within minutes of deploy. (`VACUUM FULL`/`CLUSTER` cannot run in a migration txn and is unnecessary at this table size.)
- **`.down.sql`:** `ALTER TABLE … RESET (autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor, autovacuum_analyze_threshold, autovacuum_analyze_scale_factor, fillfactor);` for each table (restores defaults; matches Phase-0 observed NULL reloptions).

### Phase 2 — Migration shape test

Add `apps/web-platform/test/supabase-migrations/123-tame-autovacuum.test.ts` mirroring `038-039-disk-io-fix.test.ts` (file-parse, strip-comments, regex-assert). Assert, for each targeted table: an `ALTER TABLE public.<t> SET (…)` block sets `autovacuum_vacuum_threshold`, `autovacuum_vacuum_scale_factor = 0`, and `fillfactor = 70`; and the `.down.sql` `RESET`s the same params. Pin the exact param names byte-shape so a future edit can't silently drop one. Also assert the migration contains **no** `ALTER TABLE auth.` / `ALTER TABLE realtime.` / `ALTER TABLE cron.` (owned-tables-only guard).

### Phase 3 — Follow-Through soak probe (Phase 2.9.1 enrollment — verification is soak-gated)

`autovacuum_count` is cumulative, so proving the vacuum **rate** dropped requires a post-deploy soak. Create `scripts/followthroughs/autovacuum-thrash-<issue>.sh`:
- Reads `SUPABASE_ACCESS_TOKEN` from Doppler (`-p soleur -c prd`), queries `pg_stat_all_tables` for the three tables via the Supabase query API (read-only; no ssh).
- Computes each table's `autovacuum_count` delta since the Phase-0 baseline pinned strictly after deploy; exits 0 when the weekly rate is `< 15`/table (down from 49–142), else exits non-zero with the current rates.
- Tracker directive: `<!-- soleur:followthrough script=scripts/followthroughs/autovacuum-thrash-<issue>.sh earliest=<deploy+7d> secrets=SUPABASE_ACCESS_TOKEN -->` + `follow-through` label; wire `SUPABASE_ACCESS_TOKEN` into `.github/workflows/scheduled-followthrough-sweeper.yml` if not already present.

### Non-Goals / scoped out (with rationale)

- **JWT access-token / session lifetime** — security-sensitive; tracked by #5739. Untouched.
- **Widening the mint cache reuse window (`TTL/4 → TTL/2`)** — reverses the deliberate Resolution C (#3363) tightening; not cheap-and-safe. Defer to #5739.
- **Heartbeat ping interval (30 s → 45 s)** — optional ~1.5× write reduction on one table the migration already reduces ~20×; tightens the 120 s sweep-freshness margin. Recommend **not** shipping in this PR; if a reviewer wants it, gate on: `2 × interval < 120 s` with ≥1 dropped-ping margin. Documented, not implemented.
- **`ALTER`ing `auth.*` / `realtime.*`** — Supabase-managed; forbidden. Their churn is #5739's scope.

## Files to Create
- `apps/web-platform/supabase/migrations/123_tame_autovacuum_on_tiny_hot_tables.sql`
- `apps/web-platform/supabase/migrations/123_tame_autovacuum_on_tiny_hot_tables.down.sql`
- `apps/web-platform/test/supabase-migrations/123-tame-autovacuum.test.ts`
- `scripts/followthroughs/autovacuum-thrash-<issue>.sh`

## Files to Edit
- `.github/workflows/scheduled-followthrough-sweeper.yml` — only if `SUPABASE_ACCESS_TOKEN` is not already a wired secret for the sweeper (verify first).

## Open Code-Review Overlap
None — no open `code-review` issue references the target migration paths or the three tables (verify with the two-stage `gh issue list --label code-review --json` + `jq --arg` query at Step 1.7.5 before freeze).

## Observability

```yaml
liveness_signal:
  what: existing disk-IO monitor RPC (migrations 095 + 114 top_wal_statements / max_wal_pct) surfaced by the disk-IO monitor cron
  cadence: existing cron schedule (unchanged by this PR)
  alert_target: existing disk-IO budget alert path
  configured_in: apps/web-platform/supabase/migrations/095_*, 114_disk_io_top_wal_statements.sql
error_reporting:
  destination: N/A at runtime (DDL-only migration); migration-apply failures surface via web-platform-release.yml#migrate + verify-migrations job
  fail_loud: true (transactional DDL — a failed ALTER rolls the migration back and fails the release migrate job)
failure_modes:
  - mode: threshold set too high, unbounded bloat on a table that later grows
    detection: pg_stat_all_tables.n_dead_tup / n_live_tup ratio on the three tables (Follow-Through probe + Phase-0 query)
    alert_route: Follow-Through sweeper exits non-zero, follow-through issue stays open
  - mode: vacuum rate does NOT drop after deploy (params ignored / wrong table)
    detection: scripts/followthroughs/autovacuum-thrash-<issue>.sh autovacuum_count delta
    alert_route: scheduled-followthrough-sweeper.yml, non-zero exit
logs:
  where: web-platform-release.yml migrate + verify-migrations job logs (GitHub Actions)
  retention: GitHub Actions default
discoverability_test:
  command: >
    doppler run -p soleur -c prd -- bash -c 'curl -sS -X POST
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json"
    "https://api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query"
    -d "{\"query\":\"SELECT relname, reloptions FROM pg_class WHERE relname IN (''user_concurrency_slots'',''mint_rate_window'',''runtime_mint_intent'')\"}"'
  expected_output: each row's reloptions array contains autovacuum_vacuum_threshold=1000, autovacuum_vacuum_scale_factor=0, fillfactor=70 (NO ssh)
```

## Architecture Decision (ADR/C4)

**No ADR required.** This is reversible parameter tuning on three existing internal tables in the established disk-IO-remediation line (#3358 → #5736 → this). It creates no ownership/tenancy boundary move, no new substrate/integration pattern, no resolver/dispatch/trust-boundary change, and reverses no existing ADR. A competent engineer reading the ADR corpus + C4 would not be misled by this change.

**C4 views — no impact (enumeration checked against all three `.c4` model files):** the change adds no external **human actor** (no new correspondent/reviewer/recipient), no external **system/vendor** (no new webhook/API/store — Supabase Postgres is already modeled), no **container/data-store** (the three tables live inside the already-modeled web-platform Postgres container), and no **actor↔surface access relationship** (grants/RLS unchanged). Autovacuum storage parameters are sub-container tuning invisible at C4 Context/Container/Component granularity. Verifier: read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and confirm none reference per-table vacuum tuning; cite the check in the PR.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Migration `123_*.sql` sets `autovacuum_vacuum_threshold` (500–2000), `autovacuum_vacuum_scale_factor = 0`, `autovacuum_analyze_threshold`, `autovacuum_analyze_scale_factor = 0`, and `fillfactor = 70` on each confirmed owned table (the three named + any Phase-0 addition). Grep-assertable in the shape test.
- [ ] Migration touches **zero** `auth.*` / `realtime.*` / `cron.*` tables (shape test asserts absence of `ALTER TABLE auth.` / `ALTER TABLE realtime.`).
- [ ] `.down.sql` `RESET`s exactly the params `123_*.sql` sets, for every table it touched.
- [ ] `123-tame-autovacuum.test.ts` passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/123-tame-autovacuum.test.ts`.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] Follow-Through probe script exists, is executable, and its tracker directive + `earliest=<deploy+7d>` are recorded; `SUPABASE_ACCESS_TOKEN` confirmed wired into the sweeper workflow.
- [ ] PR body uses **`Ref #5739`** (related, NOT `Closes`) and references the #3358/#5736 lineage.

### Post-merge (operator/automated)
- [ ] `web-platform-release.yml#migrate` + `verify-migrations` jobs green (migration applied to prod).
- [ ] Discoverability test (Observability block) confirms the three tables' `reloptions` carry the new params — run post-deploy, read-only, no ssh.
- [ ] **Soak (7 d, automated via Follow-Through sweeper):** each of the three tables' `autovacuum_count` weekly rate drops below 15 (from 49–142). Follow-Through issue auto-closes when the probe exits 0.

## Test Scenarios
1. **Shape test** (file-parse, offline): params present + correct values; `auth.*`/`realtime.*` absent; `.down.sql` symmetry. (Phase 2.)
2. **Apply-in-prod** (release pipeline): transactional DDL applies cleanly; `verify-migrations` green.
3. **Post-deploy reloptions read** (read-only prod): `pg_class.reloptions` reflects the new params (Observability discoverability_test).
4. **Soak** (read-only prod, +7 d): `pg_stat_all_tables.autovacuum_count` rate on the three tables falls ~15–20× (Follow-Through probe).

## Domain Review
**Domains relevant:** none (single-domain infrastructure/DB tuning).

No cross-domain implications — reversible Postgres autovacuum tuning on three internal tables; no UI surface (Product/UX Gate = NONE), no new data processing (GDPR: migration sets storage params only, adds no columns/PII/flows — no regulated-data surface introduced), no new infrastructure/secret/vendor (IaC gate: pure migration against already-provisioned Supabase; deploys via existing `web-platform-release.yml#migrate`).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD`/omits the threshold fails `deepen-plan` Phase 4.6 — this plan fills all three lines + the `threshold: none, reason:` scope-out bullet (`.sql` is a sensitive path per preflight Check 6).
- `fillfactor` only affects **future** page writes; existing rows are not rewritten by `ALTER`. Safe here because the target tables are hot (pages rewrite within minutes) and tiny. Do **not** add `VACUUM FULL`/`CLUSTER` — non-transactional, fails inside Supabase's per-migration txn (SQLSTATE 25001 class), same constraint as `CREATE INDEX CONCURRENTLY` (see 025/027/029 headers).
- Verification is **soak-gated** (cumulative counter) → Follow-Through enrollment is mandatory (ship Phase 5.5 fail-closes without it).
- Use `Ref #5739`, never `Closes #5739` — #5739 is the separate auth-churn tracker and must stay open.

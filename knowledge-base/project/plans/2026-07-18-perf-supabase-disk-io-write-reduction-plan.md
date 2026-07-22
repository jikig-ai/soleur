---
title: Supabase Disk-IO write reduction (Micro tier — optimize, keep tier)
type: perf
date: 2026-07-18
branch: feat-one-shot-supabase-disk-io-reduction
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# ⚡ Supabase Disk-IO write reduction (Micro tier — optimize, keep tier)

## Enhancement Summary

**Deepened:** 2026-07-18 · **Review agents:** learnings-researcher, code-simplicity-reviewer, security-sentinel,
data-integrity-guardian, architecture-strategist (×2 — coupling + flow), observability-coverage-reviewer.

**Load-bearing corrections applied from review (each verified against live source):**
1. **Live pg_cron sweep is migration 115** (`0 * * * *` hourly), not 029 (per-minute) — copying 029 would have
   been a 60× WAL regression, inverting the PR goal. (data-integrity R1, security, architecture R1)
2. **Concurrency-slot coupling is 7 sites, not 5** — added `ws-handler.ts:801`/`:2059` liveCutoff literals +
   `find_stuck_active_conversations` default (mig 037). AC8 is now a **grep-based drift-guard**, not an
   enumerable allowlist. (architecture R3/R4, spec-flow E2)
3. **Worktree-lease has a SQL twin** (`acquire_worktree_lease` mig 116:128) — raising only the TS window halves
   the cross-host takeover tolerance (split-brain risk). Added to migration 133. (data-integrity F3, architecture R2)
4. **RLS must source from LIVE `pg_policies`, not defining migrations** — `conversations`/`kb_files` write
   policies were redefined in mig 129 (#6334); a stale source silently drops the `is_workspace_member` WITH
   CHECK → cross-tenant exposure. AC5 changed to a before/after diff invariant; `users` guards excluded;
   candidate set gated to advisor-confirmed findings. (security CRITICAL-1/2, data-integrity F2)
5. **The cap-hit "immediate reclaim" claim was false** — lazy sweep is threshold-gated + reconnect mints a
   fresh UUID, so a crashed cap-hit user is locked out up to 240 s. Added the no-live-socket reap mitigation
   (Phase 3e / AC14). (spec-flow E3)
6. **Soak metric was mathematically broken** — `top_write_churn.writes` is a cumulative counter that only
   climbs. AC12 rewritten to a windowed delta-rate; enrolled as an automated follow-through probe (AC13)
   modeled on the existing `autovacuum-thrash-6168.sh` for the same tables. (observability P1)
7. Function is `acquire_conversation_slot` (4-arg), not `acquire_slot`; grants preserved via `CREATE OR REPLACE`.

**Surfaced (not applied) — User-Challenge DC-1:** split into 3 PRs (recorded in `decision-challenges.md`).

## Overview

Supabase sent a "Disk IO Budget depleting" warning for prod project `ifsccnjhymdmidffkzhl`
("soleur-web-platform"). The live signal (pulled at plan time, no operator involvement) shows
this is **write IO** (WAL + checkpoints), not a read/missing-index problem:

- `cache_hit_pct = 100.000%` — well above our monitor floor `CACHE_HIT_FLOOR_PCT = 98.0`
  (`cron-supabase-disk-io.ts:61`). No read-pressure regression.
- `max_wal_pct = 15.19%` — well below our concentration ceiling `WAL_CONCENTRATION_PCT_CEIL = 40`
  (`cron-supabase-disk-io.ts:72`). No single-statement WAL hog. WAL is **diffuse** across many writers.

The compute tier is the smallest included (Micro-class, ~87 MB/s Disk-IO baseline; no
`compute_instance` add-on). The operator chose to **OPTIMIZE (free, reversible) and KEEP the Micro
tier** rather than pay to upgrade. This PR is therefore a code+migration change that reduces write
IO — **not** a compute change.

**Baseline signal (measured 2026-07-18T08:12:29Z via `disk_io_pressure_signal` RPC):**

- `cache_hit_pct`: 100.000 · `max_wal_pct`: 15.19
- `top_write_churn`: `processed_github_events` (395,685) → `user_concurrency_slots` (8,711) →
  `routine_runs` (5,566) → `mint_rate_window` (3,656) → `runtime_mint_intent` (3,635)
- `top_wal_statements` (share of WAL): routine RPC `p_rou…` 15.19% · `refresh_tokens` INSERT 15.11% ·
  `sessions` INSERT 11.20% · `mfa_amr_claims` INSERT 9.68% · `processed_github_events` INSERT 7.26%

**Where the controllable write IO is.** `processed_github_events` (webhook dedup) was already
remediated by **migration 114 (2026-06-30, WAL-from-webhook-INSERT retention)**; `refresh_tokens` +
`sessions` + `mfa_amr_claims` (≈36% of WAL) are **GoTrue-managed and OUT OF SCOPE** (see Non-Goals).
The largest *controllable* write churn is `user_concurrency_slots` (8,711 writes — a 30 s heartbeat)
plus the periodic heartbeat writers on `routine_run_progress` and `worktree_write_lease`. Migration
**123 (2026-07-07, tame-autovacuum-on-tiny-hot-tables)** already tamed the *autovacuum* thrash on
these same three tables (it measured `user_concurrency_slots` 6,836 upd/7d, `mint_rate_window` 2,616,
`runtime_mint_intent` 2,532) via `fillfactor=70` + autovacuum tuning — but the **UPDATE WAL itself
remains**. This PR reduces that WAL at the source by backing off the heartbeat cadences.

**Three workstreams, in ascending risk order:**

1. **Drop unused secondary indexes** (highest leverage, safest) — every unused index is pure
   write-amplification (maintained on every INSERT/UPDATE for zero read benefit). Migration 132.
2. **Wrap `auth_rls_initplan` hotspots** (mechanical, low risk) — `auth.<fn>()` → `(select auth.<fn>())`
   so it evaluates once per query instead of once per row. Migration 134. Query-efficiency win
   (indirect WAL relief via reduced CPU contention on the Micro tier), bounded to the hottest tables.
3. **Back off tight heartbeat writers** (highest risk — cross-layer reaper-threshold coupling) — halve
   the periodic heartbeat WAL on `user_concurrency_slots`, `routine_run_progress`, `worktree_write_lease`.
   Requires proportionally raising every matching staleness/reaper threshold to avoid false session
   reaping. TS edits + migration 133.

## PR-Split Recommendation (User-Challenge — operator decides)

Multi-agent plan review (code-simplicity + security-sentinel + data-integrity-guardian + architecture-strategist)
converged on a recommendation that **diverges from the operator's stated "one PR, three workstreams" framing**,
so it is surfaced here rather than silently applied (recorded in
`knowledge-base/project/specs/feat-one-shot-supabase-disk-io-reduction/decision-challenges.md`):

**Recommendation: split into 3 PRs** (the phases already map cleanly):
1. **Migration 132 (index drops)** — safest, direct write-amp win; ship first, independent.
2. **Migration 133 + TS heartbeat (Phase 3)** — the actual write-IO lever AND the load-bearing cross-layer
   risk (7-site coupling, cross-host lease fence, cap-hit lockout mitigation). Isolate so its blast radius
   and rollback are clean.
3. **Migration 134 (RLS initplan wrap)** — a *different* optimization axis (read/CPU initplan, not WAL) that
   the PR's own AC12 write-count metric **cannot measure**, with a disjoint reviewer set and its own
   cross-tenant-exposure risk (CRITICAL-1). Its measured benefit is marginal (the churn-priority tables' hot
   writes go through the RLS-bypassing `SECURITY DEFINER` `touch_conversation_slot`).

**Rationale:** bundling two disjoint `single-user incident` risks (false-reap + cross-tenant RLS drift) in one
PR maximizes blast radius and defeats granular rollback. **The operator may keep all three in one PR** — this
plan is written to support either path (the workstreams are already independent migrations). If kept together,
Workstream 3 stays capped to advisor-confirmed policies per Phase 2.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task brief) | Reality (verified at plan time) | Plan response |
|---|---|---|
| "20 `unused_index` findings" | Advisor returns exactly **20** (verified via `/advisors/performance`). | Drop **14 mature** candidates; **defer 6** created in migrations 126/127 (2026-07-08/09 — ~10-day-old beta-CRM stats, too young to trust `idx_scan=0`). |
| "58 `auth_rls_initplan` policies" | Advisor returns exactly **58** across 38 tables. | Cap to the hottest tables (~23 policies); defer the rest to a labeled follow-up. |
| Priority tables incl. `mint_rate_window`, `runtime_mint_intent` | Neither has **any** flagged RLS policy (service-role-only tables; RLS not the write cost). | RLS workstream targets only `user_concurrency_slots`, `routine_runs`, `routine_run_progress` from the churn set + read-hot tables. |
| "routine-run-progress heartbeat 30000→60000 (line ~28)" | Confirmed `HEARTBEAT_INTERVAL_MS = 30_000` at `routine-run-progress.ts:28`; coupled `STUCK_THRESHOLD_MS = 90_000` (line 29), `ORPHAN_IGNORE_MS` 60 min (line 30). | Also raise `STUCK_THRESHOLD_MS` 90_000→180_000 (keep 3× ratio). `ORPHAN_IGNORE_MS` unchanged. |
| "worktree-write-lease WORKTREE_LEASE_HEARTBEAT_MS 25000 (line ~392)" | Confirmed at `worktree-write-lease.ts:392`; matching staleness `LEASE_LIVENESS_WINDOW_MS = 120_000` (line 79, ~4.8×). | Raise heartbeat 25_000→50_000 AND `LEASE_LIVENESS_WINDOW_MS` 120_000→240_000 (preserve missed-beat tolerance). |
| "ws-handler concurrency-slot heartbeat (~2959) + 60 s stuck-active reaper (index.ts ~159)" | Heartbeat is a **bare literal** `setInterval(…, 30_000)` at `ws-handler.ts:~2969` calling `touch_conversation_slot`. The 120 s threshold is coupled across **7 sites** per the code's own coupling comments (§Phase 3a): 4 TS (`ws-handler:545`, `agent-runner:789`, `ws-handler:801`, `ws-handler:2059`) + 3 SQL (mig 093 `acquire_conversation_slot`, LIVE pg_cron sweep = mig **115** not 029, mig 037 `find_stuck_active_conversations` **default 120**). The first pass found only 5; 3 review agents each surfaced more. | Extract heartbeat to `SLOT_HEARTBEAT_INTERVAL_MS`=60_000; de-dupe the 2 TS thresholds into one shared const; raise all 7 sites → 240; grep-based drift-guard (AC8), not an allowlist. |
| "worktree-write-lease is TS-only" (my Phase-1 assumption) | **FALSE** — the lease reclaim function at **migration 116:128** carries its own `heartbeat_at < now() - interval '120 seconds'` predicate (the SQL twin of `LEASE_LIVENESS_WINDOW_MS`). | System B needs a SQL change too: raise 116:128 → 240 s in migration 133 alongside the concurrency-slot SQL. |

## User-Brand Impact

**If this lands broken, the user experiences:** (a) their live agent session abruptly reaped
mid-run — a false "stuck/stale" reclaim that releases their concurrency slot and terminates an
in-flight Claude loop; or (b) an access-control regression if an RLS `USING`/`WITH CHECK`
expression is altered incorrectly while wrapping `auth.uid()`.

**If this leaks, the user's data is exposed via:** a mangled RLS predicate that widens row
visibility (e.g., dropping the `= id` / `workspace_member` clause while editing the policy) so one
user reads another user's `conversations` / `messages` / `users` rows.

**Brand-survival threshold:** `single-user incident`.

**Consequence:** `requires_cpo_signoff: true` in frontmatter. CPO sign-off required at plan time
(covered by Domain Review, below). `user-impact-reviewer` runs at review time (review skill's
conditional-agent block). The two load-bearing mitigations: (1) the heartbeat-vs-threshold ratio is
preserved exactly (4 missed beats before reap, both before and after) and asserted by tests; (2)
every RLS `ALTER POLICY` recreates the **exact** current `USING`/`WITH CHECK` expression, wrapping
**only** the `auth.<fn>()` call, verified by a `pg_policy` shape assertion.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `apps/web-platform/supabase/migrations/132_drop_unused_indexes.sql` drops exactly the
      14 mature unused indexes listed in Phase 1; `132_drop_unused_indexes.down.sql` recreates all 14
      with their exact original definitions. Round-trip: `apply 132 → apply 132.down` returns
      `pg_indexes.indexdef` for those 14 **codepoint-for-codepoint** to the pre-132 state (not just index
      name presence — catches a partial-`WHERE`/`DESC`-ordering drift in the down file).
- [ ] **AC2** — `grep -c CONCURRENTLY apps/web-platform/supabase/migrations/132_*.sql` == 0 (both files).
      Decision (resolved at plan time, not deferred): the down file recreates all 14 indexes
      **non-concurrently inside the per-file txn** — a rollback is a deliberate maintenance-window op, so the
      brief `ACCESS EXCLUSIVE` locks are acceptable and this keeps the down file inside `run-migrations.sh`'s
      standard txn (no runner special-casing). CONCURRENTLY is never used (would fail SQLSTATE 25001).
- [ ] **AC3** — The 6 beta-CRM indexes (migrations 126/127) are **NOT** dropped; a labeled follow-up
      issue exists (`disk-io`, `perf`, `deferred-scope-out`) to re-evaluate them once stats mature.
- [ ] **AC4** — `133_heartbeat_threshold_backoff.sql` raises **all four** SQL staleness thresholds to
      `interval '240 seconds'` / default 240: (a) `CREATE OR REPLACE acquire_conversation_slot(uuid,uuid,integer,uuid)`
      (source mig 093); (b) reschedule `user_concurrency_slots_sweep` reproducing mig **115** with cadence
      `'0 * * * *'` UNCHANGED; (c) `find_stuck_active_conversations` default `120`→`240` (source mig 037);
      (d) `acquire_worktree_lease` (source mig 116). `.down.sql` restores all four to the pre-133 live state
      (115 at `'0 * * * *'`+120 s, NOT 029). Assertions: `grep -c "120 seconds" up == 0`; the sweep cadence
      is `0 * * * *` (grep asserts no `* * * * *`/`*/15` reintroduced); post-apply `pg_proc.proconfig` for
      `acquire_conversation_slot` contains `search_path=public, pg_temp` AND `prosecdef = true`; the 4-arg
      signature is unchanged (a wrong overload leaves the live fn at 120 s); `service_role` retains EXECUTE
      on both RPCs.
- [ ] **AC5** — `134_rls_initplan_hotspots.sql` `ALTER POLICY`s each **advisor-confirmed** targeted policy
      (Phase 2) so every `auth.uid()`/`auth.jwt()` becomes `(select auth.uid())`/`(select auth.jwt())`.
      Verify via a **before/after full-expression diff invariant** (NOT a `contains` check — a substring test
      cannot detect a dropped `AND is_workspace_member(...)` conjunct, and false-negatives correct wraps
      because `pg_get_expr` reserializes as `( SELECT auth.uid() AS uid)`): capture `pg_get_expr(polqual/
      polwithcheck)` + `polpermissive` + `polroles` + `polcmd` for every targeted policy BEFORE 134; after
      134, assert that stripping the `(select …)` wrapper from the after-form yields **byte-equality** with
      the before-form, and `polpermissive`/`polroles`/`polcmd` are unchanged. `.down.sql` restores the
      unwrapped form from the same before-snapshot.
- [ ] **AC6** — The **one shared** concurrency-slot staleness const (`SLOT_STALENESS_THRESHOLD_SECONDS`,
      new — see Phase 3b) is imported by BOTH `ws-handler.ts` (replacing the local `STALE_HEARTBEAT_THRESHOLD_SECONDS`)
      and `agent-runner.ts` (replacing the local `STUCK_ACTIVE_THRESHOLD_SECONDS`) — i.e. the two TS thresholds
      are structurally de-duplicated to a single symbol, not two copies asserted equal. AC6 also covers the
      stale-comment sweep (all `120`/`120 s` prose refs in `ws-handler.ts`/`agent-runner.ts`/`index.ts:159`
      updated to 240 s so the coupling comments stay honest).
- [ ] **AC14** — A cap-hit `acquire` for user U reaps any of U's slots whose conversation has **no live local
      socket** on this instance, threshold-independent (restores immediate reclaim after a crash so the 240 s
      threshold does not produce a ≤4 min self-lockout). Test: seed a slot for U with a stale-but-<240 s
      heartbeat and no open socket → a new acquire succeeds (not `CONCURRENCY_CAP`).
- [ ] **AC7** — Invariant test **imports the live symbols** (not re-declared copies) and asserts, for all three
      heartbeat systems, `threshold >= 3 × interval` (routine-run-progress: `STUCK_THRESHOLD_MS`=180_000 ≥
      3×`HEARTBEAT_INTERVAL_MS`=60_000; worktree-lease: `LEASE_LIVENESS_WINDOW_MS`=240_000 ≥ ~4×`WORKTREE_LEASE_HEARTBEAT_MS`=50_000;
      concurrency-slot: `SLOT_STALENESS_THRESHOLD_SECONDS`=240 == 4×`SLOT_HEARTBEAT_INTERVAL_MS`/1000=60), matching the
      pre-change missed-beat tolerance. Also asserts `routine-run-progress` `STUCK_THRESHOLD_MS < ORPHAN_IGNORE_MS` still holds.
- [ ] **AC8** — **Grep-based drift-guard, not an enumerated allowlist** (the enumerated approach is what let
      3 sites slip past the first pass). The guard FAILS if any residual `120`-second liveness literal keyed on
      `last_heartbeat_at`/`heartbeat_at` survives across the code + migration surface:
      `grep -rnE "120_000|interval '120 seconds'" apps/web-platform/server/ws-handler.ts apps/web-platform/server/agent-runner.ts apps/web-platform/supabase/migrations/133_*.sql` returns **0**, AND
      `grep -c "interval '240 seconds'" migrations/133_*.sql` == 3 (acquire_conversation_slot + pg_cron sweep + acquire_worktree_lease)
      plus the `find_stuck_active_conversations` default is `240`. AC6's stale-comment sweep separately updates
      the `120`-in-prose references at `ws-handler.ts:504,514,534-544,2960` + `agent-runner.ts:781-794` +
      `index.ts:159` (comments can't reap a session, so they're swept but not part of the failing guard).
- [ ] **AC9** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. Test suite green via
      the package's actual runner (vitest — verify `apps/web-platform/vitest.config.ts` `include:` globs
      before placing new test files; do NOT assume `bun test`).
- [ ] **AC10** — Existing tests asserting old constants (30_000 / 90_000 / 25_000 / 120 s) are updated,
      not deleted, to the new values.

### Post-merge (operator/automated)

- [ ] **AC11** — Migrations 132/133/134 apply cleanly in prod via `web-platform-release.yml#migrate`
      (`doppler run -c prd`). Verify via `public._schema_migrations` containing 132/133/134
      (`gh` + Supabase MCP, no SSH).
- [ ] **AC12** — Post-deploy soak measured as a **windowed delta-rate**, NOT a single cumulative read
      (`top_write_churn.writes` and `pg_stat_statements.wal_bytes` are cumulative-since-`stats_reset` counters
      that only climb — a lone re-call can never "halve"). The follow-through probe (AC13) records a pre-deploy
      baseline `{n_tup_upd, ts}` for `user_concurrency_slots` from `pg_stat_user_tables` (via the Management API
      `/database/query`, `stats_reset`-aware), then at `earliest = deploy + 7d` computes the write rate and PASSes
      when it ≈ halves vs baseline. A **separate** advisor check (`/advisors/performance`, needs `SUPABASE_ACCESS_TOKEN`)
      confirms no NEW `unused_index`/slow-query regression from the drops, and an aggregate-controllable-write-rate
      check confirms the RLS change did not raise diffuse WAL (which `max_wal_pct` cannot catch — it stays low
      precisely because WAL is diffuse). No dashboard eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] **AC13** — Soak enrolled as an automated follow-through probe (not left to human memory): a new
      `scripts/followthroughs/concurrency-slot-wal-backoff-<issue>.sh` modeled on the existing
      `scripts/followthroughs/autovacuum-thrash-6168.sh` (same three hot tables, migration 123), a PR-body
      `<!-- soleur:followthrough script=… earliest=<deploy+7d> secrets=SUPABASE_ACCESS_TOKEN -->` directive with
      the `follow-through` label, and `secrets=` wired into `.github/workflows/scheduled-followthrough-sweeper.yml`
      (exit 0=PASS/auto-close, 1=FAIL/comment, 2=TRANSIENT).

## Implementation Phases

> **Phase order is load-bearing** (`Sharp Edges`): SQL threshold-raise (Phase 3a migration 133) is the
> *contract*; the TS heartbeat-interval backoff (Phase 3b) is the *consumer*. Migrations apply during
> `web-platform-release` **before** the container restarts with the new code, so the 240 s threshold is
> live before the 60 s heartbeat ships — the safe direction. Author the migration phase first.

### Phase 1 — Drop unused indexes (migration 132)

**Drop these 14 mature, non-UNIQUE secondary indexes** (all `idx_scan=0` per advisor; each verified
against its defining migration as a plain `CREATE INDEX`, not backing a UNIQUE/PK constraint; FK-column
indexes noted — FK *integrity* does not require the index, only cascade-lookup speed, and `idx_scan=0`
means even cascade checks are not using them):

| Index | Table (cols) | Defining mig | Notes |
|---|---|---|---|
| `idx_api_keys_user_id` | `api_keys(user_id)` | 001 | FK col; tiny table |
| `conversations_visibility_workspace_idx` | `conversations(workspace_id) WHERE visibility='workspace'` | 075 | partial |
| `idx_conversations_context_path` | `conversations(context_path) WHERE context_path IS NOT NULL` | 024 | partial |
| `dsar_export_jobs_pending_idx` | `dsar_export_jobs(requested_at) WHERE status='pending'` | 041 | partial |
| `idx_kb_share_links_content_sha256` | `kb_share_links(content_sha256)` | 026 | |
| `dsar_export_audit_pii_job_idx` | `dsar_export_audit_pii(job_id)` | 041 | FK col |
| `audit_byok_use_delegation_ts_idx` | `audit_byok_use(delegation_id, ts) WHERE delegation_id IS NOT NULL` | 064 | partial, FK col |
| `audit_byok_use_workspace_id_idx` | `audit_byok_use(workspace_id)` | 059 | FK col |
| `workspace_member_actions_workspace_created_idx` | `workspace_member_actions(workspace_id, created_at DESC)` | 063 | |
| `byok_delegation_acceptances_delegation_idx` | `byok_delegation_acceptances(delegation_id)` | 074 | FK col |
| `messages_workspace_id_idx` | `messages(workspace_id)` | 059 | **hot table — best write-amp win** |
| `outbound_sends_owner_sent_idx` | `outbound_sends(owner_id, sent_at DESC)` | 104 | |
| `kb_files_workspace_idx` | `kb_files(workspace_id)` | 077 | |
| `workspaces_installation_repo_idx` | `workspaces(github_installation_id, repo_url)` | 079 | |

**FK-cascade safety check (deepen-plan/work):** six candidates are on FK columns
(`idx_api_keys_user_id`, `dsar_export_audit_pii_job_idx`, `audit_byok_use_delegation_ts_idx`,
`audit_byok_use_workspace_id_idx`, `byok_delegation_acceptances_delegation_idx`, plus the workspace-keyed
ones). Before asserting drop-safety, verify each referencing FK's actual `confdeltype` from `pg_constraint`
(learning `2026-07-07-migration-cascade-safety-prose-must-verify-actual-fk-ondelete.md`) — an index-less
`ON DELETE CASCADE` against a *large* child table does a seq scan per parent delete. All these child tables
are small/low-write and `idx_scan=0`, so the risk is negligible, but confirm `confdeltype` rather than
assume. Also confirm none of the 14 is compensating for an index-free retention sweep elsewhere (learning
`2026-06-30-pgcron-cadence-is-wal-lever-retention-prune-is-disk-play.md`) — none are (all are secondary
lookup indexes, not sweep-sargability indexes).

**DEFER (young stats — do NOT drop):** `beta_contacts_user_last_contact_idx`,
`beta_contacts_user_stage_idx`, `interview_notes_contact_occurred_idx`,
`beta_contact_stage_transitions_contact_entered_idx` (all mig 126, 2026-07-08),
`beta_contact_access_log_user_accessed_idx`, `beta_contact_access_log_contact_idx` (mig 127,
2026-07-09). File the follow-up issue (AC3).

- `132_drop_unused_indexes.sql`: `DROP INDEX IF EXISTS public.<name>;` ×14 (non-concurrent; fine inside txn).
- `132_drop_unused_indexes.down.sql`: recreate all 14 with the **exact** definitions above.

### Phase 2 — Wrap `auth_rls_initplan` hotspots (migration 134)

Bounded to the hottest tables (write-churn-priority + read-hot). **Candidate set:**
`user_concurrency_slots`(1), `routine_runs`(1), `routine_run_progress`(1), `conversations`(5),
`messages`(2), `kb_files`(4), `push_subscriptions`(4). **Defer** the remaining ~35 low-traffic policies
to the same labeled follow-up as AC3.

**CRITICAL — source from LIVE `pg_policies`, NOT the defining migration** (security CRITICAL-1 +
data-integrity Finding 2). Several targeted policies were **redefined after** their original migration, and
sourcing the stale original silently drops a load-bearing clause:
- `conversations_owner_update`, `conversations_owner_insert`, `kb_files_owner_update` — authoritative
  definition is **migration 129** (`129_rls_write_check_workspace_member.sql`, #6334/ADR-111), whose
  `WITH CHECK` adds `AND public.is_workspace_member(workspace_id, auth.uid())`. That conjunct MUST survive
  the wrap — dropping it reopens the cross-tenant row-rehoming exposure #6334 was filed to close.
- `user_concurrency_slots_workspace_member_select` (mig 059), `messages_workspace_member_*` (mig 059) —
  live def is 059, not the mig-001/029 originals.
So: for every targeted policy, resolve its **current name + full `pg_get_expr(polqual, polrelid)` /
`pg_get_expr(polwithcheck, polrelid)` + `polpermissive` + `polroles` + `polcmd` from live `pg_policies`**
(via the Supabase MCP / introspection query), then emit `ALTER POLICY "<name>" ON public.<table>
USING (<wrapped>) [WITH CHECK (<wrapped>)];` wrapping **only** the `auth.<fn>()` calls, every other clause
byte-identical.

**Gate the candidate set to advisor-confirmed findings** (security Finding 6): cross-check each candidate
against a fresh `/advisors/performance` `auth_rls_initplan` pull and DROP any policy not actually flagged.
In particular **EXCLUDE the 3 `users` guard policies** ("Users cannot update github_username directly",
"Prevent client health_snapshot update", "Users cannot update kb_sync_history directly") and "Users can
read/update own profile": their `auth.uid()` already sits inside an uncorrelated scalar subquery
(`SELECT … WHERE id = auth.uid()`) that Postgres already hoists to a one-shot InitPlan — they are almost
certainly NOT in the 58 findings, so altering them is pure risk (highest mis-copy blast radius:
mig 016 documents that mangling the guard re-enables GitHub-installation-takeover) with zero measurable gain.

**Marginal-win note:** for the `is_workspace_member(...)`-based policies the wrap only hoists the `auth.uid()`
argument, not the per-row SECURITY DEFINER function call — the initplan win there is small (security Finding 5).

Example (canonical, verified safe): `conversations_owner_select` `USING (auth.uid() = user_id)` →
`USING ((select auth.uid()) = user_id)`.

`.down.sql` restores every unwrapped form (re-derived from the same live pre-134 `pg_get_expr` snapshot). **This is regulated-surface / RLS work** — `data-integrity-guardian`
+ `security-sentinel` must vet at deepen-plan/review; run `/soleur:gdpr-gate` (semantics are preserved, so
expected finding is "no material compliance change", but the gate must run).

### Phase 3 — Heartbeat backoff (highest risk)

#### Phase 3a — Staleness thresholds, SQL (migration 133) — CONTRACT, author first

Covers **both** heartbeat systems' staleness thresholds. Raise every 120 s liveness site to **240 s**
(= 4 × the new 60 s slot heartbeat = same missed-beat tolerance as today's 30 s/120 s; and 240 s ≈ 4.8 ×
the new 50 s lease heartbeat = same as today's 25 s/120 s). **The coupled set is 7 sites for the
concurrency slot + 1 SQL site for the lease** — the code's own coupling comments (`ws-handler.ts:534-538`,
`agent-runner.ts:781-788`, `037:38-42`) are the authoritative enumeration; a literal grep alone undercounts
(three review agents each found sites the first pass missed). Verified via
`grep -rn "120_000\|interval '120 seconds'\|last_heartbeat_at <\|heartbeat_at <" server/ migrations/`:

| # | Site | Current | New | Kind |
|---|---|---|---|---|
| 1 | `ws-handler.ts:545` `STALE_HEARTBEAT_THRESHOLD_SECONDS` | 120 | 240 | TS → **shared const** (slot) |
| 2 | `agent-runner.ts:789` `STUCK_ACTIVE_THRESHOLD_SECONDS` | 120 | 240 | TS → **shared const** (slot) |
| 3 | `ws-handler.ts:801` cap-drift self-eviction `liveCutoff` `120_000` (mirrors 093 sweep; load-bearing for mig-115 throttle) | 120_000 | 240_000 | TS literal (slot) |
| 4 | `ws-handler.ts:2059` `siblingSlotActive` snapshot-restore gate `120_000` | 120_000 | 240_000 | TS literal (slot) |
| 5 | mig 093 `acquire_conversation_slot(uuid,uuid,integer,uuid)` lazy sweep `interval '120 seconds'` (line 81) | 120 | 240 | **SQL — mig 133 (slot)** |
| 6 | mig **115** `user_concurrency_slots_sweep` pg_cron body (line 73, cadence `'0 * * * *'`) — the **live** sweep (029→038→115 supersession, last-writer-wins) | 120 | 240 | **SQL — mig 133 (slot)** |
| 7 | mig 037 `find_stuck_active_conversations` RPC **`p_threshold_seconds integer default 120`** (line 44) — coupled site #3 per the code comments; caller overrides to 240 but the default must move to keep the coupling honest + kill latent drift | 120 | 240 | **SQL — mig 133 (slot)** |
| 8 | `index.ts:159` comment "120 s slot-heartbeat…" | 120 | 240 | comment only (not guarded) |
| 9 | mig 116 `acquire_worktree_lease` takeover `heartbeat_at < now() - interval '120 seconds'` (line 128) | 120 | 240 | **SQL — mig 133 (lease)** |
| — | mig 029/038 sweeps + 029 `acquire_slot` | 120 | — | **superseded — do NOT touch/copy** |

- `133_heartbeat_threshold_backoff.sql` (4 SQL objects, each `CREATE OR REPLACE` copied **verbatim** from
  its LIVE source with only the interval literal changed, `SECURITY DEFINER`/`set search_path`/`lock_timeout`/
  advisory-lock/grants preserved): (a) `acquire_conversation_slot` (mig 093:50, 4-arg signature) lazy sweep
  120→240; (b) reschedule `user_concurrency_slots_sweep` reproducing **mig 115's** idempotent `DO $cron_block$`
  (cadence `'0 * * * *'` UNCHANGED) with 240 s body; (c) `find_stuck_active_conversations` (mig 037, latest
  def incl. mig-128 grant/comment) default `120`→`240`; (d) `acquire_worktree_lease` (mig 116:87) takeover
  120→240.
- `.down.sql`: restore all four to 120 s reproducing the **pre-133 LIVE state** — 093 acquire_conversation_slot,
  115 sweep at `'0 * * * *'`+120 s (NOT 029's per-minute), 037 default 120, 116 lease at 120 s.
- **Pin the coupling with cross-referencing comments** at all sites (learning
  `bug-fixes/2026-05-05-cc-stuck-active-conversation-leaks-slot.md` — divergent thresholds silently
  false-reap): each site's comment should name the other four and the shared 240 s value.
- **PostgREST schema cache:** `acquire_conversation_slot`'s signature is unchanged (body-only edit), so no
  `NOTIFY pgrst 'reload schema'` is required — but note the stale-cache risk from learning
  `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` if the signature ever changes.
- **/work must copy verbatim from the LIVE source:** `acquire_conversation_slot` (mig 093:50-120),
  the `user_concurrency_slots_sweep` `DO $cron_block$` (mig **115**:64-76, cadence `'0 * * * *'`),
  `find_stuck_active_conversations` (mig **037**, latest def + mig-128 grant/comment), and
  `acquire_worktree_lease` (mig **116**:87-131). The heartbeat writers `touch_conversation_slot` (mig 029)
  and `touch_worktree_lease` (mig 116) need **no** change — they only write `last_heartbeat_at`/`heartbeat_at`,
  no threshold. Use `CREATE OR REPLACE` (not `DROP`+`CREATE` — that loses the `grant execute … to service_role`
  at 093:124-125 / 037:63-64, making the RPC uncallable; security/data-integrity HIGH).

#### Phase 3b — TS heartbeat interval backoff — CONSUMER

- `ws-handler.ts:~2969`: extract the bare `setInterval(…, 30_000)` slot heartbeat into a named module
  const `SLOT_HEARTBEAT_INTERVAL_MS = 60_000` and use it. (Enables AC7 to assert on a symbol.)
- **Introduce ONE shared exported const** `SLOT_STALENESS_THRESHOLD_SECONDS = 240` (place in a small shared
  module, e.g. `server/concurrency-slots.ts`, or export from agent-runner) imported by BOTH `ws-handler.ts`
  (replacing local `STALE_HEARTBEAT_THRESHOLD_SECONDS`) and `agent-runner.ts` (replacing local
  `STUCK_ACTIVE_THRESHOLD_SECONDS`) — structurally de-duplicates the two TS thresholds so they cannot drift
  (simplicity reviewer: dedupe > drift-guard).
- `ws-handler.ts:801` and `ws-handler.ts:2059`: replace both bare `120_000` liveCutoff literals with
  `SLOT_STALENESS_THRESHOLD_SECONDS * 1000` (the cap-drift self-eviction + the sibling-snapshot-restore
  gate — architecture R3: leaving these at 120 s desyncs the read-side from the 240 s reaper).
- `routine-run-progress.ts:28-29`: `HEARTBEAT_INTERVAL_MS` 30_000→60_000; `STUCK_THRESHOLD_MS` 90_000→180_000.
  Consumers `list-routines.ts` (imports both) and `_cron-claude-eval-substrate.ts:914` recompile unchanged.
- `worktree-write-lease.ts`: `WORKTREE_LEASE_HEARTBEAT_MS` 25_000→50_000 (line 392); `LEASE_LIVENESS_WINDOW_MS`
  120_000→240_000 (line 79). `WORKTREE_LEASE_RELEASE_TIMEOUT_MS` (2 s) unchanged. **NOTE:** the matching
  SQL reclaim threshold (mig 116:128) is raised in Phase 3a — System B has a TS *and* a SQL side; both
  must move together or a live lease-holder gets its lease stolen after only 120 s (2.4 missed 50 s beats).

#### Phase 3d — worktree-lease SQL (folded into migration 133)

`acquire_worktree_lease` (mig 116:87) takeover predicate 120→240 s — see Phase 3a table row 9. Without it,
the TS window rises to 240 s but a competing host can still seize the lease at 120 s of silence (2.4 missed
50 s beats vs today's 4.8), a split-brain cross-host-write window on the worktree the lease exists to fence
(architecture R2 / data-integrity F3, single-user-incident surface).

#### Phase 3e — Cap-hit immediate-reclaim mitigation (in-scope, AC14)

Add the no-live-local-socket reap to `start_session` ledger-divergence recovery (see corrected Sharp Edge).
Without it the 240 s threshold produces a ≤4 min post-crash self-lockout for a cap-hit user.

#### Phase 3f — Tests

Add/adjust: the invariant test (AC7, imports live symbols), the grep-based drift-guard (AC8), the AC14
mitigation test, and update every existing test that pins an old constant (AC10). Place test files where
vitest's `include:` globs collect them (`apps/web-platform/test/**`), not co-located.

#### Rollback-ordering runbook (E5)

On any revert, **redeploy the old (30 s-heartbeat) code BEFORE rolling back migration 133** — else the live
60 s-heartbeat code runs against a rolled-back 120 s threshold (2 missed-beat tolerance) and falsely reaps a
session that pauses ~120 s (long tool call / GC). The forward deploy order is safe (migrate → deploy widens
tolerance first); only the inverse needs this guard. Record in the PR body's post-deploy section.

## Observability

```yaml
liveness_signal:
  what: disk_io_pressure_signal RPC (cache_hit_pct, max_wal_pct, top_write_churn, top_wal_statements)
        surfaced by cron-supabase-disk-io.ts threshold verdict. NOTE the returned counters are
        cumulative-since-stats_reset (mig 095/114) — trend/soak requires a windowed delta (AC12/AC13),
        never a single read.
  cadence: "0 */6 * * *" (every 6 h) — existing cron
  alert_target: auto-filed/auto-closed [disk-io] GitHub issue + Sentry (WAL-concentration breach)
  configured_in: apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts
error_reporting:
  destination: web-platform-release.yml#migrate fails loud on migration error (blocks deploy);
               cron-supabase-disk-io mirrors verdict to GitHub issue + Sentry
  fail_loud: true
failure_modes:
  - mode: false-reap of a live agent session (heartbeat/threshold ratio wrong) — THE load-bearing risk
    detection: NO existing signal fires at the reap site — the acquire_conversation_slot lazy sweep (mig 093), the
               user_concurrency_slots_sweep pg_cron (mig 115), and startStuckActiveReaper (agent-runner.ts)
               all DELETE silently on success; the existing reportSilentFallback(op="start_session-recovery",
               extra.staleHeartbeatCount) at ws-handler.ts:~626 fires on next-connect recovery and does NOT
               distinguish a correct dead-slot reclaim from a false live-slot reap. PLAN ADDS a distinct
               structured Sentry event AT the reap site when a reaped/finalized conversation was plausibly-live
               (heartbeat age within one interval OR open WS), carrying pre-reap heartbeat_age_seconds — the
               only signal that separates "mis-tuned threshold false-reaped a live loop" from routine cleanup.
    alert_route: Sentry (new reap-site event)
  - mode: RLS predicate semantic drift (row visibility widened/narrowed)
    detection: pg_policy shape assertion test incl. polpermissive (AC5) pre-merge; post-deploy no access-denied
               spike. NOTE a botched policy causing a seq scan raises DIFFUSE WAL that max_wal_pct cannot catch
               (stays low precisely because diffuse) — the follow-through (AC13) asserts aggregate write rate did not rise.
    alert_route: pre-merge test + Sentry auth errors + follow-through probe
  - mode: dropped index needed by a future query path
    detection: fresh /advisors/performance pull (Management API, SUPABASE_ACCESS_TOKEN) shows no new unused_index/
               slow-query; disk-io cron cache_hit regression
    alert_route: Supabase advisor + [disk-io] issue
logs:
  where: Sentry (server) + web-platform-release CI logs (migration apply) + follow-through sweeper run logs
  retention: Sentry default
discoverability_test:
  command: doppler run -p soleur -c prd -- bash -c 'curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/disk_io_pressure_signal" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" -d "{}"'
  expected_output: valid JSON with cache_hit_pct/max_wal_pct/top_write_churn present (liveness of the signal path). The write-rate HALVING verdict is NOT read from this single call — it is computed by the AC13 follow-through probe as a delta-rate over pg_stat_user_tables.n_tup_upd for user_concurrency_slots vs a pre-deploy baseline.
```

### Soak Follow-Through Enrollment (plan Phase 2.9.1 — mandatory: AC12 is a soak-gated close criterion)

AC12/AC13 declare a time-gated post-deploy verdict (write rate ≈ halves over 7 d), so the closure MUST be
automated. Deliverable: `scripts/followthroughs/concurrency-slot-wal-backoff-<issue>.sh` cloned from
`scripts/followthroughs/autovacuum-thrash-6168.sh` (already solves the cumulative-counter → delta-rate problem
for these exact three tables, migration 123); the PR-body `<!-- soleur:followthrough script=… earliest=<deploy+7d>
secrets=SUPABASE_ACCESS_TOKEN -->` directive + `follow-through` label; `secrets=` wired into
`.github/workflows/scheduled-followthrough-sweeper.yml`. Enforced at ship time by `/ship` Phase 5.5.

## Infrastructure (IaC)

No new infrastructure. Pure code + SQL migration against the already-provisioned Supabase project.
Migrations apply through the existing `web-platform-release.yml#migrate` path (`doppler run -c prd`);
the pg_cron sweep is re-scheduled *within* migration 133 (existing mechanism, not a new cron surface).
No server, secret, DNS, vendor, or firewall change. Phase 2.8 gate: **skip** (no new infra surface).

## Architecture Decision (ADR/C4)

**No ADR required.** This is parameter tuning *within* an already-documented invariant (the
heartbeat-vs-staleness-threshold coupling, warned in `ws-handler.ts:528-543`), plus removal of unused
indexes and a semantics-preserving RLS optimization. No ownership/tenancy move, no new substrate, no
resolver/trust-boundary change, no reversal of an existing ADR.

**No C4 impact.** Checked all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`): (a) no new external
human actor (no new correspondent/sender/recipient); (b) no new external system/vendor (no new webhook or
outbound API); (c) no new container/data-store — `user_concurrency_slots`, `routine_run_progress`,
`worktree_write_lease`, and all RLS-target tables live inside the already-modeled `supabase = database
"Supabase PostgreSQL"` element (`model.c4:164`); (d) no changed actor↔surface access relationship — the RLS
`ALTER POLICY`s preserve identical row-visibility semantics. Nothing to add or edit.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — sign-off gate).

### Engineering (CTO)
**Status:** to be covered by deepen-plan (data-integrity-guardian + architecture-strategist + security-sentinel)
and Plan Review (Kieran/DHH/Simplicity + arch-strategist + spec-flow at single-user-incident threshold).
**Assessment:** cross-layer heartbeat/threshold coupling is the load-bearing risk; the grep-based drift-guard
(AC8, over the full 7-site coupled set) and the invariant test (AC7, imports live symbols) are the mitigations.
SQL `CREATE OR REPLACE` of the four `SECURITY DEFINER` RPCs must preserve the `search_path` pin
(`cq-pg-security-definer-search-path-pin-pg-temp`) and `service_role` grants.

### Product/UX Gate
**Tier:** NONE — no user-facing UI surface (no `components/**`, `app/**/page.tsx`). Server/DB perf change only.

### Product (CPO sign-off)
**Status:** required at plan time (`requires_cpo_signoff: true`). Headless pipeline: sign-off is recorded as a
plan deliverable; `user-impact-reviewer` enforces at review time. The single-user-incident framing (false-reap
of a live session; RLS drift exposing another user's rows) is the sign-off subject.

## Non-Goals / Out of Scope

- **GoTrue-managed WAL (~36%): `refresh_tokens` / `sessions` / `mfa_amr_claims`.** These are internal
  Supabase Auth tables. Reducing them means JWT/session-lifetime config — a security tradeoff to decide
  separately. **Do not touch.** Follow-up: evaluate session/refresh-token lifetime config with a security lens.
- **Compute-tier upgrade.** Operator chose to keep Micro. No `compute_instance` add-on.
- **The 6 beta-CRM unused indexes** (mig 126/127) — deferred pending mature stats.
- **~35 low-traffic `auth_rls_initplan` policies** — deferred to a labeled follow-up.
- **32 `unindexed_foreign_keys` advisor findings** — out of scope (adding indexes increases write IO;
  the opposite of this PR's goal). Note for a future read-optimization pass only if a slow-query surfaces.

## Sharp Edges

- **Phase order is load-bearing:** the SQL 240 s threshold (mig 133, *contract*) must be authored/applied
  before the TS 60 s heartbeat (*consumer*). Migrations run before container restart in
  `web-platform-release`, so the safe direction is natural — but do not reorder the plan phases.
- **`CREATE INDEX CONCURRENTLY` cannot run inside the per-file txn** of `run-migrations.sh` (SQLSTATE 25001;
  learning `integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md`, which documents
  siblings 025/027 rejecting CONCURRENTLY). The down file for 132 recreates non-concurrently; verify whether
  the runner has a no-txn path (siblings 035/103 use CONCURRENTLY) before choosing CONCURRENTLY for the
  hot-table index rebuild.
- **`SECURITY DEFINER search_path` pin** must be preserved verbatim when `CREATE OR REPLACE`-ing `acquire_conversation_slot`
  in mig 133 (`cq-pg-security-definer-search-path-pin-pg-temp`) — do not let the copy drop `SET search_path`.
- **RLS `ALTER POLICY` must be byte-identical except the `(select …)` wrap.** A dropped `= id` /
  `workspace_member` clause is a single-user data-exposure incident. Assert via `pg_policy` shape (AC5).
- **[CORRECTED — the original claim here was false, spec-flow E3] Raising the threshold to 240 s DOUBLES a
  real cap-hit lockout.** A user at their concurrency cap whose WS crashes and then starts a **new**
  conversation is denied (`CONCURRENCY_CAP`) for up to **240 s** (was 120 s). The lazy sweep in
  `acquire_conversation_slot` is threshold-gated (deletes only slots ALREADY > 240 s stale), and the normal
  reconnect mints a **fresh** conversation UUID (`ws-handler.ts:~1774`), so `ON CONFLICT (user_id,
  conversation_id)` does NOT match the crashed row — a second slot is inserted and trips the cap. Only
  resume-**by-context-path** (same conversation row, no `acquireSlot` call) recovers immediately. At the
  `single-user incident` threshold a 4-minute self-lockout is NOT an acceptable silent tradeoff.
  **Mitigation (Phase 3e, in-scope deliverable):** the `start_session` ledger-divergence recovery
  (`ws-handler.ts:426-650`) must reap any of the user's slots whose `conversation_id` has **no live local
  socket on this instance** (the server already tracks its own OPEN sockets — the supersede path at
  `ws-handler.ts:234` uses exactly this signal), **independent of the 240 s heartbeat threshold** — this
  restores the immediate-free-on-reconnect behavior the plan wrongly assumed already existed. New AC14 covers it.
- **`index.ts:159` "60 s cadence" vs `agent-runner.ts:798` `STUCK_ACTIVE_CHECK_INTERVAL_MS = 300 s`** — the
  comments disagree on reaper cadence; the *threshold* (120→240 s) is what couples to the heartbeat. Only
  update the threshold + the stale comment; do not "fix" the cadence in this PR.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6.** It is filled above.
- Verify the vitest `include:` globs before placing new test files (repo uses vitest, not `bun test`;
  typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, not `npm run -w`).

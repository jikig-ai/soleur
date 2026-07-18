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

## Research Reconciliation — Spec vs. Codebase

| Claim (from task brief) | Reality (verified at plan time) | Plan response |
|---|---|---|
| "20 `unused_index` findings" | Advisor returns exactly **20** (verified via `/advisors/performance`). | Drop **14 mature** candidates; **defer 6** created in migrations 126/127 (2026-07-08/09 — ~10-day-old beta-CRM stats, too young to trust `idx_scan=0`). |
| "58 `auth_rls_initplan` policies" | Advisor returns exactly **58** across 38 tables. | Cap to the hottest tables (~23 policies); defer the rest to a labeled follow-up. |
| Priority tables incl. `mint_rate_window`, `runtime_mint_intent` | Neither has **any** flagged RLS policy (service-role-only tables; RLS not the write cost). | RLS workstream targets only `user_concurrency_slots`, `routine_runs`, `routine_run_progress` from the churn set + read-hot tables. |
| "routine-run-progress heartbeat 30000→60000 (line ~28)" | Confirmed `HEARTBEAT_INTERVAL_MS = 30_000` at `routine-run-progress.ts:28`; coupled `STUCK_THRESHOLD_MS = 90_000` (line 29), `ORPHAN_IGNORE_MS` 60 min (line 30). | Also raise `STUCK_THRESHOLD_MS` 90_000→180_000 (keep 3× ratio). `ORPHAN_IGNORE_MS` unchanged. |
| "worktree-write-lease WORKTREE_LEASE_HEARTBEAT_MS 25000 (line ~392)" | Confirmed at `worktree-write-lease.ts:392`; matching staleness `LEASE_LIVENESS_WINDOW_MS = 120_000` (line 79, ~4.8×). | Raise heartbeat 25_000→50_000 AND `LEASE_LIVENESS_WINDOW_MS` 120_000→240_000 (preserve missed-beat tolerance). |
| "ws-handler concurrency-slot heartbeat (~2959) + 60 s stuck-active reaper (index.ts ~159)" | Heartbeat is a **bare literal** `setInterval(…, 30_000)` at `ws-handler.ts:~2969` calling `touch_conversation_slot`. The 120 s staleness threshold is replicated across **5 sites** (see §Phase 3 coupling table). | Extract heartbeat to a named const → 60_000; raise **all five** 120 s sites → 240 s (TS ×3 + SQL ×2). |

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
      with their exact original definitions (columns, partial `WHERE`, ordering). Round-trip:
      `apply 132 → apply 132.down` returns `pg_indexes` for those 14 to the pre-132 state.
- [ ] **AC2** — Neither 132 file uses `CREATE INDEX CONCURRENTLY` (would fail SQLSTATE 25001 inside the
      per-file txn of `run-migrations.sh`). `DROP INDEX` (non-concurrent) is used in the up file. The
      down file recreates non-concurrently (rollback is a maintenance-window op; brief locks acceptable)
      — OR, if deepen-plan confirms `run-migrations.sh` has a documented no-txn path, hot-table indexes
      (`messages_workspace_id_idx`) recreate `CONCURRENTLY` in a no-txn down file. (Verify runner behavior.)
- [ ] **AC3** — The 6 beta-CRM indexes (migrations 126/127) are **NOT** dropped; a labeled follow-up
      issue exists (`disk-io`, `perf`, `deferred-scope-out`) to re-evaluate them once stats mature.
- [ ] **AC4** — `133_concurrency_slot_heartbeat_backoff.sql` `CREATE OR REPLACE`s the **live** `acquire_slot`
      (source: migration 093) with the lazy-sweep predicate `interval '120 seconds'` → `interval '240 seconds'`
      and re-schedules the `user_concurrency_slots_sweep` pg_cron job (source: migration 029) with the
      240 s predicate. `.down.sql` restores both to 120 s. `grep -c "120 seconds"` in the up file == 0.
- [ ] **AC5** — `134_rls_initplan_hotspots.sql` `ALTER POLICY`s each targeted policy (Phase 2 list) so
      every `auth.uid()` / `auth.jwt()` becomes `(select auth.uid())` / `(select auth.jwt())`, and the
      rest of each `USING`/`WITH CHECK` expression is **byte-identical** to the current definition.
      `.down.sql` restores the unwrapped form. Post-apply, a `pg_policy` shape check confirms every
      targeted policy's `polqual`/`polwithcheck` contains `(SELECT auth.` and the original predicate.
- [ ] **AC6** — TS heartbeat backoff applied: `routine-run-progress.ts` `HEARTBEAT_INTERVAL_MS`=60_000
      & `STUCK_THRESHOLD_MS`=180_000; `worktree-write-lease.ts` `WORKTREE_LEASE_HEARTBEAT_MS`=50_000 &
      `LEASE_LIVENESS_WINDOW_MS`=240_000; `ws-handler.ts` slot heartbeat=60_000 (named const) &
      `STALE_HEARTBEAT_THRESHOLD_SECONDS`=240; `agent-runner.ts` `STUCK_ACTIVE_THRESHOLD_SECONDS`=240;
      `index.ts:159` comment updated to "240 s slot-heartbeat staleness threshold".
- [ ] **AC7** — Invariant test asserts, for all three heartbeat systems, `threshold >= 3 × interval`
      (routine-run-progress: 180_000 ≥ 3×60_000; worktree-lease: 240_000 ≥ ~4×50_000; concurrency-slot:
      240 s == 4×60 s), matching the pre-change missed-beat tolerance. Test also asserts the
      `routine-run-progress` `STUCK_THRESHOLD_MS < ORPHAN_IGNORE_MS` invariant still holds.
- [ ] **AC8** — Cross-layer consistency test (or a source-grep drift-guard) asserts the concurrency-slot
      staleness threshold is `240` at **all five** sites: `ws-handler.ts` `STALE_HEARTBEAT_THRESHOLD_SECONDS`,
      `agent-runner.ts` `STUCK_ACTIVE_THRESHOLD_SECONDS`, and `interval '240 seconds'` in migration 133's
      `acquire_slot` + pg_cron sweep. No residual `120` staleness literal at any of the five.
- [ ] **AC9** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. Test suite green via
      the package's actual runner (vitest — verify `apps/web-platform/vitest.config.ts` `include:` globs
      before placing new test files; do NOT assume `bun test`).
- [ ] **AC10** — Existing tests asserting old constants (30_000 / 90_000 / 25_000 / 120 s) are updated,
      not deleted, to the new values.

### Post-merge (operator/automated)

- [ ] **AC11** — Migrations 132/133/134 apply cleanly in prod via `web-platform-release.yml#migrate`
      (`doppler run -c prd`). Verify via `public._schema_migrations` containing 132/133/134
      (`gh` + Supabase MCP, no SSH).
- [ ] **AC12** — Post-deploy soak: re-call `disk_io_pressure_signal` (24 h+ after deploy) and confirm
      `user_concurrency_slots` write count roughly halves vs the 8,711 baseline and its slice drops in
      `top_wal_statements`; confirm the 14 dropped indexes no longer appear in a fresh `unused_index`
      advisor pull. Automated (no dashboard eyeballing) per `hr-no-dashboard-eyeball-pull-data-yourself`.

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

Bounded to the hottest tables (write-churn-priority + read-hot). **Targeted set (~23 policies):**
`user_concurrency_slots`(1), `routine_runs`(1), `routine_run_progress`(1), `conversations`(5),
`messages`(2), `users`(5), `kb_files`(4), `push_subscriptions`(4). **Defer** the remaining ~35 policies
(beta-CRM, DSAR, byok_delegation*, workspace_* admin, org/team, audit, email, scope_grants, etc.) to the
same labeled follow-up as AC3. *(Plan-review/deepen-plan may trim to the top 3 churn tables +
`conversations` if a smaller diff is preferred.)*

For each targeted policy: read its **current** `USING`/`WITH CHECK` expression (from the defining
migration, cross-checked live via `pg_policies` if an introspection RPC is available), and emit
`ALTER POLICY "<name>" ON public.<table> USING (<wrapped>) [WITH CHECK (<wrapped>)];` wrapping **only**
the `auth.<fn>()` calls. Preserve every other clause byte-for-byte (especially the `users` guard
policies "Users cannot update github_username directly", "Prevent client health_snapshot update",
"Users cannot update kb_sync_history directly" — surgical edits only).

Example (canonical): `users` / "Users can read own profile": `USING (auth.uid() = id)` →
`USING ((select auth.uid()) = id)`.

**Permissive vs restrictive:** a table may carry both PERMISSIVE (allow) and RESTRICTIVE (deny) policies
(learning `2026-06-04-supabase-bucket-migration-down-and-rls-takeover-proof.md`). `ALTER POLICY` preserves
the policy's permissive/restrictive kind (it only edits `USING`/`WITH CHECK`/roles), so wrapping is safe
regardless — but the `pg_policy` shape assertion (AC5) must read `polpermissive` too and confirm it is
unchanged, not just that the predicate contains `(SELECT auth.`.

`.down.sql` restores every unwrapped form. **This is regulated-surface / RLS work** — `data-integrity-guardian`
+ `security-sentinel` must vet at deepen-plan/review; run `/soleur:gdpr-gate` (semantics are preserved, so
expected finding is "no material compliance change", but the gate must run).

### Phase 3 — Heartbeat backoff (highest risk)

#### Phase 3a — Concurrency-slot staleness threshold, SQL (migration 133) — CONTRACT, author first

The `user_concurrency_slots` 120 s staleness threshold is replicated across **5 sites** (per the
warning comment at `ws-handler.ts:528-543`). Raise all to **240 s** (= 4 × the new 60 s heartbeat =
same missed-beat tolerance as today's 30 s/120 s):

| # | Site | Current | New | Kind |
|---|---|---|---|---|
| 1 | `ws-handler.ts:545` `STALE_HEARTBEAT_THRESHOLD_SECONDS` | 120 | 240 | TS threshold |
| 2 | `agent-runner.ts:789` `STUCK_ACTIVE_THRESHOLD_SECONDS` | 120 | 240 | TS threshold |
| 3 | `index.ts:159` comment "120 s slot-heartbeat…" | 120 | 240 | comment only |
| 4 | mig 093 `acquire_slot` lazy sweep `interval '120 seconds'` (line 81) | 120 | 240 | **SQL — mig 133** |
| 5 | mig 029 `user_concurrency_slots_sweep` pg_cron `$sweep$` `interval '120 seconds'` | 120 | 240 | **SQL — mig 133** |

- `133_concurrency_slot_heartbeat_backoff.sql`: `CREATE OR REPLACE FUNCTION` `acquire_slot(...)` copied
  from migration 093 verbatim with the single `120 seconds`→`240 seconds` change (preserve the
  `SECURITY DEFINER` / `search_path` pin per `cq-pg-security-definer-search-path-pin-pg-temp`, the
  advisory-lock, `lock_timeout`, and the workspace_id INSERT contract exactly). Re-schedule the pg_cron
  sweep (unschedule + re-schedule, or replace its body) with the 240 s predicate. Keep the cron **cadence**
  unchanged.
- `.down.sql`: restore both to 120 s (re-`CREATE OR REPLACE` from 093, re-schedule sweep at 120 s).
- **Pin the coupling with cross-referencing comments** at all five sites (learning
  `bug-fixes/2026-05-05-cc-stuck-active-conversation-leaks-slot.md` — divergent thresholds silently
  false-reap): each site's comment should name the other four and the shared 240 s value.
- **PostgREST schema cache:** `acquire_slot`'s signature is unchanged (body-only edit), so no
  `NOTIFY pgrst 'reload schema'` is required — but note the stale-cache risk from learning
  `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` if the signature ever changes.
- **Deepen-plan must pull:** the exact live `acquire_slot` body (mig 093 full function) + the pg_cron
  `cron.schedule('user_concurrency_slots_sweep', …)` block (mig 029 lines ~219-230) so 133 replaces
  them faithfully. Confirm whether `touch_conversation_slot` (the heartbeat UPDATE RPC) needs no change
  (it does not — it only writes `last_heartbeat_at`, no threshold).

#### Phase 3b — TS heartbeat interval backoff — CONSUMER

- `ws-handler.ts:~2969`: extract the bare `setInterval(…, 30_000)` slot heartbeat into a named module
  const `SLOT_HEARTBEAT_INTERVAL_MS = 60_000` and use it. (Enables AC7/AC8 to assert on a symbol.)
- `routine-run-progress.ts:28-29`: `HEARTBEAT_INTERVAL_MS` 30_000→60_000; `STUCK_THRESHOLD_MS` 90_000→180_000.
  Consumers `list-routines.ts` (imports both) and `_cron-claude-eval-substrate.ts:914` recompile unchanged.
- `worktree-write-lease.ts`: `WORKTREE_LEASE_HEARTBEAT_MS` 25_000→50_000 (line 392); `LEASE_LIVENESS_WINDOW_MS`
  120_000→240_000 (line 79). `WORKTREE_LEASE_RELEASE_TIMEOUT_MS` (2 s) unchanged.

#### Phase 3c — Tests

Add/adjust: the invariant test (AC7), the 5-site consistency/drift-guard (AC8), and update every existing
test that pins an old constant (AC10). Place test files where vitest's `include:` globs collect them
(`apps/web-platform/test/**`), not co-located.

## Observability

```yaml
liveness_signal:
  what: disk_io_pressure_signal RPC (cache_hit_pct, max_wal_pct, top_write_churn, top_wal_statements)
        surfaced by cron-supabase-disk-io.ts threshold verdict
  cadence: "0 */6 * * *" (every 6 h) — existing cron
  alert_target: auto-filed/auto-closed [disk-io] GitHub issue + Sentry (WAL-concentration breach)
  configured_in: apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts
error_reporting:
  destination: web-platform-release.yml#migrate fails loud on migration error (blocks deploy);
               cron-supabase-disk-io mirrors verdict to GitHub issue + Sentry
  fail_loud: true
failure_modes:
  - mode: false-reap of a live agent session (heartbeat/threshold ratio wrong)
    detection: ws-handler emits staleHeartbeat Sentry events on boundary-race reaps; a spike
               (>1% of cap-hit events) signals mis-tuned thresholds
    alert_route: Sentry
  - mode: RLS predicate semantic drift (row visibility widened/narrowed)
    detection: pg_policy shape assertion test (AC5) pre-merge; post-deploy no access-denied spike
    alert_route: pre-merge test + Sentry auth errors
  - mode: dropped index needed by a future query path
    detection: next unused_index/slow-query advisor pull; disk-io cron cache_hit regression
    alert_route: Supabase advisor + [disk-io] issue
logs:
  where: Sentry (server) + web-platform-release CI logs (migration apply)
  retention: Sentry default
discoverability_test:
  command: doppler run -p soleur -c prd -- bash -c 'curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/disk_io_pressure_signal" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" -d "{}"'
  expected_output: JSON with user_concurrency_slots write count ~halved vs 8711 baseline; dropped indexes absent from a fresh unused_index advisor pull
```

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
**Assessment:** cross-layer heartbeat/threshold coupling is the load-bearing risk; the 5-site consistency
guard (AC8) and the invariant test (AC7) are the mitigations. SQL `CREATE OR REPLACE` of a `SECURITY DEFINER`
RPC must preserve the `search_path` pin (`cq-pg-security-definer-search-path-pin-pg-temp`).

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
- **`SECURITY DEFINER search_path` pin** must be preserved verbatim when `CREATE OR REPLACE`-ing `acquire_slot`
  in mig 133 (`cq-pg-security-definer-search-path-pin-pg-temp`) — do not let the copy drop `SET search_path`.
- **RLS `ALTER POLICY` must be byte-identical except the `(select …)` wrap.** A dropped `= id` /
  `workspace_member` clause is a single-user data-exposure incident. Assert via `pg_policy` shape (AC5).
- **Raising the concurrency-slot threshold to 240 s doubles the window** a genuinely-crashed session holds
  its slot against the user's cap (was 120 s). Mitigation: the lazy sweep on the *same user's* next acquire
  frees it immediately regardless; only fully-abandoned slots wait for the 240 s sweep. Acceptable tradeoff.
- **`index.ts:159` "60 s cadence" vs `agent-runner.ts:798` `STUCK_ACTIVE_CHECK_INTERVAL_MS = 300 s`** — the
  comments disagree on reaper cadence; the *threshold* (120→240 s) is what couples to the heartbeat. Only
  update the threshold + the stale comment; do not "fix" the cadence in this PR.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6.** It is filled above.
- Verify the vitest `include:` globs before placing new test files (repo uses vitest, not `bun test`;
  typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, not `npm run -w`).

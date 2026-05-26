---
date: 2026-05-06
topic: supabase-disk-io-budget
status: complete
brand_survival_threshold: single-user incident
---

# Brainstorm: Supabase Prod Disk IO Budget Depletion

## What We're Building

A two-lever remediation for the prod Supabase project (`ifsccnjhymdmidffkzhl`, soleur-web-platform, eu-west-1, Postgres 17.6, Micro tier) that stops Disk IO Budget depletion before it causes a brand-visible outage.

**Lever (a) — slow the pg_cron `user_concurrency_slots` sweep.** Currently every minute (`* * * * *`), running 1,440 times/day. In the captured stats window only 38 actual rows were ever deleted across 20,478 invocations. Each invocation still costs 4 writes (1 DELETE + 3 cron-plumbing writes to `cron.job_run_details`). New cadence: `*/5 * * * *` or `*/15 * * * *`, decided in the spec.

**Lever (b) — audit the Realtime publication on `conversations` + `messages`** (added in migration `034_conversations_messages_realtime_publication.sql`). The Realtime WAL parser is the #1 query by total exec time (1.12M ms / 219,793 calls / 325M block hits) — driven by ~10 polls/sec regardless of actual data. Decide: keep as-is, scope to fewer event types / row filters, or replace the dashboard subscription (`apps/web-platform/hooks/use-conversations.ts:232-279`, `:294-316`) with on-demand fetch.

## Why This Approach

- **Optimize-first beats upgrade-first** (CTO + CPO + COO agree). Bumping the compute add-on Micro → Small ($15/mo) only doubles the IO baseline (87 → 174 MB/s) and rents around an indexable problem; CPO flagged "billing surprise" as a worst-case in the user-impact framing.
- **The IO is structural, not user-driven.** Live data is tiny: 58 conversations, 126 messages, 0 live concurrency slots. The IO consumers are housekeeping plumbing (cron + Realtime polling), independent of how many users are active.
- **Cheapest defensible path** under the single-user incident threshold: change behavior we control before paying recurring rent. Lever (a) is one migration, online, instantly reversible. Lever (b) is a scoped audit — could land as "no change, ship instrumentation" if Realtime is genuinely needed.

## User-Brand Impact

**Brand-survival threshold: `single-user incident`.** Operator answered "all of them" to the user-impact framing question (outage / slow degradation / billing surprise / data loss).

**Artifact at risk:** every authenticated session backed by prod Supabase — chat history, conversation state, billing-tied API keys.

**Vector:**
1. IO budget exhausts → instance becomes unresponsive → every logged-in user sees timeouts, broken chat, failed sends.
2. Hasty compute upgrade locks in higher monthly burn for a problem that was indexable / schedule-tunable.
3. Aggressive remediation (e.g., dropping the Realtime publication mid-traffic, or running VACUUM FULL during peak) corrupts or temporarily delays user-owned data.

**Threshold:** any plan derived from this brainstorm inherits `Brand-survival threshold: single-user incident`. Plan Phase 2.6 carries this forward; user-impact-reviewer + CPO sign-off mandatory before `/work`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Diagnose-first vs upgrade-first | Diagnose-first | CTO: upgrade masks root cause, locks in burn, recurs at higher floor. CPO: upgrade is a *bridge*, not a *destination*. |
| Path | Both (a) + (b) | Operator selected. (a) is cheap and instant; (b) attacks the dominant offender (Realtime WAL parsing). |
| Compute bump as tripwire | Deferred | Only if depletion rate during diagnosis exceeds X%/hr. Deferred to a separate issue with the Terraform-gap closing as prereq. |
| Cron cadence | Defer to spec/plan | Choose between `*/5 * * * *` (5-min) and `*/15 * * * *` (15-min). Trade-off: dead slot persistence window. |
| Realtime audit outcome | Defer to spec/plan | Three options: keep, scope (row filters / event-type narrowing), or replace with on-demand fetch in `use-conversations.ts`. |
| SECDEF `pg_temp` pin fixes (017, 027) | Defer | Security side-finding, separate issue. |
| Supabase Terraform provider gap | Defer | Required if/when a compute-tier change ships; not on this PR's path. |

## Non-Goals

- **Compute add-on tier upgrade** — explicitly NOT this PR. Re-evaluate only if depletion accelerates during the diagnose window. Tracked separately.
- **Closing the Supabase Terraform gap** — required prerequisite for any future tier change but not needed for the cron + Realtime fixes. Tracked separately.
- **Fixing the 2 SECURITY DEFINER `pg_temp` gaps** in migrations 017 + 027 — security correctness side-finding, separate issue.
- **Reducing the 30s WS heartbeat or 60s WS subscription refresh** — not in top IO offenders; user-data row churn is already negligible.
- **Caching middleware `users` SELECT** — not in top 15 by exec time; revisit if traffic grows.
- **Read replica or pooler-tier change** — wrong tool: no read pressure, the IO is from WAL writes + cron plumbing.

## Open Questions

1. **Cron cadence target** — 5-min or 15-min? With 0 live slots and 38 deletes in 14+ days, 15-min seems safe. Plan should verify whether any code path reads concurrency slots assuming sub-5-min freshness.
2. **Realtime consumer impact** — what does `use-conversations.ts` actually need from the postgres_changes subscription? If it's "refresh the conversation list when one is created/archived," a `INSERT, UPDATE` filter (no DELETE) and column-level filtering would shrink WAL fan-out. If it's purely cosmetic, drop the subscription and rely on existing on-demand fetch.
3. **Will slowing cron break the stuck-active reaper?** Migration 037 adds a separate `find_stuck_active_conversations` RPC called every 60s from `agent-runner.ts:523`. That is a different code path — confirm in the plan that the cron change does not cross-impact it.
4. **Stats reset window** — when did `pg_stat_statements` last reset? Numbers above are over an unknown window (likely ~14 days based on autovacuum dates). Plan should re-pull stats post-fix to verify the savings.

## Domain Assessments

**Assessed:** Engineering, Product, Legal, Operations

### Engineering (CTO)

**Summary:** Diagnose-first with a tripwire is the only defensible ordering under the single-user incident threshold. Cheapest path is index/query work + cron-cadence change + Realtime publication audit; compute bump is a fallback, and the Supabase Terraform gap blocks any IaC-compliant tier change. Two SECURITY DEFINER functions in migrations 017 + 027 violate `cq-pg-security-definer-search-path-pin-pg-temp` — flagged as a security side-finding.

### Product (CPO)

**Summary:** Threshold confirmed: `single-user incident`. Instrument before remediating so we can prove the fix worked from the user's perspective, not just the operator's IO graph. Acceptable remediation postures: no-window > soft-degrade with banner > maintenance gate. Hard-blocked: silent data loss, partial writes, unannounced spikes. Compute upgrade is acceptable only as a *time-bounded cushion* with an explicit downgrade trigger.

### Legal (CLO)

**Summary:** Cron-cadence + Realtime-audit + index/query work have **zero subprocessor surface** (no new vendor disclosure required). Cache layers, Upstash/Redis, or read replicas in different regions WOULD trigger Privacy Policy / DPA / GDPR processing-register edits — explicitly out of scope here. Hard line during diagnostics: no raw slow-query output containing PII in public PRs or new APMs. Cross-tenant exposure from a botched query rewrite is the highest-severity legal risk in the menu and would be a 72h GDPR notification.

### Operations (COO)

**Summary:** Current line item: Supabase Pro $25 + custom domain $10 = $35/mo (default Micro compute tier — no add-on selected). Optimize-only path = $0 incremental. The Supabase Terraform provider is **not** in `apps/web-platform/infra/` — only the Cloudflare CNAME. Any future compute change requires closing that IaC gap first per `hr-all-infrastructure-provisioning-servers`. `/ship` Phase 5.5 COO expense-tracking gate fires only on new vendors today; if a tier bump ever ships, file a parallel issue to widen the trigger to add-on changes too.

## Capability Gaps

- **Supabase Terraform provider** is not declared in `apps/web-platform/infra/main.tf` (verified by COO via direct read of `apps/web-platform/infra/dns.tf:84-95` showing only `cloudflare_record.supabase_custom_domain`, and `apps/web-platform/infra/main.tf` containing no `supabase/supabase` provider). Consequence: any compute-tier change is dashboard-only today, which would violate `hr-all-infrastructure-provisioning-servers`. **Not a blocker for this PR** (no tier change here) but called out so the deferred tripwire-bump issue can include the gap-closure as a prereq.

## Diagnostics Captured (2026-05-06)

Pulled live from prod via Supabase Management API:

**Top 4 queries by total exec time:**
1. Realtime WAL parser (`SELECT wal->>$5 as type ...`) — **1,119,896 ms** / 219,793 calls / 325M block hits / 100% cache hit
2. Realtime WAL parser (variant) — 88,151 ms / 25,437 calls
3. `SELECT name FROM pg_timezone_names` — 74,174 ms / 102 calls (727 ms each — Studio/dashboard query)
4. `INSERT INTO cron.job_run_details` — 68,783 ms / 20,478 calls (cron plumbing)

Plus combined cron `UPDATE` writes: ~50K ms / ~41K calls.

**Top write churn (`pg_stat_user_tables`):**
- `user_concurrency_slots`: 38 ins / 829 upd / 38 del — heartbeat-driven, sweep-cleaned
- `conversations`: 98 ins / 410 upd / 37 del
- `messages`: 246 ins / 0 upd / 120 del
- `users`: 24 ins / 320 upd / 11 del
- `realtime.subscription`: 147 ins / 147 del — subscribe/unsubscribe churn

**Cron schedule:** 1 job, `* * * * *`, deleting `user_concurrency_slots` rows older than 120s. 1,440 runs/day verified.

**Compute add-on:** None selected (Micro default). Baseline 87 MB/s disk IO, burst 2,085 MB/s.

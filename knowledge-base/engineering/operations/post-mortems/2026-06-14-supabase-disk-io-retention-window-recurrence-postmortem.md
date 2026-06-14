---
title: "Supabase prod Disk-IO budget depletion recurrence — processed_github_events 90d retention window too long"
date: 2026-06-14
incident_pr: 5286
incident_window: "2026-06-12T18:00Z (monitor first tripped) → 2026-06-14 (fix shipped)"
recovery_at: "pending — monitor auto-closes #5225 when row count drops below 100k post-deploy"
suspected_change: "migration 094 (2026-06-02) — copied the 90-day retention window from the processed_stripe_events sibling onto processed_github_events"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - vendor warning (Supabase Disk-IO Budget depletion email, re-sent 2026-06-14)
  - proactive monitor tripwire (cron-supabase-disk-io, migration 095) filed #5225 on 2026-06-12
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

Production Supabase (`soleur-web-platform`, ref `ifsccnjhymdmidffkzhl`) re-sent a Disk-IO Budget depletion warning on 2026-06-14, ~12 days after the 2026-06-02 remediation (migration 094 retention sweep + migration 095 proactive monitor) that was supposed to fix exactly this. The proactive monitor had already detected the recurrence and filed action-required issue #5225 on 2026-06-12, but no operator acted for ~2 days while the `processed_github_events` table kept growing.

This was an **availability-risk** incident (write-IO budget depletion that, if fully exhausted, throttles all DB writes), caught **before** any user-visible outage by the monitor built for this exact purpose. No data was exposed.

## Status

resolved — fix (migration 103) shipped in PR #5286; recovery is auto-verified by the existing monitor.

## Symptom

Supabase Disk-IO Budget depleting on the single prod project. `cron-supabase-disk-io` tripped its `DEDUP_TABLE_ROW_CEIL = 100_000` lever: `processed_github_events` at 123,416 rows (2026-06-12), climbing to 128,589 over the next two days. `cache_hit_pct = 100%` (write-driven, not read-driven).

## Incident Timeline

- **Start time (detected):** 2026-06-12T18:00:49Z (monitor filed #5225)
- **End time (recovered):** pending post-deploy budget-recovery verification
- **Duration (MTTR):** fix shipped within hours of the 2026-06-14 operator-forwarded vendor warning

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-06-12T18:00Z | `cron-supabase-disk-io` tripwire fired (123,416 rows > 100k ceil); filed #5225 (p1, action-required). |
| system | 2026-06-13 → 06-14 | Monitor re-commented every 6h; row count climbed to 128,589. |
| human | 2026-06-14 | Operator forwarded the Supabase vendor warning to `/soleur:go`. |
| agent | 2026-06-14 | Diagnosed via Management API: cron scheduled+active but `DELETE 0` nightly; oldest row only ~24 days old vs 90-day window. |
| agent | 2026-06-14 | Shipped migration 103 (window 90d→7d + one-time purge + stale-comment correction) in PR #5286. |

## Participants and Systems Involved

- Supabase prod project `ifsccnjhymdmidffkzhl` (single shared substrate for all authenticated sessions).
- `public.processed_github_events` (GitHub webhook delivery dedup), `pg_cron` job `processed_github_events_retention`.
- `cron-supabase-disk-io` Inngest monitor + `disk_io_pressure_signal()` RPC (migrations 094/095).

## Detection (+ MTTD)

- **How detected:** the project's own proactive monitor (`cron-supabase-disk-io`, 6-hourly) — exactly the early-warning system the 2026-06-02 work built. The vendor email arrived after the monitor had already filed #5225.
- **MTTD:** ~hours (monitor fires every 6h; tripped on the first crossing of the 100k ceiling).

## Triggered by

system — an internal retention-window misconfiguration (migration 094), surfaced by ongoing webhook INSERT volume.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Retention cron stopped (monitor's stated guess + auto-triage comment) | row count climbing | `cron.job_run_details`: job active, `succeeded`, runs nightly | REJECTED |
| Retention window (90d) exceeds the table's max age, so DELETE matches nothing | oldest row 2026-05-21 (~24d); every run `DELETE 0`; window=90d | — | CONFIRMED |
| Read-pressure regression (missing index) | — | `cache_hit_pct = 100%` | REJECTED |

## Resolution

Migration 103: re-schedule `processed_github_events_retention` with a 7-day window (>2× margin over GitHub's documented 3-day github.com webhook-delivery-log retention horizon), plus a one-time `DELETE` of ~91k stale rows so relief lands at deploy (atomic under `run-migrations.sh --single-transaction`). Also corrected the stale `052` `COMMENT ON TABLE` ("30-day partition rotation" — never existed) that misled 094 into copying the Stripe 90-day window, and widened the monitor's alert text to name both failure modes (sweep stopped OR window too long).

## Recovery verification

Post-merge (automated, no dashboard eyeballing): the migrate job applies 103; the next `cron-supabase-disk-io` fire reads `processed_github_events` row count < 100k (purge drops it to ~37k) and auto-closes #5225. Belt-and-suspenders: Management-API `SELECT count(*)` (PASS ≤ 40k) + `cron.job` command query (PASS contains `interval '7 days'`), then a ~3-day `disk_io_pressure_signal()` re-check (`cache_hit_pct ≥ 98`, row count stable/declining).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the Disk-IO budget deplete?** Constant INSERT + index write-IO on an unbounded-growing `processed_github_events` table.
2. **Why was it unbounded?** Its daily retention sweep deleted 0 rows every night.
3. **Why did it delete 0 rows?** The DELETE window (90 days) exceeded the table's maximum row age (~24 days), so no row ever qualified.
4. **Why was the window 90 days?** Migration 094 copied it verbatim from the `processed_stripe_events` sibling (where 90d = Stripe's replay horizon).
5. **Why was the wrong window copied?** A stale `COMMENT ON TABLE` in migration 052 falsely described retention as "autovacuum + 30-day partition rotation," so the real horizon (GitHub's 3-day redelivery window) was never the reference point.

## Versions of Components

- **Version(s) that triggered the outage:** migration 094 (2026-06-02).
- **Version(s) that restored the service:** migration 103 (PR #5286).

## Impact details

### Services Impacted

Prod Supabase write path (degraded headroom only; no exhaustion reached). No user-visible outage.

### Customer Impact (by role)

- Prospect: none (no public surface depends on this table).
- Authenticated app user: none observed — budget never fully exhausted; risk was throttled writes had it depleted.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none observed (billing reads share the substrate; no throttling reached).
- OAuth installation owner: none — webhook dedup remained correct throughout (no double-processing; the bloat was stale-but-harmless rows).

### Revenue Impact

None.

### Team Impact

~2 days of an open p1 action-required issue unactioned; one diagnosis+fix cycle.

## Lessons Learned

### Where we got lucky

The proactive monitor (built 2026-06-02) caught the recurrence before the budget fully depleted — no user-visible outage. The dedup correctness was never at risk (over-retention is harmless to dedup; only under-retention risks double-processing).

### What went well

Diagnosis was fast and data-driven (Management API: cron run history + age distribution immediately falsified the "sweep stopped" hypothesis). The monitor's `top_write_churn` + row-count signal pointed straight at the table.

### What went wrong

(1) The 2026-06-02 fix chose a window from a stale comment rather than the table's real replay horizon — re-arming the same class. (2) The monitor's diagnostic text ("retention sweep may have stopped") was single-cause and misleading; the auto-triage comment amplified the wrong hypothesis. (3) The action-required issue sat ~2 days before an operator acted.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #5225 | Verify prod Disk-IO budget recovers (row count < 100k and stable/declining; `cache_hit_pct ≥ 98`) post-deploy, then close — auto-closed by the `cron-supabase-disk-io` monitor on recovery, or manually with the API verdict if not. | open |

---
title: "Latent read of a nonexistent action_sends.created_at column in the leader loop and cost route"
date: 2026-09-25
incident_pr: 8837
incident_window: "2026-09-03 (6bc762c66b, #7774) to the #8837 merge; zero founder traffic in the window"
recovery_at: "the #8837 merge"
suspected_change: "6bc762c66b fix(model-launch): Fable 5.1 would have made the drift cron permanently red (#7774)"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - code review of #8837 (data-integrity seat, live zero-row PostgREST probe)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was exposed; the defect only made a read fail"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

From 2026-09-03 the leader loop (`agent-on-spawn-requested`, step `read-action-send-created-at`) and the dashboard cost route (`app/api/dashboard/today/[id]/cost/route.ts`) selected `action_sends.created_at`. No migration declares that column; the table's timestamp is `clicked_at` (migration 051). Any spawn would have failed at that step, and the cost route would have answered 0 cents.

This was a **latent** defect. The prd `action_sends` table has never held a row (read-only count on 2026-09-25: 0 rows, against 17 `users` and 1,460 `messages` in the same query as a control). No founder reached either path, so there was no user-visible failure.

## Status

resolved — both reads use `clicked_at` in #8837, and a contract test now fails on any `action_sends` column no migration declares.

## Symptom

None observed. The expected symptom on first use was a spawn stuck on "Working" (the run would fail with no `onFailure`, which is #8803 itself) and a 0-cent cost line.

## Incident Timeline

- **Start time (detected):** 2026-09-25, during #8837 review
- **End time (recovered):** the #8837 merge
- **Duration (MTTR):** under one day from detection

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-03 | 6bc762c66b (#7774) lands the `created_at` read; every suite mocks Supabase, so CI stays green. |
| agent | 2026-09-25 | #8837 review: the data-integrity seat runs `select=created_at&limit=0` against PostgREST and gets 42703. |
| agent | 2026-09-25 | Both reads switched to `clicked_at`; `test/action-sends-column-contract.test.ts` added. |
| agent | 2026-09-25 | prd `action_sends` counted: 0 rows ever, so no founder was affected. |

## Participants and Systems Involved

Claude Code (review and fix). Systems: Inngest function `agent-on-spawn-requested`, the dashboard cost route, Supabase `action_sends`.

## Detection (+ MTTD)

- **How detected:** code review with a live schema probe, not monitoring. The path had no traffic, so no monitor could fire.
- **MTTD (mean time to detect):** 22 days.

## Triggered by

system — a code change (6bc762c66b).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| A column name written from memory, certified by mocked suites | PostgREST 42703 on `created_at`; migration 051 declares `clicked_at`; every suite that touches the table mocks the client | none | confirmed |

## Resolution

#8837 reads `clicked_at` in both places and adds a migrations-derived column contract test with a positive control.

## Recovery verification

`test/action-sends-column-contract.test.ts` passes on the #8837 head in CI's required `test` context; its positive control flags `created_at`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why would a spawn have failed? The read selected a column that does not exist.
2. Why was the column named wrong? It was written from the common Supabase convention (`created_at`), not from the migration.
3. Why did CI pass? Every suite touching `action_sends` mocks the Supabase client, and a mock answers for any column name.
4. Why did no monitor catch it? The path had zero traffic in prd.
5. Why was there no schema check? Nothing compared app-side column references to the DDL; the new contract test does.

## Versions of Components

- **Version(s) that triggered the outage:** 6bc762c66b onward (no failure was ever served; see Overview)
- **Version(s) that restored the service:** the #8837 merge

## Impact details

### Services Impacted

Spawned agent runs from the Today card, and the dashboard cost line for them. Neither had traffic.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none (0 `action_sends` rows in prd)
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

One review finding and a fix inside an in-flight PR.

## Lessons Learned

### Where we got lucky

The feature had no traffic yet, so the defect never reached a founder.

### What went well

A reviewer tested the schema itself (a zero-row live query) instead of trusting green mocked suites.

### What went wrong

A mocked data layer certified a nonexistent column for 22 days.

## Action Items & Follow-ups

No action items — incident fully resolved in the source PR with no residual work.

---
title: "Better Stack 80% log-quota warning — host-metrics ingest near-miss"
date: 2026-06-10
incident_pr: 5105
incident_window: "2026-05-21 → 2026-06-10 (volume accumulating since the Vector source was created)"
recovery_at: "2026-06-10 (remediation merged; deploy + AC12 verdict tracked in #5110)"
suspected_change: "30s host_metrics scrape in apps/web-platform/infra/vector.toml shipping as log events through the generic HTTP sink"
brand_survival_threshold: none
status: resolved
triggers:
  - vendor quota threshold email (Better Stack "80% of plan quota")
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data exposure; availability/quota near-miss only, data egress strictly decreased"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Near-miss, not an outage: Better Stack emailed the operator that org Jikigai reached 80% of its free-tier plan quota (3 GB/month logs, 3-day retention + 30 GB metrics). At 100%, Better Stack drops new data — which would have silently blinded the WARN+ log/diagnosis channel (Sentry and uptime monitors were unaffected). No data was dropped; no user-facing impact occurred.

## Status

resolved

## Symptom

Vendor email: "Your organization Jikigai is at 80% of your plan quota. Any new data will be dropped once you hit the limit." No source, quota type, or number named; Better Stack has no public usage API.

## Incident Timeline

- **Start time (detected):** 2026-06-10 (operator read the vendor email and pasted it into a session)
- **End time (recovered):** 2026-06-10 (remediation merged; runtime verdict pending per #5110)
- **Duration (MTTR):** same-day from detection to merged remediation

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-10 ~13:00 | Pasted the Better Stack 80%-quota email into a session (`/soleur:go`). |
| agent | 2026-06-10 13:06–13:25 | Enumerated sources via Telemetry API; measured per-source volume via `scripts/betterstack-query.sh`: host metrics >99% of rows (~196k/day) vs ~50 journald WARN+ rows/day. |
| agent-with-ack | 2026-06-10 ~13:30 | Operator chose "Tune Vector, stay free" and approved deleting the leftover "Onboarding • Real-time flights" demo source (id 2327782, 10-year retention); deletion executed via Telemetry API (HTTP 204). |
| agent | 2026-06-10 14:00–16:00 | PR #5105: `scrape_interval_secs` 30→300 + `loop*`/`dm-*` device excludes (binary-verified on pinned Vector 0.43.1); expense ledger updated ($0.00 unchanged). |

## Participants and Systems Involved

Operator (Jean), Better Stack Telemetry (logs source 2457081, eu-fsn-3), Vector 0.43.1 on the Hetzner cx33, Doppler `soleur/prd_terraform` (API + query credentials).

## Detection (+ MTTD)

- **How detected:** external — vendor threshold email read by the operator. No internal monitor watches Better Stack quota consumption (no public usage API exists).
- **MTTD (mean time to detect):** unknowable precisely; the volume ran ~20 days (source created 2026-05-21) before the 80% email. Detection depended entirely on the operator reading email — the bottleneck #5103 (operator inbox delegation) exists to remove.

## Triggered by

provider — vendor quota threshold notification.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Host metrics dominate ingest via the generic HTTP sink (counted against the LOGS quota) | ~196k aggregated metric rows/day vs ~50 journald WARN+ rows/day; metric events arrive as JSON log events because the native `better_stack_logs` sink does not exist | — | confirmed |
| Leftover onboarding demo source consuming quota | 10-year retention, created 2026-03-28 | demo source lives in a different region cluster; volume small relative to host metrics | contributing, minor |

## Resolution

PR #5105: cut host-metrics volume ~90% (300s scrape + `loop*`/`dm-*` excludes on disk/filesystem collectors), stay on the free tier ($0.00; ledger upgrade trigger "first paying customer" unchanged). Demo source deleted same-day outside the PR. Decision record: `knowledge-base/operations/expenses.md` Better Stack row; learning: `knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`.

## Recovery verification

Pre-merge: `vector validate` exit 0 on pinned 0.43.1; PII parity suite 26/26; AC1–AC8 grep/diff gates green; `validate-vector-config.yml` CI green. Runtime verdict: #5110 (first full post-deploy day ≤ 25,000 host rows vs ~196k baseline via `scripts/betterstack-query.sh`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the quota warning fire? Better Stack log ingestion approached 3 GB/month.
2. Why was ingestion that high? The `host_metrics` source scraped ~100 series every 30s (~196k rows/day), >99% of shipped volume.
3. Why did metrics count against the LOGS quota? Vector ships them as JSON events through the generic HTTP sink (`[sinks.betterstack]` is `type = "http"` — the native metrics-aware sink does not exist; Vector PR #19274 closed unmerged).
4. Why was the 30s interval chosen? It was carried over from the original Sentry-bound design (#4250, "low cardinality, low cost" under Sentry's envelope model) and never re-derived when the sink pivoted to Better Stack (#4277/#4279), whose billing is per-GB ingested.
5. Why did nobody notice for ~20 days? Better Stack has no usage API and no internal monitor watches quota; detection depended on the operator reading a vendor email (#5103).

## Versions of Components

- **Version(s) that triggered the near-miss:** vector.toml with `scrape_interval_secs = 30` (since PR #4277/#4279 pivot; source created 2026-05-21)
- **Version(s) that restored headroom:** PR #5105 (300s + device excludes), deployed via `vinngest-v1.1.12` + PR #5131 (collector trim: network dropped, filesystem mountpoint allowlist) deployed via vinngest-v1.1.13 after the AC12 verdict FAILED at 198 rows/scrape (~57k/day projected)

## Impact details

### Services Impacted

None user-facing. At 100% quota the WARN+ log/diagnosis channel to Better Stack would have gone dark (operator blind spot); Sentry error tracking and uptime monitors were independent and unaffected.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None. $0.00 spend unchanged; remediation avoided an unnecessary ~$30/mo (Nano) or pay-as-you-go upgrade.

### Team Impact

~3 hours of one session (diagnosis → decision → remediation → ship).

## Lessons Learned

### Where we got lucky

The vendor emails at 80% (not 95%), and the operator read the email the same day. With the email unread, data would have started dropping silently — there is no in-repo signal for Better Stack quota.

### What went well

Per-source measurement was one query away (`scripts/betterstack-query.sh` + Telemetry API token already in Doppler); the dominant producer was unambiguous; remediation needed no spend and no new vendor.

### What went wrong

The 30s scrape interval was never re-derived when the metrics destination pivoted from Sentry (per-envelope billing) to Better Stack (per-GB billing); the onboarding demo source lingered with 10-year retention; quota detection depends on a human reading vendor email.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5110 | AC12 runtime verdict: first full post-deploy day ≤ 25k host-metrics rows (operator-confirmed follow-through, sweeper-tracked). First verdict FAILED 2026-06-10 (198 rows/scrape, ~57k/day projected); second-pass collector trim (PR #5131, vinngest-v1.1.13) re-runs the verdict — closure gates on the post-trim `RESULT: PASS` | open |
| #5103 | Operator inbox delegation — remove "human reads vendor email" as the detection path for vendor notifications (this near-miss is the motivating example) | open |

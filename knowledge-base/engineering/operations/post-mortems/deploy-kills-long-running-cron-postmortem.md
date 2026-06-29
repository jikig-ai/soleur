---
title: "Post-Incident Report — app redeploy kills long-running Claude-eval crons mid-flight"
date: 2026-06-29
status: RESOLVED (Option 1 — graceful drain via host-mounted lease; ADR-068)
incident_class: availability (cron-cohort, single-tenant)
brand_survival_threshold: single-user incident
gdpr_art_33_notifiable: false
gdpr_art_33_rationale: "Availability-only incident. No personal data was accessed, exfiltrated, altered, or lost — a killed cron simply did not produce its scheduled output (an article, a triage, a digest). No confidentiality or integrity breach."
gdpr_art_34_notifiable: false
gdpr_art_34_rationale: "No high risk to data-subject rights and freedoms — no personal-data processing was involved in the failure mode."
issue: 5669
adr: ADR-068
---

## Summary

Every `soleur-web-platform` container redeploy stops the running container
(`docker stop --time=12 soleur-web-platform`). When a deploy landed mid-flight,
it killed any in-progress Claude-eval cron child, surfacing as
`_cron-claude-eval-substrate.ts:706` "spawn cwd /tmp/soleur-cron-* no longer
exists". The founder's scheduled crons (content-generator, follow-through-monitor,
bug-fixer, community-monitor, roadmap/agent-native/legal audits) would silently
produce nothing for that cycle, with no obvious cause.

## Why it was not caught earlier

The predecessor memory-safety work (#5417 / #5420 / ADR-062) resolved the OOM /
crash incident class but, by scope, never targeted **deploy frequency** — so it
could not reach the ≤1/day "Server startup" restart proxy. The deploy-kills-cron
mechanism is a distinct failure mode (clean SIGTERM from a deploy, not an OOM
kill) and had not been independently post-mortemed until now.

## Root cause

Crons spawn `claude` via `child_process.spawn` *inside* the web-platform
container (ADR-033). The deploy lifecycle had no awareness of in-flight cron
children — the container swap (`docker stop`) was unconditional. Heavy crons run
up to ~70 min (`cron-growth-audit`), so any deploy in that window truncated them.

## Resolution (Option 1 — graceful drain; ADR-068)

A host-mounted **lease** (`/mnt/data/workspaces/.deploy-lease`, == container
`/workspaces/.deploy-lease`) plus a host-side **drain loop** in `ci-deploy.sh`:

- The lease (written before the drain) is read at the single claude-eval
  choke point `setupEphemeralWorkspace`; a fresh lease defers a NEW cron start
  (`DeployInProgressError`), closing the start-race.
- The drain loop (`while cron_in_flight`) waits up to `CRON_DRAIN_TIMEOUT` (4200s)
  for any in-flight claude child to finish before the `docker stop`. Old prod
  keeps serving throughout — zero added downtime.
- Fail-safe everywhere: a stale lease is TTL-expired (90 min) → fail-open; a
  drain timeout pages (Sentry `op=cron-drain-timeout` + `cron_drain_timed_out=1`).

The CTO ruling selected the lease over native `inngest pause`/`resume` because
the lease is cron-scoped (not server-global), fail-safe (skip one fire) vs
pause's fail-dangerous (kill in-flight child), and unit-verifiable.

## Action Items & Follow-ups

| Issue | Item | Owner |
| --- | --- | --- |
| #5694 | Evaluate Option 2 (isolated, deploy-stable cron-worker container) — the RCA-recommended durable fix — if any ADR-068 re-eval criterion fires (2nd hosted founder, deploys timing out >~1×/week per `cron_drain_timed_out`, host upsized to ≥16GB, a claude-spawn pool's concurrency turns the drain wait Σ-shaped, or sustained OOM during a drain window). The `cron_drain_timed_out` / `cron_drain_wait_secs` deploy-status webhook fields are the observability that feeds criteria (b) and (d). | agent |

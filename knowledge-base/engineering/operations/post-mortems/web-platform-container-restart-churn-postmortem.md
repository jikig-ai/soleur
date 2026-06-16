---
title: "soleur-web-platform container restart churn — uncapped host-OOM killed Claude-eval crons"
date: 2026-06-16
incident_pr: 5417
incident_window: "~2026-06-08 to 2026-06-16 (restart spikes: 06-08 52, 06-11 40, 06-12 42, 06-15 60, 06-16 ~10-12 per the Sentry 'Server startup' issue)"
recovery_at: "pending — fix verifies post-deploy (next web-platform-release deploy applies the cap; AC12 confirms via 72h Sentry rate-drop)"
suspected_change: "long-standing config gap — the container ran `docker run --restart unless-stopped` with NO --memory cap on an 8GB cx33 since inception; surfaced under the heavy concurrent Claude-eval cron load that the #5413 window exposed"
brand_survival_threshold: single-user incident
status: unresolved but ended
triggers:
  - "Sentry 'Server startup vX.Y.Z' issue: container restarted ~10-60x/day (stable = 0-1/day)"
  - "Sentry cron error: spawn cwd /tmp/soleur-cron-content-generator-* no longer exists (container restarted)"
  - "cron-egress-firewall: enforcement rules were MISSING at tick (jump/drop absent) — DOCKER-USER flush downstream of the restart"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability incident, no personal-data exposure (the only new surface, the /hooks/deploy-status OOM journald tail, is signkey-redacted kernel-ring metadata behind HMAC + CF-Access)"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

A **second, independent** root cause of the same multi-day window documented in
[`cron-egress-lb-rotation-outage-postmortem.md`](./cron-egress-lb-rotation-outage-postmortem.md)
(#5413, the egress LB-rotation drop). The `soleur-web-platform` container ran
with **no `--memory` cap** on an 8GB cx33 host. Under heavy concurrent
Claude-eval cron load, total host RAM pressure drove the **host kernel** OOM
killer, which selected an arbitrary victim (possibly dockerd / inngest-server /
the firewall resolver, not necessarily the Node process); `--restart
unless-stopped` then churned the container ~10-60×/day. Each restart killed any
in-flight ≤55-min Claude-eval cron mid-run and flushed the `DOCKER-USER`
`SOLEUR-EGRESS` jump (the firewall self-heal event is a **symptom** of the
restart, not an independent cause). #5413 fixed the *primary* egress cause; this
PR (#5417) fixes the *restart churn* second factor.

## Status

`unresolved but ended` — the fix is committed and verifies on the next deploy +
a 72h Sentry rate-drop window (AC12). Mirrors `status:` above.

## Symptom

Scheduled Claude-eval crons (content-generator, follow-through, bug-fixer,
community-monitor, roadmap-review, agent-native-audit) silently died mid-run and
produced no output; the operator saw nothing was done and could not tell why.

## Incident Timeline

- **Start time (detected):** ~2026-06-08 (first restart spike: 52/day) — `agent`, retroactively via the Sentry "Server startup" issue's hourly distribution while diagnosing #5413.
- **Diagnosis:** 2026-06-16 — `agent` — config inspection found no `--memory`/`--init` on either `docker run` block (`ci-deploy.sh`), no top-level `uncaughtException` handler (`server/index.ts`), and no host swap (cloud-init); root cause = host-OOM victim lottery.
- **Remediation committed:** 2026-06-16 (#5417) — `agent` — cgroup memory cap (A) + restart/OOM monitor (B) + crash attribution (C) + Sentry alert + ADR-062.
- **Recovery:** pending the next `web-platform-release` deploy (applies the `--memory` cap) + AC12's 72h Sentry "Server startup" rate-drop to ≤1/day.

## Root Cause

Uncapped container memory on an 8GB host: heavy concurrent crons → host-OOM →
kernel kills an arbitrary victim → `--restart unless-stopped` churn. A secondary
class — uncaught exceptions exiting the process — was **un-attributable** (no
top-level handler), so crash-restarts were indistinguishable from OOM-restarts.

## Resolution

Deliverable A converts host-OOM into deterministic cgroup-OOM (kills only the
container, sparing dockerd/inngest/firewall). B adds a host-side detector that
classifies deploy-vs-crash-vs-OOM and pages no-SSH (Sentry + Resend). C adds
top-level fatal handlers so crash-restarts are attributable. See ADR-062.

## What Went Well

- The #5413 diagnosis surfaced this orthogonal factor instead of stopping at the egress fix.
- The fix is fully no-SSH observable (monitor + webhook fields + Sentry alert) per `hr-no-dashboard-eyeball-pull-data-yourself`.

## What Went Poorly

- The container shipped without a memory cap since inception; no monitor watched container `RestartCount`/`OOMKilled` (resource-monitor.sh samples host RAM% only). The churn ran for ~8 days before being noticed — only incidentally, while diagnosing #5413.

## Action Items & Follow-ups

| Issue | Action | Owner | Status |
| --- | --- | --- | --- |
| #5417 | Post-deploy: confirm the Sentry "Server startup" event frequency drops to ≤1/day over 72h (AC12) + firewall-flush frequency drops in step (AC13); raise `PROD_MEMORY_CAP` if the monitor reports `class=OOM` (AC2 cap-too-low regression); then close #5417. Verification is no-SSH (Sentry stats API) — the deployed `container-restart-monitor` + `container_restart_burst` alert auto-page if churn persists. | agent | open (this PR; closure gated on the 72h verdict) |

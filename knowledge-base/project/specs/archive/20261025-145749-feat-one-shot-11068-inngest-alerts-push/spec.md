---
title: "Inngest alert resources route email-only — flip push=true (measured-flip convention)"
issue: 11068
branch: feat-one-shot-11068-inngest-alerts-push
lane: cross-domain
date: 2026-10-25
---

# Spec — #11068 Inngest alerts push channel

One-shot pipeline spec stub (no brainstorm ran — `plan` entered directly from the one-shot route).

## Problem

`logtail_exploration_alert.inngest_luks_wrong_volume` (betterstack-logs-alerts.tf:264) and
`betteruptime_heartbeat.inngest_server_probe` (uptime-alerts.tf:531) route `email = true` with
`push/call/sms = false` — P1-class signals reaching only an email surface. A third Inngest-serving
alert, `logtail_exploration_alert.inngest_step_524` (betterstack-logs-alerts.tf:725), carries the
identical block and is folded in per the issue's "every Inngest-serving alert resource" framing.

## Chosen approach

Flip `push = true` on the three resources, mirroring the measured `app_health` flip (#9168) and the
two heartbeat flips already live (`inngest_prd`, `inngest_consumer`, PR #11001, apply green
2026-10-25). Vendor refusal at apply → revert to `push = false` in a follow-up (#9168 convention).
Update `inngest-server-probe-heartbeat.test.sh` row (d) and ship
`plugins/soleur/scripts/inngest-alerts-push-probe.ts` (discoverability probe, `PUSH_ARMED`).

Alternatives descoped: `var.betterstack_paid_tier` (unverified paid plan + fleet-wide policy
re-wire), dedicated Slack/webhook channel (subsumed by #7662).

Plan: `knowledge-base/project/plans/2026-10-25-chore-inngest-alerts-push-channel-plan.md`

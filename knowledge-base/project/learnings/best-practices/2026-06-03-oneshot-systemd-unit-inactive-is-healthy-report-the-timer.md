---
title: "A Type=oneshot systemd unit reports `inactive` as its HEALTHY steady state — report the .timer for liveness"
date: 2026-06-03
category: best-practices
module: apps/web-platform/infra
tags: [systemd, observability, deploy-status, oneshot, timer, incident-triage]
issue: 4896
related_prs: [4895, 4886]
---

# `systemctl is-active` on a `Type=oneshot` timer-driven unit reads `inactive` when healthy

## Problem

Issue #4896 reported web-platform deploys "failing since #4886" with the root
signal `inngest_heartbeat: inactive` in the deploy-status JSON, framing the
cause as "#4886 moved/broke the heartbeat systemd unit or its storage path" and
asking to "restore the heartbeat service."

Two things were wrong with that framing:

1. **The incident had already self-resolved.** PR #4895 (the revert cited *in
   the issue body itself*) merged at 18:00 UTC; `gh run list
   --workflow=web-platform-release.yml` showed `success` from `b06de5b6`
   onward and `/health` already reported v0.102.0. The deploy queue was
   unstuck before the issue was even triaged. The actual cause was #4886's
   `sudo mkdir -p /mnt/data/workspaces/.cron` ENOSPC-ing under `set -e` on the
   already-full volume → `ci-deploy.sh`'s EXIT trap wrote `reason=unhandled`.

2. **`inngest_heartbeat: inactive` was a red herring, never the gate input.**
   The deploy-completion gate (`web-platform-release.yml`) keys ONLY on
   `exit_code`/`reason` — `grep -c inngest_heartbeat` against it returns **0**.
   The field is reporter-only (`cat-deploy-state.sh`).

## Key Insight

`inngest-heartbeat.service` is a `Type=oneshot` unit (no `RemainAfterExit=yes`)
driven by `inngest-heartbeat.timer` (`OnUnitActiveSec=60s`). `systemctl
is-active` returns `inactive` the instant a oneshot's `ExecStart` completes
successfully — so **`inactive` is the NORMAL, healthy steady state between the
60s timer fires**, not a fault. A reporter that surfaces only the `.service`
state shows `inactive` on a perfectly healthy host, which is exactly the
misleading signal that mis-framed this incident (a /ship auto-filer read the
correlated field as the root cause).

For a timer-driven oneshot, the durable liveness signal is the **`.timer`'s**
active-state (`active` on a healthy host), NOT the `.service`'s transient state.
Report both:

- `.timer` `active` → liveness (the schedule is still running)
- `.service` `failed` → the real fault (e.g. the empty-URL #4116 class)
- `.service` `inactive` → healthy between fires (do not alert on this)

## Solution

Add a parallel `services.inngest_heartbeat_timer` field to
`cat-deploy-state.sh` reading `systemctl is-active inngest-heartbeat.timer`, via
the existing best-effort `service_status()` helper + `--arg`/`jq` emit (same
shape as the three existing `.service` readers). Retain the `.service` field for
fault detection. Document the oneshot steady-state semantics inline so the next
operator/auto-filer does not re-read `inactive` as a failure. Touch no systemd
unit and no gate logic.

## What NOT to do

- **Do NOT add `RemainAfterExit=yes`** to make `is-active` read `active` — that
  mutates a healthy unit's semantics on the prod host (a redeploy, larger blast
  radius) to paper over a reporter bug.
- **Do NOT gate the deploy on `inngest_heartbeat == active`** — a healthy
  oneshot is `inactive`, so this would fail *every* healthy deploy. This is the
  wrong fix the issue's framing nudges toward.

## Generalizable lesson

When a deploy-status / health reporter surfaces `systemctl is-active <unit>` and
`<unit>` is `Type=oneshot` driven by a `.timer`, report the **timer's** state as
the liveness signal. A bare `is-active` read of the oneshot service is a
guaranteed false `inactive` between fires. Incident-triage corollary: when an
issue cites a revert PR in its own body, verify current state (`gh run list` +
`/health`) before planning a fix — the incident may already be resolved.

## Tags
category: best-practices
module: apps/web-platform/infra

---
title: "web-2 fsn1 warm-standby not serving — deploy-path GHCR auth_denied on a stale baked token"
date: 2026-07-13
incident_pr: 6395
incident_window: "2026-07-13T20:06Z – 2026-07-13 (fix merged)"
recovery_at: "pending post-merge web-2-recreate verification"
suspected_change: "#6393 web-2 hel1→fsn1 relocation -replace re-triggered a fresh boot + deploy"
brand_survival_threshold: none
status: resolved
triggers:
  - availability degradation (failover coverage), non-user-facing
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

The **web-2 warm-standby host** (fsn1, LB weight-0) failed to serve after the #6393 hel1→fsn1 relocation `-replace`. **No user-facing / production impact:** web-2 serves zero production traffic; web-1 (the sole live origin) was unaffected throughout. The impact was purely a **resilience gap** — zero cross-DC failover coverage while web-2 was down. Classified as an availability/resilience incident (not a data-exposure incident): Art. 33/34 do not apply.

## Status

resolved — root cause diagnosed and fixed (§1A, PR #6395); recovery verification is the post-merge `web-2-recreate` fresh boot.

## Symptom

web-2 was not serving and shipped no logs; `web-platform-release` went red on web-2's leg (`ci-deploy.sh exited 1 reason=image_pull_failed`). Reported as a recurring cloud-init fresh-boot image-pull failure (#6090 class).

## Incident Timeline

- **Start time (detected):** 2026-07-13T20:39:22Z (release deploy `image pull failed (auth_denied)`)
- **End time (recovered):** 2026-07-13 (§1A fix merged; full recovery on post-merge `web-2-recreate`)
- **Duration (MTTR):** ~diagnosis-to-fix same day

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-13T20:05 | #6393 relocation `-replace` re-triggers web-2 fresh boot in fsn1. |
| system | 2026-07-13T20:10:26 | web-2 boot reaches `webhook_bound` (info) — image pull SUCCEEDED; no fatal. |
| system | 2026-07-13T20:39:22 | Release deploy `ci-deploy.sh` fails `image pull failed (auth_denied)` (Sentry WEB-PLATFORM-59). |
| agent | 2026-07-13 | Self-pulled Sentry + Hetzner + release telemetry (no SSH); root-caused stale baked GHCR token + EMPTY-only fallback. |
| agent | 2026-07-13 | Shipped §1A re-fetch-on-failure fix (PR #6395). |

## Detection (+ MTTD)

- **How detected:** operator follow-on report + the red `web-platform-release` web-2 leg; Sentry `WEB-PLATFORM-59` `image pull failed (auth_denied)` is the monitored signal.
- **MTTD:** immediate (release-leg red on the failing deploy).

## Triggered by

system — the #6393 relocation `-replace` re-rendered `user_data` and re-triggered a fresh boot + subsequent release deploy, exposing a latent credential-staleness hole.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| cloud-init image-pull failure (#6090 class) | operator report | boot reached `webhook_bound` info, past the pull; no `pull`/`ghcr_login` fatal | REJECTED |
| deploy-path GHCR auth on stale baked token | Sentry WEB-PLATFORM-59 `auth_denied`, 5s fail (not timeout); live Doppler cred pulls the denied tag → 200 | — | CONFIRMED |

## 5-Whys (final root cause)

1. web-2 not serving → 2. release deploy `image_pull_failed` → 3. GHCR returned 401 `auth_denied` → 4. `ci-deploy.sh:ghcr_prelude_and_login` used a **stale-but-present baked token** → 5. the Doppler re-fetch fired only when the baked cred was **EMPTY**, never on a present-but-expired token whose `docker login` **fails** (non-fatal). Same EMPTY-only anti-pattern also in `cloud-init.yml`'s seed login.

## Resolution

§1A (PR #6395): on a baked/first `docker login` **FAILURE** (not only EMPTY), re-fetch current `GHCR_READ_{USER,TOKEN}` from Doppler and retry once, fail-open — in both `ci-deploy.sh` `ghcr_prelude_and_login` and `cloud-init.yml` seed `ghcr_login`. ADR-088 amended with the consumer-side staleness note.

## Recovery verification

- `ci-deploy.sh` reaches running hosts via `apply-deploy-pipeline-fix.yml` auto-apply on merge.
- Post-merge `apply-web-platform-infra.yml apply_target=web-2-recreate`: confirm Sentry `cloud_init_complete` with no `pull`/`ghcr_login` fatal, and the `web-platform-release` web-2 leg green — via `gh workflow run` + the Sentry API (no SSH, no dashboard eyeball).

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6396 | web-2 boot observability: Vector "ships logs" + cloud-init terminal-block `soleur-boot-emit` fatal trap + `pull_failure_event` `host_id` tag + C4 edge — so the next web-2 boot incident is no-SSH-diagnosable and the boot-path silent-exit gap is closed. | agent |

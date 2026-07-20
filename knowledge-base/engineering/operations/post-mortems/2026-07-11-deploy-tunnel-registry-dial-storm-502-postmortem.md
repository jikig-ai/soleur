---
title: "Registry-origin dial storm on the shared cloudflared tunnel → transient POST /hooks/deploy 502 (~10 min)"
date: 2026-07-11
incident_pr: 6358
incident_window: "2026-07-11 ~21:06Z–21:16Z (502 window); deploys blocked until ~21:44Z self-recovery"
recovery_at: "2026-07-11 ~21:44Z"
suspected_change: "zot registry container transiently DOWN during the #6288 OOM/region-migration (nbg1→hel1) window; dial storm on the shared tunnel degraded the sibling deploy-webhook route"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (prod deploy-pipeline blocked; prod app stayed healthy)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; availability-only incident (deploy-pipeline), no confidentiality event"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

On 2026-07-11, `cloudflared` on web-1 logged continuous `dial tcp 10.0.1.30:5000: operation was canceled`
for ingressRule=2 (`registry.soleur.ai`) — the zot registry origin was transiently DOWN (registry
container OOM/restart-loop during the #6288 nbg1→hel1 region migration, whose fresh hel1 volume was
re-filling from GHCR). The registry, deploy-webhook, and SSH routes all share ONE cloudflared daemon on
the small web-1 host, so the pile-up of ~30s-held registry dials degraded a sibling route: `POST
deploy.soleur.ai/hooks/deploy` returned **HTTP 502 at the tunnel edge** for ~10 minutes, blocking two
prod deploy jobs. The prod app itself stayed healthy throughout — this was a deploy-pipeline-availability
incident, not a user-facing outage.

## Status

resolved

## Symptom

`POST deploy.soleur.ai/hooks/deploy` → **502** at the CF tunnel layer (~21:06–21:16Z); the packets never
reached the webhook binary (on-host `curl localhost:9000` processed POST/GET, returning 403/500 on bad
sig — proving the app was healthy and the drop was above L7-app, at the edge/daemon). `restart-inngest-server.yml`
(21:06Z) and `web-platform-release.yml`'s `deploy` step (21:12Z, 21:16Z re-run) failed on the 502.

## Incident Timeline

- **Start time (detected):** 2026-07-11 ~21:06Z (first failed deploy job)
- **End time (recovered):** 2026-07-11 ~21:44Z (re-run of the release `deploy` returned 202, deployed v0.212.3 via the GHCR fallback path)
- **Duration (MTTR):** ~38 min from first failed deploy to a green re-run (502 window itself was ~10 min)

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-07-11 ~21:06Z | `restart-inngest-server.yml` deploy hook POST → 502 at the tunnel edge. |
| system | 2026-07-11 ~21:12Z | `web-platform-release.yml` `deploy` step → 502; re-run at 21:16Z also 502. |
| agent | 2026-07-11 ~21:16Z | Self-pulled evidence: `systemctl is-active cloudflared webhook inngest-server` all `active`; `journalctl -u cloudflared` shows repeated `dial tcp 10.0.1.30:5000: operation was canceled` for `registry.soleur.ai`; webhook binary healthy (403/500 on bad-sig localhost POST). |
| system | 2026-07-11 ~21:44Z | 502 window self-cleared (registry dial storm drained); a release `deploy` re-run returned 202 and deployed `v0.212.3` (GHCR fallback; `ZOT_GATE_DEGRADED: probe_unreachable`). |

## Participants and Systems Involved

The shared web-1 `cloudflared` daemon (registry + deploy-webhook + SSH ingress on one tunnel), the zot
registry origin (`10.0.1.30:5000`), the prod deploy webhook binary, and GitHub Actions release/restart
workflows. No operator action was required for recovery (self-recovered).

## Detection (+ MTTD)

- **How detected:** system — two consecutive GitHub Actions deploy jobs went red on a tunnel-layer 502. No independent deploy-path monitor exists today (tracked → #6178).
- **MTTD:** ~immediate (the failed deploy jobs were the signal).

## Triggered by

provider/system — the zot registry container was transiently unavailable during the #6288 OOM/region-migration window; the dial storm on the shared tunnel daemon degraded the sibling deploy route.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Registry origin DOWN → dial storm saturates the shared cloudflared daemon's HA-stream budget → sibling deploy-webhook 502 | `journalctl` shows continuous `dial…canceled` for `registry.soleur.ai` only; webhook binary healthy in-window; 502 at edge not app; self-recovery when the storm drained | cloudflared `--metrics` (`ha_connections`, `concurrent_requests_per_tunnel`) were NOT captured → the saturation MECHANISM is unverified (observability gap → #6178) | LIKELY (mechanism unverified) |

## Resolution

Self-recovered on 2026-07-11 when the registry stabilized and the dial storm drained; a release re-run
deployed `v0.212.3` via the GHCR fallback. The **durable mitigation** (this PR, #6358): a fail-fast
`origin_request { connect_timeout = 5; no_happy_eyeballs = true }` scoped to the registry ingress rule in
`apps/web-platform/infra/tunnel.tf`, bounding the TCP dial so a DOWN registry origin can no longer pile up
~30s-held dials against the shared daemon. The PR also corrects the issue's false "stale rule" premise
in-line (the origin is the LIVE ADR-096/#6122 registry-push path; #6288 moved the region, not the IP).
This is a blast-radius mitigation, NOT a cure — the root cause (registry stability) is #6288, and the
architectural fix (decouple the deploy webhook from sibling tunnel traffic + add an independent monitor +
cloudflared metrics) is #6178.

## Recovery verification

The 2026-07-11 ~21:44Z release re-run returned 202 and deployed `v0.212.3` (self-recovery confirmed by a
green deploy). The mitigation is verified statically pre-merge: `terraform fmt -check` + `terraform
validate` pass against the v4-pinned root (validate confirms the integer `connect_timeout`). Post-merge,
the `apply-web-platform-infra.yml` auto-apply lands the edge-config change, and the no-SSH
`deploy.soleur.ai/hooks/deploy-status` probe (bad-sig POST returns 403/500, not 502) confirms the
tunnel→webhook path is healthy.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did prod deploys fail?** `POST /hooks/deploy` returned 502 at the tunnel edge.
2. **Why did the tunnel edge 502?** The web-1 cloudflared daemon could not get a healthy origin stream for the deploy-webhook route.
3. **Why couldn't it?** The registry origin (`10.0.1.30:5000`) was DOWN, and each retry/probe held an edge HA-stream slot for the full ~30s default `connect_timeout`, saturating the shared daemon's stream/CPU budget on the small host.
4. **Why was the registry origin down?** The zot container was OOM/restart-looping during the #6288 nbg1→hel1 region migration (fresh hel1 volume re-filling from GHCR).
5. **Why did a registry problem break the deploy path?** The registry, deploy-webhook, and SSH ingress all share ONE cloudflared daemon/tunnel — a per-route origin failure has cross-route blast radius (architectural coupling → #6178).

## Versions of Components

- **Version(s) that triggered the outage:** `tunnel.tf` registry ingress rule with the default ~30s `connect_timeout` (no `origin_request` override); zot registry mid-#6288-migration.
- **Version(s) that restored the service:** self-recovery deployed `v0.212.3`; durable mitigation in PR #6358.

## Impact details

### Services Impacted

Prod deploy pipeline — `POST /hooks/deploy` unreachable for ~10 min; two deploy jobs blocked until ~21:44Z self-recovery. The prod web-platform app served traffic normally throughout (no runtime cutover was in flight during the window).

### Customer Impact (by role)

- Prospect: none (marketing site + app unaffected).
- Authenticated app user: none — the running app was healthy; only the ability to ship NEW deploys was blocked.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None (single-user / tenant-zero stage; deploy-pipeline availability only).

### Team Impact

~minimal — self-recovered without operator intervention; the evidence was self-pulled during triage.

## Lessons Learned

### Where we got lucky

The 502 hit a short window with no runtime cutover pending, and the registry stabilized on its own before any operator action — so the shared-daemon coupling caused no user-facing outage this time.

### What went well

The failure was fully self-diagnosable from telemetry (journalctl + on-host service state), the fail-closed deploy jobs correctly blocked rather than shipping through a degraded path, and the GHCR fallback let the re-run deploy succeed once the storm drained.

### What went wrong

A single DOWN origin on the shared cloudflared tunnel degraded a sibling route (no blast-radius bound), there is no independent monitor for the deploy path (the 502 surfaced only via CI failure), and the issue that filed the incident mis-attributed the cause to a "stale ingress rule," inviting a destructive removal that would have broken CI registry push.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6288 | Fix the zot registry container OOM/restart-loop (the true root cause) and un-pause the registry liveness heartbeat. | open |
| #6178 | Decouple the deploy webhook from sibling tunnel traffic + add an independent deploy-path monitor + export cloudflared `--metrics` (verifies the shared-daemon HA-stream saturation mechanism). | open |

---
title: "Every fresh web-host boot was dark — the zot selection read Doppler without a token, so the ref stayed on a revoked GHCR credential"
date: 2026-09-24
incident_pr: 8660
incident_window: "Latent since the zot migration (#6120, 2026-07-07): the web seed pull never once selected zot. It became fatal when the GHCR read PAT was revoked (AP-016, 2026-07-29). Observed on 2026-09-23T19:52:50Z–20:10:36Z (run 35912244388, web-host-replace of web-2)."
recovery_at: "PENDING — the fix is in #8660, but merging changes no host (hcloud_server.web ignores user_data). Recovery is the first web-host-replace of web-2 that boots zot-served, graded by scripts/followthroughs/web-fresh-boot-zot-8651.sh."
suspected_change: "#6120 (2026-07-07) gated the web seed pull's zot ref on a Doppler read in a runcmd shell that never exported DOPPLER_TOKEN (#6985); AP-016 (2026-07-29) then removed the only registry that read could fall back to."
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - availability (web-tier replacement path — no live host was affected; web-1 kept serving throughout)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only and not user-realized. The one host that went dark
# (web-2) was being provisioned and was never in service. No personal data was read, exposed or
# lost. The threshold is `aggregate pattern` because the latent defect removed the web tier's
# ability to replace or add a host; web-1 is the sole live origin, so a replace of web-1 would
# have taken the app offline.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A `web-host-replace` of web-2 booted dark: the seed image pull failed at `stage=pull` with
`ghcr_login_fail: … denied | pull_err: … unauthorized`. The cause was not network timing. The
seed item chose zot only when `doppler secrets get ZOT_REGISTRY_URL` returned a value, and that
call ran in a runcmd shell where `DOPPLER_TOKEN` had never been exported. It returned empty on
every boot, so every fresh web boot since the zot migration had selected GHCR. Once the GHCR read
PAT was revoked, that meant every fresh web boot failed.

## Status

ongoing — the fix is merged-pending in #8660; recovery is observed only by a web-2 replace.

## Symptom

Run 35912244388: the seed pull's fatal detail reported a GHCR login denial and an unauthorized
pull. The host never reached `cloud_init_complete`, and the boot-trail step reddened the job even
though the Terraform apply had succeeded.

## Incident Timeline

- **Start time (detected):** 2026-09-23T20:10:36Z
- **End time (recovered):** pending (the web-2 replace after #8660 merges)
- **Duration (MTTR):** open

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-07 | #6120 adds the Doppler-gated zot selection to the web seed pull; the read is tokenless from its first boot. |
| human | 2026-07-29 | The GHCR read PAT is revoked (AP-016); from here a fresh web boot has no working registry. |
| human | 2026-09-23T19:52:50Z | `web-host-replace` of web-2 dispatched (run 35912244388). |
| agent | 2026-09-23T20:10:36Z | Run fails; the boot-trail step reports web-2 dark at `stage=pull`. Incident detected. |
| human | 2026-09-23T20:15:55Z | Issue 8651 filed; web-2 is left dark as evidence. |
| agent | 2026-09-23 | Root cause measured: tokenless reproduction plus the 90-day Sentry count (0 `app_zot`, 3 `app_ghcr_served`). |
| agent | 2026-09-24 | #8660 bakes the endpoint and credential and passes an 11-agent review. |

## Participants and Systems Involved

Web hosts (`hcloud_server.web`, cloud-init runcmd seed pull), the zot registry host, GHCR,
Doppler, the `apply-web-platform-infra.yml` replace job, and Sentry boot-stage events.

## Detection (+ MTTD)

- **How detected:** a monitoring system. `fresh-host-boot-trail.sh`, the replace job's own step, turned the job red on the seed fatal.
- **MTTD (mean time to detect):** ~78 days from the defect becoming fatal (2026-07-29) to the first fresh web boot that exercised it. No fresh web boot happened in that window, so no earlier signal was possible from this detector.

## Triggered by

system — an operator-dispatched host replace exercised a path no host had exercised since the revocation.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The 3 s `/v2/` probe lost a race with private-NIC convergence (#8539 shape) | The inngest host hit a NIC race on 2026-09-22; `ZOT_REGISTRY_URL` is set in Doppler | The probe sits behind `[ -n "$ZURL" ]` and ZURL was empty on every boot; 0 `app_zot` in 90 days | Rejected |
| The Doppler read was tokenless, so ZURL was always empty | Reproduced `Doppler Error: you must provide a token`; the token file is only ever sourced with a bare `.` inside subshells (#6985) | None found | Confirmed |

## Resolution

#8660 bakes the zot endpoint and pull credential into `user_data`. It rewrites only digest-pinned
`ghcr.io` refs, gates each registry leg on its own login, adds the inngest networkd fallback,
reload and a bounded NIC wait, and names both legs in the fatal detail.

## Recovery verification

Pending. Recovery is proven by a `web-host-replace` of web-2 whose boot trail shows `app_zot` with
`zot_login=ok` and `fresh_boot_ready`. The graded evidence is the job log, read by
`scripts/followthroughs/web-fresh-boot-zot-8651.sh`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was web-2 dark? Its seed pull went to GHCR, and the GHCR credential is revoked.
2. Why GHCR? `REF` defaults to the GHCR ref and switches to zot only when `ZURL` is non-empty.
3. Why was `ZURL` empty? `doppler secrets get` ran without `DOPPLER_TOKEN` in its environment, and `2>/dev/null || true` turned the error into an empty string.
4. Why no token? The runcmd parent shell never sourced the token file, and the subshells that did used a bare `.`, which assigns without exporting (#6985).
5. Why was it not caught in 78 days? No fresh web boot happened, and nothing alerted on a zot path that had served zero boots. A never-exercised branch reads as healthy.

## Versions of Components

- **Version(s) that triggered the outage:** `cloud-init.yml` from #6120 onward, combined with the AP-016 revocation.
- **Version(s) that restored the service:** #8660, once a web host is re-created from it.

## Impact details

### Services Impacted

Web-tier host replacement and scale-out. No service that users reach was affected.

### Customer Impact (by role)

- Prospect: none (web-1 served throughout).
- Authenticated app user: none realized. The latent exposure: a replace of web-1 would have made the app unreachable.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One dark provisioning run, plus the diagnosis and fix session. web-2 is held out of service as evidence.

## Lessons Learned

### Where we got lucky

The first host to exercise the path was web-2, which was not in service. A replace of web-1 — the
sole live origin — would have taken the app offline, and runcmd is once-per-instance, so a reboot
cannot repair a dark host.

### What went well

The replace job's boot-trail step turned a successful Terraform apply red on the host's own fatal,
so the failure was caught at the dispatch that caused it.

### What went wrong

The issue named a plausible mechanism (probe timing) that the telemetry contradicted. Looking one
step upstream of the gate — at a success count of zero over its whole life — was what found the
real cause. `2>/dev/null || true` on a credentialed read turned "cannot authenticate" into
"not configured".

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8651 | Dispatch the `web-host-replace` of web-2 from the fixed template; the follow-through sweeper closes the issue on a zot-served, `fresh_boot_ready` boot. | open |
| #6985 | Remove the remaining tokenless Doppler read in `soleur-host-bootstrap.sh`, which the bake supersedes (dead code, deferred because host-script edits break the replace job's coherence preflight). | open |
| #6122 | Count a web fresh-boot `stage=pull` fatal in `zot-soak-6122.sh`'s `FAIL_QUERIES`. With GHCR dead, a zot miss no longer emits `app_ghcr_fallback`. | open |

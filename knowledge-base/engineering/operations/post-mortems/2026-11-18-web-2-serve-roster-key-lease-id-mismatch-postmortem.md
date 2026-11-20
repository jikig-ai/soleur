---
title: "web-2 serve window: roster keys never matched the lease host id, and turns on web-2 self-stopped 2026-11-18"
date: 2026-11-20
incident_pr: 12918
incident_window: "2026-11-18T12:47:47Z → 2026-11-18T14:08:06Z"
recovery_at: "2026-11-18T14:08:06Z"
suspected_change: "Latent since multi-host serving was built: the lease host id (SOLEUR_HOST_ID = hetzner-<instance id>) and the Doppler prd SOLEUR_HOST_ROSTER keys (web-1, web-2) were never the same name. Exposed by the owner-authorized web-2 serve dispatch, cf-lb-overlay.yml run 44304068922."
brand_survival_threshold: single-user incident
status: resolved
triggers:
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach (availability only)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

web-2 was put back in the GA load balancer for about 80 minutes to produce the AC-P3 proxied-session proof for #8211. In that window no chat turn and no proxied connection could complete across the two hosts: the cross-host router could not find the lease owner in the host roster, and a turn that landed on web-2 stopped before it ran. The owner was the only user affected; there were no external users.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

The impact ended when web-2 was drained (weight 0) at 14:08:06Z. The underlying defects are fixed by PR #12918; web-2 stays at weight 0 until that fix is verified on both hosts (#12986).

## Symptom

With web-2 at weight 1 (random steering), about half of new turns landed on web-2 and stopped with `agent-readiness-self-stop` (`gitKind=absent gitValid=false source=host-pre-heal`). A connection that landed on web-1 while a lease was held on the other host was closed with `ROUTING_UNAVAILABLE`, because web-1 logged `session-router: owning host 'hetzner-<id>' is not in SOLEUR_HOST_ROSTER` (`resolveSessionRoute.owner-unresolved`). `relay_hello_window` had never logged on either host in 30 days.

## Incident Timeline

- **Start time (detected):** 2026-11-18T12:47:47Z
- **End time (recovered):** 2026-11-18T14:08:06Z
- **Duration (MTTR):** 1h20m

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent-with-ack | 2026-11-18T12:27:22Z | `cf-lb-overlay.yml` arm=ga-pool-update mode=serve dispatched (run 44304068922), owner-authorized, for the #8211 AC-P3 proof. |
| agent-with-ack | 2026-11-18T12:44:04Z | Serve apply complete: web-2 at LB weight 1. The serve gate (`lb-weight-gate.sh` A.3) passed on the name-keyed roster. |
| agent | 2026-11-18T12:47:47Z | web-2 logs `agent-readiness-self-stop gitKind=absent source=host-pre-heal` for the owner's workspace; `relay_probe` reports `workspaces_populated=0`. Incident detected. |
| agent | 2026-11-18T12:55:30Z | web-1 logs `resolveSessionRoute.owner-unresolved` (again at 12:56:11Z) and closes the socket with `ROUTING_UNAVAILABLE`. |
| agent-with-ack | 2026-11-18T14:06:38Z | `cf-lb-overlay.yml` mode=drain dispatched (run 44320672915). |
| agent-with-ack | 2026-11-18T14:08:06Z | Drain apply complete: web-2 at weight 0. Impact ends. |
| agent | 2026-11-18 | Issue #12910 filed with both defects and the Better Stack evidence. |

## Participants and Systems Involved

Operator (single founder), who authorized the serve and drain dispatches; Claude Code (dispatch, Better Stack reads, diagnosis). Systems: Cloudflare GA load balancer pool, web-1 and web-2 app containers, the worktree write-lease (migration 116 lease table), `session-router.ts`, the readiness self-stop in `cc-dispatcher.ts`, Doppler `prd` `SOLEUR_HOST_ROSTER`, `ci-deploy.sh`.

## Detection (+ MTTD)

- **How detected:** monitoring — the Better Stack log rows above, read by the agent during the proof window.
- **MTTD (mean time to detect):** 0h0m from the first failing turn (the first self-stop row is the detection point); 3m43s after the serve apply completed.

## Triggered by

user — the owner-authorized serve dispatch put web-2 into rotation, which exposed two latent defects.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The roster is keyed by a different name than the lease host id | web-1 `owner-unresolved` row names a `hetzner-<id>` owner; the Doppler roster is keyed `web-1`/`web-2` | none | confirmed |
| web-2's pre-heal probe fires on a workspace the heal then repairs | `source=host-pre-heal` with `gitKind=absent` and `workspaces_populated=0` | none | confirmed; narrowed in #12918 (T8/T8a) |

## Resolution

Immediate: web-2 drained to weight 0 (run 44320672915). Permanent: PR #12918 makes the lease host id the verified `var.web_hosts` key (`web-1`, `web-2`), accepted only when `roster[key]` equals the host's own private IP, with a fallback to `hetzner-<id>`. Deploys refuse to change, drop, or fail to verify a running host's key before the canary. The pre-heal self-stop now fires only when a stranding shape survives the heal, and skips transient errnos.

## Recovery verification

Impact end: run 44320672915 `ga_pool_update` succeeded with `MODE_RAW: drain` and `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` at 14:08:06Z. Fix verification is post-merge and owner-gated (#12986): Better Stack must show `host_key resolved=web-1` from web-1 and `host_key resolved=web-2` from web-2, then one cold turn on web-2 must reach `cc_queries>=1` and the owner host must log `relay_hello_window accepted=<n>` with n>0.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did proxied sessions fail? The router looked up the lease owner `hetzner-<id>` in a roster keyed `web-1`/`web-2` and found nothing.
2. Why were the names different? `ci-deploy.sh` set the lease identity from the Hetzner metadata instance id, while the roster was written by hand with the Terraform `var.web_hosts` names.
3. Why did nothing catch it before serving? The serve gate (A.3) checked the roster's own shape ("web-2 present"), not that roster keys match the id the runtime records, so the gate and the runtime disagreed on what the key is.
4. Why had it never shown in production? `relay_hello_window` had never logged: no proxied session had ever completed, so the path was untested end to end until this window.
5. Why did turns on web-2 stop? The pre-heal probe read a workspace before the heal populated it (`workspaces_populated=0`) and treated `gitKind=absent` as stranding, a second, independent defect.

## Versions of Components

- **Version(s) that triggered the outage:** main as deployed on 2026-11-18 (the latent id mismatch in `ci-deploy.sh` / `session-router.ts`); exposure by run 44304068922.
- **Version(s) that restored the service:** run 44320672915 (drain). Fix: PR #12918.

## Impact details

### Services Impacted

Chat turns and proxied WebSocket sessions on the two-host pool, only while web-2 served (12:44Z–14:08Z). Single-host serving on web-1 was unaffected before and after.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: none (no marketing surface involved).
- Authenticated app user: the owner only; about half of new turns stopped and some connections closed for about 80 minutes. No external users.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

Unknown / N/A — no paying external users were active.

### Team Impact

About one working session spent on diagnosis and the fix plan.

## Lessons Learned

### Where we got lucky

There were no external users, and the serve was a deliberate, owner-watched proof window rather than an unattended rollout.

### What went well

Better Stack carried both failure signatures with timestamps, so diagnosis needed no host login. The drain path worked in under two minutes.

### What went wrong

A gate checked a configuration's shape against itself instead of against what the runtime reads. Two identities for one host (instance id and roster name) coexisted with no test that pinned them equal.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #12986 | Owner-approved post-merge redeploy, then one web-2 serve dispatch and one proof turn once `host_key resolved=web-N` holds on both hosts. | open |
| #12979 | Make the serve gate check the lease key each pooled host actually resolved, not only the roster's shape. | open |
| #12981 | Give the cloud-init first-boot web container a lease identity before its first deploy. | open |
| #12919 | Derive SOLEUR_HOST_ROSTER and the peer allowlist from var.web_hosts instead of hand-kept Doppler values. | open |

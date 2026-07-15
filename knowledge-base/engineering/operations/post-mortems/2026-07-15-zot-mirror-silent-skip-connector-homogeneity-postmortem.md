---
title: "Postmortem: zot mirror silently skipped on ~every release for ~8 days (web-2 tunnel connector had no private-net route)"
date: 2026-07-15
incident_pr: 6421
incident_window: "2026-07-07 (#6120 landed the ADR-096 zot dual-push: registry. ingress + zot_bridge/zot_mirror steps) → ongoing at time of writing (web-2's private-net attach is a post-merge warm-standby dispatch; PR #6421 guards recurrence + un-masks the signal but does not itself attach web-2)"
recovery_at: "n/a — ongoing"
suspected_change: "#6120 (ADR-096) added the registry. tunnel ingress + zot_bridge/zot_mirror release steps assuming a single web-host cloudflared connector. soleur-web-2 was already a live second connector on the same tunnel WITHOUT a private-net attachment, so the ~94% of bridge attempts that CF load-balanced onto it had no route to 10.0.1.30:5000."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - zot mirror skipped
  - registry bridge context deadline exceeded
  - ADR-096 zot-primary path dead end-to-end
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The self-hosted zot registry (ADR-096) has received at most **one** image since it went live. Every other release since 2026-07-07 pushed to GHCR, failed to mirror to zot, **and reported green**. The ADR-096 zot-primary path was dead end-to-end while the release pipeline, the Slack release message, and the GitHub check-suite all said success.

No user was affected: the pull side does an atomic GHCR fallback, so hosts kept booting the correct image from the correct digest. The harm is **latent** — the redundancy ADR-096 was built to provide did not exist, and nothing said so. Had GHCR degraded during this window (the exact scenario zot exists to survive), there would have been no fallback.

## Status

`ongoing` — PR #6421 guards recurrence (`host_creates` HALT) and un-masks the signal (the mirror now reports degraded instead of skipping into silence), but it does **not** restore web-2's private-net attachment. That is a post-merge `warm-standby` dispatch. zot is still not being backfilled as of this writing; #6416 is enrolled in the follow-through sweeper and auto-resolves once ≥5 consecutive releases mirror cleanly.

## Symptom

From a release job log (run 29367887995, reported as a **successful** release):

```
Error response from daemon: Get "http://127.0.0.1:5000/v2/": context deadline exceeded
  (Client.Timeout exceeded while awaiting headers)
```

Observed shape across the 16 most recent completed release runs that built an image:

| `zot_bridge` step `conclusion` | `zot_mirror` step | count |
|---|---|---|
| `success` | **skipped** | **15** |
| `success` | `success` | **1** |

## Incident Timeline

- **Start time (detected):** 2026-07-07 — #6120 landed the dual-push. The very first release after it began skipping. Nobody detected it for ~8 days.
- **First human/agent detection:** 2026-07-15, during #6400 recovery — noticed incidentally, not by any alarm.
- **End time (recovered):** n/a — ongoing.
- **Duration (MTTR):** ≥8 days to detection; recovery pending the post-merge dispatch.

| When | Actor | Event |
|---|---|---|
| 2026-07-07 | `agent` | #6120 lands ADR-096 dual-push: `registry.` tunnel ingress → `tcp://10.0.1.30:5000`, plus `zot_bridge` + `zot_mirror` release steps. Design assumes **the** web host's cloudflared. |
| 2026-07-07 → 2026-07-15 | — | Every release skips the mirror. Release runs green. Slack says nothing. zot stays empty. |
| 2026-07-15 | `agent` | Found incidentally while recovering #6400: `soleur-web-2` has `private_net: []`. |
| 2026-07-15 | `agent` | #6416 filed. |
| 2026-07-15 | `agent` | Measured 16 release runs via the GitHub jobs API: 15 skipped / 1 success. Root cause confirmed from the bridge's own log. |
| 2026-07-15 | `agent` | PR #6421: `host_creates` HALT (recurrence guard) + mirror un-masking (signal) + ADR-114 (the invariant). |
| pending | `agent` | Post-merge: dispatch `apply_target=warm-standby` to restore web-2's attach. Soak proves it. |

## Root Cause

Three independent failures composed. Any one alone would have been caught.

**1. A latent topology violation.** There is exactly **one** Cloudflare tunnel with **multiple** connector replicas — web-1 and web-2 both run cloudflared against it, and CF load-balances across them. `soleur-web-2` had **no** `hcloud_server_network` attachment, so it was not a `10.0.1.0/24` member and could not reach zot at all. The `registry.` ingress is *origin-relative* (`tcp://10.0.1.30:5000`) — the correct pattern — but it is correct only if **every** connector can honor it. It could not.

Why web-2 was born unattached: `-target` is transitive at the **resource** level, so the per-PR apply's allow-listed `cloudflare_record.app` (dns.tf) and `hcloud_firewall_attachment.web` (firewall.tf) each pull the whole `hcloud_server.web` for_each map — **including web-2's server**. But `hcloud_server_network.web["web-2"]` is *not* target-reachable, so it stayed behind. The host came up; its private NIC never did.

**2. Total observability masking, by construction.** Every layer that could have reported this was silent:

- `zot_bridge` carries `continue-on-error: true` → its step **`conclusion` is forced to `success`**; the truth lives only in `outcome`.
- `zot_mirror` was gated `if: steps.zot_bridge.outcome == 'success'` → it **skipped**.
- A skipped step runs no emitter → `mirror_status` stayed **unset**.
- The Slack degraded line reads `steps.zot_mirror.outputs.mirror_status` **by step id** → **inert**.

`reusable-release.yml`'s own comment documented this as intended behaviour — *"Empty on the happy path AND when the mirror step was skipped (bridge failed) … the append is inert"* — which is how it survived review at #6120 and #6274.

**3. The drift detector was drowned, not blind.** The 12h `scheduled-terraform-drift.yml` runs `plan -detailed-exitcode` with no `-target`, so it **did** see the missing attachment (exit 2). But `server.tf` documents 10+ resources that permanently show "will be created", so **exit 2 is the steady state**. A detector that always alarms is not a detector. Filed as #6443.

## What Went Wrong (analysis)

- **The singular assumption was written down and never challenged.** `tunnel.tf`, `cf-tunnel-registry-bridge/action.yml`, and ADR-096's prose all said "**the** web host's cloudflared". ADR-068 had *already* recorded the truth verbatim — *"both hosts run cloudflared on that ONE tunnel, so a POST load-balances to ONE connector non-deterministically"* — and even chose the deploy-path fan-out to work around it. That knowledge simply never generalized from `deploy.` to `registry.`/`ssh.`. ADR-114 now records the generalization.
- **A `conclusion` field was trusted where the platform guarantees it is false.** `continue-on-error` exists to force `conclusion: success`. Any check reading it is reading a value the platform is contractually obliged to falsify.
- **Absence was read as health.** No degraded line meant "fine", when it actually meant "the emitter never ran".

## What Went Right

- The pull-side **atomic GHCR fallback** (ADR-096) did exactly its job: zero user impact across ~8 days of a fully-dead primary. The dark-launch design (`ZOT_ACTIVE=0` during soak) is why this was a latent redundancy gap and not an outage.
- The failure was found **before** the zot cutover retired GHCR push. Post-cutover this would have been a hard deploy outage rather than a silent one.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6416 | Restore web-2's private-net attach (post-merge `warm-standby` dispatch) and prove it with ≥5 consecutive clean mirrors. Enrolled in the follow-through sweeper — auto-resolves on evidence, not at merge. | `agent` |
| #6440 | Audit web-1 vs web-2 for the 12 provisioner-applied host configs — Terraform state may be false. `ssh.` is connector-relative, so an unknown share of past provisioner runs may have written web-1's config to web-2. **P1.** | `agent` |
| #6441 | ADR-114 I2: deterministic tunnel origin for host-specific routes. Also carries the wrong-host tripwire cut from #6421 (it certified a different SSH session than the one that writes) and the third exposed `deploy.` leg (`/hooks/infra-config`, no fan-out). | `agent` |
| #6442 | `hcloud_firewall_attachment` does not attach before first boot — a per-PR-born host boots public with **no firewall**. Independent reason the per-PR apply must never birth a host. | `agent` |
| #6443 | The 12h drift detector always alarms (exit 2 is the steady state) — it saw this and could not say so. Needs a documented-noise allowlist. | `agent` |
| #6449 | `/ship` Phase 0 trailer-parse gate false-positives on prose section labels (found while shipping the fix). | `agent` |

## Prevention

Shipped in PR #6421:

- **`host_creates` HALT** — a 7th destroy-guard counter. A host birth was invisible to all three existing counters (no delete, no nested-block shrinkage, not an `["update"]`). It now HALTs the per-PR apply, evaluated **outside** the `destroy_count` sum so `[ack-destroy]` cannot reach it. Covers `["create"]`, `["delete","create"]` (replace), and `["create","delete"]` — an earlier draft narrowed to exact-`["create"]` and would have let a replace through the ack path, reproducing this incident *through the guard*.
- **The mirror can no longer skip into silence** — gated on `docker_build` (not `zot_bridge`) and branches on the bridge **internally**, so a failed bridge reaches the same `degraded()` emitter and the same output id the Slack line already reads. ADR-096 is not reversed: `continue-on-error` stays; the ask is satisfied by loudness, not blocking.
- **ADR-114** records the invariant (I1 connector homogeneity, I2 origin-relative ingress) and the normative anti-pattern: a per-hostname ingress does **not** pin a connector.
- **A soak probe** (`scripts/followthroughs/zot-mirror-connector-6416.sh`) that requires a **positive liveness marker** — it cannot PASS on the absence of a failure signal, which is the defect class that caused this incident.

Generalizable lessons: `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`.

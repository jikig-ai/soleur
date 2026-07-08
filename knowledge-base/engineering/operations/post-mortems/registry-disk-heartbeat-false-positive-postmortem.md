---
title: "soleur-registry-disk-prd missed-heartbeat — deploy-sequencing false positive (heartbeat shipped without its host redeploy)"
date: 2026-07-08
incident_pr: 6210
incident_window: "2026-07-08 13:30 UTC (15:30 CEST) alert fired → same-day diagnosis as false-positive; alerting-layer fix built + reviewed (PR #6238); heartbeat armed by post-merge registry-host-replace dispatch"
recovery_at: "2026-07-08 — post-merge `registry-host-replace` dispatch installs the ping cron; heartbeat status transitions to `up`; Better Stack auto-resolves the incident"
suspected_change: "#6210 (zot capacity PR) created the disk-full heartbeat resource in Better Stack (paused=false) in the same PR as the `zot-disk-heartbeat.sh` ping cron, but `terraform apply` creating the heartbeat does NOT redeploy the registry host — so the cron that pings it was never installed and the heartbeat never received a first ping."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - monitoring (Better Stack heartbeat "soleur-registry-disk-prd | Missed heartbeat")
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
gdpr_na_rationale: "n/a — availability/alerting non-event. No personal data was accessed, exposed, altered, or lost; the incident was an orphaned deploy-pipeline heartbeat, not a data-processing surface. Art. 33 (supervisory-authority notification) and Art. 34 (data-subject notification) are therefore not triggered."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Better Stack fired a heartbeat incident, `soleur-registry-disk-prd | Missed heartbeat`, at
2026-07-08 15:30 CEST (13:30 UTC), and it stayed unacknowledged. The alert name reads like a
disk-full outage on the self-hosted zot registry host. It was **not** one.

The incident was a **deploy-sequencing false positive**. The 2026-07-07 zot capacity PR (#6210)
created a new disk-full heartbeat resource in Better Stack (`paused=false`) in the *same* PR as
the host cloud-init that installs the `zot-disk-heartbeat.sh` ping cron. But creating a heartbeat
via `terraform apply` does **not** redeploy the host — and the registry host had no CI reprovision
path — so the ping cron was never installed. The heartbeat therefore **never received a single
ping** (Better Stack `attributes.status` never became `up`; a Better Stack heartbeat has no
`last_event_at` field to disambiguate). After its grace window elapsed with zero pings, Better
Stack raised "missed heartbeat" — an orphaned-resource artifact, not a disk-full signal.

The same missing redeploy also meant #6210's *actual* disk-full mitigations (the `storage.retention`
pruning in the zot config) were not live either.

**Disk was verified NOT full, out-of-band:** the Hetzner volume API reported ~30 GB, disk IO was
near-idle, and a CI release at 13:37 UTC the same day successfully pushed a full image to zot (many
`pushed blob:` lines, zero `no space left on device`). **Serving was never at risk** — ADR-096's
GHCR dark-launch fallback covers image pulls independently of the self-hosted registry.

Classified `aggregate pattern` for brand-survival because the degraded surface was the
**deploy-pipeline alerting layer** (a shared, systemic capability), not a single user's data or
session — and the miss was compounded by an alert-routing gap that would silence *every* free-tier
incident, not just this one. There was zero customer-facing impact.

## Status

`resolved` — the underlying disk-full condition never existed (verified not-full independently), so
serving was never impaired. The orphaned heartbeat is armed by the post-merge `registry-host-replace`
dispatch (PR #6238, Fix A), which installs the ping cron and activates the retention pruning; the
heartbeat then transitions to `up` and Better Stack auto-resolves the incident. The alert-routing
gap (ops@ never notified) is closed by the IaC-managed recipient (Fix B).

## Symptom

Better Stack heartbeat `soleur-registry-disk-prd` in the "missed heartbeat" state, unacknowledged,
with `attributes.status` never having reached `up` since creation. No corresponding disk-pressure
signal anywhere (Hetzner volume API, disk IO, zot push logs all healthy).

## Incident Timeline

- **Start time (detected):** 2026-07-08 13:30 UTC (15:30 CEST)
- **End time (recovered):** 2026-07-08 — post-merge `registry-host-replace` dispatch arms the ping cron; heartbeat `up`; incident auto-resolves
- **Duration (MTTR):** alerting-layer only; serving MTTR = 0 (serving never impaired). Time from detection to diagnosed-false-positive: same day (hours).

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-07 23:30 | PR #6210 (zot capacity) merged to main. |
| agent | 2026-07-07 ~23:34 | `terraform apply` creates the registry host's disk-full heartbeat in Better Stack (`paused=false`) — but does NOT redeploy the host, so the `zot-disk-heartbeat.sh` ping cron and `storage.retention` pruning are never installed. |
| system | 2026-07-08 13:30 | Better Stack raises `soleur-registry-disk-prd | Missed heartbeat` after the grace window elapses with zero pings received. |
| human | 2026-07-08 15:30 CEST | Incident surfaced to the operator; remains unacknowledged (no IaC-managed recipient — see contributing factors). |
| agent | 2026-07-08 | Diagnosis: false positive. Hetzner volume API shows ~30 GB, disk IO near-idle. |
| agent | 2026-07-08 13:37 | Independent confirmation: a CI release pushes a full image to zot (many `pushed blob:` lines, zero `no space left on device`) — disk provably not full. |
| agent | 2026-07-08 | Alerting-layer fix built + multi-agent-reviewed (PR #6238): Fix A `registry-host-replace` dispatch path, Fix B `betteruptime_team_member.ops` recipient. No P0/P1; gate 12/12, parity 48/48, test-all 163/163. |
| agent | 2026-07-08 | Post-merge: `registry-host-replace` dispatch installs the ping cron + activates retention; heartbeat → `up`; Better Stack auto-resolves. |

## Participants and Systems Involved

- **Better Stack** — heartbeat monitoring + incident routing (free-tier: `policy_id=null`, email-only).
- **Hetzner** — registry host (`hcloud_server.registry`) + attached zot data volume.
- **zot** — self-hosted OCI registry (ADR-096); GHCR dark-launch fallback covers serving.
- **GitHub Actions** — `apply-web-platform-infra.yml` (now carries the `registry-host-replace` dispatch job).
- **Claude Code (agent)** — diagnosis, fix authoring, review, post-merge redeploy.
- **Operator (ops@jikigai.com)** — intended alert recipient.

## Detection (+ MTTD)

- **How detected:** monitoring — Better Stack raised the missed-heartbeat incident automatically. Note: it reached the operator only incidentally; the account-owner email path, not an IaC-managed recipient, surfaced it.
- **MTTD (mean time to detect):** the heartbeat fired at its designed grace boundary (13:30 UTC). The *misclassification* (false positive vs real disk-full) was resolved same-day via out-of-band verification.

## Triggered by

system — an orphaned monitoring resource created by an infra change (#6210) whose host-side half (the ping cron) was never deployed.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Registry disk actually full (zot data volume exhausted) | Alert name literally says "disk"; registry is disk-backed | Hetzner volume API ~30 GB; disk IO near-idle; 13:37 UTC CI push succeeded with zero `no space left on device` | REJECTED |
| Registry host down / unreachable | A down host would also miss the heartbeat | 13:37 UTC CI push to zot succeeded → host + registry serving fine | REJECTED |
| Ping cron never installed (heartbeat orphaned by a missing host redeploy) | Heartbeat `status` never reached `up` since creation; #6210 created it but did not redeploy the host; no reprovision path existed | — | CONFIRMED |

## Resolution

Two-part fix shipped in PR #6238:

- **Fix A — `registry-host-replace` dispatch path.** A dispatch-only `workflow_dispatch` job that
  runs a scoped `terraform apply -replace='hcloud_server.registry'` (5-target, destroy-guard
  preserves the zot data volume) to reprovision the registry host **without SSH**. This installs the
  `zot-disk-heartbeat.sh` ping cron (arming the heartbeat) and activates the `storage.retention`
  pruning from #6210. It gives the registry host the CI reprovision escape hatch it previously
  lacked (the inngest host already had one).
- **Fix B — `betteruptime_team_member.ops`.** ops@jikigai.com added as the IaC-managed free-tier
  alert recipient, so future incidents email the operator instead of only the account owner.

## Recovery verification

Post-merge, the agent dispatches `registry-host-replace`, then verifies (a) the heartbeat
`attributes.status` transitions to `up` (first ping received), and (b) Better Stack auto-resolves the
`soleur-registry-disk-prd` incident. Independent disk-health evidence already on record: the
2026-07-08 13:37 UTC CI release pushed a full image to zot with zero `no space left on device`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the incident fire?** The `soleur-registry-disk-prd` heartbeat never received a ping, so
   Better Stack raised "missed heartbeat".
2. **Why did it never receive a ping?** The `zot-disk-heartbeat.sh` ping cron that pings it was never
   installed on the registry host.
3. **Why was the cron never installed?** #6210 shipped the heartbeat resource and the host cloud-init
   cron in the *same* PR, but `terraform apply` that creates a Better Stack heartbeat does **not**
   redeploy the Hetzner host — and the registry host had no CI reprovision path
   (OPERATOR_APPLIED_EXCLUSION; no dispatch-replace escape hatch like the inngest host has).
4. **Why did nobody notice the host wasn't redeployed?** A disk-gated heartbeat cannot, alone,
   distinguish host-down vs cron-missing vs disk-full; and a Better Stack heartbeat exposes no
   `last_event_at`, so "never pinged since creation" looks identical to "stopped pinging". The alert
   also never reached ops@ (see contributing factor) so it sat unacknowledged.
5. **Why was the misfire's blast radius acceptable anyway?** Serving does not depend on the
   self-hosted registry — ADR-096's GHCR dark-launch fallback covers image pulls — so a broken/absent
   registry heartbeat degrades deploy-pipeline observability, not user serving.

**Final root cause:** a new disk-gated heartbeat resource was shipped in the same PR as the host
cloud-init cron that feeds it, but creating the heartbeat via `terraform apply` does not redeploy the
host, and the registry host lacked any CI reprovision path — leaving the heartbeat orphaned and
guaranteeing a missed-heartbeat alert. Compounded by no IaC-managed alert recipient, so the false
positive reached no on-call.

## Versions of Components

- **Version(s) that triggered the outage:** #6210 (zot capacity PR) as merged 2026-07-07 — heartbeat created, host not redeployed.
- **Version(s) that restored the service:** PR #6238 (`registry-host-replace` dispatch + `betteruptime_team_member.ops`) + the post-merge dispatch that reprovisions `hcloud_server.registry`.

## Impact details

### Services Impacted

- **Deploy-pipeline observability (alerting layer):** the registry disk-full heartbeat was orphaned and produced a false-positive incident; #6210's retention pruning was also not live. Degraded capability, not availability.
- **Serving / image pulls:** none — GHCR dark-launch fallback (ADR-096) covers pulls independently of the self-hosted registry.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: None — no customer-facing surface touched.
- Authenticated app user: None — serving unaffected (GHCR fallback covered pulls).
- Legal-document signer: None.
- Admin via Access: None.
- Billing customer: None.
- OAuth installation owner: None.

### Revenue Impact

None. No serving disruption, no billing surface touched.

### Team Impact

An unacknowledged false-positive incident consumed diagnosis time (out-of-band disk verification via
Hetzner API + CI push logs) and eroded trust in the registry alert. No user-facing cost.

## Lessons Learned

### Where we got lucky

- The alert name said "disk" but disk was independently verifiable as not-full (Hetzner volume API,
  IO, and a same-day successful zot push) — the false positive was falsifiable in minutes.
- ADR-096's GHCR dark-launch fallback meant a broken self-hosted registry never threatened serving,
  so an orphaned registry heartbeat was safe to be wrong.

### What went well

- Diagnosis correctly rejected the scary literal reading ("disk full") using three independent
  disk-health signals rather than reacting to the alert name.
- The fix was structural (a reprovision escape hatch + an IaC-managed recipient), not a one-off
  ping/ack.

### What went wrong

- A monitoring resource and the host-side cron that feeds it shipped in the same PR, but only the
  monitoring half took effect on `terraform apply` — creating a guaranteed-orphaned heartbeat.
- The registry host had no non-SSH reprovision path, so the host-side half could not be armed without
  one being built first.
- Better Stack alert recipients were not managed in Terraform (free-tier, `policy_id=null`,
  email-only, zero-user on-call schedule), so the incident reached no on-call — only the account
  owner was emailed.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #6241 | Operator-only: ops@jikigai.com must ACCEPT the Better Stack team-member invite (a click in ops@'s own inbox; `betteruptime_team_member` is inert until accepted). Re-evaluate after the next Better Stack incident fires — confirm ops@ received the email. | open |
| #6242 | Recurrence-prevention: audit whether other dedicated hosts (git-data) shipped a heartbeat/monitor without a redeploy path — same failure class as this incident. | open |

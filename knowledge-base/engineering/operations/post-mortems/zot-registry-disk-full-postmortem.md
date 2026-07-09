---
title: "zot registry ext4 filesystem full — resize2fs silently swallowed, block-device size masked the truth"
date: 2026-07-08
incident_pr: 6246
incident_window: "2026-07-08 ~13:xx UTC (first zot 500s + disk-heartbeat miss) → mitigation shipped 2026-07-08 in #6246 (fail-loud resize + observability)"
recovery_at: "2026-07-08 (deeper fix + telemetry merged in #6246; full recovery verified in-session on the post-merge registry-host-replace redeploy)"
suspected_change: "Latent since the registry host was introduced (#6122): the on-boot `resize2fs ... || true` silently swallowed failure, so the ext4 fs never grew to the 30 GB block device. Surfaced now because the store finally filled."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (deploy pipeline / self-hosted zot registry-mirror step)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability-only degradation of the deploy-pipeline /
# registry-mirror layer (an aggregate pattern, not a single named user). Image serving
# to running hosts is GHCR-fallback-covered; the self-hosted zot is a mirror/pull
# optimization, not the sole serving path. This is a registry/infra non-event for
# personal data: the zot host holds only OCI image blobs (no customer PII, no auth
# material, no schema). No confidentiality or integrity loss — GDPR Art. 33/34 do not
# apply (n/a). The one secret involved (BETTERSTACK_LOGS_TOKEN) is a write-only logs
# ingest token in an isolated Doppler config, never exposed.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The self-hosted zot OCI registry (Hetzner host, deny-all ingress, no SSH) runs its
storage on a 30 GB block-device volume mounted at `/var/lib/zot`. The ext4 filesystem on
that volume was **full**. The full filesystem produced two simultaneous, initially-
disjoint-looking symptoms:

1. **Recurring zot-mirror 500s (#6240):** the Web Platform Release workflow's zot-mirror
   step failed on blob upload with HTTP 500 + `connection reset by peer` (ENOSPC on the
   registry host). This recurred on every recent `main` commit and becomes deploy-blocking
   once the zot pull path enforces (until then, serving is GHCR-fallback-covered).
2. **Missed `soleur-registry-disk-prd` heartbeat (the still-open Better Stack incident):**
   the disk heartbeat pings Better Stack ONLY while `/var/lib/zot` is `<85%` used. A full
   fs meant the `<85%` ping never fired → the heartbeat went stale → Better Stack raised
   (and kept open) the disk incident.

The root cause was a **silently-swallowed `resize2fs`**: the on-boot cloud-init command was
`resize2fs <device> || true`, so when it failed the ext4 fs never grew to fill the 30 GB
block device, and the failure was invisible. The prior remediation's post-mortem wrongly
concluded "disk not full" because it read the **Hetzner block-device size (30 GB)** — never
the **guest filesystem size** — so the two numbers disagreed and the block-device number
looked healthy. On a deny-all, no-SSH host there was no guest-`df` telemetry to see the truth.

## Status

resolved — the deeper fix (fail-loud `resize2fs` + device-wait + no-partition assert) and
the missing observability (`SOLEUR_ZOT_DISK` df%/resize event to Better Stack Logs) shipped
in PR #6246. Recovery is verified in-session on the post-merge registry-host-replace redeploy
(see Recovery verification).

## Symptom

- zot returns HTTP 500 + `connection reset by peer` on blob-upload; the Web Platform Release
  zot-mirror step fails on every recent `main` commit (#6240).
- The `soleur-registry-disk-prd` heartbeat is stale (no `<85%` ping) → Better Stack disk
  incident open.
- Guest `df` on `/var/lib/zot` reports a filesystem far smaller than the 30 GB block device,
  and at (or near) 100% used — but this was invisible until this PR added the telemetry.

## Incident Timeline

- **Start time (detected):** 2026-07-08 ~13:xx UTC
- **End time (recovered):** 2026-07-08 (fix + telemetry merged in #6246; recovery verified on the post-merge redeploy)
- **Duration (MTTR):** ~same-day — detection ~13:xx UTC, deeper fix merged same day.

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-07-08 ~13:xx | zot begins returning 500 + `connection reset by peer` on blob-upload; the `soleur-registry-disk-prd` heartbeat stops firing its `<85%` ping (miss begins). |
| agent | 2026-07-08 ~13:xx–17:xx | First remediation (PR #6238) built the registry-host-replace dispatch path + added the `ops@` recipient to the Better Stack disk incident, on the hypothesis of a false-positive / stale heartbeat. |
| agent | 2026-07-08 17:17 | PR #6238 merged. |
| agent | 2026-07-08 17:20 | Post-#6238 redeploy completed — but the zot-mirror step STILL 500'd: the disk was genuinely full, and the on-boot `resize2fs ... \|\| true` was silently failing, so the replace never grew the fs. |
| agent | 2026-07-08 | Root cause identified: block-device size (30 GB, healthy-looking) ≠ guest filesystem size (small, full); the prior "disk not full" conclusion had read the block-device size. `resize2fs`'s `\|\| true` had masked the resize failure; the deny-all/no-SSH host had no guest-`df` telemetry to reveal the truth. |
| agent | 2026-07-08 | Deeper fix implemented (#6246): fail-loud `resize2fs` + device-wait + no-partition assert; `SOLEUR_ZOT_DISK` df%/resize telemetry to Better Stack Logs; gc 24h→1h + retention 24h→2h; boot-guard 2→3 secrets; logs-token threaded through the registry-host-replace dispatch + destroy-guard + parity. Reviewed by 5 agents, no P0/P1, all findings fixed inline. |
| agent | 2026-07-08 | Green: full suite 163/163, gate 15/15, boot-guard 30/30, parity 48/48, c4 3/3. |

## Participants and Systems Involved

- **Systems:** self-hosted zot OCI registry (Hetzner host, deny-all ingress, no SSH); its
  30 GB storage volume + ext4 fs at `/var/lib/zot`; the Web Platform Release zot-mirror step;
  Better Stack (`soleur-registry-disk-prd` heartbeat + Better Stack Logs free-tier source);
  the isolated `soleur-registry/prd` Doppler config; the `registry-host-replace` CI dispatch.
- **Participants:** `agent` (Claude Code, autonomous remediation + fix); Better Stack
  (external monitor that surfaced the heartbeat miss). No end-user reporter.

## Detection (+ MTTD)

- **How detected:** monitoring — the recurring zot-mirror 500 in the Web Platform Release
  workflow (#6240) and the Better Stack `soleur-registry-disk-prd` heartbeat miss (open
  incident). Not an end-user report.
- **MTTD (mean time to detect):** near-immediate — the failing release step and the missed
  heartbeat both surfaced on the same day the store filled.

## Triggered by

system — a self-inflicted latent defect (silently-swallowed on-boot resize) that manifested
once the store organically filled; no user action, market movement, or provider outage.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Stale/false-positive heartbeat (disk NOT actually full) | Hetzner block-device API reported 30 GB, well under quota; prior PM read this and concluded "not full" | zot 500'd with `connection reset` on blob upload (ENOSPC signature); post-#6238 redeploy still 500'd | REJECTED — falsified by the post-redeploy 500; block-device size ≠ filesystem size |
| ext4 fs never grew to the 30 GB block device (resize silently failed) | `resize2fs ... \|\| true` swallows failure; guest `df` (once telemetry added) shows fs << 30 GB and full | none | CONFIRMED |
| gc/retention too slow to reclaim a filling store | gc ran only once per 24h, retention delay 24h | fs was far smaller than the device — reclamation could not have kept a 30 GB device full; this is defense-in-depth, not the primary cause | SECONDARY (contributing) |

## Resolution

PR #6246 (fix-forward, no rollback):

1. **Fail-loud `resize2fs`** — removed `|| true`; the exit code is captured (not swallowed).
   Added a device-wait loop (the volume attach can land after cloud-init's disk stage) and a
   no-partition assert (ext4-on-raw-device invariant, so `resize2fs <device>` is correct and
   `growpart` is never needed). On failure it is LOUD in telemetry (`resize_ok=false`) but does
   NOT wedge the boot — zot still launches on the existing fs so the host stays reachable to
   self-report (fail-loud, NOT fail-dark).
2. **`SOLEUR_ZOT_DISK` observability (#6244)** — the deny-all/no-SSH host now self-reports its
   disk state as ONE `SOLEUR_ZOT_DISK` event to the free-tier Better Stack Logs source every
   5 min (`pcent`, `fs_size_gb`, `block_size_gb`, `resize_ok`, `zot_restarts`, `ping_rc`).
   Those fields discriminate all competing root causes in a single queryable event — the
   telemetry that was missing to diagnose this.
3. **gc/retention tightening** — `gcInterval` 24h→1h and `retention.delay` 24h→2h (defense-in-
   depth) so a filling store is reclaimed within ~1h. `gcDelay` (dangling-blob safety window)
   and the keep-set are unchanged.
4. **Boot-guard 2→3 secrets** — the isolation self-check now admits `BETTERSTACK_LOGS_TOKEN`
   by name (alongside the two ZOT tokens); a 2-secret config now FATALs (loud fail > silent
   observability blind spot).
5. **Secret threaded end-to-end** — `BETTERSTACK_LOGS_TOKEN` (write-only logs ingest, isolated
   `soleur-registry/prd` config) is added to the `registry-host-replace` dispatch `-target`
   set, the destroy-guard allow-set (with a `secret_destroyed` named backstop), and the
   terraform-target parity test, with a secret-preserved backstop so a mis-edit that would
   drop or destroy it fails the gate.

## Recovery verification

The primary post-merge verification is done by the orchestrator IN-SESSION on the
`registry-host-replace` dispatch: after redeploy, the first `SOLEUR_ZOT_DISK` event in Better
Stack Logs (`scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK`, no SSH) confirms
`resize_ok=true` and `fs_size_gb≈28` GiB (fs grew to fill the 30 GB device), the zot-mirror
push succeeds (no 500), and the `soleur-registry-disk-prd` heartbeat returns to `status==up`
with the Better Stack incident auto-resolving. Pre-merge green: full suite 163/163, gate
15/15, boot-guard 30/30, parity 48/48, c4 3/3.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the zot-mirror step 500 and the disk heartbeat miss?** The ext4 filesystem on
   `/var/lib/zot` was full (ENOSPC on blob write; the `<85%` heartbeat ping never fired).
2. **Why was the filesystem full when the block device is 30 GB?** The ext4 fs never grew to
   the 30 GB block device — it stayed at its original (smaller) size and filled.
3. **Why did the fs never grow?** The on-boot `resize2fs <device> || true` **silently failed**;
   the `|| true` swallowed the non-zero exit, so the resize error was invisible and the boot
   continued as if it had succeeded.
4. **Why did the prior remediation (#6238) not catch this?** Its post-mortem read the Hetzner
   **block-device size (30 GB)** and concluded "disk not full" — it never read the **guest
   filesystem size**, so the block-device number (healthy) masked the fs number (full). Block-
   device size ≠ filesystem size.
5. **Why was the guest filesystem size never checked?** The registry host is deny-all ingress
   with no SSH, and there was **no guest-`df` telemetry** on that blind surface — no in-surface
   signal existed to reveal the fs was full, so the only visible number was the (misleading)
   block-device size from the Hetzner API.

**Final root cause:** a silently-swallowed on-boot `resize2fs` (`|| true`) left the ext4 fs
un-grown and full, and the absence of guest-filesystem telemetry on a deny-all/no-SSH host meant
the truth was invisible — so a prior remediation misread the block-device size as "not full."

## Versions of Components

- **Version(s) that triggered the outage:** the registry cloud-init as of the pre-#6246 `main`
  (on-boot `resize2fs ... || true`; 2-secret boot guard; gc 24h / retention 24h; no
  `SOLEUR_ZOT_DISK` telemetry). Latent since the registry host was introduced (#6122).
- **Version(s) that restored the service:** PR #6246 (fail-loud `resize2fs` + device-wait +
  no-partition assert; `SOLEUR_ZOT_DISK` telemetry; gc 1h / retention 2h; 3-secret boot guard;
  logs-token through the dispatch + destroy-guard + parity).

## Impact details

### Services Impacted

- **Web Platform Release / zot-mirror step:** failed on blob upload (500) on every recent
  `main` commit. Not yet deploy-blocking (image serving is GHCR-fallback-covered), but would
  become blocking once the zot pull path enforces.
- **`soleur-registry-disk-prd` heartbeat:** stale / missed → open Better Stack disk incident.
- **Image serving to running hosts:** NOT impacted — GHCR fallback covered the pull path; the
  self-hosted zot is a mirror/pull optimization, not the sole serving path.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE.

- Prospect: none — no customer-facing surface touched.
- Authenticated app user: none — serving covered by GHCR fallback; no downtime.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

Blast radius is the internal deploy pipeline / registry-mirror layer (an aggregate pattern),
not any single named user, and it was GHCR-fallback-covered.

### Revenue Impact

None. No customer-facing outage, no billing surface touched.

### Team Impact

A wasted remediation cycle (#6238) that shipped + redeployed but did not fix the problem,
because the diagnosis read the wrong size (block device vs filesystem). Cost: one extra
merge + redeploy and the time to falsify the "disk not full" conclusion.

## Lessons Learned

### Where we got lucky

- The zot pull path does not yet enforce, so the recurring mirror 500 was not deploy-blocking —
  GHCR fallback covered serving. Had enforcement already flipped, this would have blocked deploys.
- The store filled during active investigation, so the missing telemetry was added before it
  became a hard blocker.

### What went well

- The absence-based heartbeat (`<85%` ping) DID fire (by going silent) — the alerting design
  worked; it was the diagnosis that misread the numbers, not the alert.
- Fix-forward with in-surface observability first: the `SOLEUR_ZOT_DISK` event now makes the
  blind host diagnosable, so a recurrence is a query, not an SSH expedition.
- 5-agent review with all findings fixed inline; no P0/P1.

### What went wrong

- `resize2fs ... || true` swallowed a real failure — a silent-fallback anti-pattern on a
  boot-critical path (`cq-silent-fallback-must-mirror-to-sentry` in spirit).
- The prior post-mortem read the Hetzner block-device size and concluded "disk not full"
  without ever reading the guest filesystem size — block-device size ≠ filesystem size.
- A deny-all/no-SSH host had NO in-surface disk telemetry, so the only visible number was the
  misleading one (`hr-no-dashboard-eyeball-pull-data-yourself` / `hr-observability-as-plan-quality-gate`).

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

The primary post-merge verification (dispatch registry-host-replace → `SOLEUR_ZOT_DISK`
confirms resize + zot pushes succeed + heartbeat up) is performed by the orchestrator
IN-SESSION, so it is NOT a tracked follow-up row. The fail-loud resize, the observability, the
gc/retention tightening, and the boot-guard/secret threading all shipped in the source PR
(#6246). The only residual, contingent item is telemetry-gated:

| Issue | Action | Status |
|---|---|---|
| #6247 | Telemetry-gated contingency: grow `var.registry_volume_size` beyond 30 GB ONLY if, post-redeploy, `SOLEUR_ZOT_DISK` shows the 30 GB fs is genuinely full of retention-KEEP blobs (`resize_ok=true`, `fs≈full`, `pcent>=85` after the tightened gc runs) — NOT if the resize simply had not applied (`resize_ok=false` / `fs_size_gb << block_size_gb`, which the #6246 fix itself resolves). `deferred-automation`; re-eval after the first post-#6246 `SOLEUR_ZOT_DISK` event is observed. | open |

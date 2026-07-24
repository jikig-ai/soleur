---
title: "Postmortem: web-1 /workspaces LUKS cutover silently reverted by its own dead-man timer; encryption dark ~6h, 27min of sole-copy writes stranded"
date: 2026-07-22
incident_pr: 6809
incident_window: "2026-07-20 22:14:50Z (cutover aborted at app_canary on a CF 521; LUKS mount serving) → 2026-07-20 22:42:13Z (dead-man timer fired, remounted plaintext /dev/sdb over the LUKS mount). Detected 2026-07-21 ~04:36Z by the #6807 verify dispatch. Encryption-at-rest remains NOT in effect as of 2026-07-22 (re-cut pending)."
recovery_at: "unresolved — re-cut authorized, tracked on #6812"
suspected_change: "The 2026-07-20 LUKS cutover (run 29782780158): app_canary probes /health ~590ms after docker start, took Cloudflare's instant 521, and die()d. CANARY_OK=1 is set by the host canary BEFORE app_canary, so cleanup() correctly did not roll back — but disarm_dead_man runs AFTER app_canary, so the armed dead-man timer was never cleared and fired 30min later."
brand_survival_threshold: single-user incident
status: unresolved but ended
triggers:
  - workspaces luks cutover
  - dead-man timer
  - mount_not_mapper
  - encryption at rest not in effect
  - sole-copy data stranded
  - silent revert
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability + encryption-posture incident, NOT a personal-data exposure/breach. The plaintext volume was never accessed by an unauthorized party; the data was mis-encrypted-at-rest and briefly divergent, not exfiltrated. GDPR Art. 32 (security of processing) posture is degraded — the published privacy policy claims LUKS while /mnt/data is plaintext — but there is no Art. 33/34 notifiable personal-data breach."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

On 2026-07-20 a LUKS-at-rest cutover of web-1's `/workspaces` volume (ADR-119, #6604) landed: `/mnt/data`
became `crypto_LUKS` on `/dev/mapper/workspaces` and served production traffic. ~0.6s into the app canary
it hit a Cloudflare 521 (the origin was still booting) and the cutover script `die()`d. Because the host
canary had already set `CANARY_OK=1`, the abort's `cleanup()` correctly declined to roll back — but the
same ordering meant `disarm_dead_man` (which runs *after* the app canary) was never reached, leaving the
freeze's dead-man timer armed. 30 minutes later (22:42:13Z) the timer fired and remounted the retained
plaintext volume (`/dev/sdb`) over the healthy LUKS mount.

The net effect: encryption-at-rest was silently undone, ~27 minutes of user writes (22:14–22:42) were
stranded on the now-unmounted LUKS volume, and **nothing paged for ~6 hours** — a successful dead-man
remount emitted no marker on any channel. The state was discovered 2026-07-21 ~04:36Z when the #6807
verify workflow (whose whole purpose was to answer "is the repointed volume serving user data?") returned
`FAIL (mount_not_mapper): mount_source=/dev/sdb`.

## Status

`unresolved but ended` — the divergence has stopped growing only in the sense that the app now serves
consistently from the plaintext volume; encryption-at-rest is still not in effect and the stranded writes
are still on the detached LUKS volume. The re-cut (with the #6807 fixed probes) is the resolution and is
tracked on #6812.

## Symptom

`/mnt/data` mounted from raw `/dev/sdb` (plaintext ext4), not `/dev/mapper/workspaces`. The published
privacy/GDPR/DPD documents assert LUKS encryption at rest; that claim is false for the live volume.

## Incident Timeline

- **Start time (detected):** 2026-07-21T04:36:09Z (verify dispatch surfaced it)
- **Actual onset:** 2026-07-20T22:42:13Z (dead-man remount)
- **End time (recovered):** not yet — re-cut pending (#6812)
- **Duration (MTTR):** open; ~6h from onset to detection (MTTD)

| Actor | Time (UTC) | Action |
|---|---|---|
| agent-with-ack | 2026-07-20 22:11:49 | Cutover run 29782780158: FREEZE begins, `arm_dead_man` fires (`DEAD_MAN_MIN=30`). |
| agent | 2026-07-20 22:14:50.31 | Host canary passes; `/mnt/data` IS the LUKS mapper; `CANARY_OK=1` set. |
| agent | 2026-07-20 22:14:50.89 | `app_canary`: `FATAL app /health=521` (CF instant 521, origin booting) → `die` → `ABORT (rc=1)`. |
| system | 2026-07-20 22:14–22:42 | LUKS mount serves production traffic; ~27min of sole-copy writes land on it. |
| system | 2026-07-20 22:18:19 | `luks-monitor`: `OK: /mnt/data is LUKS-backed` (last healthy observation). |
| system | 2026-07-20 22:42:13 | `workspaces-luks-deadman.service: Failed with result 'exit-code'` — timer fired, remounted plaintext `/dev/sdb` over the LUKS mount. No success marker emitted. |
| agent | 2026-07-21 04:36:09 | #6807 verify dispatch (run 29801673645): `FAIL (mount_not_mapper): mount_source=/dev/sdb`; incident detected. |
| agent | 2026-07-21 ~04:40 | Better Stack journald pulled to reconstruct the 22:18→22:42 timeline; #6812 filed (P0). |
| human | 2026-07-21 | Operator accepted the 27-min loss; authorized a re-cut AFTER the fixed probes merge. |

## Participants and Systems Involved

web-1 (single prod host), the `workspaces-luks-cutover.yml` / `workspaces-luks-verify.yml` workflows,
`workspaces-cutover.sh` (the dead-man), `luks-monitor.sh`, Cloudflare edge (the 521), Better Stack journald
(the forensic timeline). Actors: the cutover agent-with-ack dispatch, and the #6807 work session that detected it.

## Detection (+ MTTD)

- **How detected:** the #6807 verify workflow dispatch — a ground-truth gate built for a *different* question
  ("is the volume populated?") returned the mount-identity failure. NOT a monitor: the daily `luks-monitor`
  timer never ran after 22:18 (the dead-man's own restart chain, which re-arms the timer, exited non-zero),
  and the Better Stack heartbeat that would have caught a dead probe is UNFED (#6808).
- **MTTD:** ~6h (22:42 onset → 04:36 detection).

## Triggered by

system — a Cloudflare edge 521 during the container-boot window, racing a single-shot canary.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Dead-man fired because app_canary aborted before disarm | source ordering (`CANARY_OK` @ :2307, `app_canary` @ :2321, `disarm` @ :2330); journald `deadman.service Failed` @ 22:42:13 exactly 30min after arm | none | CONFIRMED |
| The remount target was the plaintext volume | dead-man inline mounts `${dev:-/dev/disk/by-label/workspaces_plain}`; observed `mount_source=/dev/sdb` | none | CONFIRMED |

## Resolution

Not yet applied. The resolution is a re-cut using the #6807 fixed probes (bounded retry so the 521 boot race
no longer aborts, `/health` endpoint corrected, readiness+inventory assert, dead-man arm/fired/disarm markers).
Sequence (tracked on #6812): merge #6809 → dispatch `workspaces-luks-cutover.yml dry_run=false` through its
environment gate → dispatch `workspaces-luks-verify.yml -f seed_workspace_count=8` to satisfy the deferred AC1.
The operator accepted the 27-minute write loss (the re-cut luksFormats the plaintext device, discarding the
stranded LUKS-volume window — an irreversible, accepted data loss recorded on #6812).

## Recovery verification

TBD — the re-cut's own `workspaces-luks-verify.yml` run must conclude `success` with the verdict line
`SOLEUR_WORKSPACES_READYZ ready=true ... workspace_count=8 expected=8` against a genuinely LUKS-backed mount.
That is the deferred AC1, tracked on #6812.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why is /mnt/data plaintext?** The dead-man timer remounted the plaintext volume over the LUKS mount.
2. **Why did the dead-man fire?** It was armed at the freeze and never disarmed — `disarm_dead_man` runs after
   `app_canary`, and `app_canary` `die()`d first.
3. **Why did app_canary die?** It was single-shot and hit Cloudflare's instant 521 ~590ms after `docker start`,
   before the origin was listening; `--max-time 20` did not help because a 521 is a fast response, not a hang.
4. **Why was the 27-min divergence + the dead-man revert invisible for 6h?** Three independent blind spots:
   the `/health` abort called a bare `die` and emitted nothing to Sentry; a *successful* dead-man remount
   emitted no marker at all; and the dead-man's restart chain (which re-arms the daily monitor) failed, so the
   only steady-state probe never ran. The Better Stack heartbeat that would have caught a dead probe is unfed (#6808).
5. **Why did the verify workflow not catch it earlier?** It asserted 200 on the no-route API-prefixed health
   path and was structurally incapable of passing (the #6807 defect) — the runbook §5 gate was dead.

Final root cause: **an unattended backstop whose success emits nothing, sitting downstream of a single-shot
canary that a fast edge error can abort, with the disarm gated behind that canary.** #6807 fixes the probe
(bounded retry, correct endpoint, readiness assert, dead-man markers); #6812 tracks the production remediation.

## Versions of Components

- **Version(s) that triggered the outage:** `workspaces-cutover.sh` @ origin/main pre-#6807 (single-shot
  `app_canary`, dead-man with success-silent fire), `workspaces-luks-verify.yml` @ the no-route `/api/health` assertion.
- **Version(s) that restored the service:** none yet — #6809 ships the fixed probes; the re-cut restores encryption.

## Impact details

### Services Impacted

`/workspaces` at-rest encryption (not in effect). App availability was NOT impacted — the container served
throughout (from the LUKS mount 22:14–22:42, from plaintext since). No user-visible downtime.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: their checked-out repositories are served correctly (from the plaintext volume), so
  no functional impact. Two latent exposures: (1) encryption-at-rest is not in effect despite the privacy
  policy's claim; (2) any write committed 22:14–22:42Z lives only on the detached LUKS volume — if a user made
  a sole-copy change in that 27-min window it is not on the currently-served volume. Signup-provisioned
  workspaces have no git remote, so such a change has no upstream to rehydrate from.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One work session (#6807) pivoted from a probe fix to incident triage; the operator made an accept-the-loss
decision and authorized a re-cut.

## Lessons Learned

### Where we got lucky

The 27-minute window fell in low-activity hours and shows automated GitHub-webhook processing rather than
confirmed human source edits — the real sole-copy delta may be small or zero. The `cryptsetup close` succeeded
cleanly (no `mapper_close_failed` marker), so no decrypted copy was left open at `$STAGING` — the specific
at-rest-exposure #6588 exists to prevent did NOT occur.

### What went well

The ground-truth verify gate did exactly its job — it surfaced the true production state instead of a green
liveness lie. Reading the actual `mount_not_mapper` marker (not "run: failure") and pulling Better Stack
journald to reconstruct the timeline is what turned a confusing "test failed" into a diagnosed incident. The
operator was not asked to fetch anything (`hr-no-dashboard-eyeball-pull-data-yourself`).

### What went wrong

An unattended backstop was allowed to revert a landed cutover with zero telemetry; a single-shot canary was
abortable by a fast edge error; the disarm was gated behind the canary; and the off-host verify was structurally
incapable of catching any of it. Four failure modes, all of which #6807 closes at the probe layer.

## Action Items & Follow-ups

Every follow-up is issue-backed. The probe-layer fixes are IN #6809 (this PR); the production remediation and
the observability wiring are the residual work.

| Issue | Action | Status |
|---|---|---|
| #6812 | Re-cut web-1 to LUKS with the fixed probes; restore encryption at rest; satisfy deferred AC1/AC12. Records the accepted 27-min write loss. | open |
| #6808 | Wire `WORKSPACES_LUKS_HEARTBEAT_URL` so a dead daily probe pages (the missing signal that would have caught this within a day, not 6h). | open |
| #6814 | Decide whether the DAILY luks-monitor should assert readyz+inventory (would need a soak-query redesign). | open |

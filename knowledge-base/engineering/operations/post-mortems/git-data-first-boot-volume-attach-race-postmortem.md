---
title: "git-data rotate: the new host's first-boot bootstrap raced the volume attachment and stopped at its plaintext check"
date: 2026-10-13
incident_pr: 10210
incident_window: "2026-10-13 10:36:13Z (server created) to 10:38:20Z (apply returned); the new host stays unbootstrapped until the recovery sequence in #10138 runs"
recovery_at: "pending: the fix merges with PR #10210, then a rung-2 rehearsal, an evidence-only PR and a rotate re-dispatch, each dispatch needing an operator go-ahead that names the command"
suspected_change: "Latent since first-boot cloud-init began resolving the by-id link once; the rotate on 2026-10-13 hit the tail of Hetzner's attach latency (65 s and 125 s as Terraform recorded them, against 17-33 s on four earlier boots)"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - availability (git-data host first boot during a planned rotate)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale (inherited from #10175, 2026-10-13): the git-data store flag is off
# and no user repository is served from this host, so the failure cost a host build and left
# the rotate half-done; it exposed no personal data and caused no confidentiality or integrity
# loss. GDPR Art. 33/34 do not apply. The bootstrap was fail-closed by construction: it wrote
# no store marker, so no store action could run against the unverified host.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The real `git-data-host-rotate` run 38384137515 applied (7 added, 3 changed, 7 destroyed: measured, apply log, 2026-10-13). The fresh host's first-boot bootstrap then stopped at the named FATAL `plaintext_unverified reason=source`, because it resolved the plaintext volume's by-id link once and the attachment had not landed. The new host (server 170081857, LUKS volume 107125716) is up and unbootstrapped. The d6 cutover gate reads `d6_last_rotate_failed 38384137515`, as designed.

## Status

ongoing — the cause is fixed in PR #10210, but the host is recovered only by a new server (`user_data` is ForceNew and runcmd runs once per instance), so recovery waits on the sequence tracked in #10138.

## Symptom

Sentry showed `FATAL: plaintext_unverified reason=source — /dev/disk/by-id/scsi-0HC_Volume_106867358 does not resolve to a block device` at stage=bootstrap, and the apply step's boot poll ended `VERDICT=silent` after its 20 reads (measured, run log and Sentry, 2026-10-13). No `boot_complete` was emitted.

## Incident Timeline

- **Start time (detected):** 2026-10-13 10:37:11Z (the fatal), read by the operator from the run
- **End time (recovered):** not yet; see Status
- **Duration (MTTR):** open

Order of events (measured: apply log and Sentry, 2026-10-13):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent-with-ack | 10:36:13 | `hcloud_server.git_data` created by the rotate apply (the operator's go-ahead named the command). |
| agent | 10:36:30 | Cloud-init `bootcmd_start` on the new host. |
| agent | 10:37:11 | Bootstrap reached the plaintext check, resolved the link once and exited at the named FATAL. |
| agent | 10:37:18 | LUKS volume attachment completed (65 s after create, as Terraform recorded it). |
| agent | 10:38:19 | Plaintext volume attachment completed (125 s after create). |
| agent | 10:38:20 | Apply returned; the boot poll then read 20 times and ended `VERDICT=silent`. |
| human | 10:38 onward | Operator read the failed boot and asked for the cause to be fixed before any re-dispatch. |

## Participants and Systems Involved

Operator, Claude Code, `hcloud_server.git_data`, `hcloud_volume_attachment.git_data` and `.git_data_luks`, `git-data-bootstrap.sh`, `cloud-init-git-data.yml`, Sentry, the apply workflow's boot poll, the d6 cutover gate.

## Detection (+ MTTD)

- **How detected:** the apply workflow's boot poll and the Sentry fatal (monitoring), read by the operator.
- **MTTD (mean time to detect):** about 2 minutes (apply returned at 10:38:20, the fatal was at 10:37:11).

## Triggered by

provider — Hetzner attaches block volumes as separate actions after the server exists, and their latency varies.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| First boot raced the volume attachment | Terraform recorded the plaintext attachment finishing 70 s after the check ran; the bootstrap resolved the link once | none found | confirmed |
| A LUKS or key fault on the new volume | none | the failing check was the plaintext link, not the LUKS step | rejected |

## Resolution

PR #10210: the bootstrap waits up to 300 s at the plaintext link and stays fail-closed (the same named FATAL, the plaintext-empty verification never skipped); the `luks_open` heredoc's device wait is 300 counted passes, then one settle and a size-0 refusal before any `luksFormat`; the paid rehearsal delays both attachments on purpose so it exercises the waits. The recovery order is in the cutover runbook's entry of this date.

## Recovery verification

Not yet verifiable: it needs the rehearsal's `boot_complete` evidence and a successful rotate carrying the d6 marker, none of which has been run (each needs a go-ahead naming the command).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. The new host's bootstrap exited at the plaintext check — it resolved the by-id link once and the link did not yet exist.
2. The link did not exist because the attachment was still in flight: Hetzner attaches a volume in a separate action after the server is created.
3. First boot starts at server create, so it races those actions; four earlier boots attached in 17-33 s, so the race stayed latent.
4. Nothing in the bootstrap, the rehearsals or the tests modelled a slow attachment; the rehearsal harness attached in the same 17-33 s window.
5. The bootstrap was written against the observed latency rather than against the provider's contract (an attachment is eventually consistent after create).

## Versions of Components

- **Version(s) that triggered the outage:** `main` at 274fdd4a51 (bootstrap and cloud-init without a wait)
- **Version(s) that restored the service:** PR #10210 (not yet deployed to a host)

## Impact details

### Services Impacted

The git-data host rebuild only. The store flag is off and no repository is served from git-data (inherited from #10175, 2026-10-13).

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none (no repository is served from git-data)
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None measured.

### Team Impact

One planned rotate half-completed: one host build spent, a pending recovery sequence with three operator dispatches.

## Lessons Learned

### Where we got lucky

The bootstrap was fail-closed: it wrote no store marker, so no store action could run against the host, and the store flag was off.

### What went well

The named FATAL reached Sentry and the boot poll reported silence rather than success; the failure was read from evidence, with no host login.

### What went wrong

First boot assumed an attachment had landed. The rehearsals could not reproduce a slow attachment. A review of the first fix then showed its own wait charged 10 s per pass while sleeping 5 s, so it waited half as long as it said.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #10138 | Run the rung-2 rehearsal with the late-attachment delay, land the evidence-only PR, then re-dispatch the rotate (a plain replace first if #10207 merged as drafted); each dispatch needs an operator go-ahead naming the command | open |
| #10217 | The inngest host's LUKS stage loses the same attach race; the registry and inngest cloud-init waits still use 30 passes and should get the same bounded, fail-closed wait | open |

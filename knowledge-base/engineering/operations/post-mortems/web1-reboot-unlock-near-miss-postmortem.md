---
title: "Postmortem (near-miss): web-1 reboot would have stranded every workspace — fstab literal glob, no boot-time LUKS unlock, ADR-119 §(e) mount gate undelivered"
date: 2026-09-29
incident_pr: 9179
incident_window: "Latent since web-1's first boot 2026-03-17 (cloud-init wrote a literal-glob /mnt/data fstab line); the trigger armed when apply run 36340195638 (2026-09-27) printed reboot-required=yes on the live host. No outage occurred — the defect was measured before any reboot fired it."
recovery_at: "preempted — remediation shipped by PR #9179 and delivered by terraform_data.workspaces_boot_unlock_install on merge"
suspected_change: "No change. Three latent defects compounded: (1) the 2026-03-17 first-boot fstab line '/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2' — a literal glob systemd-fstab-generator cannot expand, no nofail; (2) the 2026-07-23 LUKS cutover left /dev/mapper/workspaces serving /mnt/data with no crypttab entry and no boot-time unlock unit on web-1; (3) the ADR-119 §(e) structural mount gate (RequiresMountsFor drop-in + chattr +i on the covered root-disk inode) was never delivered to web-1."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - web-1 reboot
  - fstab literal glob
  - mnt-data.mount emergency mode
  - no boot-time LUKS unlock
  - ADR-119 section-e mount gate undelivered
  - unattended-upgrades reboot-required
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability-class near-miss, NOT a personal-data exposure/breach. No reboot occurred; no data was written outside the LUKS volume; the ADR-119 §(e) hazard was a *latent* write path, never exercised."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Issue #9123 measured that web-1 (`soleur-web-platform`) could not survive a reboot. The forensic print
(apply run 36340195638, 2026-09-27) read `findmnt --fstab` and found the `/mnt/data` line still naming
the literal glob `/dev/disk/by-id/scsi-0HC_Volume_*` — written by cloud-init on first boot 2026-03-17,
predating the #6604 by-id pin. systemd-fstab-generator does not expand globs, and the line carries no
`nofail`, so `local-fs.target` would fail and the boot would drop into emergency mode — unreachable over
SSH and over the Terraform apply bridge. Even past that, nothing unlocks `/dev/mapper/workspaces` at
boot (no crypttab line, no unlock unit on web-1; #6931 covers only the fresh-host path), and the
ADR-119 §(e) structural gate preventing plaintext writes to the covered root-disk inode was never
delivered.

The same forensic print measured `reboot-required=yes` on the live host: the trigger was armed and an
unattended-upgrades reboot would have fired the outage by itself, with no automated path back. **No
outage occurred** — this postmortem documents a measured, armed near-miss remediated before it fired.

## Status

`resolved` — the coupled fix (fstab mapper pin, `workspaces-luks-reopen` unlock family, §(e) mount gate)
shipped in PR #9179 and is delivered host-side by `terraform_data.workspaces_boot_unlock_install` on
merge; delivery prints land AC11's evidence fields in the apply log. The supervised restart proof is
the runbook's separate gated step (`workspaces-luks-cutover-6604.md` §4).

## Symptom

No live symptom — latent armed defect. Had any reboot occurred: `mnt-data.mount` waits on a device named
`scsi-0HC_Volume_*` that never appears → `local-fs.target` fails → emergency mode → every user workspace
offline until manual Hetzner-console repair.

## Incident Timeline

- **Start time (detected):** 2026-09-27 — apply run 36340195638 `luks_monitor_install` state print
- **Trigger armed:** unknown earlier; confirmed `reboot-required=yes` on 2026-09-27
- **End time (recovered):** 2026-09-29 — PR #9179 remediation merged and delivered by apply
- **Duration (MTTR):** ~2 days detection-to-remediation; 0 minutes of user impact (near-miss)

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-27 | Forensic print on apply run 36340195638 surfaces literal-glob fstab line + reboot-required=yes |
| agent | 2026-09-28 | Issue #9123 filed; plan written; ADR-154 channel re-weigh sampled cx33 hel1-dc2 (CTO verdict: ship in-place) |
| agent | 2026-09-29 | Coupled fix shipped via PR #9179 (`terraform_data.workspaces_boot_unlock_install`, web-1 only per ADR-119 §(d)) |

## Participants and Systems Involved

- web-1 (`soleur-web-platform`) — Hetzner host carrying the LUKS-encrypted `/mnt/data` workspaces volume
- systemd-fstab-generator / `local-fs.target` — the boot-ordering surface that fails on the glob
- `workspaces-luks-reopen.{service,timer}` + `-failure.service` — the new boot-unlock family (mirrors #8210's git-data reopen)
- `terraform_data.workspaces_boot_unlock_install` — the Terraform-owned installer delivering all three parts
- `luks-monitor` daily probe — extended to report fstab/crypttab/`+i` fields so host-side drift pages via `workspaces_luks_drift`

## Detection (+ MTTD)

- **How detected:** manual forensic read of the `luks_monitor_install` state print inside an apply run — monitoring-adjacent, not a page. The gap it reveals: nothing probed "would a reboot succeed" until this measurement.
- **MTTD:** the fstab defect was latent ~6.5 months (2026-03-17 → 2026-09-27); the LUKS-boot gap was latent ~2 months (2026-07-23 cutover → detection).

## Triggered by

system — latent first-boot configuration defect, surfaced by forensic measurement before it fired.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| cloud-init wrote a literal glob that systemd cannot expand | `findmnt --fstab` prints the literal `*` path; cloud-init.yml at 5b8e24206c appends it verbatim | none | confirmed |
| LUKS cutover never delivered a boot-unlock path to web-1 | no crypttab line delivered; `What=/dev/mapper/workspaces` live but absent from fstab | none | confirmed |
| §(e) gate undelivered to web-1 | covered-inode `chattr +i` absent; no docker drop-in | none | confirmed |

## Resolution

PR #9179 delivers all three parts through one Terraform-owned installer: canonical
`/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2` fstab line (superseded lines commented,
exactly-one + line-count + live-source asserts); `workspaces-luks-reopen` unit family with Doppler
key-fetch → `cryptsetup luksOpen --key-file -` (key never on argv/disk/journal), bounded restart
ladder, standing 15-min retry timer, crypttab `noauto` by-id pin; and the §(e) gate (docker
`RequiresMountsFor=/mnt/data` drop-in + `chattr +i` on the covered inode via bind peek). Every mutating
step carries the exit-17 freeze refusal while `workspaces-luks-deadman.timer` is armed.

## Recovery verification

The apply run's before/after prints land AC11's fields (`findmnt --fstab`, crypttab count, unit states,
peek `lsattr`); a post-merge `workspaces-luks-verify` dispatch re-confirms the live mount. Guard suite
`workspaces-boot-unlock.test.sh` 585/585 including 47 mutation rows; `luks-monitor-install.test.sh`
199/199. The supervised restart proof is the runbook's separate gated step — `workspaces-luks-cutover-6604.md` §4.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why would a reboot take the site down? `local-fs.target` fails on an unexpandable fstab device line with no `nofail`.
2. Why is that line there? First-boot cloud-init appended `/dev/disk/by-id/scsi-0HC_Volume_*` verbatim on 2026-03-17; nothing ever rewrote it after the LUKS cutover repointed the live mount.
3. Why did the cutover leave it? The #6604 by-id pin and the #6931 boot-unlock work covered the fresh-host path; web-1 was the standing ADR-154 in-place exception and got neither.
4. Why did nothing notice for months? No probe asked "would this host come back from a reboot" — the daily `luks-monitor` checked mount posture, not boot-time recoverability.
5. Why did it become urgent on 2026-09-27? `reboot-required=yes` armed the trigger — the next unattended-upgrades reboot fires it without anyone choosing to reboot.

## Versions of Components

- **Version(s) that triggered the outage:** n/a — latent host configuration, no software release involved; no outage occurred.
- **Version(s) that restored the service:** PR #9179 merge + `terraform_data.workspaces_boot_unlock_install` apply.

## Impact details

### Services Impacted

None live — near-miss. Had it fired: soleur.ai app + every workspace volume on web-1.

### Customer Impact (by role)

- Prospect: none (no outage occurred)
- Authenticated app user: none — would have been total workspace loss-of-access until console repair
- Legal-document signer: none — same blast radius as app user had it fired
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None realized. The avoided event was full product unavailability with an unbounded manual-recovery MTTR (console-level repair, no automated path).

### Team Impact

Two days of forensic + remediation work inside the existing one-shot pipeline; no page, no scramble.

## Lessons Learned

### Where we got lucky

The forensic print ran *before* the armed trigger fired — `reboot-required=yes` was caught on a routine apply read, not by an outage. The defect failed closed for data (the glob line blocks boot rather than silently serving the root disk), so the latent state risked availability, never confidentiality.

### What went well

The measurement path itself worked: reading `findmnt --fstab` and `reboot-required` off the apply state print surfaced three stacked defects with no host login. The ADR-154 expiry clause did its job — cx33 availability was re-sampled and the CTO verdict recorded on the issue rather than assumed. The fix shipped as one coupled installer so no partial state (fstab fixed without boot-unlock, or vice versa) can exist.

### What went wrong

A literal-glob fstab line survived ~6.5 months and a LUKS cutover because nothing reconciles on-host fstab/crypttab against the post-cutover reality, and web-1's standing exception exempted it from the fresh-host hardening path without a re-weigh until now. The §(e) structural gate was designed but never delivered to the one host that needed it.

## Action Items & Follow-ups

The remediation itself is this PR; the supervised restart proof is deliberately tracked in the cutover
runbook (`workspaces-luks-cutover-6604.md` §4, dated by the cutover record) rather than a new issue.
Residual issue-backed work:

| Issue | Action | Status |
|---|---|---|
| #9187 | Re-weigh the ADR-154 web-1 in-place exception once cx33 hel1-dc2 availability is *sustained* (not a single sample); sequence exception retirement | open |
| #6931 | Land the fresh-host boot-unlock path so the same defect class cannot recur on the next provisioned host | open |
| #6730 | Unblock `host_creates > 0` birth routes so a `-replace` redeploy (the structural exit from the exception) is executable at all | open |

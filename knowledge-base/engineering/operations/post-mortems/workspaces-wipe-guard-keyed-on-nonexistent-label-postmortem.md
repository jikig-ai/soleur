---
title: "The plaintext-wipe mode and the rollback witness keyed on a filesystem label that never existed on web-1"
date: 2026-09-30
incident_pr: 9286
incident_window: "2026-09-30T08:53:54Z – merge of PR #9286"
recovery_at: "merge of PR #9286"
suspected_change: "403487494d (PR #9163, CONFIRM_WIPE mode)"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was exposed, altered or lost; the defect made two guards refuse (fail-closed), it did not touch data"
---

## Actor key

- `agent`: Claude Code did this autonomously (no operator ack required).
- `agent-with-ack`: Claude Code did this AFTER the operator confirmed via a menu option, per `hr-menu-option-ack-not-prod-write-auth`.
- `human`: the operator did this directly.

# Incident Overview

PR #9163 merged the `CONFIRM_WIPE` mode of `apps/web-platform/infra/workspaces-cutover.sh`. The mode zeroes web-1's retired plaintext `/workspaces` volume (Hetzner 105149570) after the LUKS cutover.

Two guards in that PR used the ext4 label `workspaces_plain` as the plaintext volume's identity. The first was the wipe target check (W6). The second was the Guard 5 physical witness: "no such label" meant "the plaintext is gone", which blocks `rollback()` and the dead-man restore.

No repo artifact ever wrote that label, so web-1's plaintext volume has none. As a result, main's copy of the script:

- would have refused the wipe (fail-closed, and harmless);
- would have refused every pre-wipe rollback and dead-man restore on web-1. That silently removed the documented recovery path for a failed cutover.

## Status

resolved

## Symptom

The read-only prod rehearsal (`workspaces-luks-cutover.yml`, `dry_run=true`, run 36710773788) refused with `wipe_target_label_mismatch label=none`. No write reached the host.

## Incident Timeline

- **Start time (latent defect on main):** 2026-09-30T08:53:54Z (PR #9163 merged)
- **Detected:** 2026-09-30T11:48:12Z (rehearsal run 36710773788)
- **End time (recovered):** merge of PR #9286
- **Duration (MTTR):** from detection to the #9286 merge (same day)

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-30T08:53:54Z | PR #9163 merged with the label-keyed W6 and Guard 5 witness. |
| agent | 2026-09-30T11:48:12Z | Read-only rehearsal dispatched. It refused with `wipe_target_label_mismatch label=none`, and nothing was written. |
| agent | 2026-09-30 | Root cause traced: no artifact writes the label. The rollback impact was identified from the same premise. |
| agent | 2026-09-30 | PR #9286 opened: identity bound to the recorded `PLAINTEXT_DEV`, with a single `_plaintext_record_status` predicate. 11-seat review; all findings fixed. |

## Participants and Systems Involved

The operator and Claude Code. The systems were `workspaces-cutover.sh` (delivered only by manual `workspaces-luks-cutover.yml` dispatch), web-1, and the plaintext volume 105149570.

## Detection (+ MTTD)

- **How detected:** by the designed read-only rehearsal, the pre-dispatch probe the runbook requires, rather than by monitoring or a user report.
- **MTTD:** about 3 hours after merge.

## Triggered by

system: a false premise in merged code.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The label was never written by any artifact | `blkid` on the target returned no LABEL. A repo grep finds no `mkfs -L` / `e2label` / `tune2fs -L` writer for `workspaces_plain`. #9123's plan had already noted that "labels are written by no repo artifact observed". | none | confirmed |

## Resolution

PR #9286 changes both guards:

- **W6** binds the target to `readlink -f` of the device the cutover itself recorded at freeze time (`PLAINTEXT_DEV`, from `findmnt -no SOURCE /mnt/data`).
- **Guard 5** reads "gone" only when the mapper is mounted and the recorded device is not an intact ext4 plaintext. A physical "record gone" gets its own refusal slug and never claims "wiped".

## Recovery verification

- The wipe, freeze and luks-monitor suites are green: 177, 187 and 88 rows, 0 failing.
- CI on the #9286 head runs the root-only loopback rows, including an unlabelled-loop row.
- The post-merge read-only rehearsal must emit `rehearsal_ok` with `plaintext_dev=` and `plaintext_fs_uuid=`. Tracked on #6604.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the rehearsal refuse?** W6 required the label `workspaces_plain`, and the volume has no label.
2. **Why did W6 require a label?** The #9163 plan chose the label as the plaintext identity.
3. **Why was a non-existent label chosen?** Nobody checked which artifact writes it. The one earlier signal was a line in #9123's plan, and it never reached #9163's plan.
4. **Why did 160 suite rows and a 10-seat review pass?** Every fixture created the label (`mkfs -L`), so the tests encoded the same premise.
5. **Why did no gate catch that?** No plan-time rule required a guard's on-host identity to cite its writer. That rule is added to `plan-sharp-edges.md` by #9286.

## Versions of Components

- **Version(s) that triggered the outage:** 403487494d (PR #9163)
- **Version(s) that restored the service:** the squash-merge of PR #9286

## Impact details

### Services Impacted

The web-1 LUKS cutover tooling only: the wipe mode, `rollback()` and the dead-man restore. The live app and the live LUKS volume were unaffected.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none observed. The latent risk was that, had a cutover failure needed a rollback during the window, recovery would have refused. No rollback was needed or attempted.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One fix-forward PR, which delays the ADR-119 plaintext destruction by about a day.

## Lessons Learned

### Where we got lucky

No cutover rollback was needed during the window.

### What went well

The two-step design (rehearsal before dispatch) caught the premise with zero writes, and the wipe guard failed closed.

### What went wrong

Tests and review built on the same unverified premise, so they could not falsify it.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6604 | Re-run the read-only rehearsal on main after #9286 merges. Then run the wipe dispatch under a per-command operator go-ahead, followed by the state forget and PR B. | open |

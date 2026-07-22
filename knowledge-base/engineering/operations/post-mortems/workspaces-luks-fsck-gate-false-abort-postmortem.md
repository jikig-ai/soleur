---
title: "workspaces-luks cutover: seven aborted freezes, the last on a gate that measured the wrong property"
date: 2026-07-20
status: RESOLVED
severity: SEV-3
brand_survival_threshold: single-user incident
duration: "~10 min cumulative production downtime across 7 freeze windows (2026-07-18 → 2026-07-20)"
detection: operator-observed (each dispatched cutover run failed visibly in its own Actions run)
gdpr_art33_notifiable: false
gdpr_art34_notifiable: false
gdpr_rationale: >-
  Availability-only. No personal data was accessed, altered, disclosed, or lost. Every abort was a
  fail-closed safe-abort followed by the DP-6 automatic remount of the untouched plaintext volume;
  the LUKS copy was never repointed and no user data left the host. Art. 33/34 do not engage.
issue: 6733
tags: [workspaces-luks, cutover, fail-closed-gate, false-positive, availability]
---

# workspaces-luks cutover: seven aborted freezes, the last on a gate that measured the wrong property

## Summary

The LUKS at-rest migration for `web-1` (ADR-119) was dispatched seven times between 2026-07-18 and
2026-07-20. Every run safe-aborted. Each abort held a production freeze — webhook + inngest-redis
quiesced, `docker stop -t 120` — for roughly 90 seconds on the first six attempts and ~4.5 minutes on
the seventh, then auto-rolled back to the plaintext mount via DP-6. Cumulative user-visible downtime
was on the order of ten minutes across the seven windows.

No data was lost or exposed in any run. The system failed in the direction it was designed to fail.
The defect was that it kept failing for reasons its own logs could not explain.

## Impact

- **Users:** `app.soleur.ai` unavailable for the duration of each freeze window (~90 s × 6, ~4.5 min × 1).
  No data loss, no data exposure, no degraded state after rollback — `/health` returned 200 after each.
- **Migration:** encryption-at-rest for the 8 production workspace repos slipped by two days and is
  still not complete as of this report. The workspaces remain on a plaintext volume.
- **Operator:** seven dispatch cycles, each requiring a manual environment-gate approval.

## Timeline (UTC)

| When | What |
|---|---|
| 2026-07-18 12:33 → 17:31 | Runs 29644526137 / 29649845529 / 29654062280 abort at C1 byte-identity verify |
| 2026-07-19 06:46 → 17:04 | Runs 29676994044 / 29687729540 / 29695998561 abort identically at C1 |
| 2026-07-19 (during) | Root cause 1 found: the script `luksFormat`'d and `luksOpen`'d but never ran `mkfs`, so the mount silently failed and rsync wrote to the **root disk** under the mountpoint. Fixed + fail-closed |
| 2026-07-19 22:34 | Run 29706401639 — first with the mkfs fix. Aborts at C1 on `.d..t...... ./` |
| 2026-07-20 (early) | Root cause 2 found: the G4 quiescence probe created and unlinked a file **inside** `$MOUNT` between the pass-2 delta rsync and C1, advancing the transfer root's mtime. C1 had been correct on all five aborts. Probe changed to a read-open with a PID self-filter |
| 2026-07-20 07:37 | Run 29725194755 dispatched. Both prior fixes hold: `STAGING_TARGET result=ok fs=ext4`, correct mapper, no stray; C1's mtime abort does not recur. Bulk rsync, FREEZE and G3 all pass |
| 2026-07-20 07:45 | Aborts at the `git fsck` gate: `FSCK FAIL` on 8 of 10 workspaces. DP-6 rolls back. `/health` 200 |
| 2026-07-20 (after) | Root cause 3 diagnosed; fix shipped in PR #6745 |

## Root causes

Three distinct defects, each masked by the previous one.

**1. Missing `mkfs` (fixed 2026-07-19).** The staging target was formatted as a LUKS container but
never given a filesystem, so `mount` failed. Under `set -uo pipefail` with no `-e` that failure was
swallowed, and the `mkdir -p` above had already created `$STAGING` as a plain directory on the root
disk. Every downstream gate then certified the wrong device, because C1, the `du` assert and the G3
manifest are all pure functions of the strings `$MOUNT` and `$STAGING` — nothing in that closure
anchored either string to a block device.

**2. A quiescence probe that perturbed what it measured (fixed 2026-07-19).** The G4 probe wrote and
unlinked a file inside the rsync transfer root, between the delta rsync and the verify. That advanced
the root directory's mtime, which `rsync -i` reports as `.d..t...... ./`. C1 was right every time; the
instrument was wrong.

**3. A gate that measured the wrong property and discarded its evidence (this report; fixed in #6745).**
The gate was:

```
git -C "$ws" fsck --full >/dev/null 2>&1 || { fsck_fail=$((fsck_fail+1)); log "FSCK FAIL: $ws"; }
```

Two defects, and they are the *same two* the C1 verify had before #6604-followup and the G4 probe had
before #6735 — three instances is a pattern, not a coincidence:

- **Evidence discarded.** `>/dev/null 2>&1` threw away the only datum that distinguishes a corrupt
  object from a benign pre-existing repo condition. The gate could say *that* it failed and nothing
  more, and `hr-no-ssh-fallback-in-runbooks` means there is no second way to ask.
- **Wrong property measured.** Its job is *"did the copy corrupt anything"*. What it tested is *"are
  these repos pristine"*. Any pre-existing property fails identically on the plaintext source, so
  8-of-10 is a systemic-cause signature, not a corruption signature.

The most likely underlying condition (still formally UNKNOWN, because the deciding datum was
discarded) is `fatal: detected dubious ownership`: the cutover runs as root, container repos are uid
1001 per the Dockerfile's `USER soleur`, and git refuses before reading a single object.

## What went right

- **Every abort was fail-closed and reversible.** DP-6 auto-remounted the plaintext volume on all
  seven runs, with no operator intervention and no residual state.
- **C1 was correct on all five of the aborts it was blamed for.** The instinct to narrow it was
  resisted; narrowing would have silenced the one signal that catches a wrong-device copy.
- **The environment gate held.** Every run required a human approval; nothing irreversible ever fired
  unattended.

## What went wrong

- **Three fail-closed gates in one script shipped without emitting the evidence that discriminates
  their own verdict.** Each cost an irreversible-freeze approval to discover.
- **A green rehearsal was not evidence.** `prepare_staging_target` short-circuits in the `DRY_RUN`
  arm, so three green dry runs on 2026-07-19 were each followed within minutes by a real-run failure.
- **The fix for defect 3 initially reproduced defect 3.** During implementation the verdict was
  returned via command substitution, which captured every marker row into a shell variable and left
  the run log and Better Stack with nothing. Caught by a local driver before commit.

## Corrective actions (shipped in PR #6745)

- The gate is now **differential**: it fsck's both the plaintext source and the LUKS copy and aborts
  only on a delta, so a pre-existing condition present on both sides no longer aborts.
- It is **self-reporting**: a monitored `SOLEUR_WORKSPACES_LUKS_FSCK` marker carries per-workspace
  `classification`, `reason`, `src_rc`, `dst_rc` and a scrubbed excerpt of the real fsck output to
  the run log and Better Stack, before any abort.
- The differential cannot degrade into a no-op: `probe_failed` is a separate **aborting** class
  evaluated before the comparison, an object-count floor makes `ok` mean *"walked N objects and found
  nothing"* rather than *"walked nothing"*, and the classifier is total with a fail-closed default.
- A **pre-freeze advisory probe** runs in both arms, so a rehearsal now answers the ownership
  hypothesis without spending a freeze approval — and aborts before the outage if any source repo is
  un-inspectable.

## Amendment — what the corrective actions did NOT cover (PR #6759, 2026-07-20)

The section above describes the gate as shipped. Follow-up work found that three of its properties
were **asserted but untested**, so this report should not be read as evidence the gate was
trustworthy on the day it merged:

- **The abort threshold had no test.** `_fsck_emit_and_verdict` aborts on ANY `probe_failed`
  (`-gt 0`), but every gate fixture in the loopback suite probed exactly ONE workspace, where
  `1-of-1` is indistinguishable from `all-of-1`. Mutation-proven: restoring the superseded ALL
  threshold passed every case while turning a 1-of-2 `probe_failed` into `rc 0, "no copy-introduced
  regression"` — this incident's own 8-of-10 shape, in the **gate** path, inside the freeze, where a
  false green precedes Phase 5's plaintext wipe. Now covered by L6k's two-workspace fixture.
- **`_FSCK_SETUP_FATAL_RE` carried a dead alternative.** `cannot chdir` never matched anything —
  git emits `fatal: cannot change to '<path>'`. Fail-closed via branch (2b), so no cutover was
  mis-certified, but the allowlist claimed precision it did not have. Every alternative now carries
  a measured/unmeasured record.
- **Branch (2b) itself had no test.** It is the only thing preventing an unrecognised fatal —
  which appears *identically on both sides*, so the differential finds no delta — from classifying
  `preexisting` and returning 0. Now covered by L6l.
- **H1 was never actually reproduced in CI.** The ownership refusal had not fired once across five
  PRs. The cause was measured, not inferred: the GitHub runner image ships `safe.directory = *` in
  its system gitconfig, so no ownership check could fire under any mechanism. With ambient config
  neutralized it fires from genuine foreign-uid ownership, and L6m now proves `-c safe.directory=`
  load-bearing against real git.

None of this changes the incident's timeline or its Art. 33/34 assessment. It does change how much
confidence the "Corrective actions" section above should carry on its own.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6754 | Phase 5's plaintext wipe should gate on `skipped=0` — a skipped workspace was never inspected, and nothing between the gate's log line and that wipe reads the count | engineering |
| #6754 | Loopback Session D builds a dm-crypt device it never mounts, so the cross-mount hazard L6a describes is not reproduced | engineering |
| #6733 | The cutover itself is still not complete. This report covers the aborts; only a completed run closes it | engineering |
| #6766 | The loopback suite ran red on `main` unnoticed: `infra-validation.yml` has no `push` trigger and `deploy-script-tests` is not a required check, so an absent or failing run is indistinguishable from a passing one | engineering |

## Cross-references

- Issue: #6733 (open — closed only by a completed cutover, never by a merge)
- Fix: PR #6745
- Learning: `knowledge-base/project/learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`
- ADR-119 (workspaces at-rest encryption)
- Prior fixes in this sequence: the `mkfs` fail-closed fix and the G4 read-probe fix, both merged 2026-07-19

---
title: The wipe guard read a filesystem label that no artifact ever wrote
date: 2026-09-30
category: logic-errors
module: apps/web-platform/infra/workspaces-cutover.sh
tags: [luks, wipe, guard, host-state, premise, review, pr-9286, pr-9163]
issue: 6604
pr: 9286
---

# Learning: the wipe guard read a label no artifact ever wrote

## Problem

PR #9163 shipped the `CONFIRM_WIPE` mode with an identity check (W6). The check required web-1's retained plaintext volume to carry the ext4 label `workspaces_plain`. Guard 5 read `/dev/disk/by-label/workspaces_plain` as "the plaintext still exists", which made "no label" mean "gone".

No repo artifact had ever written that label. The one earlier signal was a single line in #9123's plan: "labels are written by no repo artifact observed". It never reached #9163's plan, its 10-seat review, 160 green suite rows, or CI. The suites passed because every fixture handed the stub the label (`mkfs -L`).

The prod read-only rehearsal (run 36710773788) was the first thing to test the premise against the real host. It refused with `wipe_target_label_mismatch label=none`, and nothing was written.

The same premise also silently disarmed rollback. On web-1 the label is always absent, so Guard 5 read "gone" and refused every pre-wipe rollback and dead-man restore.

## Solution (PR #9286)

- **W6 identity.** The target must equal `readlink -f` of the device the cutover itself recorded (`PLAINTEXT_DEV`, from `findmnt -no SOURCE` at freeze). This is the only witness the host observed at cutover time.
- **Guard 5 and rollback.** Both use one predicate, `_plaintext_record_status`: valid, a block device, not the mapper, and ext4. The dead-man fire carries a documented subset, trusted only within the same boot because the transient timer cannot survive a reboot.
- **Pre-reboot evidence.** The rehearsal row now carries `plaintext_fs_uuid=`, a stable content anchor to rebind to if a reboot remaps kernel names.
- **Refusal vocabulary.** A physical "record gone" refusal no longer claims "wiped", and it always escalates. Only a persisted wipe marker proves a wipe.
- **Rollback ack.** A completed cutover now requires the rollback acknowledgement whatever `/mnt/data` is mounted on. The scope-out CONCUR gate DISSENTED on deferring this: the fix widened when rollback could remount the stale copy.

## Key Insight

A guard that reads a property of production state is only as good as the artifact that CREATES that state. Before a plan names an on-host identity (a label, a UUID, a path, a unit, a file) as a gate input, grep for its WRITER. If none exists, the guard asserts a premise, not a fact. Fixtures built from the same premise pass by construction, and the first real run falsifies it.

The cheapest falsifier was the read-only rehearsal. It exists for exactly this, and it ran only after merge.

## Session Errors

1. **#9163 shipped a guard on an unwritten label.** Recovery: the rehearsal refused fail-closed, and #9286 fixed forward. **Prevention:** plan sharp edge. For every on-host identity a guard reads, cite the artifact that writes it, or treat it as unverified and require a read-only rehearsal before the PR is called done.
2. **A scope-out was proposed as `pre-existing-unrelated` while the PR widened the hazard.** Recovery: the CONCUR gate DISSENTED and the fix went inline. **Prevention:** already covered by review §5. Grep the diff for the premise's gate before claiming "not exacerbated".
3. **`pgrep -f` in a status check was blocked by the self-match hook.** Recovery: I dropped it and read `git log`/`status`. **Prevention:** already hook-enforced; use `list_runs` from `proc.sh`.
4. **Suite flakes under host load (load average 50–65) in the fix agent's validation run.** Recovery: serial reruns were green. **Prevention:** one-off. Treat a single-row red on untouched code under a load banner as unresolved and re-run serially.
5. **The history seat's timeline was internally inconsistent** (a dead-man fire on 07-20 using a record first written on 07-23). **Prevention:** one-off. Verify seat timelines against commit dates before relying on them.

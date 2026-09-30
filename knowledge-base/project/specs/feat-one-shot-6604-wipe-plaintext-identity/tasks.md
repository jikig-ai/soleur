# Tasks — fix(infra): bind the plaintext wipe and Guard 5 to the recorded plaintext device

Plan: `knowledge-base/project/plans/2026-09-30-fix-wipe-plaintext-identity-binding-plan.md`.
Refs #6604 #6588. Do not close either.

## 1. Setup / RED

- [ ] 1.1 Harness (`workspaces-luks-harness.sh`) seam and default seed:
  - the `_plaintext_dev_type` seam records its argument;
  - `PLAINTEXT_DEV_TYPE` defaults to `ext4`;
  - `run_case` seeds `PLAINTEXT_DEV=/dev/sdz9`, with `PLAINTEXT_DEV_UNSEEDED=1` as the opt-out.
- [ ] 1.2 Wipe suite stub world:
  - delete the dead `_plaintext_label_present` override;
  - `blkid` `LABEL` defaults to empty;
  - `dumpe2fs` prints `<none>`;
  - the default seed gains `PLAINTEXT_DEV=$TGT_BLK`.
- [ ] 1.3 Write the G1 rows: P1, P2 (built with `PRE_INV`), R1, R2 (letter drift, built with
  `PRE_INV`), R3 and H3. Confirm G1-P1 is RED with `wipe_target_label_mismatch`.
- [ ] 1.4 Write G5b rows H1 (with the seam-argument assert), R1, D, U and M, and update G5c.
- [ ] 1.5 G5d:
  - add `g5d_arm <record>` for per-row arming;
  - give `G5D_BIN` its own `blkid` stub (`$G5D_TYPE`);
  - add rows R1, R2, H2 and H1;
  - delete the old markerless row.
  - Confirm H2 is RED today.
- [ ] 1.6 Arm rows A1 (unrecorded), A2 (injection payload), A3 (the mapper) and A4 (`BLKID_ABSENT`).
- [ ] 1.7 Freeze T35/T42b assert `^mount /dev/sdz9[[:space:]]`.
- [ ] 1.8 Loopback:
  - `new_plain` formats unlabelled;
  - `seed_state` appends `PLAINTEXT_DEV=$WP_DEV` before `$1`;
  - seed the record before any real arm;
  - add LW-P1..LW-P3, calling `seed_state` before each probe.
- [ ] 1.9 `luks-monitor.test.sh`: add `result=arm_refused reason=plaintext_dev_unrecorded` to the
  `_deadman_row` census.

## 2. Core implementation (`apps/web-platform/infra/workspaces-cutover.sh`)

- [ ] 2.1 Remove `PLAINTEXT_LABEL` and `_plaintext_label_present`. Add the `_plaintext_dev_type`
  seam, with a rationale comment and a keep-in-sync comment.
- [ ] 2.2 `_plaintext_gone` physical arm: the record is empty, is the mapper, or has a type other than
  `ext4`. `PLAINTEXT_GONE_WHY=plaintext_dev_gone`. Set `PLAINTEXT_DEV_SEEN` and `PLAINTEXT_DEV_TYPE`.
- [ ] 2.3 The refusal messages in `rollback()` and `assert_rollback_not_post_cutover()` carry
  `recorded=` and `recorded_type=`. Update the comments.
- [ ] 2.4 `rollback()` remount: `mount "$(read_state PLAINTEXT_DEV)" "$MOUNT"` only.
- [ ] 2.5 `arm_dead_man`:
  - validate the record: non-empty, charset, not the mapper, `blkid` resolvable. Otherwise emit
    `arm_refused reason=plaintext_dev_unrecorded` and `deadman_arm_failed`, then die;
  - the `gone_guard` physical clause uses `${blkid_bin} … ${dev}`, with a keep-in-sync comment;
  - the mount clause becomes `mount ${dev} ${MOUNT}`.
- [ ] 2.6 W6 `first_wipe` binding:
  - the record resolves to `$real`, else refuse `wipe_target_not_recorded_plaintext` with `target=`,
    `recorded=` and `recorded_real=`;
  - `label=` is kept as evidence (`none` when absent);
  - add `plaintext_dev=` to `rehearsal_ok`;
  - update the W7 comment.
- [ ] 2.7 `grep -c workspaces_plain workspaces-cutover.sh` → 0.

## 3. Docs

- [ ] 3.1 Runbook:
  - step 7b expected row (no hardcoded `/dev/sdb`) plus the reboot note;
  - new `wipe_target_not_recorded_plaintext` verdict row (all columns, no hand-edit of the state
    file);
  - rewrite the `wipe_deadman_armed` row;
  - the "no rollback" paragraph and the two `refused_plaintext_wiped` rows;
  - the W9 sentence in the rollback section;
  - `arm_refused reason=plaintext_dev_unrecorded`.
- [ ] 3.2 ADR-119 addendum: two sentence swaps.
- [ ] 3.3 Destruction record: rename the field to `format / observed label / recorded mount source`.
  The value stays `(fill …)`.

## 4. Verification

- [ ] 4.1 Run the wipe suite (unprivileged), the freeze suite, `luks-monitor.test.sh` and the
  loopback suite (sudo). Raise `WIPE_MIN_PASS` from 143 and `FREEZE_MIN_PASS` from 170 to the
  measured counts.
- [ ] 4.2 Apply every Guard Contract mutation (Guard 1 M1–M6, Guard 2 M1–M8). Each must drive its row
  RED. Put the table in the PR body.
- [ ] 4.3 Check every census AC and grep AC in the plan. Run `shellcheck` and `bash -n`.
- [ ] 4.4 Confirm no `.tf`, workflow or cloud-init file is in `git diff --name-only origin/main...HEAD`.

## 5. Post-merge

- [ ] 5.1 Dispatch the read-only rehearsal and arm a watch. Expect `rehearsal_ok`, `label=none`, and a
  `plaintext_dev` that resolves to `target`. A `wipe_target_not_recorded_plaintext` refusal means
  halt per the runbook.
- [ ] 5.2 The destructive dispatch needs a separate per-command go-ahead. It is not part of this PR.

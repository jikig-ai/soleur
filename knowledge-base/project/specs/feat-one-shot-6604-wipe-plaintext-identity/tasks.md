# Tasks — fix(infra): bind the plaintext wipe and Guard 5 to the recorded plaintext device

Plan: `knowledge-base/project/plans/2026-09-30-fix-wipe-plaintext-identity-binding-plan.md`.
Deepened 2026-09-30. Refs #6604 #6588; do not close either.

## 1. Setup / RED

- [ ] 1.1 Harness (`workspaces-luks-harness.sh`), inside the `bash -c` body with no apostrophes:
  - [ ] the `_plaintext_dev_type` seam records its argument and prints `${PLAINTEXT_DEV_FSTYPE-ext4}`.
    The knob is named `PLAINTEXT_DEV_FSTYPE`, NOT `PLAINTEXT_DEV_TYPE`;
  - [ ] the `_plaintext_blkid_bin` seam honours `BLKID_ABSENT` and `BLKID_BIN_PATH`;
  - [ ] after `source`, run `[ "${PLAINTEXT_DEV_UNSEEDED:-}" = 1 ] || persist_state PLAINTEXT_DEV /dev/sdz9`;
  - [ ] update the knob documentation.
- [ ] 1.2 Wipe suite stub world:
  - [ ] delete the dead `_plaintext_label_present` override;
  - [ ] `blkid` `LABEL` defaults to empty with rc 0;
  - [ ] `dumpe2fs` prints `<none>`;
  - [ ] the default seed gains `PLAINTEXT_DEV=$TGT_BLK`;
  - [ ] the happy-path field list becomes `label=none plaintext_dev=$TGT_BLK`.
- [ ] 1.3 G1 rows, all built with `PRE_INV` where they need `$W_CASE_DIR`: P1 (`W_LABEL=`), P2
  (alias), H2 (`W_LABEL=other`), R1, R2 (letter drift), R3 (last wins), R4 (`-o`) and H3 (`re_zero`
  with a wrong record). Refusals assert their evidence fields, no BEGUN, and `hdrs_gone`.
  - [ ] Confirm G1-P1 is RED with `wipe_target_label_mismatch`.
- [ ] 1.4 The W-row (writer→reader) and the G5b rows H1 (seam argument), R1, D, B, U, M and V, plus
  G5c.
  - [ ] Confirm G5b-H1's seam assertion is RED.
- [ ] 1.5 G5d:
  - [ ] `g5d_arm <record>` rebinds `G5D_FIRE` and `G5D_STATE`;
  - [ ] the `G5D_BIN/blkid` stub checks its argv (`G5D_EXPECT_DEV`, exit 64 otherwise);
  - [ ] the `findmnt` stub checks its argv;
  - [ ] replace the instrument guard;
  - [ ] add rows R1, R2, D, H2 and H1;
  - [ ] delete the old "markerless, label gone" row;
  - [ ] rename the "label" titles.
  - [ ] Confirm H2 is RED.
- [ ] 1.6 Arm rows A1–A6 (T33 shape, `DRY_RUN=0`), each with its expected `detail=`.
  - [ ] Confirm A1 arms today.
- [ ] 1.7 Freeze T5/T35/T42b assert `^mount /dev/sdz9[[:space:]]`.
- [ ] 1.8 Loopback:
  - [ ] `new_plain` formats unlabelled;
  - [ ] `seed_state` appends `PLAINTEXT_DEV=$WP_DEV` before `$1`;
  - [ ] the LW1a assertion becomes `'^PLAINTEXT_WIPE(_BEGUN|D)='`;
  - [ ] add LW-P1..LW-P4 (`seed_state` before each; echo `why=`; place them before `new_plain lw4`).

    The suite never arms, so no arm seeding is needed.
- [ ] 1.9 `luks-monitor.test.sh`: add `result=arm_refused reason=plaintext_dev_unrecorded` to the
  `_deadman_row` census.

## 2. Core implementation (`apps/web-platform/infra/workspaces-cutover.sh`)

- [ ] 2.1 Remove `PLAINTEXT_LABEL` and `_plaintext_label_present`. Add:
  - the pure `_plaintext_dev_valid`;
  - the `_plaintext_blkid_bin` seam (a fixed path list, never `command -v`);
  - the `_plaintext_dev_type` seam (`-b` guard, `blkid_unavailable`, a rationale comment and a
    keep-in-sync comment).
- [ ] 2.2 `_plaintext_gone`:
  - [ ] initialise `PLAINTEXT_GONE_WHY`, `PLAINTEXT_DEV_SEEN` and `PLAINTEXT_DEV_TYPE` first;
  - [ ] the physical arm reads as gone when the record is invalid, the `readlink -f` mapper equality
    holds (NOT `_same_dev`), or the type is not `ext4`;
  - [ ] use `why=plaintext_dev_gone`.
- [ ] 2.3 Neutral refusal wording, with `why=`, `recorded=` and `recorded_type=` passed through
  `_deadman_detail`, at three sites:
  - [ ] the `rollback()` log;
  - [ ] `_rollback_refuse`;
  - [ ] the ROLLBACK `die`.

  Append the same fields after the existing ones on the `cutover_aborted outcome=refused_plaintext_wiped`
  row.
- [ ] 2.4 `rollback()` remount mounts the record only if `_plaintext_dev_valid`.
- [ ] 2.5 `arm_dead_man`:
  - [ ] validation: `blkid_absent`, `record_invalid:`, `record_is_mapper:`, `record_not_ext4:`, then
    `arm_refused reason=plaintext_dev_unrecorded detail=`, `deadman_arm_failed` and die. Do not add a
    line starting `}` or a new dead-man-unit stop/reset-failed line (L7);
  - [ ] split `gone_guard` into a marker `if` (`why=marker`) and a physical `if` (`t=$(${blkid_bin} …)`
    giving `why=plaintext_dev_gone recorded= recorded_type=`), with a keep-in-sync comment;
  - [ ] the mount clause becomes `mount ${dev} ${MOUNT}`;
  - [ ] add `mount_source=${dev}` to the ok and remount_failed rows;
  - [ ] rewrite the comment.
- [ ] 2.6 W6 `first_wipe` binding:
  - [ ] `_plaintext_dev_valid` plus `readlink -f` equality with `$real`, else refuse
    `wipe_target_not_recorded_plaintext` with `target=`, `recorded=` and `recorded_real=`;
  - [ ] `label=` evidence becomes `none` when absent;
  - [ ] add `plaintext_dev=` to `rehearsal_ok`;
  - [ ] update the W7 comment.
- [ ] 2.7 `grep -c workspaces_plain workspaces-cutover.sh` → 0.

## 3. Docs

- [ ] 3.1 Runbook:
  - [ ] the step 7b expected row (no hardcoded `/dev/sdb`), plus the reboot note and the
    `plaintext_only` note;
  - [ ] the new verdict row;
  - [ ] rewrite the `wipe_deadman_armed` row;
  - [ ] the "no rollback" paragraph and both `refused_plaintext_wiped` rows (`why=` / `recorded_type=`
    reading guide);
  - [ ] the W9 sentence;
  - [ ] the `arm_refused` `detail=` values.
- [ ] 3.2 ADR-119 addendum: two sentence swaps.
- [ ] 3.3 Destruction record: rename the field. The value stays `(fill …)`.

## 4. Verification

- [ ] 4.1 Run the wipe suite (unprivileged), the freeze suite, `luks-monitor.test.sh` and the loopback
  suite (sudo). Raise the floors (143, 170) to the measured counts.
- [ ] 4.2 Mutation battery:
  - [ ] the pristine tree passes first;
  - [ ] apply Guard 1 M1–M7 and Guard 2 M1–M10, each inside its named function (check the hunk
    range);
  - [ ] only rc=1 counts as caught;
  - [ ] put the table in the PR body.
- [ ] 4.3 Check every census and grep AC, including the comment-stripped counts. Run `shellcheck`,
  `bash -n`, and `sh -n` on the captured fire.
- [ ] 4.4 Check `git diff --name-only origin/main...HEAD` for `.tf`, workflow or cloud-init files. The
  count must be 0.

## 5. Post-merge

- [ ] 5.1 Dispatch the read-only rehearsal and arm a watch. Expect `rehearsal_ok`, `label=none`, and a
  `plaintext_dev` that resolves to `target`. Record `plaintext_only=`. Drift means halt per the
  runbook.
- [ ] 5.2 The destructive dispatch needs a separate per-command go-ahead. It is not part of this PR.

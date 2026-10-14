# Tasks — fix(infra): bind the plaintext wipe and Guard 5 to the recorded plaintext device

Plan: `knowledge-base/project/plans/2026-09-30-fix-wipe-plaintext-identity-binding-plan.md`.
Deepened 2026-09-30. Refs #6604 #6588; do not close either.

## 1. Setup / RED

- [x] 1.1 Harness (`workspaces-luks-harness.sh`), inside the `bash -c` body with no apostrophes:
  - [x] the `_plaintext_dev_type` seam records its argument and prints `${PLAINTEXT_DEV_FSTYPE-ext4}`.
    The knob is named `PLAINTEXT_DEV_FSTYPE`, NOT `PLAINTEXT_DEV_TYPE`;
  - [x] the `_plaintext_blkid_bin` seam honours `BLKID_ABSENT` and `BLKID_BIN_PATH`;
  - [x] after `source`, run `[ "${PLAINTEXT_DEV_UNSEEDED:-}" = 1 ] || persist_state PLAINTEXT_DEV /dev/sdz9`;
  - [x] update the knob documentation.
- [x] 1.2 Wipe suite stub world:
  - [x] delete the dead `_plaintext_label_present` override;
  - [x] `blkid` `LABEL` defaults to empty with rc 0;
  - [x] `dumpe2fs` prints `<none>`;
  - [x] the default seed gains `PLAINTEXT_DEV=$TGT_BLK`;
  - [x] the happy-path field list becomes `label=none plaintext_dev=$TGT_BLK`.
- [x] 1.3 G1 rows, all built with `PRE_INV` where they need `$W_CASE_DIR`: P1 (`W_LABEL=`), P2
  (alias), H2 (`W_LABEL=other`), R1, R2 (letter drift), R3 (last wins), R4 (`-o`) and H3 (`re_zero`
  with a wrong record). Refusals assert their evidence fields, no BEGUN, and `hdrs_gone`.
  - [x] Confirm G1-P1 is RED with `wipe_target_label_mismatch`.
- [x] 1.4 The W-row (writer→reader) and the G5b rows H1 (seam argument), R1, D, B, U, M and V, plus
  G5c.
  - [x] Confirm G5b-H1's seam assertion is RED.
- [x] 1.5 G5d:
  - [x] `g5d_arm <record>` rebinds `G5D_FIRE` and `G5D_STATE`;
  - [x] the `G5D_BIN/blkid` stub checks its argv (`G5D_EXPECT_DEV`, exit 64 otherwise);
  - [x] the `findmnt` stub checks its argv;
  - [x] replace the instrument guard;
  - [x] add rows R1, R2, D, H2 and H1;
  - [x] delete the old "markerless, label gone" row;
  - [x] rename the "label" titles.
  - [x] Confirm H2 is RED.
- [x] 1.6 Arm rows A1–A6 (T33 shape, `DRY_RUN=0`), each with its expected `detail=`.
  - [x] Confirm A1 arms today.
- [x] 1.7 Freeze T5/T35/T42b assert `^mount /dev/sdz9[[:space:]]`.
- [x] 1.8 Loopback:
  - [x] `new_plain` formats unlabelled;
  - [x] `seed_state` appends `PLAINTEXT_DEV=$WP_DEV` before `$1`;
  - [x] the LW1a assertion becomes `'^PLAINTEXT_WIPE(_BEGUN|D)='`;
  - [x] add LW-P1..LW-P4 (`seed_state` before each; echo `why=`; place them before `new_plain lw4`).

    The suite never arms, so no arm seeding is needed.
- [x] 1.9 `luks-monitor.test.sh`: add `result=arm_refused reason=plaintext_dev_unrecorded` to the
  `_deadman_row` census.

## 2. Core implementation (`apps/web-platform/infra/workspaces-cutover.sh`)

- [x] 2.1 Remove `PLAINTEXT_LABEL` and `_plaintext_label_present`. Add:
  - the pure `_plaintext_dev_valid`;
  - the `_plaintext_blkid_bin` seam (a fixed path list, never `command -v`);
  - the `_plaintext_dev_type` seam (`-b` guard, `blkid_unavailable`, a rationale comment and a
    keep-in-sync comment).
- [x] 2.2 `_plaintext_gone`:
  - [x] initialise `PLAINTEXT_GONE_WHY`, `PLAINTEXT_DEV_SEEN` and `PLAINTEXT_DEV_TYPE` first;
  - [x] the physical arm reads as gone when the record is invalid, the `readlink -f` mapper equality
    holds (NOT `_same_dev`), or the type is not `ext4`;
  - [x] use `why=plaintext_dev_gone`.
- [x] 2.3 Neutral refusal wording, with `why=`, `recorded=` and `recorded_type=` passed through
  `_deadman_detail`, at three sites:
  - [x] the `rollback()` log;
  - [x] `_rollback_refuse`;
  - [x] the ROLLBACK `die`.

  Append the same fields after the existing ones on the `cutover_aborted outcome=refused_plaintext_wiped`
  row.
- [x] 2.4 `rollback()` remount mounts the record only if `_plaintext_dev_valid`.
- [x] 2.5 `arm_dead_man`:
  - [x] validation: `blkid_absent`, `record_invalid:`, `record_is_mapper:`, `record_not_ext4:`, then
    `arm_refused reason=plaintext_dev_unrecorded detail=`, `deadman_arm_failed` and die. Do not add a
    line starting `}` or a new dead-man-unit stop/reset-failed line (L7);
  - [x] split `gone_guard` into a marker `if` (`why=marker`) and a physical `if` (`t=$(${blkid_bin} …)`
    giving `why=plaintext_dev_gone recorded= recorded_type=`), with a keep-in-sync comment;
  - [x] the mount clause becomes `mount ${dev} ${MOUNT}`;
  - [x] add `mount_source=${dev}` to the ok and remount_failed rows;
  - [x] rewrite the comment.
- [x] 2.6 W6 `first_wipe` binding:
  - [x] `_plaintext_dev_valid` plus `readlink -f` equality with `$real`, else refuse
    `wipe_target_not_recorded_plaintext` with `target=`, `recorded=` and `recorded_real=`;
  - [x] `label=` evidence becomes `none` when absent;
  - [x] add `plaintext_dev=` to `rehearsal_ok`;
  - [x] update the W7 comment.
- [x] 2.7 `grep -c workspaces_plain workspaces-cutover.sh` → 0.

## 3. Docs

- [x] 3.1 Runbook:
  - [x] the step 7b expected row (no hardcoded `/dev/sdb`), plus the reboot note and the
    `plaintext_only` note;
  - [x] the new verdict row;
  - [x] rewrite the `wipe_deadman_armed` row;
  - [x] the "no rollback" paragraph and both `refused_plaintext_wiped` rows (`why=` / `recorded_type=`
    reading guide);
  - [x] the W9 sentence;
  - [x] the `arm_refused` `detail=` values.
- [x] 3.2 ADR-119 addendum: two sentence swaps.
- [x] 3.3 Destruction record: rename the field. The value stays `(fill …)`.

## 4. Verification

- [ ] 4.1 Run the wipe suite (unprivileged), the freeze suite, `luks-monitor.test.sh` and the loopback
  suite (sudo). Raise the floors (143, 170) to the measured counts.
  (Stubbed suites run green and floors raised to 160 / 176; the loopback suite needs root + loop +
  dm-crypt and runs only in CI — edited and checked with `bash -n` + `shellcheck` only, so this stays
  open until the CI `deploy-script-tests-fixed` loopback leg is green.)
- [x] 4.2 Mutation battery (23 mutants incl. two harness rows, every one rc=1 with its named row RED; G1-M2 is
  caught by the added G1-R5, not G1-R4 — see the hand-off):
  - [x] the pristine tree passes first;
  - [x] apply Guard 1 M1–M7 and Guard 2 M1–M10, each inside its named function (check the hunk
    range);
  - [x] only rc=1 counts as caught;
  - [ ] put the table in the PR body. (The table is in the implementer's hand-off; the PR is written at ship.)
- [x] 4.3 Check every census and grep AC, including the comment-stripped counts. Run `shellcheck`,
  `bash -n`, and `sh -n` on the captured fire.
- [x] 4.4 Check `git diff --name-only origin/main...HEAD` for `.tf`, workflow or cloud-init files. The
  count must be 0.

## 5. Post-merge

- [ ] 5.1 Dispatch the read-only rehearsal and arm a watch. Expect `rehearsal_ok`, `label=none`, and a
  `plaintext_dev` that resolves to `target`. Record `plaintext_only=`. Drift means halt per the
  runbook.
- [ ] 5.2 The destructive dispatch needs a separate per-command go-ahead. It is not part of this PR.

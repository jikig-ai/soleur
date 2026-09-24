---
title: "Tasks — git-data plaintext count through a dm snapshot (dirty-journal forward fix)"
branch: feat-one-shot-git-data-dirty-journal-dm-snapshot
plan: knowledge-base/project/plans/2026-09-24-fix-git-data-plaintext-dirty-journal-dm-snapshot-plan.md
lane: cross-domain
---

# Tasks

Derived from the finalized (post-review) plan. The plan is the source of truth; ACs live there.
No task below authorises a production dispatch — G1-G4 each stop for the operator's go-ahead.

## 0. Prove the mechanism (first commit)

- 0.1 Write `apps/web-platform/infra/git-data-plaintext-snapshot-loopback.test.sh` with only the
  negative control (ro origin refuses a direct `mount -o ro`) and arm B (dirty-empty through a
  snapshot over a `--setro` origin).
- 0.2 Register it as `sudo bash …` in `.github/workflows/infra-validation.yml`, and add its exemption
  entry to `.github/scripts/test/test-infra-suite-registration.sh`.
- 0.3 Push, then read the `infra-validation.yml` result (AC0). If it fails, stop at the Phase 0
  decision point.

## 1. Tests first (RED)

- 1.1 Stub harness `git-data-bootstrap-store-verify.test.sh`:
  - 1.1.1 New stubs: blockdev, dmsetup, losetup, cryptsetup, udevadm, and per-device dumpe2fs.
  - 1.1.2 Rewrite S6/R1 to the pinned mount options and snapshot source. Change R4 into R4a/R4b/R4c.
  - 1.1.3 New rows: `source` (isLuks), `snapshot` (setro, getro, geometry, losetup, create, Invalid),
    and `umount` (the teardown steps).
  - 1.1.4 An order row (isLuks < setro < create < mount), and a teardown-order row that also runs
    on partial failure.
  - 1.1.5 Guard 1 mutation self-tests, then re-derive `MIN_ASSERTIONS`.
- 1.2 Complete the loopback suite:
  - 1.2.1 Arms A, C (with the `debugfs -c` precondition) and D.
  - 1.2.2 Every arm runs in a child bash. Each checks the sha256, `--getro`=1, and that nothing
    leaks.
  - 1.2.3 Add the inner `plaintext-count` sentinels, spanning `_repo_count`.
  - 1.2.4 Satisfy the orphan-suite and census lints.
- 1.3 Write `tests/scripts/test-git-data-rung2-plan-shape.sh` (Guard 3 matrix, `additive`/`host-only`).
- 1.4 Extend `tests/scripts/test-git-data-rung2-evidence-capture.sh` with the Guard 2 rows, the
  `RUNG2_REPLACE_BOOT` append, and `RUNG2_REPLACE_SINCE`.
- 1.5 Field sweep: add `plaintext_journal` to `git-data-emit.test.sh`,
  `test-git-data-boot-signal-poll.sh` and the store-verify trailer.
- 1.6 Run every suite and confirm each is RED for the right reason.

## 2. Bootstrap (GREEN)

- 2.1 Replace the `_pt_id` block in `apps/web-platform/infra/git-data-bootstrap.sh`:
  - the isLuks refusal, then `--setro` with its read-back;
  - the origin journal state, and the COW size from the journal geometry;
  - `mktemp -d -p /dev/shm`, then losetup;
  - `_pt_sz`, then `dmsetup create`;
  - a mount with no noload, using `errors=remount-ro`;
  - the SOURCE equality check, the post-replay check, the count, and the `Invalid` check.
- 2.2 Make `_pt_release` idempotent and collect-then-exit: `trap - EXIT` first, flags cleared on
  success, and `udevadm settle || true`.
- 2.3 Add `plaintext_journal` to `boot_complete`. Update the §7b and header comments.
- 2.4 Add `dmsetup` to `packages:` in `apps/web-platform/infra/cloud-init-git-data.yml`. Confirm no
  new env seam is needed; if one is, update the `env -u` list and census C2.
- 2.5 Re-measure with `git-data-userdata-budget.sh` and record the byte figure.

## 3. Rung-2 rehearsal

- 3.1 Add `rehearsal_phase` to `rung2-rehearsal/variables.tf` (no default). Make `user_data` in
  `rehearsal.tf` conditional.
- 3.2 Write `rung2-rehearsal/seed-dirty-journal.sh`: rw mount, writes, `sync -f`, then `sysrq o`.
  Emit `stage=seed_*` rows, and escape it for `templatefile`.
- 3.3 Write `scripts/git-data-rung2-plan-shape.sh` and replace the inline jq guard.
- 3.4 Rework the workflow `git-data-rung2-rehearsal.yml`:
  - 3.4.1 Sequence: seed apply, off-poll, payload apply, capture #1, then the reboot arm.
  - 3.4.2 Replace arm: `-replace` of the server and `tls_private_key`, then capture #2 with
    `RUNG2_REPLACE_SINCE`.
  - 3.4.3 Distinct step ids.
  - 3.4.4 Move the evidence upload after capture #2, with the `replace_rc` condition.
  - 3.4.5 Recompute the time budget in the header. Put teardown in a separate `if: always()` job.
- 3.5 Evidence capture: select `plaintext_volume`/`plaintext_journal`, make PASS require
  `present`+`dirty`, and add the replace-arm invocation.
- 3.6 Add `plaintext_journal` to the informational list in `git-data-birth-emitter-6982.sh`.
- 3.7 `git-data-rung2-rehearsal.test.sh`: new user_data/seed rows and a budget check summed over
  every step bound.

## 4. Records

- 4.1 ADR-239: add the dated amendment, strike through the dirty-journal-gap consequence, and add
  alternatives I-M.
- 4.2 ADR-149: add a dated pointer line.
- 4.3 Runbook `git-data-luks-cutover-5274.md`: the reason words, the 2026-09-24 note, the G1-G4
  sequence, GO and the #8710 precondition.
- 4.4 Runbook `git-data-rung2-rehearsal.md`: the three-phase run, the failure table, the 2-run cap
  and the budget.
- 4.5 `model.c4`: correct the `gitDataStore` description.
- 4.6 `preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES`, with its entry.

## 5. Verify and ship

- 5.1 Run every suite named in plan Phase 5, plus the lints (guard contract, infra human steps,
  guard-vacuity-floor, c4 tests).
- 5.2 Re-derive floors, baselines and byte budgets against `origin/main`. Resolve `PROMOTED_FILES` as
  a union.
- 5.3 Merge gate: every required context present and `success` by name on the head SHA (counted).
  The PR body's first line: "merging alone does not mutate production".
- 5.4 STOP before G1 for the operator's go-ahead.

## Operator-gated sequence (each stops the pipeline)

- G1: rung-2 rehearsal, then the evidence-only PR. Hold merges that void the hash.
- #8710: separate PR, started now, merged before G2.
- G2: the `plan_only` replace; "clean" is as defined in the plan.
- G3: the real replace, one attempt.
- G4: the strict dry run, then GO. Sweep and re-drive the Art. 17 refusals by 2026-10-24.

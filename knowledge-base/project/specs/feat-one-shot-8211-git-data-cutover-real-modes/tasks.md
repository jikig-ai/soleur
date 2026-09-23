# Tasks: feat-one-shot-8211-git-data-cutover-real-modes (PR1, the hash-bound payload)

Plan: `knowledge-base/project/plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md`

## 1. Setup

- 1.1 Comment on #5914: hold ADR-237 post-merge step 2 (the #8511 rung-2 rehearsal) until PR1
  merges, so one rehearsal covers both payloads.
- 1.2 Re-probe PR #8563 (#8209). Record its file list, and stay out of it.
- 1.3 Re-probe ADR-239 across `origin/*` refs.
- 1.4 Enumerate the suites that pin the old layout:
  `git grep -ln 'scsi-0HC_Volume_\|git-data-luks\|GIT_DATA_BOOT_TERMINAL' -- tests/ scripts/ apps/web-platform/infra/ plugins/soleur/test/`.

## 2. Tests first (RED)

- 2.1 Script suites (provision, remove, transport, gc):
  - 2.1.1 Thread the `GIT_DATA_STORE_DEVICE` and `GIT_DATA_STORE_VERIFIED` seams through the
    `env -i` helpers.
  - 2.1.2 Add the rows: match, mismatch, prefix look-alike, marker absent, `findmnt` missing, and
    the order row.
- 2.2 `git-data-store-device-census.test.sh` (Guard 1):
  - 2.2.1 Derive the set from `main.tf`, with the bootstrap and pre-receive-placeholder exemptions.
  - 2.2.2 Add the floor plus set identity.
  - 2.2.3 Add the sshd row.
  - 2.2.4 Encode each mutation row as a self-test.
  - 2.2.5 Register the suite in `scripts/test-all.sh`.
- 2.3 Bootstrap suite (Guard 2): plaintext verified, absent, mount-failed, and non-empty or partial;
  `fence_on_mapper`; the probe against passing, refusing and env-leak stubs; the marker ordering;
  the lock dotfile invisible to the counts.
- 2.4 Evidence capture and boot poll: the new booleans are required, and the reboot arm `target`
  must be `/mnt/git-data`.
- 2.5 Render suites: the new layout, and the budget for both render branches.
- 2.6 `git-data-luks-reopen.test.sh`: only the `/mnt/git-data` target is accepted.

## 3. Core implementation (GREEN)

- 3.1 `cloud-init-git-data.yml`: remove the plaintext mount and fstab line; mount the mapper at
  `/mnt/git-data`; fix the comments.
- 3.2 `git-data-bootstrap.sh`: merge §1 and §1b, then add steps 1-6 (the plaintext temp-mount
  check, the fence on the mapper, the marker, the `env -i` probe, the binary booleans and the
  informational fields).
- 3.3 `git-data-luks-reopen.sh`: narrow the target.
- 3.4 The four store-acting scripts: the mapper assertion plus the marker; fix the comments.
- 3.5 Update the consumers: `git-data-rung2-evidence-capture.sh` (booleans and `target` in
  `HOST_SQL`), `git-data-boot-signal-poll.sh`, `git-data-birth-emitter-6982.sh`, and the
  `git-data-emit.test.sh` roster.
- 3.6 `git-data.tf`: `automount = false`. Verify the plan shows no change with the local TF triplet;
  if it does not, drop the edit.
- 3.7 `git-data-userdata-budget.sh`: re-measure.
- 3.8 `git-data-cutover.sh`: header text only.

## 4. Docs and records

- 4.1 ADR-239 via `soleur:architecture`. Amend ADR-068 D10, and ADR-220 D6 with "pending PR2".
- 4.2 `model.c4` `gitDataStore` AT REST. Regenerate `model.likec4.json`. Run the c4 tests.
- 4.3 Article 30: the PA-36 (g)(2) addendum, and the mechanism Superseded markers on PA-36 (g)(1),
  PA-1 (g)(13) and PA-2 (g)(17).
- 4.4 Runbooks:
  - 4.4.1 the #8511 hold;
  - 4.4.2 the pre-replace reads, quoting the exact precheck line;
  - 4.4.3 the verdict-map rows;
  - 4.4.4 the failed-replace recovery;
  - 4.4.5 the rung-2 note.
- 4.5 `scripts/encryption-posture-ledger.json`, if its git-data entry names the repoint.
- 4.6 Archive `knowledge-base/project/specs/feat-one-shot-7226-5914-host-key-pinning/` via
  `soleur:archive-kb`.
- 4.7 A compound pass on PR #8511's ship-phase errors: fixes not re-checked against earlier CI
  failures; the shallow repo at 12:48 (#7924, PR #8510); the deploy-arm `head_sha` (`deploy-arm.sh`).

## 4b. Deepen-plan revisions (binding; see the plan's "Deepen-Plan Revisions")

- 4b.1 The probe runs as `env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 runuser -u git -- …`,
  with `env -i` BEFORE `runuser`. Add the static order row.
- 4b.2 Make `luks_residue` (`served_repos>0`) FATAL. `needs_recovery` counts as
  `plaintext_unverified reason=journal`.
- 4b.3 The marker holds the mapper's filesystem UUID, and the scripts compare it with
  `findmnt -n -o UUID`. Create the directory with `install -d`, write the marker atomically, and
  make the bootstrap its only writer.
- 4b.4 The temporary mount goes under `$(mktemp -d)/mnt` with `ro,noload,nosuid,nodev,noexec`. A
  trap unmounts it, and a failed `umount` is FATAL.
- 4b.5 Every new failure goes through `log "FATAL: …"` (`stage=bootstrap`). gc refuses with exit 1.
- 4b.6 The `sshd -T` stage enforces `acceptenv` and `permituserenvironment`. Add `no-user-rc`, and
  `env -u` the seams in `git-data-gc.service`.
- 4b.7 Test harness:
  - 4b.7.1 the extraction seam, and the stubs for `mount`, `umount` and `runuser`;
  - 4b.7.2 the bootstrap seams, the remove contract row, and look-alikes derived from the real
    SOURCE;
  - 4b.7.3 the required set derived from `boot_complete`;
  - 4b.7.4 a `git-data-replication.test.ts` row: exit 1 maps to `refused`.
- 4b.8 Runbook:
  - 4b.8.1 the unconditional pin-redeploy dispatch after a failed step-3 replace;
  - 4b.8.2 recovery starts with a Sentry or Better Stack read;
  - 4b.8.3 the refused-id sweep and re-drive after the forward fix.
- 4b.9 ADR-239 and the PA-36 addendum say that `erased` means unlinked (blocks stay readable to a
  holder of the LUKS key until rotation).

## 5. Verification and ship

- 5.1 Run the full affected battery, then `scripts/test-all.sh`.
- 5.2 PR body:
  - 5.2.1 opens with "Merging this alone does not change production";
  - 5.2.2 `Ref #8211`, `Ref #8101` and `Ref #8549`;
  - 5.2.3 names #8571, #8572 and #8573;
  - 5.2.4 notes the stale `apply-web-platform-infra.yml:4338` summary;
  - 5.2.5 renders the decision challenges.
- 5.3 Admin-merge only when every required check is present and green on the exact head SHA
  (`--match-head-commit`), and only after asking the operator.

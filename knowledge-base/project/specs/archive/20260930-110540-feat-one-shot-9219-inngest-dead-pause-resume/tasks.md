# Tasks: remove dead inngest pause/resume calls (#9219)

Plan: `knowledge-base/project/plans/2026-09-30-fix-inngest-bootstrap-dead-pause-resume-plan.md`

## Phase 1: Setup

- [x] 1.1 Re-read the upgrade-detection block, resume block and comment anchors in
  `apps/web-platform/infra/inngest-bootstrap.sh`. Use content anchors, not line numbers.
- [x] 1.2 Record the baseline: run `bash apps/web-platform/infra/inngest.test.sh` and
  `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (both green on main).

## Phase 2: Core Implementation

- [x] 2.1 Test first (RED): in `apps/web-platform/infra/inngest.test.sh`, replace the "upgrade-drain resume
  command still present" assertion with the #9219 verb-allowlist guard (subset plus a
  `start` floor, with the found and unmeasured verbs printed in the description). Run the suite. The guard must be RED
  on the unedited bootstrap (`pause` and `resume` unmeasured).
- [x] 2.2 `inngest-bootstrap.sh`: delete the `"$INSTALL_PATH" pause … || log warn` line. Keep
  `sleep "$DRAIN_SLEEP_SEC"`, drop its inline "drain to SQLite" comment, and reword the log line
  to `…; ${DRAIN_SLEEP_SEC}s settle delay before binary replace`.
- [x] 2.3 `inngest-bootstrap.sh`: delete the `sleep 2` and the `"$INSTALL_PATH" resume … || log warn`
  line. Keep the `UPGRADE_FROM` branch with the `upgrade complete` log.
- [x] 2.4 `inngest-bootstrap.sh` comment sweep. Cover every anchor listed in the plan's Proposed
  Solution §1:
  - the header contract
  - the `DRAIN_SLEEP_SEC` comment
  - the upgrade-block comment, shrunk to two lines with `not a drain` on one physical line
  - "upgrade-drain stay inside"
  - the ExecStart comment clause
  - the restart comment
  - the resume-block comment

  Leave the Postgres idle-drain prose alone. Add no systemd start/restart line.
- [x] 2.5 GREEN: re-run `inngest.test.sh`, which should be all green. Then run mutation rows 1–6
  by hand:
  - copy all of `apps/web-platform/infra/` to scratch
  - run the unmutated copy first; it must exit 0
  - mutate the copy's bootstrap and read the verdict from the guard's own PASS/FAIL line
  - expected: rows 1, 2, 3, 5 and 6 FAIL; row 4 PASS
- [x] 2.6 `apps/web-platform/infra/inngest-cli.provenance.md`: amend the "`inngest pause` drain
  verb" verdict tail to say the calls were removed and the path is a settle delay with no drain
  (#9219). Keep the measurement.
- [x] 2.7 `knowledge-base/engineering/operations/runbooks/inngest-server.md`: replace "pauses →
  drains → restarts → resumes (~5s downtime on loopback)" with the settle delay → binary replace
  → restart sequence.

## Phase 3: Testing

- [x] 3.1 Run the AC1–AC4 and AC8 grep checks from the plan and confirm the expected outputs.
- [x] 3.2 Run the ratchets:
  - `bash apps/web-platform/infra/inngest.test.sh`
  - `bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`
  - `bash apps/web-platform/infra/inngest-cli-staleness.test.sh` and
    `bash apps/web-platform/infra/inngest-cli-staleness-mutation.test.sh`
  - `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`. The only permitted FAIL
    is Guard A naming `inngest-bootstrap.sh`.
- [x] 3.3 Run `bash -n` and `shellcheck` on `inngest-bootstrap.sh` and `inngest.test.sh`. Then
  run `bash scripts/lint-shell-capture-exit.test.sh` and
  `bash plugins/soleur/test/fixture-relative-assert.test.sh` (no baseline row change).
- [x] 3.4 AC5 diff-scope check: `git diff --name-only origin/main...HEAD`, plus the
  systemd start/restart grep, which must return nothing.
- [ ] 3.5 PR body. The first line says there is no host or Terraform mutation. The body also
  carries:
  - `Closes #9219`
  - the expected Guard A red
  - the automatic mint → bump chain
  - the mutation-row results
  - the note that success-path upgrade log lines are host-local only (no new signal)
- [ ] 3.6 Merge gate: every `CI Required` check is green. The only `deploy-script-tests` FAIL
  line is Guard A naming `inngest-bootstrap.sh`. Push no tags, dispatch nothing, apply nothing.

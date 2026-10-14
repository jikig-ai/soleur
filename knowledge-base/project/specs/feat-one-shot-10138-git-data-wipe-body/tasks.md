# Tasks: git-data wipe body (`mode=wipe` / `wipe_finish` / `wipe_check`)

Plan: `knowledge-base/project/plans/2026-10-14-feat-git-data-wipe-body-plan.md`
Issue: #10138 (Ref, not Closes). Also Ref #6897. Follow-ups already filed: #10296 (PR-R), #10297 (stamp clear), #10298 (retire the job), #10300 (single-name carrier).
Constraints: nothing is dispatched, applied or deleted; no legal document, no `AGENTS.rules.md`; never push to an armed/queued PR without asking. RED first in every phase; targeted suites only (machine load); CI is the gate.

## Layer 1 — read-only front (`wipe_check`), shippable alone

### Phase 0 — Re-read and baseline
- [ ] 0.1 Re-read live Hetzner state (servers, both volumes, `/volumes/<id>/actions`) read-only; pin stub shapes from the real read and the retired job `git show 3ed3e4e6da^:.github/workflows/workspaces-luks-cutover.yml`
- [ ] 0.2 Baseline pass counts of the pinned suites (access census, flag-precheck, tier census, argv-bearer sweep S3/S4, boot-signal-poll, dirty-scan, size, target-parity, fixture-relative-assert, lint-workflows)
- [ ] 0.3 Read the retired wipe job and `git-data-plaintext-snapshot-loopback.test.sh`
- [ ] 0.4 Measure loader step durations over the last 30 apply runs (`gh run view --json jobs`) to size the epoch bounds
- [ ] 0.5 Post the V-13 retention measurement on #6897 (counts, commands, 2027-01-09 horizon; no ids, no names)

### Phase 1 — Libraries and flag precheck
- [ ] 1.1 RED: flag-precheck rows (three predicates, pinned `WIPE_SOAK_FLOOR_SECONDS=604800`, env override ignored via sed-mutated copy in `assert_fixture_dir` tmp, `wipe:off` refuses, `wipe_reread` writes no pin)
- [ ] 1.2 `git-data-flag-precheck.sh`: `FLAG_MODE` `wipe|wipe_check|wipe_reread`, constant, predicates
- [ ] 1.3 RED then GREEN: `scripts/lib/git-data-wipe-runs.sh` (+ `.test.sh`): title classes incl. `wipe_other`, `wipe_last_rollback_epoch` (legacy-after-stamp refuses, no `gh run view`), `wipe_origin_run_ok`
- [ ] 1.4 `scripts/lib/git-data-boot-signal-poll.sh`: field-read query, strict freshness reuse, absent-row verdict (+ rows in `tests/scripts/test-git-data-boot-signal-poll.sh`)
- [ ] 1.5 Dirty-scan fixture row for a wipe-run jobs payload (`scripts/lib/git-data-store-dirty-scan.test.sh`)

### Phase 2 — Hetzner helper (read verbs first)
- [ ] 2.1 RED: `git-data-wipe.test.sh` stub-curl state machine rows (identity, state, actions, phases, no-fallback, id mismatches, no argv token, no stderr discard)
- [ ] 2.2 `git-data-wipe.sh`: `phases`, `state`, `identity --expect attached|detached`, `actions`, `record_check`; stdin token handoff; xtrace refusal; errexit-capture-safe `source`
- [ ] 2.3 Register the helper in the argv-bearer sweep S4 manifest and raise `S4_POP_FLOOR` / `S4_SCALLS_FLOOR` to the measured values

### Phase 3 — Host verb (checks only; listing port is Layer 2)
- [ ] 3.1 RED: shim rows for H1-H10 verdicts, `getro`, sectors, boot-time bind, timeout (rc 124)
- [ ] 3.2 `git-data-cutover.sh` `MODE=wipe_assert` (`pre|finish|post_detach`), `gd_capture` optional stdin-file + pinned timeout parameters, `git-data-wipe-assert.sh` checks, `layout_signal=not_run` in `wipe_check`, `reboot_since_row`, days-left output
- [ ] 3.3 Re-pin G2 exemption and G5 call-site count

### Phase 4 (Layer 1 part) — workflow front
- [ ] 4.1 `run-name`, `volume_id` input, `wipe_check` mode and token, `cutover`/`wipe` `if:` strings
- [ ] 4.2 `wipe` job steps W1-W7 + inline pinned Doppler install + teardown (`exec env -i`, `${NAME:-}` forms), `needs: [cutover, wipe]` notify clause (read-only wording), `phase`/`refusal`/`started` outputs
- [ ] 4.3 `git-data-wipe-access.test.sh` rows + cross-job pins in the old census; register suites in `infra-validation.yml`, regenerate shard manifest
- [ ] 4.4 Runbook `wipe_check` subsection; checkpoint commit "wipe_check W1 to W7 plus teardown, census green"

## Layer 2 — destructive path

### Phase 3 (Layer 2 part) — listing
- [ ] 3.4 RED then GREEN: loopback test (dirty-journal ext4, synthesized tenant names, image bytes unchanged, snapshot + loop gone, no name anywhere); also on the CI runner image
- [ ] 3.5 Port the plaintext-count unit into `git-data-wipe-assert.sh` (counts only, path-typed allowlist, teardown, counters re-check); `wipe_finish` runs the W10 mapper check

### Phase 2 (Layer 2 part) — destructive verbs
- [ ] 2.4 RED then GREEN: `detach` (record_check right before POST, 30-attempt poll, no re-POST), `delete`, `readback` (404 + empty name list + LUKS attached; absent-volume branch)

### Phase 4 (Layer 2 part) — workflow
- [ ] 4.5 `mode` choice gains `wipe`, `wipe_finish`; `origin_run` input; tokens; order pins move (first Layer-2 commit)
- [ ] 4.6 Steps W7b, loader (Tier-B input only), W9a (checks before marker), W9, W10, W10b (epoch re-stamp), W11a (60 s bound), W11, W12; `wipe_origin_check`; every post-loader step `exec env -i`
- [ ] 4.7 Notify words and `refusal` mapping; executed-body rows; marker kill-point stub rows; confirm outputs publish on failure and from a cancelled/timed-out step

### Phase 5 — Census completion
- [ ] 5.1 Credential rows (site counts derived, `HCLOUD_TOKEN` value-source only in W9/W11, loader once, `source == tier_b` before marker, first-statement `exec env -i`, Doppler pin literals equal the loader's, `uses:` set, no env printing, composite `runs.using`)
- [ ] 5.2 Order / time-bound / TOCTOU / emptiness rows; `wipe_check` and `wipe_finish` stub-log rows; doc-parity row; argv-bearer floors (read live)
- [ ] 5.3 `lint-guard-contract.py`, `lint-workflows.sh`, errexit-capture lint, grep -q pipe guard, shell-trace lint, fixture-relative-assert, workflow-file-size, terraform-target-parity, tier census

### Phase 6 — Wedge test
- [ ] 6.1 RED then GREEN: `tests/scripts/test-git-data-wipe-wedge.sh` (derived population; post-delete and detached-state fixtures); raise to the owner if a path cannot refuse

### Phase 7 — Documents
- [ ] 7.1 Runbook "The wipe" section (dispatch lines, never-Re-run note, preconditions, 2026-11-04 date, S1-S6, CTO precondition text, wedge cost, reboot dead-end, retention line, CLO wording, verdict-map rows)
- [ ] 7.2 `infra-credential-tiers-8209.md` `::wipe` row
- [ ] 7.3 ADR-241 amendment via `soleur:architecture` (first loader consumer in a mixed-tier workflow; wording per plan); References
- [ ] 7.4 C4 edge text edits (`github -> hetzner` new sentence, `github -> gitDataStore`, `github -> doppler`); c4-count-parity + syntax + render tests

### Phase 8 — Verification and hand-off
- [ ] 8.1 Targeted gate list green; collision probe 2 clean
- [ ] 8.2 PR body: `Ref #10138`, `Ref #6897`, Changelog, CPO sign-off line, "nothing dispatched", "NOT proven" block, follow-up issues
- [ ] 8.3 `soleur:engineering:review:user-impact-reviewer` at review; CLO reviews the actual strings before merge

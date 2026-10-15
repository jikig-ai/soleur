# Tasks: git-data wipe body (`mode=wipe` / `wipe_finish` / `wipe_check`)

Plan: `knowledge-base/project/plans/2026-10-14-feat-git-data-wipe-body-plan.md`
Issue: #10138 (Ref, not Closes). Also Ref #6897. Follow-ups already filed: #10296 (PR-R), #10297 (stamp clear), #10298 (retire the job), #10300 (single-name carrier).
Constraints: nothing is dispatched, applied or deleted; no legal document, no `AGENTS.rules.md`; never push to an armed/queued PR without asking. RED first in every phase; targeted suites only (machine load); CI is the gate.

## Layer 0 — Amendment A1 (2026-10-15): the separated wipe (plan Amendment A1; CTO and CLO rulings 2026-10-15)

Order: documents first (CLO needs them by 10-22), then RED rows, then code. Nothing here dispatches, applies, writes Doppler or touches a volume.

- [x] A.1 `soleur:architecture`: ADR-239 amendment (headed `Ruled by CLO agent, 2026-10-15; v1 internal attestation, provisional to 2026-10-24` and `Ruled by CTO agent, 2026-10-15`) stating the separated predicate set; supersede ONLY "gated by the flip chain" (2026-10-09), "bound to the flip chain" and the blocker chain (2026-10-12) with a `> **Superseded 2026-10-15 (#6897): ...**` marker under each; same marker in every sibling file repeating them (grep `gated by the flip chain`, `bound to the flip chain`, `blocker chain` across ADR-239, the design doc, the cutover runbook, both plans, decision-challenges.md, the ledger row). Effective on merge of this PR. [done 2026-10-15 (ADR-239 amendment + markers)]
- [x] A.2 `scripts/encryption-posture-ledger.json` row `hcloud_volume.git_data`: rewrite `defends_against`, `justification`, `reevaluate_when`, `live_verification` per plan A1.5, each sentence labelled measured (date) / policy / inherited; `expires_on` stays 2026-11-12; `git-data.tf:542` cite becomes a content anchor. Run `python3 scripts/lint-encryption-posture.py` and `scripts/lint-encryption-posture.test.sh`. [done (ledger row; lint PASS)]
- [x] A.3 ADR-241 amendment note gains the #8609 residual disclosure; owner acceptance on #6897 is an owner action named in the PR body (not performed by an agent). [done (ADR-241 note)]
- [x] A.4 `decision-challenges.md`: add rows for the 2026-10-15 CTO ruling (separability, replacement predicates, schedule) and CLO ruling (soak not a legal gate for the separated variant, evidence record, `wipe_check` listing, notice dates), plus a taste row for the A1.2 verdict-word names. [done (decision-challenges rows)]
- [x] A.5 Correct stale ids/counts where the plan states them (server 170370833, LUKS volume 107140231, 20 bound files); re-measure in 0.1 before pinning any stub. [done (ids re-measured 2026-10-15; 20 bound files)]
- [x] A.6 RED rows: Guard 6 rows 6a-6g (variant selection, unreadable flag, `store_dirty`, stale/populated `boot_complete`, newest-row-decides, W7b `variant_changed`) in `git-data-flag-precheck` and access-census suites; then build A1.2 in `git-data-flag-precheck.sh` (`wipe_variant=` first line; `store_clean` via `scripts/lib/git-data-store-dirty-scan.sh`, job gains `actions: read`). [done (precheck variants, 170/0)]
- [x] A.7 (partly: wipe_check runs the listing; lock_residue and store_root_repos added; the leftover-snapshot trap and refusal already existed) Host verb: `wipe_check` runs the counts-only listing (A1.3); add `lock_residue_n` (integer, strict-regex parse, no names); exit trap removes `git-data-pt-snap`; leftover-snapshot refusal verdict; RED rows Guard 9 (1-6). Phase 0 first confirms by code read that the verb reuses the bootstrap `plaintext-count unit` logic.
- [x] A.6b `scripts/lib/git-data-store-dirty-scan.sh`: skip `GITHUB_RUN_ID` only (a second in-progress run still refuses); new step `wipe_separated_gate` after W5 (scan + `boot_complete` predicates, only when the printed variant is `separated`); F and S read unconditionally; `wipe_reread` gains an S read; closed value check `^(true|false)?$` (`wipe_precondition_flag_unreadable`) and `wipe_precondition_stamp_malformed`. RED rows: Guard 6 6d (i)-(iv) with rollback-run and flip-with-failed-probe fixtures. Also: W7 `pre` host verb prints `store_root_repos=<n>` (integer; bootstrap `_repo_count` exclusions) and `wipe_separated_gate` refuses `wipe_separated_store_root_populated` when n != 0 (host is not told the variant); self-exclusion is attempt-aware (take the `queued` branch for the own id; earlier attempts of the own id still read). [done (scan self-exclusion; the scan runs in W3, no extra step; W7b expectation; store_root_repos in W7)]
- [x] A.7b [done: host verb phase=clear (exit 43 wipe_snapshot_not_ours, removal via wa_release so a failed step is the existing rc 36), mode=snapshot_clear in the workflow (own step, no loader, no provider write), run-title class, runbook section, tests C01-C16/B20-B25 and clear mutants] `snapshot_clear` as its OWN dispatch mode (CTO follow-up ruling 2026-10-15): single literal `dmsetup remove git-data-pt-snap`, typed volume id, deps-equals-typed-device, H7 fd check, pinned mount and loop only, absence confirmed; owner-named, reviewer-gated; never called from `wipe_check`. RED rows Guard 9 rows 7-13.
- [x] A.8 Evidence record (A1.4): W12 success summary and `wipe_check` closing block print the six labelled lines; test that no line says erased/purged/no residue about copies, the LUKS store or web-2. [done (W7 pre-state block, W12 run-record block; copies stay unmeasured)]
- [x] A.9 [done: variants, verdict words, snapshot_clear mode row, dispatch string, 'A leftover snapshot' section] Runbook: separated vs flip-chained variant, the leftover-snapshot recovery step (read-only first), the 11-02 command-naming ask, CLO notice dates (10-30, 11-02, 11-05; latest slip notice 11-06).
- [x] A.10 Do not edit any rung-2 bound file (20 today, e.g. no `variables.tf` edit); re-run `git_data_rung2_user_data_sha256` and compare to `RUNG2_TEMPLATE_SHA256` before pushing. [done (computed hash a6092398... equals RUNG2_TEMPLATE_SHA256; no bound file changed)]
- [ ] A.11 After the 2026-10-24 CLO re-ruling: re-attest the A1 wording; if the ruling changes, amend ADR-239 and the ledger row before merge.

## Layer 1 — read-only front (`wipe_check`), shippable alone

### Phase 0 — Re-read and baseline
- [ ] 0.1 Re-read live Hetzner state (servers, both volumes, `/volumes/<id>/actions`) read-only; pin stub shapes from the real read and the retired job `git show 3ed3e4e6da^:.github/workflows/workspaces-luks-cutover.yml`
- [ ] 0.2 Baseline pass counts of the pinned suites (access census, flag-precheck, tier census, argv-bearer sweep S3/S4, boot-signal-poll, dirty-scan, size, target-parity, fixture-relative-assert, lint-workflows)
- [ ] 0.3 Read the retired wipe job and `git-data-plaintext-snapshot-loopback.test.sh`
- [x] 0.4 Measure loader step durations over the last 30 apply runs (`gh run view --json jobs`) to size the epoch bounds: measured 2026-10-14 over 83 samples of recent apply/drift runs, the Tier-B loader step took 0 s x3, 1 s x73, 2 s x7, so the W7 bound sits on its 120 s floor (`WIPE_W7_BOUND_SECONDS=120` in `git-data-wipe.sh`)
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

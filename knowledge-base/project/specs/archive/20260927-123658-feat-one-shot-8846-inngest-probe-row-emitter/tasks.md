---
title: "Tasks — fix(inngest-health): select dedicated-host probe rows by emitter (#8846)"
branch: feat-one-shot-8846-inngest-probe-row-emitter
plan: knowledge-base/project/plans/2026-09-25-fix-inngest-probe-row-emitter-selection-plan.md
lane: cross-domain
---

# Tasks — #8846 probe-row emitter selection

Source of truth: the plan above. Commit with `LEFTHOOK_EXCLUDE=bun-test`. Do not run `scripts/test-all.sh --full` or `run-registered-suites.sh`.

## Phase 0 — Setup

- [ ] 0.1 Read PR #8831's file list live with `gh pr view 8831 --json files`. Confirm it has no file in common with this plan's Files to Edit/Create. Run `git merge-tree --write-tree HEAD <8831-head>` and confirm it is clean.
- [ ] 0.2 Re-measure the emitter values from Better Stack for the probe marker, `inngest-cutover-flip` and `inngest-luks-cutover`. Record the counts for the PR body.
- [ ] 0.3 Capture one redacted `doppler` row and one redacted probe row as the fixture shape model.

## Phase 1 — RED fixtures (tests-only commit)

- [ ] 1.1 `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh`:
  - Add `SYSLOG_IDENTIFIER` to each `R_*` literal.
  - Make `run_arm` return the step's exit code and `detail=`.
  - Make the stub log its argv.
  - Make `run_arm` `unset INNGEST_PROBE_ROW_LIB` and copy the lib into `$ws/scripts/lib/`, except when a case opts out.
  - Add the cases:
    - (a) quoting no fields;
    - (a) quoting not-serving fields;
    - (a) only;
    - web-1 then `R_OK` then (a);
    - `R_OK` alone, as a must-PASS that step exit is 0 (guards `JQ_RC`);
    - `--limit 500`;
    - lib absent with `R_OK`, which must exit non-zero and write `crash_reason`.
- [ ] 1.2 `scripts/followthroughs/inngest-host-not-serving-7674.test.sh`:
  - `row()` gets an emitter default.
  - Add the cases: (a) quoting a serving line, (a) only, and `INNGEST_PROBE_ROW_LIB=/nonexistent`.
- [ ] 1.3 `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh`:
  - Export `INNGEST_PROBE_ROW_LIB`, because the `FLIP_ROLLOUT_TEST_TARGET` seam runs copies of the script.
  - In the derive arm, add an (a) row quoting ` image_ref=<pinned> ` (whitespace on both sides). Expect `boundary_underivable`, assert that `boundary DERIVED from telemetry` does not appear, and pass the competing reasons.
  - Add a lib-missing case, expecting `row_decode_failed`.
- [ ] 1.4 `scripts/followthroughs/inngest-luks-property-8296.test.sh`:
  - `row()` gets an emitter default.
  - Add a (b) row newer than the real LUKS row. It carries `host_role=dedicated data_mount_src=/dev/sdb data_mount_devid=scsi-0HC_Volume_<n>` and dt `DT_NEWEST`. Expect `5 rollback_inversion` → `2 agree`.
  - `run_probe` copies the lib, with an opt-out flag. The lib-missing case expects exit 3 with `reason=selector_unavailable`.
- [ ] 1.5 `scripts/inngest-host-state.test.sh`:
  - The python `row()` gets an emitter argument.
  - Add (b): the serving `DEDICATED_MSG`, unchanged except for the `doppler` emitter, placed LAST. Expect the `SERVING=yes` → `SERVING=no` token.
  - The existing `rawBody` case passes `doppler` explicitly.
  - Add a lib-missing case, expecting rc 6.
- [ ] 1.6 `tests/scripts/test-inngest-host-dark-gate.sh`:
  - Add (b) serving after the graded-dark row, in both entry points.
  - Add (b) from web-1 only, expecting `silent`.
  - Execute gate: use its own `$EROWS` + `$HB` + `EBID` pair, and a (b) row whose dt falls strictly between 10:00 and `NOW` (no tie).
  - Add `SYSLOG_IDENTIFIER` to the two rows built outside `bs_line`: "outer-envelope host_name must not launder" and "[I2] EMBEDDED NEWLINE".
  - Lib missing (`/nonexistent`), with both entry points and `--followthrough-rc 2`: expect `unreadable`, rc 1, and the path on stderr.
  - Export `INNGEST_PROBE_ROW_LIB`, and add the canary for unmutated `$TMP` copies.
- [ ] 1.7 `apps/web-platform/infra/cutover-inngest-workflow.test.sh`:
  - `fix_row` takes a tag argument, and the fixture sets are split into flip and LUKS.
  - `FIX_REORDER` gets the emitter.
  - Add the `eventlog` and `eventlog+2cur` modes to both harnesses.
  - Add the empty-tag case.
- [ ] 1.8 Update every assertion floor to its measured count, with an itemized comment:
  - classify `EXPECTED_ASSERTIONS=104`
  - dark-gate `_FLOOR=282`
  - cutover `_EXACT_FLOOR=914`
  - 7674 `FLOOR=14`
  - 7761 `MIN_ASSERTIONS=307`
  - 8296 `MIN_PASSES=114`
  - host-state `_min_cases=25`
- [ ] 1.9 Run each suite and record the RED counts. A new case that is not RED is a fixture defect, except control, must-PASS and canary rows.

## Phase 2 — Shared lib

- [ ] 2.1 Create `scripts/lib/inngest-probe-row.sh`:
  - the emitter and marker variables;
  - `INNGEST_PROBE_ROW_JQ`, built from those variables;
  - `inngest_probe_row_selftest`;
  - an executed `--selftest` mode.
- [ ] 2.2 Create `scripts/lib/inngest-probe-row.test.sh`:
  - unit rows;
  - `--selftest` tests, including the tampered-copy check;
  - the Guard 1 census, with:
    - the single rule and the word boundary;
    - both source spellings;
    - the allowlist;
    - an injectable file list and root, so mutation rows use a temp fixture tree;
    - the per-reader count for `cutover-inngest.sh`.
  - the parity checks. The probe emitter binds to the `LOG_TAG=` nearest the `logger … SOLEUR_INNGEST_SERVER_PROBE` line, because the file has two `LOG_TAG`s.
  - the Guard 2 caller census and tag parity.
- [ ] 2.3 Add one `scripts/suite-shard-legs.tsv` row. Do not add a `run_suite` line; the glob already registers the suite.
- [ ] 2.4 Add `scripts/lib/inngest-probe-row.sh` to the pull_request `paths:` in `.github/workflows/infra-validation.yml`.

## Phase 3 — GREEN: probe consumers

- [ ] 3.1 `tests/scripts/lib/inngest-host-dark-gate.sh`:
  - source the lib with an override;
  - both entry points check the lib-missing flag first (before G1 and G18) and refuse `unreadable`, with the path on stderr and only the bare token on stdout;
  - add `_IHDG_PROBE`;
  - prefix the def to every program;
  - remove the `wrong_host_rows` inline copy.
- [ ] 3.2 `.github/workflows/scheduled-inngest-health.yml`, dedicated step:
  - source guard: write `crash_reason` to `$GITHUB_OUTPUT`, then `exit 1` on failure;
  - `--limit 500`;
  - set `JQ_RC=0`, then run the jq selection with its exit code captured (`crash_reason=jq_rc=<n>`);
  - `returned=<n>/500` in DETAIL;
  - a #8846 comment.
- [ ] 3.2b In the "Dedicated-host consumer crashed" step, add a `cause:` line to the issue body using `crash_reason`, passed through `env:`. In the "No live scheduler check" step, when the verdict is empty, the detail says `dedicated host NOT MEASURED — consumer failed`.
- [ ] 3.3 `scripts/followthroughs/inngest-host-not-serving-7674.sh`: add the def, drop `grep -F`, and add the `selector_unavailable` arm.
- [ ] 3.4 `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`: `mine_dt` selects with the def. A failure goes to `__DECODE_FAILED__`.
- [ ] 3.5 `scripts/followthroughs/inngest-luks-property-8296.sh`:
  - The def replaces `startswith($pm)`.
  - `source` goes after `trap on_exit EXIT`.
  - Add a dedicated `CANNOT ESTABLISH: reason=selector_unavailable` line, exit 3.
- [ ] 3.6 `scripts/inngest-host-state.sh`: export the lib variables into python, and check the emitter plus the marker followed by a space.
- [ ] 3.7 `scripts/followthroughs/inngest-luks-cutover-6894.sh` (retired): source the lib and use the def in `ON_MAPPER`. No harness.

## Phase 4 — GREEN: liveness counters

- [ ] 4.1 `scripts/cutover-inngest.sh`:
  - `_current_instance_row_counts` and `_generation_scoped_count` take a tag;
  - an empty tag gets its own warning on stderr plus `__UNREADABLE__` (the tag is argument 2 of the inner function and argument 3 of the outer one);
  - the flip and LUKS callers pass literal tags;
  - update the header comment.
- [ ] 4.2 Confirm the Phase 1.7 cases go GREEN.

## Phase 5 — Verification

- [ ] 5.1 Run `bash <suite>` standalone for each of the 7 suites and the new suite. All exit 0.
- [ ] 5.2 `shellcheck` on edited `.sh` files. `actionlint` on the two workflows.
- [ ] 5.3 `bash scripts/lib/inngest-probe-row.sh --selftest` prints `inngest-probe-row selftest: ok`.
- [ ] 5.4 Re-run the Phase 0.1 checks. Run `git diff --quiet origin/main...HEAD` on the untouched-file list (AC4).
- [ ] 5.5 Run `npx markdownlint-cli2` on the plan and on `tasks.md`.

## Post-merge (soleur:ship / postmerge, automated)

- [ ] 6.1 AC13: the push-triggered `apply-web-platform-infra.yml` run for the merge SHA concludes `success`.
- [ ] 6.2 AC14:
  1. Wait, with a Monitor bounded at 30 minutes, until the newest `soleur-inngest` row in the window is `doppler`.
  2. Run `gh workflow run scheduled-inngest-health.yml`.
  3. The log must show `-> healthy`, with `rows=` equal to the selector's count.
- [ ] 6.3 AC15: the open false pair closes. Then 2 ticks pass with no new pair (Monitor bounded at 90 minutes). If a new pair appears, reopen #8846.
- [ ] 6.4 AC16: post one evidence comment on each of #8833 and #8834. Do not reopen them.

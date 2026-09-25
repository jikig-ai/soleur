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
  - Add the cases: (a) quoting no fields, (a) quoting not-serving fields, (a) only, web-1 must-PASS, `--limit 500`, and lib absent.
- [ ] 1.2 `scripts/followthroughs/inngest-host-not-serving-7674.test.sh`:
  - `row()` gets an emitter default.
  - Add the cases: (a) quoting a serving line, (a) only, and `INNGEST_PROBE_ROW_LIB=/nonexistent`.
- [ ] 1.3 `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh`: in the derive arm, add an (a) row quoting `image_ref=<pinned>`.
- [ ] 1.4 `scripts/followthroughs/inngest-luks-property-8296.test.sh`:
  - `row()` gets an emitter default.
  - Add a (b) row that is newer than the real LUKS row.
- [ ] 1.5 `scripts/inngest-host-state.test.sh`:
  - The python `row()` gets an emitter argument.
  - Add a (b) serving row that is newer than the not-serving dedicated row.
- [ ] 1.6 `tests/scripts/test-inngest-host-dark-gate.sh`:
  - Add (b) serving after the graded-dark row, in both entry points.
  - Add (b) from web-1 only, expecting `silent`.
  - Export `INNGEST_PROBE_ROW_LIB`, and add the canary for unmutated `$TMP` copies.
- [ ] 1.7 `apps/web-platform/infra/cutover-inngest-workflow.test.sh`:
  - `fix_row` takes a tag argument, and the fixture sets are split into flip and LUKS.
  - `FIX_REORDER` gets the emitter.
  - Add the `eventlog` and `eventlog+2cur` modes to both harnesses.
  - Add the empty-tag case.
- [ ] 1.8 Run each suite. Record the RED counts. Any new case that is not RED is a fixture defect (except control, must-PASS and canary rows).

## Phase 2 — Shared lib

- [ ] 2.1 Create `scripts/lib/inngest-probe-row.sh`:
  - the emitter and marker variables;
  - `INNGEST_PROBE_ROW_JQ`, built from those variables;
  - `inngest_probe_row_selftest`;
  - an executed `--selftest` mode.
- [ ] 2.2 Create `scripts/lib/inngest-probe-row.test.sh`:
  - unit rows;
  - `--selftest` tests, including the tampered-copy check;
  - the Guard 1 census, with the single rule, the word boundary, both source spellings and the allowlist;
  - the parity checks;
  - the Guard 2 caller census and tag parity.
- [ ] 2.3 Add one `scripts/suite-shard-legs.tsv` row. Do not add a `run_suite` line; the glob already registers the suite.
- [ ] 2.4 Add `scripts/lib/inngest-probe-row.sh` to the pull_request `paths:` in `.github/workflows/infra-validation.yml`.

## Phase 3 — GREEN: probe consumers

- [ ] 3.1 `tests/scripts/lib/inngest-host-dark-gate.sh`:
  - source the lib with an override and an `unreadable` refusal that names the path;
  - add `_IHDG_PROBE`;
  - prefix the def to every program;
  - remove the `wrong_host_rows` inline copy.
- [ ] 3.2 `.github/workflows/scheduled-inngest-health.yml`, dedicated step:
  - source guard, with `exit 1` on failure;
  - `--limit 500`;
  - jq selection with the jq exit code captured;
  - `returned=<n>/500` in DETAIL;
  - a #8846 comment.
- [ ] 3.3 `scripts/followthroughs/inngest-host-not-serving-7674.sh`: add the def, drop `grep -F`, and add the `selector_unavailable` arm.
- [ ] 3.4 `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`: `mine_dt` selects with the def. A failure goes to `__DECODE_FAILED__`.
- [ ] 3.5 `scripts/followthroughs/inngest-luks-property-8296.sh`: the def replaces `startswith($pm)`. The test sandbox copies the lib.
- [ ] 3.6 `scripts/inngest-host-state.sh`: export the lib variables into python, and check the emitter plus the marker followed by a space.
- [ ] 3.7 `scripts/followthroughs/inngest-luks-cutover-6894.sh` (retired): source the lib and use the def in `ON_MAPPER`. No harness.

## Phase 4 — GREEN: liveness counters

- [ ] 4.1 `scripts/cutover-inngest.sh`:
  - `_current_instance_row_counts` and `_generation_scoped_count` take a tag;
  - an empty tag gets its own warning plus `__UNREADABLE__`;
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

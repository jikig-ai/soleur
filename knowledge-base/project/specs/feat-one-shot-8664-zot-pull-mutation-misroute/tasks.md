# Tasks: fix the zot-pull mutation battery's scheduling-dependent verdicts (#8664)

Plan: `knowledge-base/project/plans/2026-09-25-fix-zot-pull-mutation-harness-row-misroute-plan.md`

## Phase 1: Site A, the battery scorer (RED, then GREEN)

- [ ] 1.1 In `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`, extract the
  named-assertion check into `failed_on` **as-is** (still piped), and call it from `case_mutate`.
- [ ] 1.2 Add the scorer self-test directly after `failed_on`:
  - [ ] 1.2.1 Write the fixture `$WORK/scorer-selftest.log` with a single `awk 'BEGIN{…}'`. It holds a
    PASS line with `SELFTEST-ONLY-ON-PASS`, then a FAIL line with `SELFTEST-TARGET`, then about
    20,000 FAIL filler lines (≥1 MiB). Then pin the fixture's shape: line 2 must be exactly
    `^  FAIL: SELFTEST-TARGET` (`^` = line start), and the file must hold at least 20000 `^  FAIL: filler` lines.
    Either check failing is a `die`.
  - [ ] 1.2.2 `failed_on` must report found (0) for `SELFTEST-TARGET` and not found (1) for
    `SELFTEST-ONLY-ON-PASS`. Otherwise `die`, which exits 2.
- [ ] 1.3 RED: run the battery and confirm it aborts with exit 2 on the needle-first probe. Record the
  output (AC1a).
- [ ] 1.4 GREEN: switch `failed_on` to capture-and-glob. A grep rc ≥ 2 is a `die`. Keep the existing
  display re-grep for the MISROUTED list. Confirm the self-test passes.

## Phase 2: Site B, the guard's Guard 1b splitter (RED, then GREEN)

- [ ] 2.1 Add the must-PASS row `g1b-mustpass-padded-pull-item`. It inserts 2,400 non-comment
  `: pad-NNNNN …` lines after the exactly-once 4-space-indented
  `docker create --name soleur-inngest-bootstrap-extract "$IREF"` anchor.
- [ ] 2.2 Bump `BATTERY_MIN_ROWS` from 60 to 61 and add a history line. Keep the literal directly
  above its `if`.
- [ ] 2.3 RED: with the guard unfixed, the row reports BROKE (non-zero rc, no FAIL lines). Record the
  observed rc (AC1b).
- [ ] 2.4 GREEN: in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, drop the
  `sed -E '/^[[:space:]]*#/d' "$DED_BLOCK_FILE" |` stage, add `/^[[:space:]]*#/ { next }` as
  awk's first rule, and pass `"$DED_BLOCK_FILE"` as awk's file operand. The row must report HELD.
- [ ] 2.5 Rewrite the three `wf_block … | grep -qxF` asserts. First compute `WF_EMIT` and `WF_DSN`,
  then assert with an escaped herestring (`<<<\"\$WF_EMIT\"`). Never put a literal `$(wf_block …)`
  inside an eval'd condition string.
- [ ] 2.6 Widen the header rule to one sentence that covers any consumer able to stop before EOF, and
  cite #8664.

## Phase 3: Drift guard and baselines

- [ ] 3.1 Add both files to `.claude/hooks/grep-q-pipe-guard.test.sh`'s named-file,
  comment-stripped zero pass, and update its message.
- [ ] 3.2 AC4: the pattern count over the two files goes from 4 to 0. Reinserting `| grep -qF`
  into `failed_on` must turn the drift guard RED. Revert that edit.
- [ ] 3.3 Run `bash plugins/soleur/test/fixture-relative-assert.test.sh`. Regenerate the baseline
  only if the two suite rows moved.
- [ ] 3.4 Run `bash scripts/guard-vacuity-floor.test.sh`.

## Phase 4: Verification

- [ ] 4.1 AC2: the battery reaches 61/61 and `OK`, and the guard reaches
  `BOOTSTRAP_SUITE_OK unconditional=153 floor=153 total=230 rendered=ran`.
- [ ] 4.2 AC5: drive Guard 1 rows 1-3 and 5, and Guard 2 rows 1-2, as scratch edits, then revert. Quote one
  output line for each.
- [ ] 4.3 AC3 (non-gating): run one round of 10 concurrent batteries with a shared `TMPDIR`, and expect
  0 non-KILLED rows. Record `nproc` and the peak load average alongside the result.
- [ ] 4.4 AC7: run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`,
  confirm the diff touches no `.ts` file, and run shellcheck on the three touched `.sh` files.
- [ ] 4.5 AC8/AC9: run `lint-guard-contract.py` on the plan, and confirm the diff touches no file
  from #8763.

## Phase 5: Follow-through (ship)

- [ ] 5.1 File one tracking issue for the six sibling-battery scorer sites (decision-challenges #1).
- [ ] 5.2 Post a comment on #7005 about the ~4 KiB write-granularity refinement, and cross-link #7376.
- [ ] 5.3 In the PR body: `Closes #8664`, the misattributed-row reconciliation, and "no production
  effect on merge" as the first line.
- [ ] 5.4 Compound: capture the learning that the SIGPIPE floor for stdio-buffered producers is
  their write size (~4 KiB), not the 64 KiB pipe capacity. Also record that `grep MISROUTED`
  matches a passing line.

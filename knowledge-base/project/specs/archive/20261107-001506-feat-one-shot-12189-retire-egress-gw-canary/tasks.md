# Tasks: retire the egress-gw probe-silence canary alert pair (Ref #12189)

Plan: `knowledge-base/project/plans/2026-11-06-chore-retire-egress-gw-probe-silent-canary-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12189-retire-egress-gw-canary/decision-challenges.md`

## Phase 0: Baseline (read-only)

- 0.1 Record pre-change counts: ceiling suite (116 of 116), egress suite with `MUT_SKIP=1` (85 passed, floor 85) and a full run (85 + 78).
- 0.2 Freeze the retirement census by name and by identifier: `git grep -nE 'silent_canary|probe-silent-canary|egress-gw-probe-canary-absent'`.

## Phase 1: Terraform and guards (one atomic commit)

- 1.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: delete the canary local, the canary comment block and both canary resources; reword the two comment spots that call the canary live (keep the INFERRED label text).
- 1.2 `tests/scripts/test-infra-privileged-tier-census.sh`: append the two canary addresses to `INTENDED_DESTROYS` AFTER the four ghcr entries (M29 anchors on the first one).
- 1.3 `apps/web-platform/infra/betterstack-alert-structure.test.sh`: `CENSUS_FLOOR_ALERTS` and `CENSUS_FLOOR_EXPLORATIONS` 19 to 18; fix the header, floor and apply-parity comments (the latter says INTENDED_DESTROYS is empty of logtail addresses).
- 1.4 `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS` 19 to 18; `MIN_PASSES` only if the run prints a different, explained count.
- 1.5 `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: `== 19` to `== 18` and the NINETEEN comment.
- 1.6 `apps/web-platform/test/infra/egress-gw-alert.test.sh`:
  - 1.6.1 Delete the G2b block, the canary rows in the resource-header loop and every canary mutation row (including the four planted-identifier file-type rows) and the `CANRES`/`CANEXPL`/`CANLINE` constants.
  - 1.6.2 Keep `PROD_NAME` and `EMITTER_TAG` probe-literal pins; drop `CANARY_NAME`/`CANARY_RESOURCE` equalities.
  - 1.6.3 Exact-count row: 2 resources and 2 names; consumers of the production SQL local 2 to 1 (and the "third consumer" row re-worded); mute-knob row eight blocks to six.
  - 1.6.4 Remove dead emitter-scan plumbing (`INFRA`, `EGW_GUARD_INFRA`, `scan-empty`) if nothing else reads it; trim header prose about the canary.
  - 1.6.5 Re-derive `PRESENCE_ROWS` and `MUT_ROWS` from runs. No positional-rooted `mv` in any helper.
- 1.7 `.github/workflows/infra-validation.yml`: comment-only edit above the egress guard step.
- 1.8 Commit: `chore(infra): retire the egress-gw probe-silence canary alert pair (Ref #12189)`.

## Phase 2: Documents

- 2.1 `cron-egress-blocked.md`: retired-canary paragraph, decision table trimmed to reachable verdicts, retirement record replaces the "Deleting the canary" recipe, residuals A (vendor keeps the incident) and B (mirror closes only when the incident leaves the open list), citing the `canary=fired` comment.
- 2.2 `betterstack-log-query.md`: egress bullet in the past tense.
- 2.3 Probe header: one comment-only STATUS line inside the `# RETIREMENT:` block (sites 1, 3b, 4, 5, 6, 7 done; 2 and 3 pending #12270; 10 pending the apply; 8 deferred to #12271; 9 unchanged).
- 2.4 ADR-218: new dated amendment (end state) plus bracketed superseded pointers on the now-false sentences.
- 2.5 Commit the documents separately.

## Phase 3: Verification (local)

- 3.1 Run the touched suites and every suite naming `logtail_exploration` (derived with `git grep`).
- 3.2 Three scratch-copy runs against the real tree (Guard 1 row 1; Guard 2 rows 1 and 2); record outcomes for the PR body. Other rows are covered by the committed batteries.
- 3.3 `lint-guard-contract.py`, `lint-infra-no-human-steps.py` on changed docs, `c4-count-parity.test.sh`, the affected-suite runner (ratchets).
- 3.4 Probe test `egress-gw-probe-silent-12180.test.sh` (edited in this PR, CTO follow-up): replace the `ref_n -ge 6` row with an expected-referrer-set assertion equal to the measured survivors; re-pin `MIN_ASSERTIONS` from the printed total after checking the delta; commit message calls both derived-count flips and names #12270.

## Phase 4: Ship preparation (stop before merge)

- 4.1 Re-run the probe read-only; post its verdict line on #12189.
- 4.2 Reference #12270 and #12271 from the ADR amendment and the probe STATUS line (already filed).
- 4.3 Empty commit carrying `[ack-destroy]` on its own line; no other commit has that line.
- 4.4 Open the PR: first line says merging destroys two Better Stack resources; `Ref #12189`; no closing keyword; `closingIssuesReferences` empty.
- 4.5 Review, fix, CI green.
- 4.6 STOP: ask for an explicit per-command go-ahead naming the merge. No merge, auto-merge, apply, dispatch or push during the queue wait.

## Phase 5: After the go-ahead (agent-run, read-only)

- 5.1 Watch the push-apply: 2 destroyed, 0 added, 0 changed.
- 5.2 Read-only checks: canary alert gone, production alert intact, canary incident state.
- 5.3 Mirror issue #12242 closes by itself, or report the kept-incident case on #12189.
- 5.4 Sweeper exit 0, or the retired exit 5 with a by-hand close citing the `canary=fired` comment.
- #12270 is its own tracked task after 5.2 holds (outside this PR and session).

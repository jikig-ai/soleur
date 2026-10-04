# Tasks: cron-egress self-heal suite SIGPIPE-disposition fix

Plan: knowledge-base/project/plans/2026-10-04-fix-cron-egress-self-heal-suite-sigpipe-disposition-plan.md

Issue: #9473 (closes). Draft PR: #9478. Edited code file: apps/web-platform/infra/cron-egress-self-heal.test.sh only.

> Counts in Phases 1-2 are the pre-review design (121/24); the post-review design is 126/25 (see the plan's Review Amendment). 4.2 is ship's, 4.3 is post-merge.

## Phase 1: RED first (do not touch the sigpipe shim branch yet)

- [x] 1.1 Add `with_sigpipe_ignored` (a subshell with `trap '' PIPE` then `exec "$@"`; external commands only) and `SIGPIPE_PROBE` near `okc()`
- [x] 1.2 Prefix `probe_out`'s `env -i` with `${PROBE_SIGPIPE_IGNORED:+with_sigpipe_ignored}`
- [x] 1.3 Make the shim's `sigpipe` branch record its own SigIgn into `$SC/shim.sigign` (before the flood; do not touch the flood yet), then add the five-row block after the existing control: canary, control ignored, capture-form ignored, routing proof; plus a one-line local-reproduction comment
- [x] 1.4 Add the `MUT_SIGPIPE_IGNORED` knob to `mut_probe` (it also requires `shim.sigign` to read `ignored`) and the fifth row, the early-exit-pipeline mutant run with SIGPIPE ignored
- [x] 1.5 Run the suite on a default shell; capture exactly 2 FAIL lines and `119 passed, 2 failed (121 cases)`
- [x] 1.6 Run `bash -c "trap '' PIPE; bash <suite>"`; capture 4 FAIL lines and `117 passed, 4 failed (121 cases)`

## Phase 2: GREEN

- [x] 2.1 Guard the shim flood with `|| exit 141` inside a `2>/dev/null` group, plus a short contract comment that does not quote the guarded literal (no guard on the trailing echo)
- [x] 2.2 Bump the floors in place, literal on the `if` line: verdicts 116 to 121 (condition and printf message), mutation rows 23 to 24
- [x] 2.3 Re-run both ambients; capture `121 passed, 0 failed (121 cases)` each, no `Broken pipe` text
- [x] 2.4 Run the suite 5 times per ambient (tail -1 per run), 0 failures

## Phase 3: Verification and ratchets

- [x] 3.1 Mutation spot-checks 1 to 5 from the plan's Guard Contract on a scratch copy; record the failing row names; leave the tree unmutated
- [x] 3.2 `bash scripts/guard-vacuity-floor.test.sh` exits 0; floors are still inline literals with no comment between a floor and its `if`
- [x] 3.3 `python3 scripts/lint-guard-contract.py` passes; the discoverability grep prints 1
- [x] 3.4 `git diff origin/main -- apps/web-platform/infra/cron-egress-resolve.sh` is empty; `plugins/soleur/skills/review/SKILL.md` is not in the diff
- [x] 3.5 markdown lint clean (no doubled blank lines) and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` clean

## Phase 4: Learning and PR

- [x] 4.1 Append Instance 3c to the existing 2026-08-20 learning under knowledge-base/project/learnings/ (recurrence, the timing misdiagnosis in #9473, the helper plus canary pattern, shim-owns-normalisation rule)
- [ ] 4.2 PR body: `Closes #9473`, the red-to-green evidence block, and the one-line correction of the issue's timing hypothesis
- [ ] 4.3 After merge, read the Infra Validation run on the merge commit with `gh run view`; `deploy-script-tests (2/4)` must be green

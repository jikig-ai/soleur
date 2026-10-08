# Tasks: grep -q drain, Item B slice S3 (scripts/*.test.sh and scripts/test-all.sh)

Plan: `knowledge-base/project/plans/2026-10-08-chore-grep-q-wave-b-s3-scripts-test-harness-plan.md`

Scope of this task list: S3 only (two deferral rows, `scripts/*.test.sh` 128 lines and `scripts/test-*` 2 lines, both taken to zero and deleted; 130 lines in 47 files under `scripts/` plus two deleted guard lines; fires no path-filtered workflow). S4 (`tests/*`), S5, S6, S7, Items D, E, F, G, I, H, the Wave A3 carriers and the #9638 and #9639 triage are later PRs of the series, not this list. Every battery runs under `ulimit -v 6000000`, one mutant at a time; a suite that starts a vitest worker runs without the cap. Stage by explicit path; the pre-staged `scripts/followthroughs/watchdog-debounce-soak-9686.sh` and the main checkout's `.mcp.json` are not yours. Do not edit anything outside this worktree and the session scratch directory.

## Phase 0: re-measure and gate (read-only)

- [ ] 0.1 `git fetch origin main`; if it is ahead of the branch (it was, by one docs-only commit, at planning), merge it once now, record `git merge-base HEAD origin/main` as the base SHA for `verify --base`, the pair-run clone and the trigger derivation, and re-run this phase (never mid-flight later).
- [ ] 0.2 Drain probe on the dev host and inside `docker run --rm ubuntu:24.04` (plan Phase 0 command): expect `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1`. If `c` prints 141, stop.
- [ ] 0.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh`; keep the `DEFERRED:` lines (expect `scripts/*.test.sh (128 hits, ceiling 128, mode <=)`, `scripts/test-* (2 hits, ceiling 2, mode <=)`, 13 lines, test-shaped total 567).
- [ ] 0.4 `python3 scripts/grep-q-drain-codemod.py apply --row 'scripts/*.test.sh' --row 'scripts/test-*'` dry run: expect POPULATION 588 lines in 132 files, WOULD-CHANGE 80 lines in 33 files, 53 QUEUE lines; diff against the plan's tables; any new entry stops the work until read. Then the same with the nine `--reviewed-suspect` files: expect 28 more lines in 9 files and a 22-line queue (4 H-m, 17 data, 1 X).
- [ ] 0.5 Trigger derivation over the edited-file list against every `push` workflow filter (expect 0 of 48 for all 18 path-filtered workflows, the seven unfiltered ones match); open-PR intersection with the exact list (expect #9745, #9772, #9640, #7390, #6778 by file, no hunk within three lines) and the added-hit screen (expect none); `uptime`; `grep -l vitest` over the edited files.

## Phase 1: red first

- [ ] 1.1 Edit only the guard rows to `'scripts/*.test.sh | <= | 22 | #9217'` and `'scripts/test-* | <= | 0 | #9217'`. The guard must go RED on both (`has 128 hits, ceiling 22`, `has 2 hits, ceiling 0`); paste those two `deferral ceiling exceeded` lines for the PR body (the red state is not committed on its own).

## Phase 2: convert

- [ ] 2.1 Commit 1: `apply --row 'scripts/*.test.sh' --row 'scripts/test-*' --write` (80 lines, 33 files), then the same with `--reviewed-suspect` for `followthroughs/inngest-provision-unit-8562`, `followthroughs/inngest-zot-boot-7462`, `guard-vacuity-floor`, `plugin-delivery-canary`, `prod-version-drift-check`, `sentry-issue-discover`, `test-all-affected`, `test-contention` (each `scripts/<name>.test.sh`) and `scripts/test-all.sh` (28 lines, 9 files); delete the `scripts/test-*` row (stale: no hits). The guard is green at 22 hits against ceiling 22.
- [ ] 2.2 Commit 2: the 4 `grep -m` here-strings in `prod-version-drift-check.test.sh` (lines 1691, 1697, 1723, 1788 base-side) and the 18 one-token conversions listed in `data-conversions.txt` (a throwaway rewrite that touches only those lines; check each result with `git diff -U0`), then the idempotency dry run `apply --row 'scripts/*.test.sh'` (`WOULD-CHANGE: 0 lines in 0 files`), then delete the `scripts/*.test.sh` row as the LAST edit. Stage by explicit path.

## Phase 3: verify

- [ ] 3.1 `verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s3-scripts-tests/hand-edits.txt` prints `verified: 126`, `hand-edited: 4`, `unexplained: 0`; the base-side lines changed outside the two codemod passes equal `hand-edits.txt` plus `data-conversions.txt` (22, by command).
- [ ] 3.2 The guard is rc 0 with 11 `DEFERRED:` lines (none for `scripts/`; the other eleven byte-identical to the merge-base's); test-shaped total 437.
- [ ] 3.3 `bash -n` on the 47 files; `git diff --numstat origin/main...HEAD -- scripts/` shows 130 and 130; `wc -l scripts/test-all.sh` unchanged; `git diff --numstat origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh` prints `0 2`.
- [ ] 3.4 Pair run: a real clone at the base SHA (detached) versus the branch, sequential, `ulimit -v 6000000`, per-suite timeout the larger of 300 s and four times the manifest weight; one table row per suite that differs or needs a caveat; the 15 hand-edit and reviewed-suspect suites plus `test-all-group-affected` (16) must read identical; 13 of the 15 were already run at planning (all identical), `test-all-affected` and `test-contention` are the two to run.
- [ ] 3.5 `bash scripts/pre-push-ratchet-lane.sh` (detached, rc file), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/test-all.sh --print-selection` (record `AFFECTED_FALLBACK reason=runner-changed`) and the runner-parity digests (`--print-selection --paths=<set>` for `README.md`, one `scripts/*.test.sh`, `scripts/test-all.sh` and one `plugins/soleur/skills/**` path, plus the `SUITE_COMMAND` records of `--enumerate-commands all`) on the base clone and the branch: equal. Do not run `--affected` (decided in the plan).

## Phase 4: mutation battery

- [ ] 4.1 Guard 1 matrix on scratch copies after a green control; first red line recorded from printed output; the two must-PASS rows rc 0; restore check clean.
- [ ] 4.2 Observer table for the 18 hand-converted sites (`-vc` inversion and `grep -m 0` force-no-match, one at a time); a survivor is listed as unobserved, not claimed.
- [ ] 4.3 Scratch evidence: old and new `grep -m` expressions on a three-line input whose first match is on line 2 (four displays); the bare-repository run of old and new `scripts/test-all.sh`; the `FATAL` pattern arms for the line-6476 expression.

## Phase 5: evidence and ship notes

- [ ] 5.1 One learning file under `knowledge-base/project/learnings/test-failures/` if still non-obvious (candidate in AC-10). Pick the date at write time.
- [ ] 5.2 `markdownlint-cli2` on the plan, this file, `decision-challenges.md` and the learning; re-measure the discoverability command under the 15 s cap, plain and in a Check 10-shaped `bwrap`.
- [ ] 5.3 Ship notes for `soleur:ship`: first PR-body line says merging fires no path-filtered workflow and no plugin or web-platform release, apply or deploy (trigger derivation over the 48 files); `Ref #9217`; `## Changelog`; NOT-fixed list; the three acknowledged code-review issues; the `AFFECTED_FALLBACK` sentence; labels `semver:patch`, `type/chore`, `domain/engineering`; tracker comment text with the command behind each number.
- [ ] 5.4 Cut S4 and S5 only after S3 has merged (the deleted lines sit next to the `apps/web-platform/*.test.sh` row); never re-sync a BEHIND branch mid-flight; on a queue ejection rebase once, re-run Phases 0 and 3, re-enter.
- [ ] 5.5 After merge: `soleur:postmerge` reads the push runs for the merge SHA (the seven unfiltered workflows ran, none of the 18 path-filtered ones), CI on main, and the files at the merge SHA.

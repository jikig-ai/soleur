# Tasks: shared mutation-battery scorer (#8855, closes #8871)

Plan: `knowledge-base/project/plans/2026-09-27-fix-mutation-battery-shared-scorer-plan.md`

## Phase 1: Setup (RED first)

- [ ] 1.1 Write `apps/web-platform/infra/lib/mutation-scorer.test.sh` (mode 100755), following the plan's "Lib self-test" section.
  - [ ] 1.1.1 Rows: S1 (with the bytes-after-needle floor), S1b, S2, S5, S6, S7, S8, S9, S10, S11 and S14. S1 and S1b use the alternation ERE, written with a bare pipe.
  - [ ] 1.1.2 `set -uo pipefail`, where `pipefail` is load-bearing.
  - [ ] 1.1.3 The temp dir in `scratch-root.test.sh` order: `mktemp -d || exit 2`, then the path check, then `trap 'rm -rf -- "$T"' EXIT INT TERM`.
  - [ ] 1.1.4 Two-space-indented PASS/FAIL lines that carry the row id.
  - [ ] 1.1.5 An `INSTRUMENT BROKEN` counter check.
  - [ ] 1.1.6 Abort rows asserted in the parent shell: rc 2 and the `HARNESS ABORT: mutation_scorer:` stderr text.
  - [ ] 1.1.7 `EXPECTED` set to the number of assertion calls.
  - [ ] 1.1.8 `mutation-scorer self-test: ALL PASS`, printed only after the count pin passes.
  - [ ] 1.1.9 The repo-root `# shellcheck source=` directive.
  - [ ] 1.1.10 Run it and record that it fails because the lib is absent.
- [ ] 1.2 Add the #8855 pass to `.claude/hooks/grep-q-pipe-guard.test.sh`:
  - [ ] 1.2.1 A header paragraph.
  - [ ] 1.2.2 `FILES_8855`, with 6 members and a comment naming the places that change together.
  - [ ] 1.2.3 The tracked-file loop, and the member-count check `!= 6`.
  - [ ] 1.2.4 `PATTERN_PIPED_SCORER`, added to the ERE-compile loop.
  - [ ] 1.2.5 The `hits_8855` scan with comment lines stripped and no opt-out marker.
  - [ ] 1.2.6 `bad-scorer.sh` and `good-scorer.sh` probe lines, compared as counts.
  - [ ] 1.2.7 The `PASS: grep-q-zero-8855-pass` line.
- [ ] 1.3 Run the guard. Record that it is RED: 7 scorer-shape hits and an untracked lib.

## Phase 2: Core Implementation

- [ ] 2.1 Write `apps/web-platform/infra/lib/mutation-scorer.sh` (mode 100644, `# shellcheck shell=bash`, no shebang) to the plan's contract:
  - a scope header;
  - `_mutation_scorer_abort` (exits 2, no `die`);
  - argument and empty-needle checks;
  - an errexit-safe capture with an abort on rc ≥ 2;
  - a quoted bash glob match;
  - an explicit `return 0`;
  - no pipes.
- [ ] 2.2 Get the lib self-test GREEN and run shellcheck on both lib files.
- [ ] 2.3 Convert betterstack's `attributed()` (the live SIGPIPE site). Source the lib from `$ROOT` with a `shellcheck source=` directive. Run the battery (36 rows).
- [ ] 2.4 Convert the `case_row()` kill path in ssl-full-mitigation and in www-apex-canonicalizer. The source-failure abort uses each file's own `die`. In both files, fix the baseline `>&2 | head -20` to `| head -20 >&2`. Rewrite www's stale `grep -qF --` comment. Run both batteries.
- [ ] 2.5 Convert apex `score()`:
  - [ ] 2.5.1 A RED row whose expectation is `-` fails the row.
  - [ ] 2.5.2 Call the lib with a bare-`|` ERE.
  - [ ] 2.5.3 Run the battery (31 rows).
- [ ] 2.6 Convert parity's three sites: `expect_red`, `expect_probe_red`, and `_g2_json_row` (keep its `want == red` short-circuit). Source from `REAL_INFRA`. Run the battery in the background, logging under `/var/tmp`.
- [ ] 2.7 Turn zot-pull's `failed_on` into a one-line wrapper and trim its comment. Source the lib before `failed_on()`, with a `[ -f ] && [ -r ] || die` check. Leave the self-test block byte-unchanged. Run the battery.

## Phase 3: Testing and Verification

- [ ] 3.1 Get `bash .claude/hooks/grep-q-pipe-guard.test.sh` GREEN. It must print the #8855 PASS line and the four existing PASS lines.
- [ ] 3.2 In a detached worktree at HEAD (`git worktree add --detach`):
  - [ ] 3.2.1 First run the pristine self-test and the pristine guard. Both must exit 0.
  - [ ] 3.2.2 Run Guard 1 matrix rows 1, 3, 6 and 11, and Guard 2 matrix rows 3 and 7.
  - [ ] 3.2.3 Only rc 1 counts as a kill. Row 3's output must name the `_g2_json_row` line.
  - [ ] 3.2.4 Restore each row after it runs, and record its observed line for the PR body.
  - [ ] 3.2.5 Remove the worktree.
- [ ] 3.3 Run all six batteries and confirm the row totals are unchanged against `origin/main`. Record before and after.
- [ ] 3.4 From the repo root, run `shellcheck -x` on the lib and its test (no SC1091). Check the modes with `git ls-files -s`. Run `python3 scripts/lint-trap-tempfile-ownership.py` on the lib test.
- [ ] 3.5 After the commit, check that `run-registered-suites.sh --list` passes the plan AC3 exact-line check (`grep -cxF` with the two-space indent) and no `NOT git-tracked` line.
- [ ] 3.6 Write the PR #9033 body:
  - [ ] 3.6.1 Line 1 says this is not a production mutation: no `.tf` changes, and the target-scoped apply should plan zero changes.
  - [ ] 3.6.2 `Closes #8855` and `Closes #8871`.
  - [ ] 3.6.3 #8871 choice 1 is fulfilled here, and choice 2 (the `| head -1` reads) stays accepted.
  - [ ] 3.6.4 #8763 already removed the SIGPIPE at the six named sites.
  - [ ] 3.6.5 The decision challenges from `decision-challenges.md`.

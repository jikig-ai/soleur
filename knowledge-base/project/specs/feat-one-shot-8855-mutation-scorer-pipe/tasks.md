# Tasks: shared mutation-battery scorer (#8855, closes #8871)

Plan: `knowledge-base/project/plans/2026-09-27-fix-mutation-battery-shared-scorer-plan.md`

## Phase 1: Setup (RED first)

- [ ] 1.1 Write `apps/web-platform/infra/lib/mutation-scorer.test.sh` with rows S1 (plus the bytes-after-needle floor), S2, S5, S6, S7, S8, S9, S10 and S14. Add an EXIT-trapped `mktemp -d`, an exact pass-count pin, and the `mutation-scorer self-test: ALL PASS` line. Run it and record that it fails because the lib is absent.
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

- [ ] 2.1 Write `apps/web-platform/infra/lib/mutation-scorer.sh` to the plan's contract:
  - a scope header;
  - `_mutation_scorer_abort` (exits 2, no `die`);
  - argument and empty-needle checks;
  - an errexit-safe capture with an abort on rc ≥ 2;
  - a quoted bash glob match;
  - an explicit `return 0`;
  - no pipes.
- [ ] 2.2 Get the lib self-test GREEN and run shellcheck on both lib files.
- [ ] 2.3 Convert betterstack's `attributed()` (the live SIGPIPE site). Source the lib from `$ROOT` with a `shellcheck source=` directive. Run the battery (36 rows).
- [ ] 2.4 Convert the `case_row()` kill path in ssl-full-mitigation and in www-apex-canonicalizer. In both files, fix the baseline `>&2 | head -20` to `| head -20 >&2`. Rewrite www's stale `grep -qF --` comment. Run both batteries.
- [ ] 2.5 Convert apex `score()`:
  - [ ] 2.5.1 A RED row whose expectation is `-` fails the row.
  - [ ] 2.5.2 Call the lib with a bare-`|` ERE.
  - [ ] 2.5.3 Run the battery (31 rows).
- [ ] 2.6 Convert parity's three sites: `expect_red`, `expect_probe_red`, and `_g2_json_row` (keep its `want == red` short-circuit). Source from `REAL_INFRA`. Run the battery in the background, logging under `/var/tmp`.
- [ ] 2.7 Turn zot-pull's `failed_on` into a one-line wrapper and trim its comment. Leave the self-test block byte-unchanged. Run the battery.

## Phase 3: Testing and Verification

- [ ] 3.1 Get `bash .claude/hooks/grep-q-pipe-guard.test.sh` GREEN. It must print the #8855 PASS line and the four existing PASS lines.
- [ ] 3.2 In a detached worktree at HEAD (`git worktree add --detach`), run Guard 1 matrix rows 1, 2 and 3 and Guard 2 matrix rows 1 and 3. Confirm each is RED, then restore it. Record the observed line for each row for the PR body, then remove the worktree.
- [ ] 3.3 Run all six batteries and confirm the row totals are unchanged against `origin/main`. Record before and after.
- [ ] 3.4 Run `shellcheck -x` on the lib and its test (no SC1091). Run `python3 scripts/lint-trap-tempfile-ownership.py` on the lib test.
- [ ] 3.5 After the commit, check that `run-registered-suites.sh --list` passes the plan AC3 exact-line check (`grep -cxF` with the two-space indent) and no `NOT git-tracked` line.
- [ ] 3.6 Write the PR #9033 body:
  - [ ] 3.6.1 Line 1 says this is not a production mutation: no `.tf` changes, and the target-scoped apply should plan zero changes.
  - [ ] 3.6.2 `Closes #8855` and `Closes #8871`.
  - [ ] 3.6.3 #8871 choice 1 is fulfilled here, and choice 2 (the `| head -1` reads) stays accepted.
  - [ ] 3.6.4 #8763 already removed the SIGPIPE at the six named sites.
  - [ ] 3.6.5 The decision challenges from `decision-challenges.md`.

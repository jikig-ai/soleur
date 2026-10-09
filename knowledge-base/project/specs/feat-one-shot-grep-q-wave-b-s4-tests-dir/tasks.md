# Tasks: grep -q drain, Item B slice S4 (tests/*)

Plan: `knowledge-base/project/plans/2026-10-09-chore-grep-q-wave-b-s4-tests-dir-plan.md`

Scope of this task list: S4 only (one deferral row, `tests/*`, 181 lines in 23 files, taken to zero and deleted; 174 plain one-token conversions, 3 shape-changing hand edits, 4 marked detector-fixture lines; seven real-table canaries added to the guard's probe; fires no path-filtered workflow). S5, S6, S7, Items D, E, F, G, I, H, the Wave A3 carriers and the #9638 and #9639 triage are later PRs of the series, not this list. Every battery runs under `ulimit -v 6000000`, one mutant at a time; a suite that starts a vitest worker runs without the cap (none of the 23 does). Stage by explicit path; the main checkout's `.mcp.json` is not yours. Do not edit anything outside this worktree and fresh scratch directories under `/var/tmp`. Never `rm -rf` a directory that contains `.git`.

## Phase 0: re-measure and gate (read-only)

- [ ] 0.1 `git fetch origin main`; if it is ahead of the branch (it was, by five commits touching none of the 24 files, at planning), merge it once now, record `git merge-base HEAD origin/main` as the base SHA for `verify --base`, the pair-run clone and the trigger derivation, and re-run this phase (never mid-flight later).
- [ ] 0.2 Drain probe on the dev host and inside `docker run --rm ubuntu:24.04` (AC-3 command): expect `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1`. If `c` prints 141, stop.
- [ ] 0.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh`; keep the `DEFERRED:` lines (expect `tests/* (181 hits, ceiling 181, mode <=)`, 11 lines, test-shaped total 437).
- [ ] 0.4 `python3 scripts/grep-q-drain-codemod.py apply --row 'tests/*'` dry run: expect POPULATION 458 lines in 85 files, `ROW tests/* (hits) H-m=1 T0=76 data=24 suspect=81`, WOULD-CHANGE 76 lines in 16 files, 106 QUEUE entries. Then the same with `--reviewed-suspect` for `tests/scripts/test-audit-ruleset-bypass.sh`, `test-registry-pull-path-health.sh`, `test-registry-restore-from-ghcr.sh`, `test-sentry-alert-live-fidelity.sh`, `test-supabase-logs-query.sh` and `test-tmp-purge.sh`: expect WOULD-CHANGE 155 lines in 22 files and a 26-line queue (24 data, 1 H-m, 1 X). Diff against the plan's tables; any new entry stops the work until read.
- [ ] 0.5 Trigger derivation over the edited-file list against every `push` workflow filter (expect 0 of 24 for all 18 path-filtered workflows; the sanity probe of three known-matching paths must still light five); open-PR intersection with the exact list (`gh pr list --state open --limit 300 --json number,title,isDraft,mergeStateStatus,files`; expect #9784 by file only) and the added-line screen with `PATTERN_V2` over `gh pr diff` (it found three new early-exit pipes in #9784 at planning; record whatever it finds now and re-run at the PR-ready step); `uptime`; `grep -lE 'vitest|bun test'` over the 23 files (expect none).
- [ ] 0.6 Fixed-fragment search for the pin class (plan, Classification check 2): for each of the 181 lines, `git grep -F` of its `grep -q ...` fragment across tracked files outside `knowledge-base/`; expect only the known coupling `test-audit-ruleset-bypass.sh:1274` to 848 and generic lookalikes in other suites.

## Phase 1: red first

- [ ] 1.1 Edit only the guard row to `'tests/* | <= | 26 | #9217'`. The guard must go RED (`has 181 hits, ceiling 26`); paste that `deferral ceiling exceeded` line for the PR body (the red state is not committed on its own).

## Phase 2: convert

- [ ] 2.1 Commit 1: `apply --row 'tests/*' --write` (76 lines, 16 files), then the same with the six `--reviewed-suspect` flags (79 lines, 6 files), plus the one-line sed-expression hand edit at `test-audit-ruleset-bypass.sh:1274` in the same commit (line 848 is converted by the codemod and the suite exits 1 until 1274 follows it). The guard is green at 25 hits against ceiling 26 (`<=`).
- [ ] 2.2 Commit 2: the 19 stub lines listed in `data-conversions.txt` by the throwaway regexp (assert each line changed; check each result with `git diff -U0`); `test-git-data-rung2-evidence-capture.sh:934` to the here-string; `test-tmp-purge.sh:300` to `grep -c >/dev/null`; the trailing `# sigpipe-demo: intentional` (after two spaces) on `test-git-data-birth-readiness-gate.sh:2971-2974`. Then the idempotency dry run `apply --row 'tests/*'` (`WOULD-CHANGE: 0 lines in 0 files`, population 277).
- [ ] 2.3 As the LAST edit: delete the `tests/*` row and widen the real-table probe (`mkdir -p` list, planted names, `real_want`, the literal 8 to 15 in `real_none` and its two messages). Nothing else in the guard. Stage by explicit path.

## Phase 3: verify

- [ ] 3.1 `verify --base "$(git merge-base HEAD origin/main)" --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/hand-edits.txt` prints `verified: 174`, `hand-edited: 7`, `unexplained: 0`; the base-side lines changed outside the two codemod passes equal `hand-edits.txt` plus `data-conversions.txt` (26, by command).
- [ ] 3.2 The guard is rc 0 with 10 `DEFERRED:` lines (none for `tests/`; the other ten byte-identical to the merge-base's); test-shaped total 256; `SWEEP_PROBE_CHECKS` still 62.
- [ ] 3.3 `bash -n` on the 23 files; `git diff --numstat origin/main...HEAD -- tests/` shows 181 and 181; `git diff --name-only origin/main...HEAD` lists no `scripts/test-all.sh` and no `scripts/lib/test-affected-paths.sh`.
- [ ] 3.4 Pair run: a real clone at the base SHA (detached) with the worktree's `node_modules` symlinked on both sides, versus the branch, sequential, `ulimit -v 6000000`, per-suite timeout max(300 s, 4 x weight); the 23 owning suites and the 5 adjacent ones (`lint-shell-capture-exit.test.sh`, `test-registry-delivery-change-mutation-battery.sh`, `test-registry-d10-workflow-wiring.sh`, `fixture-relative-assert.test.sh`, `required-checks-merge-group-coverage.test.sh`) read the same rc and the same final line; `registry-gate-mutation-battery` is `not run locally` with the reason.
- [ ] 3.5 `bash scripts/pre-push-ratchet-lane.sh` (detached, rc file), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/test-all.sh --print-selection` (record `AFFECTED_SUMMARY ... fallback=none`). Do not run `--affected` (decided in the plan). No runner-parity digest: the runner and the affected index are not in the diff.

## Phase 4: mutation battery

- [ ] 4.1 Guard 1 matrix (rows 1, 1c, 2 to 9, 10a to 10e, 11 to 15; 12, 14, 15, 10e and 6i are the measured surviving mutants) on scratch copies after a green control; first red line recorded from printed output; the must-PASS rows rc 0 with a `cmp` landing check and row 1 as the paired control; restore check clean. Build any row text by script (the `#9217` and `/dev/null` strings are sed-delimiter traps).
- [ ] 4.2 Observer table: `-vc` inversion and `-m 0 -c` never-match for the 19 stub lines, `test-tmp-purge.sh:300` and `test-audit-ruleset-bypass.sh:848`; a survivor is listed as unobserved, not claimed. Scratch runs: old and new `-m` display expressions on a populated (first match on line 2), an empty and a no-match input, plus the never-match mutant on line 934; line 1274 reverted alone (suite stops with rc 1 after `T-mq-ctl5`); one fixture line converted instead of marked (`W2-control` fails).

## Phase 5: evidence and ship notes

- [ ] 5.1 One learning file under `knowledge-base/project/learnings/test-failures/` if still non-obvious (candidate in AC-10). Pick the date at write time.
- [ ] 5.2 `markdownlint-cli2` on the plan, this file, `decision-challenges.md` and the learning; re-measure the discoverability command under the 15 s cap, plain and in a Check 10-shaped `bwrap`, with `uptime` beside each figure.
- [ ] 5.3 Ship notes for `soleur:ship`: first PR-body line says merging starts no path-filtered workflow on push (Web Platform Release's `workflow_run` arm does start and takes its clean skip) and no plugin or web-platform release, apply or deploy (trigger derivation over the 24 files); `Ref #9217`; `## Changelog`; NOT-fixed list; the `--print-selection` line and the sentence that `--affected` was not run (CI is the gate); labels `semver:patch`, `type/chore`, `domain/engineering`; tracker comment text with the command behind each number and the 12-line throwaway.
- [ ] 5.4 S5 and S6 add canaries to the same probe line and literal: the second to merge rebases once and re-counts; never re-sync a BEHIND branch mid-flight; on a queue ejection rebase once, re-run Phases 0 and 3, re-enter. #9784's three new `tests/` pipes are named in the PR body.
- [ ] 5.5 After merge: `soleur:postmerge` reads the push runs for the merge SHA (the seven unfiltered workflows ran, none of the 18 path-filtered ones), CI on main, and the files at the merge SHA.

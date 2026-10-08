# Tasks: grep -q drain, Item B slice S2 (plugins/soleur/test)

Plan: `knowledge-base/project/plans/2026-10-08-chore-grep-q-wave-b-s2-plugin-test-harness-plan.md`

Scope of this task list: S2 only (one deferral row, `plugins/soleur/test/*`, 140 lines to 5; 46 files edited; fires one plugin release). S3 to S7, Items D, E, F, G, I, H, the Wave A3 carriers and the #9638 and #9639 triage are later PRs of the series, not this list. Every battery runs under `ulimit -v 6000000`, one mutant at a time. Stage by explicit path; the pre-staged `scripts/followthroughs/watchdog-debounce-soak-9686.sh` and the main checkout's `.mcp.json` are not yours.

## Phase 0: re-measure and gate (read-only)

- [ ] 0.1 `git fetch origin main`; if it is ahead of the branch, merge it once now and re-run this phase (never mid-flight later).
- [ ] 0.2 Drain probe on the dev host and inside `docker run --rm ubuntu:24.04`: with a writer that emits a second line after the first, `grep -q` must print 141 and `grep -c 1 >/dev/null` must print 0 and a no-match input must keep rc 1, under `set -o pipefail`. If the second prints 141, stop.
- [ ] 0.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh`; keep the `DEFERRED:` lines (expect `plugins/soleur/test/* (140 hits, ceiling 140, mode <=)` and a test-shaped total of 702).
- [ ] 0.4 `python3 scripts/grep-q-drain-codemod.py apply --row 'plugins/soleur/test/*'` dry run; diff its QUEUE against the plan's disposition table (19 entries); any new entry stops the work until read.
- [ ] 0.5 Trigger derivation over the `CHANGED` file list against every workflow path filter (expect only `version-bump-and-release.yml`, 46 of 46); open-PR intersection with the 46 files (expect empty); `uptime`.

## Phase 1: red first

- [ ] 1.1 Edit only the guard row to `'plugins/soleur/test/* | <= | 5 | #9217'` with the two-line comment (five data pins, no pipes; `=` so a forgotten ceiling fails; the codemod refuses `--write` on `=` rows). The guard must go RED (`has 140 hits, ceiling 5`).

## Phase 2: convert

- [ ] 2.1 Commit 1: `apply --row 'plugins/soleur/test/*' --write`, then the same with `--reviewed-suspect` for `go-session-gates`, `issue-flow-measure`, `main-health-monitor-workflow`, `required-checks-canonical-parity`, `scripts-shard-runtime-coverage`, `ship-phase-7-poll-fixtures`, `sync-pr-behind` (122 + 9 lines).
- [ ] 2.2 Commit 2: the five hand edits (`git-tripwire:124` and `web-host-escrow-diagnose-workflow:710` `-m1` to here-strings; `roadmap-reconcile:274` heredoc stub; `worktree-manager-porcelain-sigpipe:288` marker and `:369` banner reword) and `hand-edits.txt`.

## Phase 3: verify, then flip

- [ ] 3.1 `verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s2-drain-codemod/hand-edits.txt` prints `verified: 130`, `hand-edited: 5`, `unexplained: 0`; the `apply --row` dry run prints `WOULD-CHANGE: 0 lines in 0 files`.
- [ ] 3.2 Flip the row to `= | 5` (last edit); the guard is rc 0 with `5 hits, ceiling 5, mode =, slack 0`; the other twelve `DEFERRED:` lines match the merge-base's.
- [ ] 3.3 `bash -n` on the 46 files; `git diff --numstat origin/main...HEAD -- plugins/soleur/test/` shows 135 and 135.
- [ ] 3.4 Pair run (pristine `git archive` of `origin/main` versus the branch, sequential, `timeout 150`); one table row per suite for the PR body.
- [ ] 3.5 `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/test-all.sh --print-selection` (guard selected), `bash scripts/test-all.sh --affected` if the host allows.

## Phase 4: mutation battery

- [ ] 4.1 Guard 1 matrix (eight rows) on scratch copies after a green control; first red line recorded from printed output; mutant 8 recorded as the surviving one; restore check clean.
- [ ] 4.2 Hand-edit rows: swap `-c` for `-vc` in the `roadmap-reconcile.test.sh` stub, TS15e must go RED; scratch run of the two `-m1` expressions on a three-line input whose first match is on line 2.

## Phase 5: evidence and ship notes

- [ ] 5.1 One learning file under `knowledge-base/project/learnings/test-failures/` if still non-obvious (a `<=` row does not fail on slack; the codemod refuses a `=` row, so convert then flip). Do not prescribe a date in the plan; pick it at write time.
- [ ] 5.2 `markdownlint-cli2` on the plan, this file, `decision-challenges.md` and the learning.
- [ ] 5.3 Ship notes for `soleur:ship`: first PR-body line says merging fires one plugin release (`version-bump-and-release.yml`) and no web-platform release, apply or deploy; `Ref #9217`; `## Changelog`; NOT-fixed list; the eleven #8659 files; the later work that lowers this row next (Item F or S7); labels `semver:patch`, `type/chore`, `domain/engineering`; tracker comment text with the command behind each number.
- [ ] 5.4 Cut S3, S4 and S5 only after S2 has merged (their rows sit next to the S2 row); never re-sync a BEHIND branch mid-flight.
- [ ] 5.5 After merge: `soleur:postmerge` reads the `version-bump-and-release.yml` run and the new `v` release for the merge SHA; no other path-filtered workflow ran.

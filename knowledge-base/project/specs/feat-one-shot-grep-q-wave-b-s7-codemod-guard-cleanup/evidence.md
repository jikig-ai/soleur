# Evidence: S7a codemod and guard cleanup (tracker #9217, Ref only)

Base `3eb0238125` (origin/main at branch creation); head is the S7a branch. Every command is run from inside the repository, in a tree with an empty `git status --porcelain`, under `ulimit -v 6000000`.

## Before and after: the guard's `DEFERRED:` table

| | lines | glob rows | file-exact rows | counted hits |
|---|---|---|---|---|
| before | 8 | 2 (`.claude/*.test.sh` 5, `plugins/soleur/test/*` 5) | 6 carrier rows | 10 test hits + 22 carrier hits |
| after | 12 | 0 | 12 (six test files at 1, 4, 1, 1, 1, 2, then the six carrier rows) | same 10 + 22 |

`bash .claude/hooks/grep-q-pipe-guard.test.sh | grep -c '^DEFERRED:'` prints 12 and the guard exits 0.

## Red first (AC-4)

With only `GATED_TEST_ROWS` changed to the six exact paths, the guard read `FAIL ... real-table-test-shaped: ... the test-shaped row globs are [.claude/*.test.sh plugins/soleur/test/* ], want exactly the pinned GATED_TEST_ROWS set` (rc 1). Changing the rows and `_ts_re` then read green (rc 0, twelve `DEFERRED:` lines).

## Probe-check arithmetic (AC-3)

62 pinned before. The selftest block (guard lines 1056 to 1397, 342 lines) held 29 `sweep_probe_fail+=(` checks, so 33 remained; two checks were added (`test-canaries`, `wiring`), giving 35. `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -c 'sweep_probe_fail+='` prints 35 and `SWEEP_PROBE_CHECKS=35`. The guard went from 1410 to 1101 lines; its wall time from inside the repo fell from about 7.4 s to about 3 s (context, not an acceptance claim).

## Codemod deletion (AC-2)

`scripts/grep-q-drain-codemod.py` (785 lines) removed. `git grep -n grep-q-drain-codemod -- . ':!knowledge-base'` returns only the header comment naming it as deleted and recoverable from `6a86eae0ec` (a comment line; no non-comment reference remains).

## Mutation matrix (AC-5), one mutant at a time on a scratch sandbox repo, restored from HEAD after each (clean restore verified)

Unmutated control in the sandbox: rc 0, twelve `DEFERRED:` lines. Every mutation landed (the row harness refuses a row whose tree is unchanged).

| Row | Mutation | Result |
|---|---|---|
| M1 | add a pipe to `guardrails.test.sh`, convert one `pkill-self-match-guard.test.sh` hit | RED rc 1: `outside the deferral table` naming `guardrails.test.sh:1668` (and the loose ceiling on the pkill row) |
| M2 | re-widen to `.claude/*.test.sh <= 5` | RED `real-table-test-shaped` |
| M3 | delete the `deploy-arm.test.sh` row, keep its hit | RED `outside the deferral table` naming `deploy-arm.test.sh:676` |
| M4 | widen `_ts_re` with any glob-free `.sh` | RED `real-table-production-rows: 4 non-test-shaped rows (want exactly 6)` |
| M5 | lower the pkill ceiling 4 to 3 | RED `deferral ceiling exceeded` |
| M6 | convert the one `background-poll` hit, keep its row | RED `stale deferral` |
| M7 | delete all six exact rows | RED `outside the deferral table (10 site(s))` |
| M8 | `.gitignore` entry `*.test.sh` | RED rc 3 `UNRESOLVED: no swept file under apps/web-platform/test/` from the existing root canary (that root holds only test files); the new check was not reached |
| M8b | `.gitignore` entry `scripts/*.test.sh` only | RED `test-canaries ... [scripts/actions-queue-health.test.sh ]` (the root canary stays green because `scripts/` has other files) |
| M9 | pathspec exclusion of `apps/web-platform/infra/*.test.sh` | RED; with the sibling probe rows also failing; `test-canaries ... [apps/web-platform/infra/ci-deploy.test.sh ]` present (M9b) |
| M10 | delete one canary entry, keep the count pin | RED `test-canaries ... holds 3 entries, pinned at 4` |
| M11 | invalid pathspec so the listing fails | rc 3 `UNRESOLVED: scan_sweep could not list its population` (the existing check fires first; the new check's own UNRESOLVED branch is unexercised: UNVERIFIED) |
| M12 | `|| sweep_rc=$?` replaced by `|| true` | RED `wiring: ... capture matched 0 lines` |
| M13 | `sweep_fold "$sweep_rc"` deleted | RED `wiring: ... fold 0` |
| M14 | both statements renamed | RED `wiring: matched 0 and 0` |
| H1 | delete the `loose_ctl` control check | RED `probe-count: 34 checks, pinned at 35` |
| H2 | row with extra whitespace (must-PASS) | rc 0 |
| H3 | delete the canary check's append tail | RED `probe-count: 34 checks, pinned at 35` |
| H4 | second compliant test file (must-PASS) | rc 0 |
| H5 | wiring statement only in a comment | RED `wiring: ... fold 0` |
| H6 | indented fold statement (must-PASS) | rc 0 |

Axes this battery did not edit: the `real_paths` plants and `REAL_PLANTED`, the `SWEEP_FLOOR`, `GATED_PROD_GLOBS` identity (swapped carriers), a rename of a pinned test file (it reads as a stale row, covered by M6's text), and the guard's own dispatch for `exit 3` in the new check (M11).

## AC-6: the add-one-delete-one hole

On the same tree as M1 (hit added in `guardrails.test.sh`, one `pkill-self-match-guard.test.sh` hit converted so net count is unchanged), the base guard (`3eb0238125`, with its codemod restored in the sandbox) read `PASS: grep-q-zero-sweep-pass` (rc 0); the S7a guard read RED (M1). Both runs recorded above.

## Lints (AC-8)

`python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`: 0 new findings (224 baselined). `bash scripts/guard-vacuity-floor.test.sh`: 23 passed, 0 failed. `bash scripts/lint-orphan-test-suites.sh`: 661 tracked suites, 0 orphaned. `shellcheck -S warning` on the guard: 0 findings before and after. `bash scripts/pre-push-ratchet-lane.sh`: PASS, 12 members, 0 red.

## Marked-line baseline for series Item F

`git grep -h 'sigpipe-demo: intentional' -- . ':!knowledge-base' | wc -l` prints 34 repo-wide at this head.

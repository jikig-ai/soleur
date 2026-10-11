# Evidence: S7a codemod and guard cleanup (tracker #9217, Ref only)

Base `3eb0238125` (origin/main at branch creation); head is the S7a branch. Every command is run from inside the repository, in a tree with an empty `git status --porcelain`, under `ulimit -v 6000000`.

## Before and after: the guard's `DEFERRED:` table

| | lines | glob rows | file-exact rows | counted hits |
|---|---|---|---|---|
| before | 8 | 2 (`.claude/*.test.sh` 5, `plugins/soleur/test/*` 5) | 6 carrier rows | 10 test hits + 23 carrier hits |
| after | 12 | 0 | 12 (six test files at 1, 4, 1, 1, 1, 2, then the six carrier rows) | same 10 + 23 |

`bash .claude/hooks/grep-q-pipe-guard.test.sh | grep -c '^DEFERRED:'` prints 12 and the guard exits 0.

## Red first (AC-4)

With only `GATED_TEST_ROWS` changed to the six exact paths, the guard read `FAIL ... real-table-test-shaped: ... the test-shaped row globs are [.claude/*.test.sh plugins/soleur/test/* ], want exactly the pinned GATED_TEST_ROWS set` (rc 1). Changing the rows and `_ts_re` then read green (rc 0, twelve `DEFERRED:` lines).

## Probe-check arithmetic (AC-3)

62 was pinned under the old recipe (any non-comment line holding `sweep_probe_fail+=(`, which also counted the pin's own counting line); the operator-anchored recipe the guard now uses (`||` or `&&` immediately before the append) counts 61 on the same base. The selftest block (base lines 1051 to 1391, 341 lines) held 29 checks, so 32 remained; four were added (`test-canaries`, `return-wiring`, and the two exit-status equivalence checks restored in review), giving 36. `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('` prints 36 and `SWEEP_PROBE_CHECKS=36`. The guard went from 1410 to 1146 lines; its wall time from inside the repo fell from roughly 8.6 to 11 s to roughly 2.4 to 3.6 s in sandbox copies (context, not an acceptance claim).

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

## Review round 1 (8 seats at `5754128d32`; fixes in `6e481dddff` and the commit after it)

Seat verdicts: no P1 blocking merge. PR-introduced P2s, all fixed inline and each proven RED by a sandbox mutation (one at a time, restored from HEAD, control rc 0; the `wiring` check named in the first matrix above is now `return-wiring`):

| Row | Mutation | Result |
|---|---|---|
| W1 | capture and fold wrapped in an indented dead branch | RED `return-wiring ... unindented capture 0, fold 0` |
| W2 | `sweep_rc=0` inserted between capture and fold | RED `capture immediately followed by the fold 0` |
| W3 | verdict gate `== 0` changed to `>= 0` | RED `return-wiring: the probe verdict gate matched 0` (direct report, rc 1) |
| W4 | a second `exit "$FAIL"` between the pin and the gate | RED, same direct report |
| W5 | an `exit "$FAIL"` inserted ahead of every pin | rc 0, NOT caught: a text pin cannot guard code placed before itself (documented limit) |
| T1 | pathspec exclusion of a canary file | RED `test-canaries ... ci-deploy.test.sh` (the shared listing sees it) |
| T2 | `.gitignore` entry hiding `plugins/soleur/skills/*/test/` | RED, names the hidden tracked files |
| T3 | `.gitignore` entry for one tracked non-canary file | RED, names it (the class a per-file ignore used to hide) |
| T4 | one canary deleted from the array only | RED `holds 8 entries, pinned at 9` |
| P1 | a check's append moved into a trailing comment (decoy) | RED `probe-count: 35 checks, pinned at 36` |
| M1 | a row loosened to `<= 99` | RED `1 rows use mode <=` |
| E1 | equivalence harness made blind | RED `equivalence-bash ... reported NOTHING` |
| E2 | converted form made to diverge | RED `equivalence-bash` (rows named) |
| C1 | comment-only edit (must-PASS) | rc 0 |

Before the fix the base guard (`3eb0238125`) stayed GREEN on the add-one-delete-one tree and the S7a guard went RED (AC-6, first matrix above); that result is unchanged.

Recorded as NOT fixed, with reasons:

- An `exit`, an assignment or a `trap` placed ahead of or between the pinned statements (W5, `FAIL=0` reset, `trap ... exit 0`): a text guard cannot defend code that runs before it, and a diff that edits the guard's control flow is reviewed; pinning each shape would churn `SWEEP_PROBE_CHECKS` without closing the class.
- A count swap inside one file (convert one hit, add another): the count is per file by design; now stated in the row comment.
- The `<=` mode machinery (`_loose_not_test_shaped`, `loose_ctl`, `tests_rows`) now guards a mode with no users; removing it moves the pin again, so it belongs with series Item F.
- `SWEEP_FLOOR=1400` slack (about 400 files), a colon in a swept filename dropping its hits from comment stripping, and unswept extensions (`.ts` 1 hit, `.md`, extensionless): pre-existing, already stated limits of the sweep.
- `grep` on `${BASH_SOURCE[0]}` without `--` (a script path starting with `-`): unreachable, the runner passes a `.claude/...` or absolute path.
- The `-x` anchor of the canary loop has no decoy row (a decoy `vendor/.claude/hooks/guardrails.test.sh` with the real one hidden would pass if `-x` were dropped): accepted, the identity pin and the hidden-file listing cover the realistic cases.

## Review round 2 (4 fix-round seats at `ae0da93576`; fixes in the three commits after it)

New PR-introduced defects found and fixed, each proven RED in a sandbox (control rc 0, one mutation at a time, restored from HEAD):

| Row | Mutation | Result |
|---|---|---|
| L1 | a row's mode written `< =` (blank inside the mode) | RED `1 rows use mode <=` (the count now uses the parser's own whitespace stripping) |
| L2 | capture and fold in an UNINDENTED `if false` branch | RED `return-wiring ... SWEEP_N=''` (a sweep that never ran leaves `SWEEP_N` empty) |
| L3 | the verdict gate's `FAIL=1` and `exit 1` removed with a forced probe failure | RED `the gate's FAIL=1 0 and its exit 1 0` (both are pinned) |
| L4b/L4c | the equivalence pass pointed at `true` (sh, then bash) | RED `equivalence-sh` / `equivalence-bash` (one `EQV_SH`/`EQV_BASH` name drives the run and its negative control) |
| R1 to R4 | regressions of round 1 (gate `>= 0`, indented dead branch, hidden skills tests, blind harness) | RED as before |
| C1 | comment-only edit (must-PASS) | rc 0 |

Still recorded as NOT fixed, one class with one reason: the guard cannot defend its own control flow beyond text pins. A statement placed between the pins and the gate (`exit`, an assignment, `sweep_probe_fail=()`), a deleted direct block, a trap override, and a decoy that fabricates a whole `|| sweep_probe_fail+=(` line each need an edit of the guard itself, which a reviewer reads; pinning each shape moves `SWEEP_PROBE_CHECKS` again without closing the class. The header comment states this limit.


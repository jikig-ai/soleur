# Evidence: grep -q drain, Item B slice S5 (plugins/soleur/*.test.sh)

Every figure below was read from command output on this branch. Base SHA for every comparison: `32b2fe2abb6cb57b2badf0faf8efca0ac51990c0` (origin/main merged once at the start, never again).

## Drain probe (GNU grep, dev host and `ubuntu:24.04`)

`q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1` on both.

## Red step, then conversions

- Row lowered to `<= | 14`: `FAIL: deferral ceiling exceeded: plugins/soleur/*.test.sh has 66 hits, ceiling 14`, rc 1.
- Codemod census (dry run): `POPULATION: 277 lines in 62 files`, `T0=33 data=15 suspect=21`, 31 lines in 10 files by default; with `--reviewed-suspect` for `playwright-mcp-redact-proxy.test.sh` and `boundary.test.sh` (comments only name SIGPIPE): 52 lines in 12 files, 15 data queue entries on 14 lines.
- Written in two passes (31, then 21), guard green at `14 hits, ceiling 14`; the 14 data-tier lines by a one-token throwaway (`data-conversions.txt`: 13 eval-ed assertion strings in `alpha-metrics.test.sh`, one stub-heredoc line in `resolve-regenerable-conflicts.test.sh`). Idempotency dry run afterwards: `POPULATION: 211 lines in 49 files`, `WOULD-CHANGE: 0 lines in 0 files`.

## verify

`python3 scripts/grep-q-drain-codemod.py verify --base 32b2fe2abb... --hand-edits <spec>/hand-edits.txt`: `verified: 66`, `hand-edited: 0`, `unexplained: 0`. `git diff 32b2fe2abb HEAD --numstat -- plugins`: 66 insertions, 66 deletions in 13 files.

## Guard

`bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0; 9 `DEFERRED:` lines, byte-identical to the other nine at base; test-shaped ceilings 256 to 190; `SWEEP_PROBE_CHECKS` stays 62 (63 `sweep_probe_fail+=(` occurrences before and after).

## Pair run (real detached clone at the base SHA, root and `apps/web-platform` `node_modules` linked on both sides, sequential, `ulimit -v 6000000`, `TMPDIR=/var/tmp`, `timeout 600`, `nice -n 10`; load average 10 to 19 during the run)

| suite (under plugins/soleur/) | base rc | branch rc | same final line | final line |
|---|---|---|---|---|
| scripts/admin-merge-ready.test.sh | 0 | 0 | yes | admin-merge-ready: all 77 cases passed |
| scripts/alpha-metrics.test.sh | 0 | 0 | yes | === alpha-metrics: 15 passed, 0 failed (of 15) === |
| scripts/resolve-regenerable-conflicts.test.sh | 0 | 0 | yes | resolve-regenerable-conflicts: all 140 assertions passed |
| skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh | 0 | 0 | yes | 471 passed, 0 failed, 471 cases (86 mutants, 86 mutation rows) |
| skills/archive-kb/test/archive-kb-partial-run.test.sh | 0 | 0 | yes | 10 passed, 0 failed (10 cases) |
| skills/constraint-scaffold/test/bite-proof.test.sh | 0 | 0 | yes | bite-proof.test.sh: 96 passed, 0 failed (96 assertions) |
| skills/constraint-scaffold/test/boundary.test.sh | 0 | 0 | yes | boundary.test.sh: 37 passed, 0 failed (37 assertions) |
| skills/constraint-scaffold/test/emit-fix-constraints.test.sh | 0 | 0 | yes | emit-fix-constraints.test.sh: 16 passed, 0 failed |
| skills/constraint-scaffold/test/parity.test.sh | 0 | 0 | yes | parity.test.sh: 12 passed, 0 failed (12 rows) |
| skills/incident/test/redact-sentinel.test.sh | 0 | 0 | yes | Total: 96 pass, 0 fail |
| skills/linear-fetch/test/parity.test.sh | 0 | 0 | yes | Results: 3 passed, 0 failed |
| skills/linear-fetch/test/persist-safe-integration.test.sh | 0 | 0 | yes | Results: 11 passed, 0 failed |
| skills/linear-fetch/test/redact-linear-urls.test.sh | 0 | 0 | yes | Results: 33 passed, 0 failed |

13 of 13 suites identical. `boundary` read 37 and `bite-proof` 96 assertions (not the SKIP counts), so the toolchain probes did not skip.

## Guard mutation matrix (scratch clone of the COMMITTED guard, green control first: `rc=0 ok`; one mutant at a time under `ulimit -v 6000000`; landing checked against the pristine file; clone restored and clean after every row)

59 rows: 47 killed with the named FAIL text, 12 GREEN as predicted, 0 unexpected.

Killed: 1a, 1b, 1c, 1d, 2a, 2b, 2c, 2d, 3, 4a, 4b, 5a, 5b, 6a, 6b, 6f, 6c, 6d, 6e, 6g, 6h, 6i, 7, 8, 9a, 9b, 10c, 10d, 11a, 11b, 11c, 11d, 11e, 11f, 13a, 13b, 13c, 14, 16a, 16b, 19a, 19b, 19c, 20a, 20b, 20c, 20e.

GREEN as predicted (known surviving or permitted forms, written down, not claimed as protected): 6j, 6k, 10a, 10b, 10e, 13e, 13f, 17, 12, 20d, 21a, 21c. Of these, 10a and 10b are the drained and marked forms the contract permits; 10e is the known marker hole (Item F); 6j, 6k, 13e, 13f and 12 are uncanaried subtrees or consistent weakening of the probe; 17 is a mode loosening of a pinned row; 21a and 21c are the pin's own code; 20d is an inert probe fixture.

## Ablation: each added piece is load-bearing (same rows on guards built from the committed one with pieces removed)

| row | S3-form (row deleted only) | canaries only | canaries + control | complete |
|---|---|---|---|---|
| 5a | GREEN rc 0 | RED rc 1 (killed with the named text) | RED rc 1 (killed with the named text) | RED rc 1 |
| 5b | RED rc 1, other FAIL text | RED rc 1 (killed with the named text) | RED rc 1 (killed with the named text) | RED rc 1 |
| 6a | GREEN rc 0 | RED rc 3 (killed with the named text) | RED rc 3 (killed with the named text) | RED rc 3 |
| 11d | GREEN rc 0 | GREEN rc 0 | GREEN rc 0 | RED rc 1 |
| 13a | GREEN rc 0 | RED rc 3 (killed with the named text) | RED rc 3 (killed with the named text) | RED rc 3 |
| 14 | RED rc 1, other FAIL text | RED rc 1, other FAIL text | RED rc 1, other FAIL text | RED rc 1 |
| 14b | GREEN rc 0 | GREEN rc 0 | GREEN rc 0 | RED rc 1 |

Reading: rows 11d and 14b (a narrow or below-the-pins resurrected row with its own hits) are GREEN on every variant without the pin and RED only on the complete guard, so the pinned glob set is the piece that closes them; 5a, 6a and 13a are GREEN on the S3-form and closed by the canaries.

## Observer mutants (the stub line, `resolve-regenerable-conflicts.test.sh:554`)

Run inside `unshare -Urpf --kill-child --mount-proc` with a 240 s cap and a landing check (see the incident note below). Control, the unmutated suite in the same namespace: rc 0, `all 140 assertions passed`. `-vcx` inversion: rc 1, 2 FAIL lines (`signal during commit`, `signal mid-merge`). `-m 0 -cx` never-match: rc 1, 1 FAIL line (`signal mid-merge`). The line is observed by both mutants. The planning-time results for the 13 `alpha-metrics` lines (all killed) and 8 sampled `boundary` lines (all killed) are carried over from the plan's observer table, not re-run.

## Incident note: the inverted-match observer must not run outside a PID namespace

The helper at lines 548 to 566 walks `$PPID` upwards and sends SIGTERM to the outermost ancestor whose argv holds the resolver script, stopping at the first non-matching ancestor. With the match inverted every ancestor matches, the stop never fires, and the walk ends at the top of the user session. Run on the host, that ended the desktop session four times (19:04, 20:08, 20:22, 20:37 on 2026-10-09; Hyprland SIGABRT in its own shutdown path). Inside a PID namespace the test shell is PID 1 and has no ancestor above it, so the same mutant is contained. The unmutated suite is unaffected (140/140 on the pair run and in the namespace). Follow-up hardening is tracked separately from this slice.

## Not run locally

`scripts/test-all.sh --affected`, `--print-selection`, the long ratchet lane and markdownlint (not installed here) were left to CI's required `test` check, as agreed for a contended host. Cheap repo-global lints that were run: `lint-shell-capture-exit.py --baseline ...` (0 new findings, 224 baselined), `guard-vacuity-floor.test.sh` (23 passed), `lint-orphan-test-suites.sh` (647 covered, 0 orphaned). Shellcheck delta over the 14 files: 274 findings at base, 277 at head, all three new notes (two SC2016, one SC2031) in the guard's new probe lines and of the kinds the file already carries 33 of.

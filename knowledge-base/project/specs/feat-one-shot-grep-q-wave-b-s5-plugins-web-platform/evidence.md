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


## Review addendum (2026-10-09; appended, nothing above is edited)

Panel: 12 report-only seats on PANEL_SHA `0a1c633584` (tier `aggregate pattern`, class `code`): two design-validity seats first (simplicity, architecture), then git-history, pattern-recognition, security-sentinel, performance-oracle, data-integrity, agent-native, code-quality, user-impact, test-design and a structural-enumeration seat. No P1. Two P2 (pre-existing, recorded as not fixed: decision-challenges item 23) and the rest P3. Semgrep was skipped (bash-only diff); shellcheck stood in.

### Corrections to the record above
- The ratchet lane (`scripts/pre-push-ratchet-lane.sh`) WAS run locally: 24 members, one red (`fixture-relative-assert`, a relative-fixture site in the planner's `pair-run.sh`), fixed in code with the canonical `assert_fixture_dir` (62/0, baseline untouched). "Not run locally" above does not apply to it.
- Every matrix row was run in Phase 4, including 2b to 2d, 3, 8 and 10a to 10e (tasks.md and decision item 20 said some were carried; item 24 supersedes).
- `data-conversions.txt` named an older base SHA in its header; the SHA `verify` uses is `32b2fe2abb` (line numbers are identical at both).

### What review changed (commit `33357994b4`)
- Guard: production rows pinned by identity (`GATED_PROD_GLOBS`) as well as count; the pin's failure text names the right remedy and says not to add a row for a subtree at zero; stale comments and the false "each root is V2-only" sentence corrected; hand-typed `7`s follow `SWEEP_CANARY_COUNT`; the inert hideroot additions dropped; `mktemp -d` in the probe checked; comments for the owner control and the canary-root recipe. `SWEEP_PROBE_CHECKS` still 62 (63 `sweep_probe_fail+=(` occurrences, unchanged).
- `resolve-regenerable-conflicts.test.sh`: the signal helper's parent walk is bounded at the suite's own PID, and the hazard is stated at the helper. A no-kill rehearsal (catch-all match, `kill` replaced by a print) printed the resolver's PID, below the suite's, and nothing when the variable was unset. Unmutated suite: 140/140.
- `playwright-mcp-redact-proxy.test.sh`: header prose reworded (line-count neutral).
- `verify --base 32b2fe2abb`: `verified: 66`, `hand-edited: 7`, `unexplained: 0` (seven listed hand-edit lines in `hand-edits.txt`).

### Matrix re-run on the review commit (scratch clone, green control first, `cmp` landing check, one mutant at a time under `ulimit -v 6000000`, clone restored and clean after every row)
61 rows: 49 killed with the named text, 12 GREEN as predicted, 0 unexpected. Killed: 1a, 1b, 1c, 1d, 2a, 2b, 2c, 2d, 3, 4a, 4b, 5a, 5b, 6a, 6b, 6f, 6c, 6d, 6e, 6g, 6h, 6i, 7, 8, 9a, 9b, 10c, 10d, 11a, 11b, 11c, 11d, 11e, 11f, 13a, 13b, 13c, 14, 14b, 16a, 16b, 19a, 19b, 19c, 20a, 20b, 20c, 20e, 22. GREEN as predicted: 6j, 6k, 10a, 10b, 10e, 13e, 13f, 17, 12, 21a, 21c, 22b. New rows: 22 (a production row swapped for another with the count unchanged: killed by the identity pin) and 22b (the same swap with the pin term removed: GREEN, so the pin is load-bearing); row 20d (hideroot) no longer exists; row 2b now finds its line by content because the review edit moved it.

### Observer mutants on the three shapes the test-design seat said nobody sampled
Scratch clone of the review commit with both `node_modules` linked; controls first, all rc 0. Inversion (`grep -c` to `grep -vc`) of: `redact-sentinel.test.sh` t24 `... && continue` (rc 1, `95 pass, 1 fail`); `linear-fetch/test/parity.test.sh` negated `! ... | grep -cFx` (rc 1, `2 passed, 1 failed`); `bite-proof.test.sh` `head -1 ... | grep -cF >/dev/null '# Fixture project'` (rc 1, `95 passed, 1 failed (96 assertions)`). All three observed. None is the signal helper.

### Cheap lints on the review commit
`lint-shell-capture-exit.py --baseline ...` 0 new findings (224 baselined); `guard-vacuity-floor` 23/0; `lint-orphan-test-suites` none; `fixture-relative-assert` 62/0 and `fixture-dir-operand-assert` 71/0. Shellcheck notes: guard 41 to 44 (the S5 probe additions, same kinds the file already carries), the other two files unchanged.

### Dispositions
Fixed inline: security SEC-1 and SEC-3, agent-native A1 to A4, user-impact UI-1, code-quality 1 to 9 (prose, comments, the false sentence, literals), pattern F1, F2, F4 and F5 (F5 by dropping the hideroot additions), simplicity D4, architecture A2 and test-design T3 (production identity), data-integrity DI-1. Kept (operator direction): `real_plug_row` (item 21). Recorded, not fixed: test-design T1 and T2 (the guard's tail reporter and top-level call have no witness; needs another probe-check occurrence, which moves a pin slices may not edit), T4, structural-enumeration holes (symlinks, force-added ignored paths, pathspec narrowing of docs, `references`, `assets` and `fixtures` subtrees, no canary under `plugins/soleur/test/`), `.md` fences (29 lines), performance F1 and F2 (`suite-durations.tsv` weight and the unenforced 15 s cap), SEC-2 (`/dev/null`), D2, D3, D5, D6 (taste, S6/S7).

### Round 2 (fix round over `0a1c633584..543325a268`; six seats: security, code-quality, pattern-recognition, agent-native, user-impact, test-design; no P1 or P2)
- The bounded walk, the env inheritance into the git pre-commit hook and clean filter, `$$` as the right PID, and the `mktemp` check were verified by the security seat; the production identity pin was independently reproduced closed by the test-design seat (its scenario A red, the pin term removed A2 green, a dropped glob, a dropped newline and a reorder all red).
- Measured by two seats: with `SOLEUR_TEST_SUITE_PID` unset the helper signals nothing, so only the mid-merge row fails and the commit row passes without a witness. The comment said "the rows then fail loudly"; it now says what is true. The PID bound itself cannot be observed inside a namespace (the test shell is PID 1 there); the no-kill rehearsal above is its only evidence.
- Fixed in the round-2 commit: the test-shaped FAIL text now says to delete the row AND its `GATED_TEST_ROWS` line when converting and points at the `Rewrite:` block the verdict prints; the production-rows text and comment say three-place edit, in table order, add/delete/swap/reorder; the comment about a compliant file under each canary root is exact (four older roots); the `mktemp` UNRESOLVED text has a remedy clause; hideroot carries a comment for its five roots; the helper's heredoc carries the PID-bound and PID-namespace note at the match line; `hand-edits.txt` explains its zero-entry header (`verify`: 66 verified, 9 hand-edited, 0 unexplained).
- Correction to the first review addendum's Dispositions line: pattern F5 (the compliant `c.sh` plant loop covers only the four older roots) is NOT closed by dropping the hideroot additions; it is closed by making the planted-comment exact. The "seven listed hand-edit lines" there are four entries covering seven lines; with round 2 it is five entries covering nine.
- Accepted as written: the pin pins globs, not ceilings (raising a file-exact row's `= | 1` is unpinned, as for every row since Pass 1); a helper reparented to a subreaper escapes the PID bound (no row orphans it); FAIL-message prose and the `mktemp` branch are outside every probe check (decision 28).


# Learning: a text-pipe derivation read an annotation echo as a pipe, and a stub drain called a binary its sandbox lacked

## Problem

S7b (#9217, PR #9985) added a producer-side join to `.claude/hooks/grep-q-pipe-guard.test.sh`: it derives every (test suite, stubbed verb) pair where a non-test script pipes `printf|echo|cat` into the verb, and requires a stub for that verb to drain stdin first. Three things went wrong that a green suite and a green first battery did not show.

1. **The derivation reads text, and text includes messages.** After merging main, the pre-push ratchet lane (which tests the branch merged with current main) went red: eleven suites that stub `curl` derived a new pair. The only new producer was three `echo "::error::... printf ... | curl ..."` lines in a workflow, text that shows an operator a command. Nothing in the branch had changed; main's text had.
2. **A drain that never ran.** The `operator-ack-guard` suite's `doppler` stub drained with `timeout 2 cat`, but its checks run under `env -i PATH="$stubdir:$TOOLDIR"`, and `TOOLDIR` links only the binaries the scripts under test name. `timeout` is not among them, so the drain died with `command not found` and the stub still exited unread. The text pin passed, because the text was there.
3. **The guard's own detector and window were satisfiable by shapes that do not drain.** The first battery (30 rows, all as expected) did not mutate the shapes a review then found: `cat < FILE`, a cat on the right of a pipe or behind `true ||`, a non-negated tty test, a drain window that ran into the next definition, a bare `exit` ahead of the drain, the flag token living only in a trailing comment, a verdict sink that printed `FAIL` and exited 0 when its assignment was neutered, and a heredoc writer on an opener line that counted as a drain for wildcard-keyed rows.

## Solution

- Strip the text after an annotation token (`::error::`, `::warning::`, `::notice::`) before scanning for pipes, not the whole line: a pipe that precedes the annotation on the same line is still derived. State the limit that a pipe inside the annotation text is invisible.
- Pin the number of (suite, verb, producer file) triples (`PJ_TRIPLES`) as well as the pairs: a new producer of an already-listed pair then needs a deliberate edit instead of passing silently under an `exempt text-only` row written for the old producer.
- Give the stub a drain spelling that does not depend on the sandbox PATH (`command -v timeout` with a plain-`cat` fallback, or plain `cat` where the pipe always closes), and keep the detector's list of non-draining shapes beside the list of draining ones, each run through the real hazard under both SIGPIPE dispositions.
- Move the table verdicts into one function and drive it with one-row fixtures; pin the verdict sink (the helper that sets the flag, the merge that calls it, the column-0 fold into the suite verdict) by statement-anchored text so a neutered assignment is red.

## Key Insight

A guard that derives its population from text is a function of every file the text lives in, so it can change verdict with no edit on the branch: run it on the tree merged with current main before reading it as green, and make "a new producer for a pair already accepted" its own signal. And a text pin proves a spelling exists, never that the spelling runs where the stub runs: for each stub, ask what the sandbox's PATH holds.

## Session Errors

1. **`pgrep -f` blocked by the self-match hook** — Recovery: used `pgrep <name>` and file-based waits — Prevention: wait on an output file, never on a process-pattern count.
2. **A battery row anchored a string that occurs twice in the guard (H3)** — Recovery: anchored on the definition-finder's own text — Prevention: every mutation helper asserts `count == 1`; a row that cannot land is un-run.
3. **First battery graded M11, M14 and H6 as survivors, and they were real defects** — Recovery: fixed the opener self-match and ran `sh`-tagged spellings under dash — Prevention: a WRONG row is a guard defect until proven a harness defect; read the row before editing the harness. On a host whose `/bin/sh` is bash, an `sh` spelling needs dash to be an `sh` test.
4. **An apostrophe in a comment inside a single-quoted awk program ended the quote** (`opener,: command not found`) — Recovery: reworded the comment — Prevention: no apostrophes in comments inside a quoted program; run `bash -n` and one full guard run after every edit to such a block.
5. **A helper's local variable shadowed the indirect-expansion argument** (`local v="${!1}"` called with the name `v`; the stale list showed untrimmed rows) — Recovery: namespaced the local — Prevention: locals in an indirect-expansion helper take a prefix no caller uses.
6. **A text pin counted its own message and pattern lines** (`grep -c 'PJ_FAIL=1'` returned 5) — Recovery: anchored on the one statement at column 0 — Prevention: count statements, never tokens, in a file that documents them.
7. **The guard's own fixtures derived as stubs** (a printf line naming `.../curl` matched the stub finder) — Recovery: built the fixture line from a split variable — Prevention: a fixture line must not contain the shape the finder reads.
8. **Committed fixes while `test-all.sh --affected` was in flight** (HEAD moved; the run reported 8 failed and 2 killed) — Recovery: discarded the run and re-ran on a stable tree — Prevention: the runner samples the repo boundary twice; land every commit before the run or after it.
9. **First verification seat went quiet for about two hours; I kept waiting on a file that would not appear** — Recovery: read the seat's output-file mtime, resumed it once, then respawned a smaller brief that returned in 7 minutes — Prevention: check the output-file mtime at 15 minutes; a stale one is a stalled seat, not a slow one. The respawn named the hook trap (a command whose text holds the secrets verb is deferred and silently stops the agent).
10. **Ran the full affected gate under `ulimit -v 6000000`** (three suites failed and two were killed with rc 133/134; all passed without the limit) — Recovery: re-ran the three directly — Prevention: the virtual-memory limit belongs on mutation batteries; bun/vitest suites need address space.
11. **Two battery rows did not express their mutation** (N3's fixture was masked by the new exit rule, N15 inserted a different shape than the finding, N22 asserted the wrong direction) — Recovery: re-aimed each and proved N22 both ways (pin 114 passes unmutated, reds mutated) — Prevention: a new row is run against the unmutated tree with its fixture and must pass there.
12. **Evidence prose tripped `lint-infra-no-human-steps.py` in CI** (a suite file name starting with an actor word beside a secrets-CLI token; "verified by hand") — Recovery: reworded two lines — Prevention: run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` before pushing prose under `knowledge-base/project/specs/`; the pre-push ratchet lane does not run it.

## Tags

category: test-failures
module: grep-q-pipe-guard

## Correction 2026-10-12 (#10085)

The first Solution bullet (strip the text after an annotation token, "a pipe inside the annotation text is invisible" as the only limit) is incomplete. S7c's R8 measured that stripping to the end of the line also drops a real pipe AFTER a double-quoted annotation string (`echo "::error::x"; printf '%s' "$B" | jq .` loses the `jq` pipe), and for a single-quoted or unquoted annotation the strip still drops the rest of the line. Strip to the closing unescaped quote of a double-quoted string instead, and read a pipe inside a command substitution in the string as a pipe (the one real instance is `.github/workflows/git-data-rung2-rehearsal.yml` lines 478 and 784). The body above is left as written.

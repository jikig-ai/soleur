# Learning: rerouting a catch-all exit code leaves the universal claims and the class matrix unpinned

## Problem
#11813 (tracker #11667) turned four `*) die 4` arms in `registry-restore-from-ghcr.sh` into
`NOTFOUND|BLOBMISSING) die 4; *) die 6`. The code change was five lines. The review panel (7 seats,
then a targeted round) found its defects in everything around it:

- Prose I wrote said "Every exit 4 is a measured absence, a mismatch or a refused shape". About 30
  `die 4` sites never call `classify()` (jq/parse faults, floor checks), so the sentence was false.
- The runbook's exit-6 row said both "treat a fresh exit 6 as a defect to file" and (new) "a re-run
  is safe", and it contradicted its own row-4 sentence.
- The new `*)` arm also absorbs CLASSIFIED results (CONTENTMISMATCH, LAYERFORMAT) while the message
  said "cannot classify". The engine's own `verify_die` maps those classes to 4, so the same class
  exited 4 at one site and 6 at another, undocumented.
- Tests pinned only UNKNOWN stderr. Widening the exit-4 arm by one class survived 106/106 at 3 of 8
  site-by-class combinations, and deleting NETWORK/DENIED arms (now absorbed by `*) die 6`) survived
  at 6 sites.

## Solution
CTO ruling: classified corruption/format results stay exit 6 at the four read/copy sites (a digest
read never hashes a blob; the copy site matches the image-copy site), the message names the class
(`class: ${cls}`), the header documents it. Every "exit 4 means" claim is now scoped to the sites it
holds for. The full site x class matrix is pinned as `site_case` rows (123 assertions, floor raised
in the same edit); battery rows E45-E52 stay (rc=0, 74 caught / 0 survived).

## Key Insight
Changing what a catch-all arm means changes the meaning of every sentence that describes the
neighbouring arms. Before writing "exit N means X", grep the SUBJECT (`die N`, "exit N", "NOT
retryable") across all sites, not the phrase. Then enumerate the matrix of (site x input class) the
new arm now absorbs and write one row per cell; a mutation seat that widens the sibling arm by ONE
class at a time is the cheapest way to find the empty cells. Both are the same failure: verifying
the instance you edited rather than the class.

## Session Errors
1. **`setsid -n` is not a valid option here** (the brief and my plan carried it) - the first battery launch silently produced nothing. Recovery: `setsid nohup bash -c`, verified the log existed. Prevention: plan/tasks now say `setsid nohup`; confirm the log file exists in the launch call.
2. **A hook blocked a process-name kill/search with the full-command-line flag** - Recovery: used `$!` and the rc/log files. Prevention: already hook-enforced; poll rc files, never process names. (The hook also fired on this learning's own first draft, because the heredoc text contained the flag; the file was written with the Write tool instead.)
3. **A hook blocked `git stash list`** appended to a shellcheck command - Recovery: reran alone. Prevention: already hook-enforced.
4. **The brief named `worktree-manager.sh lease`, which does not exist** - the lease is wired by `SOLEUR_SKILL_NAME`/`SOLEUR_EXPECTED_DURATION_MIN` at `create`. Prevention: verify a named subcommand with `--help` before invoking.
5. **An invalid class label and three `pending - assumed` rows failed the technical-ruling gate** - Recovery: corrected the label; one batched CTO spawn ruled the three rows. Prevention: write rulings, not assumptions, in `decision-challenges.md` at plan time.
6. **Mutation-battery anchor drifted** when the signature-copy message gained `for ${repo}` - caught before running by grepping the E47 anchor against the new text. Prevention: after editing any `die` message, grep the battery for its prefix.
7. **Guessed the assertion floor (125) instead of counting** - the suite reported 120. Prevention: run the suite once, read the count, then set the floor in the same edit.
8. **Affected-test gate deferred (rc=6)** - CI's required `test` context is the gate; no local run was called passed.
9. **Wrote universal claims and a "cannot classify" message that review falsified** (see Problem). Prevention: the Key Insight above.

## Tags
category: logic-errors
module: registry-restore

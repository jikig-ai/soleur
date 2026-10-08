# Learning: a fix that covers the instance, a cap that asks about what it never expands (PR #9653, review fix round 2)

## Problem

The last targeted round of PR #9653 (the W2 destructive-command guard, a bash hook that asks or denies) closed
about forty findings, and the one fresh-eyes verification pass over the fix commits found two more under-asks and
seven smaller defects **in the fixes themselves**:

- `env -C ~ bash -c 'rm -rf ./*'` was made to ask, but the check looked at the first wrapped word only, so
  `env -C ~ sudo bash -c ...` (and nice, timeout, command, env, nohup, busybox in between) still allowed a delete of home.
- sudo's long options were matched by unique prefix (`--us` is `--user`), but `timeout --sig KILL 5 rm -rf ~` and
  `nice --ad 5 rm -rf ~` still shifted the command word. The class was "wrappers with value-taking long options"; the fix was
  applied to the one wrapper named in the finding.
- A 4096-byte word cap (bash's `${p##*/}` and a per-character loop are quadratic in a word's length, and no clock check can
  interrupt one) was applied to **every** word. `gh pr create --body "<5.7 KB>"` and `git commit -m "<5.6 KB>"` then asked,
  and both were allowed before the round. A measurement over the reviewer's own transcripts had found no word over 2 KB,
  which was read as licence, and the ADR cited it as a justification that nobody could reproduce.

## Solution

- Fix the class, not the instance: for "a shell can sit behind a wrapper", read every wrapped word; for "getopt_long accepts a
  unique prefix", apply the prefix rule to every wrapper's value-taking options (env, sudo, timeout, nice, time).
- A cap belongs where the expensive operation runs. The placeholder still replaces every long word (so nothing downstream
  sees 60 KB), but the soft bound is set only for a word the rule table would expand: the command name, any word of an
  rm/cd/wrapper record, a dash word of git/terraform. Prose arguments are neither judged nor asked about. Pin both
  polarities with rows (the prose must not ask; the path must) and neuter each on a copy.
- Verdict-owning helpers (`row()`, `chk()`, `expect_red`, `reason_has`, `rule_last`, ...) need a probe that drives them with an
  input that must fail; the `pass()`/`fail()` probe cannot see a helper that always says ok. And the failure reporter itself
  needs one, written so that a `return` instead of an `exit` is caught (check that code after the call never runs, not the
  exit status).
- A narrowed run (`DCG_ROWS`, `GUARD_HOOK`, `GUARD_FAST_COUNT`) is a developer's tool: refuse it in CI unless the caller
  says it means it, or a stray env var turns a 1200-row gate into a green handful.

## Key Insight

A reviewer-named instance is a sample of a class. Before closing a finding, name the class in one sentence and grep every
consumer of the same input; and before adding a cap, ask which operation is quadratic and put the cap there. The
verification pass exists because the fix commits are the least-audited surface in the diff: here they carried 2 of the
9 defects found in the whole pass.

## Session Errors

1. **Shell cwd reset to the root checkout, and once drifted into `apps/web-platform`.** Recovery: `cd` back. **Prevention:** begin every Bash call in a worktree with an explicit `cd <worktree>`; never rely on a persisted cwd.
2. **The session-start `.mcp.json` restore dirtied the worktree.** Recovery: `git checkout -- .mcp.json`. **Prevention:** run the restore only where the file is meant to change, and check `git status --short` right after session start.
3. **A review seat's transcript was gone, so it could not be resumed.** Recovery: respawned a focused seat with a file-first brief. **Prevention:** persist each seat's report path in the fix brief so a respawn starts from the file, not the transcript.
4. **Edit scripts that asserted an anchor count aborted** (a 10-paren string is a substring of the 15-paren one; a count guessed as 12 was 11). Recovery: replace the longer one first, count before asserting. **Prevention:** replace in descending specificity and print the count before asserting it.
5. **A global replace rewrote my own new assertion** (`${DEADLINE_S} s time limit` inside the row that checks it is absent). Recovery: re-edit. **Prevention:** run any sweep over the pre-edit file list, not over rows you wrote in the same change.
6. **Reduced `DCG_ROWS` selections picked follow-up rows without their producing row and read stale output**, producing spurious FAILs. Recovery: follow-up rows now carry the producer's label prefix. **Prevention:** a follow-up that reads "the last output" must share a selector prefix with the row that produces it.
7. **Bare `> tofu;` rows were vacuous: the prefilter skips them.** Recovery: rows use a quote. **Prevention:** a row meant for the lexer path must contain a boundary character or a keyword the prefilter keeps.
8. **I committed past a shellcheck warning** (the chain used `;`). Recovery: amended the unpushed commit. **Prevention:** chain lint and commit with `&&`.
9. **The mutation-suite probe used baselines the earlier probe had already moved.** Recovery: reset the counters before the probe. **Prevention:** a probe asserts absolute deltas from a reset, never from a shared baseline.
10. **The first word cap asked about prose it never expands**; caught by the verifier, not by my rows (every row I wrote asserted that the cap asks). **Prevention:** for every new refusal write the row that must NOT refuse, from a shape real traffic produces (a PR body, a commit message).
11. **Two fixes covered the instance, not the class** (the shell behind any wrapper; the timeout/nice/time prefixes). **Prevention:** before closing a finding, write the class in one sentence and grep every consumer of the same input.

## Tags

category: logic-errors
module: plugins/soleur/hooks/destructive-command-guard.sh

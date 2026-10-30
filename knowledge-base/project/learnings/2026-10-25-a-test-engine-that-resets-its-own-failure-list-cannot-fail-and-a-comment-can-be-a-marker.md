# Learning: a synthetic-row engine that resets its own failure list cannot fail, and a comment can be a marker

## Problem

PR for #10923 (merge-effect classifier, `Ref #9757`) shipped a parity test whose synthetic matrix (about 40 rows
that each mutate a workflow fixture and expect a named failure) was green by construction. `run_checks()` did
`global FAILS = []` at the top of every call, `synth()` read `FAILS` after the call, and `red()`/`green()` then
restored a saved copy. Every row verdict was therefore thrown away by the next call; only the last row's verdict
survived to the exit code. Changing a row's expected needle to `ZZZNOPE` still exited 0. The author's own
mutation battery and a green 1693-check run both missed it, because every battery row mutated the script under
test, never the engine that reports.

Two sibling defects came out of the same review:

- `crashed()` in the unit suite ended with `...; return 1`, so a crash with rc 127 and any stderr that did not
  match the text patterns was reported as "not crashed" (the `||` short-circuited into the trailing `return 1`).
- The classifier read its input with `while read ... done < file` twice; a NUL byte is dropped silently by
  `read`, so a NUL-joined pair of paths was judged as one concatenated, allowed path.

## Solution

- Make the engine return its failures (`run_checks` returns a list) and give the synthetic rows their own ledger
  (`MATRIX`) that the exit code reads, plus a row-count floor taken from a measured run. A unit row now proves a
  matrix-only failure fails the gate (a copy of the script with the `# mut:widen` marker stripped).
- Give every verdict-owning helper a control that drives it with an input that must fail, requires its failure
  counter to move, then unwinds the counters (`control()` in `merge-effect-class.test.sh`).
- Reject NUL before `read` (`tr -d '\000'` byte-count compare), and make the second pass prove it saw every line
  the first pass saw.
- Derive the tracked-file population from the script (`--filter-allowed`) instead of restating the allowlist in
  Python.

## Key Insight

A harness is a guard, and the parts nobody reviews are its failure plumbing: the global that holds failures, the
helper that decides a verdict, the floor that counts rows. Mutating the code under test cannot reach them,
because the engine reports through them. For any engine that runs N scenarios and reports once, ask: where does
each scenario's verdict go, and what resets it?

A corollary seen twice in this branch: **text in a comment is still text to a counter.** A header comment
saying "`# mut:widen` is read by the parity test" raised the marker count from 1 to 2 and broke the test that
counted markers with `src.count(...)`. Count markers with a line-anchored regex, and keep markers on their own
single line.

A third: a test that asserts a markdown sentence with `grep -F` breaks when the sentence wraps. Keep each quoted
sentence on one line in the document, or the anchor silently turns into a false failure on the next reflow.

## Session Errors

- **Review worktree directory disappeared mid-panel (cause not established).** Recovery: `git worktree prune` and
  `git worktree add` on the existing branch; nothing was lost because the branch and PR were pushed.
  **Prevention:** push before spawning the panel (already required) and re-check `pwd`/`git branch --show-current`
  after the panel returns.
- **Parity test exceeded the 120 s foreground limit on its first run.** Cause: an uncached glob compile and the
  pure-Python YAML loader over 94 workflows. Recovery: `functools.lru_cache`, `CSafeLoader`, memoised loads.
  **Prevention:** time a new suite once detached before registering it.
- **Marker-count test broke on a comment** (see Key Insight). Recovery: line-anchored regex.
  **Prevention:** count markers by a line-anchored pattern.
- **Wrapped markdown sentence defeated a `grep -F` anchor.** Recovery: one sentence per line.
  **Prevention:** when a test asserts prose, put the asserted sentence on a single line.
- **`MATRIX_FLOOR` counted before its own row.** Recovery: floor set to the value at check time.
  **Prevention:** take a floor from the count at the line that asserts it, not from the final summary.
- **A PATH shim named `python3` tripped the pipe-guard's stub detector.** Recovery: a `MEC_PYTHON` seam.
  **Prevention:** inject the interpreter through a variable instead of shadowing it on PATH.
- **A review seat hit the account's weekly rate limit.** Recovery: the seat was resumed with `SendMessage`
  after the limit cleared. **Prevention:** none needed beyond resuming rather than respawning.
- **Stop hook caught a future-tense closing line.** Recovery: ended with a `Paused:` sentence naming the wait.
  **Prevention:** end a waiting turn with the label and the one thing waited on.

## Tags

category: test-failures
module: plugins/soleur/test, plugins/soleur/scripts

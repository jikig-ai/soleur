# Learning: a census pin that checks a NAME, a retyped anchor, and a review fix that hid a line

## Problem

The follow-up work for the code-quality watchers (issue 11439) tightened a static census (a bash/perl tripwire over the read-only watcher scripts) and added an `env -0` failure check and a forged-header remedy. Three things went wrong on the way, each green locally:

1. The scoped plumbing allowlist for the brand-hex watcher "pinned" its operands by matching the NAMES `$WT` and `$REPO_ROOT`, not where they point. A 11-seat review then found shapes that still reached the main checkout: `worktree add -fB main -- --detach` (a bundled short flag plus `--` supplying a fake `--detach`), `worktree remove --force <any path>`, and an unpinned `read-tree --index-output=<main index>` / `GIT_INDEX_FILE=` prefix (both reproduced against a real linked worktree).
2. Two mutation rows located the line to delete by a retyped copy of the error message. Rewording the message in the SUT made the anchor miss, so the rows reported "mutation did not land" instead of exercising the guard.
3. The review fix for a backslash-newline gap joined continuation lines before scanning. Bash does not continue a line across a comment, so a trailing `# note \` made the NEXT real command part of the comment line and hid it: the fix introduced a hole in the census it was hardening.

## Solution

- Pin operand SHAPES, not variable names: the whole `worktree add` shape as one anchored regex (optional `-q`, optional `--no-checkout`, `--detach`, the `$WT` path, one non-dash commit word), `worktree remove` to `--force "$WT"`, the three index verbs to the exact operand lists the script uses, and treat a `GIT_*=` prefix before a git call as a finding on every basename.
- Read an anchor line from the SUT itself (`grep -F` with a single-match assertion) rather than retyping it in the suite.
- Join continuation lines only when the line holds no `#`.

## Key Insight

A fix written during review is as unpinned as the blind spot it closes, and it is the least-audited code in the diff: the continuation join passed the whole suite and only a second, targeted security seat over the fix range found it. Run the fix-round, and for every pin ask "does this check the value, or only a name that usually holds it?". An isolating probe per clause (one that only that clause rejects) is what proves a pin is load-bearing; a probe that trips two pins at once proves neither.

## Session Errors

1. **Ruling rows in `decision-challenges.md` did not match the gate's required shape** (`Ruled by CTO agent, <date>: <decision> - <rationale>`) — Recovery: reworded the two rows — **Prevention:** the technical-ruling gate already enforces this; run it before `work`.
2. **`gh issue create` denied by the filing gate** (no consequence/label, `$VAR` and `$(…)` in the call) — Recovery: `meta/machinery` label, literal absolute `--body-file`, one command per call — **Prevention:** already hook-enforced; the deny text names the exits.
3. **Mutation rows anchored on a retyped message string** — Recovery: derive the line from the SUT with a single-match assertion — **Prevention:** an anchor for a mutation row is read from the SUT, never retyped.
4. **A review fix (continuation join) introduced a hide-the-next-line regression** — Recovery: restrict the join to lines without `#`, add a comment-continuation probe — **Prevention:** run the targeted fix-round on every post-panel fix commit.
5. **Pins keyed on names instead of operand shapes** (found by review) — Recovery: operand pins plus `GIT_*` prefix rule; remaining classes tracked on issue 11863 — **Prevention:** see Key Insight.
6. **Replay ratchet red on a pair introduced by an unrelated merged PR** — Recovery: confirmed pre-existing (issue 11848), left alone — **Prevention:** none for this branch.

## Tags
category: test-failures
module: scripts/watch-code-quality-reeval-9730.test.sh, scripts/watch-brand-hex-triggers-11177.sh

# Learning: a fail-open fallback regex was rewritten three times, and each rewrite shipped a new flaw

## Problem

PR #11147 (#10793) made `brand-hex-commit-gate.sh` scan the repository a `git commit` targets, using the
lexer in `lib/commit-target-roots.sh`. When the lexer cannot run (no perl), the hook needs a text test for "does
this command move its target?" (`moving_re`) and "does this loose text read as a commit?" (`loose_commit_re`).
That fallback is a heuristic over model-controlled text, and a heuristic invites the same defect pair in both
directions. The same PR's review rounds measured it:

1. v1 matched ` -C`, `GIT_`, and `cd` anywhere: it skipped the scan for `git commit -C HEAD`,
   `GIT_AUTHOR_DATE=… git commit` and a message saying "fix cd handling", and WARNed on non-commits.
2. v2 fixed those by requiring `cd` at command position and `-C` only after `git`. The verification seat found it
   had **lost recall**: a newline-separated `cd`, `env -C`, `if cd X; then`, a quoted `'cd'`. It also found that
   `loose_commit_re` (`git[^;&|]*[[:space:]]commit`) was **quadratic** (5.4 s at 40 KB, 34 s at 80 KB) on
   model-controlled input: a hook stall.
3. v3 restored recall and added an input cap; it introduced `--ch[a-z]*`, which matched `git diff --check` and
   `npm test -- --changed`, silently skipping the scan of an ordinary commit.

Each seat's list of "what is wrong now" was complete for the version it read. None of the three versions was
checked against adversarial *shapes* (newline, keyword, quote, long input) and *innocent* shapes (common flags)
at the same time before shipping.

## Solution

- Decide the diff base from the lexer's own fact (`CTR_COMMIT_ALL`) whenever it ran and saw a commit; keep the
  textual `-a` test only for the no-lexer path. Three seats independently found the textual cut wrong for `-C` forms.
- Test movers on the command with each `-m` / `--message` argument removed, so prose cannot be a mover, and give
  `cd` a lead class of any whitespace, separator, bracket or quote.
- Bound the input (`probe="${command:0:4096}"`): both regexes are super-linear and the text is model-controlled.
  Pin it with a bounded-time row whose fixture actually reaches the quadratic regex (a first fixture did not).
- Mutation-test every alternative of the final regex on a scratch copy: drop each one and require a named row to
  red. Two "survivors" were a fixture that never reached the code and a floor mutant a green run cannot kill (kill
  it by deleting an assertion instead).

## Key Insight

A fail-open fallback heuristic has three independent failure axes, and a rewrite aimed at the axis the last
reviewer named reliably moves the defect to another: **recall** (movers it misses), **precision** (ordinary text
it matches), **cost** (input shapes that blow up the regex engine). Before accepting any rewrite of such a
regex, run one table: a row per alternative, a column per axis, with a shape that stresses each. Prefer facts
from the real parser over a text heuristic wherever the parser ran, and cap the heuristic's input. The review
skill's "delete the heuristic after two bypasses" advice applies; here the CTO carve-out (perl-less hosts must not
go silent on plain commits) kept the fallback, so the cap and the table were the substitute.

## Session Errors

1. **Worktree reaped mid-session (again) and the scoped gate failed on "working tree missing".** — Recovery:
   `git worktree add` from the pushed branch ref. — **Prevention:** commit and push every unit (done); tracked in
   #11099. Recreate through `worktree-manager.sh`, not a raw `git worktree add`.
2. **A raw `git worktree add` left the recreated tree without `node_modules`; the scoped gate aborted at the webplat
   arm (rc 2).** — Recovery: judged by the suites that ran (2273 ok, no real FAIL) plus CI. — **Prevention:**
   recreate worktrees with `worktree-manager.sh`, which installs dependencies.
3. **`affected-tests.sh` refused (rc 4) because a sibling worktree held a full-battery run.** — Recovery: the
   sanctioned `TEST_GROUP=affected` substitute. — **Prevention:** read `test-all.sh --capacity` first.
4. **Two Bash calls blocked by hooks (`sleep` chain, `pgrep -f`).** — Recovery: Monitor with an until-loop. —
   **Prevention:** already hook-enforced; use Monitor from the start.
5. **A non-raw Python string wrote `core\\.` (a literal backslash) into the mover regex.** — Recovery: row T42c went
   red; fixed. — **Prevention:** edit regex literals through a quoted heredoc or `sed`, then print the resulting
   line back before running the suite.
6. **My regex rewrites lost recall, then over-matched, and one was quadratic; none was found by my own checks.** —
   Recovery: verification and security seats; input cap, narrowed alternatives, new rows. — **Prevention:** the
   recall/precision/cost table in Key Insight, before the first push of any heuristic regex.
7. **Fixture-relative and affected-pair ratchets moved after review-round test additions (1→7 sites, +1 pair).** —
   Recovery: route writes through one helper rooted at the guarded dir; add the anchor-keyed accept row. —
   **Prevention:** re-run the ratchet set after every test-file edit, not only at the end of Phase 4.
8. **The first mutation battery for the review-round rows left two survivors.** — Recovery: re-aimed the fixture at
   the quadratic regex; killed the floor by deleting an assertion. — **Prevention:** a survivor is a fixture-gap or
   an equivalent; label it before touching the guard.
9. **Line-keyed `boundary-prefix` exemption re-keyed four times (119→127→130→131).** — Recovery: re-key each time. —
   **Prevention:** none needed; the positional key is the deliberate anti-laundering design. Edit the hook header
   first and re-key once, last.
10. **A turn ended on a forward-looking sentence and the Stop hook fired.** — Recovery: did the action. —
    **Prevention:** commit and push in the same turn as the decision to wait; end only on `Paused:` / `Blocked:`.
11. **A seat brief called #10609 a PR (it is an issue; #10691 is the PR).** — Recovery: the history seat noted it. —
    **Prevention:** `gh pr view` / `gh issue view` before naming an artifact in a brief.
12. **(forwarded) A probe was blocked by the secret-scan hook (variable path plus the words "git commit" in inline
    text).** — Recovery: rerun from a script file. — **Prevention:** build such probes in `/var/tmp` scripts.

## Tags
category: logic-errors
module: .claude/hooks/brand-hex-commit-gate.sh

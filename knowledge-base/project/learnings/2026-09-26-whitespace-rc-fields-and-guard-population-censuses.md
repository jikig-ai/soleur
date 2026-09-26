# Learning: whitespace-delimited counter records cannot carry optional middle fields — and a shape-anchored guard is always a subset

Two findings from the `--rows` suite-split work (#8864, PR #8967), one per file
family it touched.

## Problem

**(a) Field collapse.** The battery's worker→parent channel writes
`echo "$PASS $FAIL $DECLARED $ELAPSED" > row.rc`, then `read -r _p _f _d _t`.
When `DECLARED` was unset the line became `4 0 0  87` — `read` splits on
whitespace *runs*, so `_d` picked up `87` (the elapsed) and the failure
reported "hollowed row" when the true defect was "undeclared field". A
mutation test (drop the declaration) caught it, but only because it ran — the
shape passed eyeball review twice.

**(b) Guard population subset.** The first tiling extractor matched only
`run_suite "…" bash <file>.test.sh --rows` lines. The structural-enumeration
seat's map showed every non-line-start, eval'd, glob-loop, non-bash, or
sourced-lib registration shape — plus the precedent battery's own
`foo-mutations.sh` filename convention — left the checked population silently.
Anchoring harder doesn't fix this class; the extractor will always be one
grammar behind the runner's expressiveness.

## Solution

(a) Never leave an optional middle field empty in a whitespace record — write
a non-numeric sentinel (`UNSET`) so the arity can't shift and the reader's
numeric check reports the true reason. The alternative orderings (fixed-width,
TAB-separated, JSON) all cost more than the sentinel.

(b) Pair every shape-anchored extractor with **census arms in both
directions**:

- *literal census:* count `--rows A-B` occurrences in the whole file
  (comment-stripped) and require the count to equal the extracted set —
  anything the anchor can't see becomes a count mismatch, not a silent miss.
- *declaration census:* grep the suite-bearing trees for every file-scope
  `DECLARED_TOTAL=` and require each file to be reachable by one of the
  tiling arms (run_suite argv or the ci.yml `rows:` run step) — catches
  batteries registered through channels the extractor never parsed.

Also closed this PR: `run_M*` function↔`ROW_IDS` parity (a defined-but-
unlisted row runs nowhere while `_site_seq` stays consistent), and the
distinct-legs pin reads the runner's *enumerated* legs (`leg_*` files) rather
than the TSV table — the realized assignment includes hash-fallback and
manifest-disengagement states the table can't express.

## Key Insight

An extractor that enumerates "the shapes I expect" silently degrades as the
host file grows new spellings. The durable pattern is: extract what you can,
then assert the *remainder is empty* — a census over the corpus, not a schema
over the shapes. Same inversion as anti-vacuity floors: never trust that you
saw everything; prove nothing was missed.

## Session Errors

1. **Empty `.rc` middle field shifted ELAPSED into the declared slot** —
   caught by mutation B-MUT2 only after the first verdict mislabeled it.
   **Prevention:** always write a non-empty sentinel for optional middle
   fields in whitespace-delimited records; mutation-test the missing-field
   path, not just the wrong-value path.
2. **Ran a battery mutation against a stale scratch copy** — refreshed the
   `/tmp` backup but executed the old `scripts/zz-mut*.test.sh`; the first
   verdict measured the pre-fix file.
   **Prevention:** regenerate the scratch from the live file in the same
   command (`cp live scratch && mutate scratch && run scratch`), never
   across separate tool calls.
3. **`grep -l` over a possibly-empty file list would have read stdin** —
   caught pre-run.
   **Prevention:** route file lists through an array + `${#arr[@]}` guard
   (or `xargs -r`) before feeding grep.
4. **First tiling verdict mislabeled a zero-flagged battery as "mixed
   contract"** — arm ordering put unflagged>0 ahead of ranges==0.
   **Prevention:** order classifier arms most-specific-first; a "0 beside N"
   state deserves its own message.
5. **`pgrep -f` self-match blocked by tool policy** — one-off; used the
   sanctioned `list_runs`/`kill_mine` path.
   **Prevention:** none needed — the policy hook is the control working.
6. **Push rejected after the rebase rewrote branch SHAs** — routine;
   `--force-with-lease` on the session's own draft-PR branch.
   **Prevention:** expect it after any mid-flight rebase; use
   `--force-with-lease`, never plain `--force`.

## Tags

bash, test-harness, shard, mutation-battery, extractor, guard, census,
whitespace-parsing, review-panel, #8864

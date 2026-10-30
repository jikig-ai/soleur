# Learning: a scan of a decoded value must run AFTER the shape check, or the scan itself is the denial of service

## Problem

PR #10970 (WikiSkill pattern layer, Ref #8293) loads human-written pattern pages and sends their title, summary
and tags to a model. Round 1 found that the PII regex ran over the RAW YAML text while the model receives the
DECODED scalar, so `"mail ops\x40example.test"` passed the scan and reached the prompt. The fix scanned the
decoded fields as well, written as `[title, summary, ...tags.map(String)]` and placed BEFORE the tags shape check.

`tags.map(String)` stringifies whatever YAML produced. A ~440-byte page of nested anchors
(`&a1 [*a0, *a0, ...]` nine wide, nine deep) is cheap to parse (gray-matter shares references) and expands to
9^N leaves when stringified: 3.2 s at depth 8, 17.9 s at depth 9, then a thrown `RangeError: Invalid string
length`. The throw was outside the loader's `try`, so ONE page aborted the whole `collect-patterns` step. The
16 KiB page cap does not bound it, because the page is tiny; the expansion is the cost.

Eight round-1 seats and the lead's own mutation battery all passed this. The structural-enumeration seat found
it, because its job is to map every path that touches untrusted text, not to attack one.

## Solution

- Move the decoded-field scan after every shape check, so only validated strings (printable ASCII, length
  capped, `TAG_RE`) are ever joined and tested (`compound-promote-patterns.ts`).
- Cap evidence entries per page (40): each is a file read plus a PII-scanned excerpt.
- Pin the order with a spy: a nested-alias page returns `schema` and the PII regex has been called exactly once
  (the raw-text scan), because the decoded scan is never reached. A wall-clock assertion would be flaky; a call
  count is not. Verified by moving the scan back above the shape check: the test reds.

## Key Insight

Normalising or decoding hostile input before validating its shape hands the attacker the expansion step. Order
the pipeline: bound size, validate type and shape, THEN decode, scan and stringify. A scan that is "defence in
depth" is still code that runs on the input, and a thrown error inside a loader that has no per-item catch turns
one bad item into a failed run.

A second, smaller lesson from the same PR: a repo-wide census (`test/github-url.test.ts`, every
`octokit.request(` must take a literal route) failed on the ledger's pass-through adapter
`octokit.request(route as never, ...)`. No file-selected suite covers a repo-global ratchet, so only the
combined-tree gate saw it. A route-checking adapter that refuses every route but the one it needs, and then
calls with a literal template, satisfies the census and is stricter.

## Session Errors

1. **The worktree directory was reaped twice mid-session** (the shell cwd vanished). Recovery: `git worktree
   prune`, `git worktree add .worktrees/<branch> <branch>`, relink `node_modules` from a sibling worktree.
   Prevention: none new; keep the branch pushed before spawning long panels so a reaped worktree costs only a
   re-add.
2. **A safety hook refused `rm -rf hooks` inside a sandbox working directory** (it resolved onto a protected
   checkout) and blocked the whole command, so no mutation ran. Recovery: remove single files with `rm -f` and
   let `soleur-sandbox.sh rm` delete the tree. Prevention: never `rm -rf` a relative path from inside a
   sandbox; name files.
3. **A multi-edit Python batch aborted atomically on a non-unique anchor** and applied nothing. The assertion
   did its job; the cost was one re-run. Prevention: anchor each replacement on a line unique in the file.
4. **`git push | grep -v remote:` returned grep's exit status**, which read as a failed push. Recovery:
   `git fetch` then compare `rev-parse HEAD origin/<branch>`. Prevention: judge a push by the ref comparison,
   not the pipeline status.
5. **The 13-seat panel's `Reviewed-By-Soleur` trailer was never emitted on the branch**, found only when the
   fix-round trailer was about to be written. Recovery: emit the main trailer, then the `--fix-round` one.
   Prevention: before any fix-round trailer, `git log origin/main..HEAD --format=%B | grep Reviewed-By-Soleur`.
6. **The affected-tests gate printed `budget-deferred` (no verdict) but its logs held real failures**, one of
   them mine (the egress census). Prevention: read the per-suite logs for `FAIL` lines even when the gate
   verdict line says deferred, then classify each by whether the diff touches the failing file.
7. **Three unrelated gate failures** (a CLA roster date check and two tombstone-census tests that need full
   docs history) appeared on the combined tree; none involve files in the diff. Recorded, not fixed here.

## Tags

category: logic-errors
module: apps/web-platform/server/compound-promote-patterns

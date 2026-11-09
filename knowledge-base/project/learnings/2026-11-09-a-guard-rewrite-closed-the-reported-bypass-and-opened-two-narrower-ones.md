# Learning: a guard rewrite closed the reported bypass and opened two narrower ones

## Problem

PR #12485 (Ref #9600) closed git config-execution through auto-approved `git log|diff|show|status`. The issue asked for a
`--ext-diff` denylist. A real-git falsifier showed a flag denylist cannot work: with a planted repo-local config, bare
`git status`, `git diff` and `git show HEAD` already run a helper (`core.fsmonitor`, `diff.external`, textconv,
`filter.*.clean`, `gpg.program`), and a bare repository COMMITTED into an untrusted repo is a carrier after a plain
clone. Three controls shipped: an env pin (`safe.bareRepository=explicit`), a `.git` file-tool guard, and a closed flag
grammar.

## Solution

See the PR and the ADR-050 2026-11-09 amendment. What this learning records is how the review loop behaved:

1. The first panel (12 seats) found a P1 the author could not see from inside the diff: pinning
   `GIT_CONFIG_GLOBAL=/dev/null` for every session removed the image's fallback commit identity, so a Start-Fresh
   workspace could no longer `git commit`. Three seats converged. Fix: an image-owned identity-only gitconfig that
   `GIT_CONFIG_GLOBAL` points at (a `GIT_CONFIG_COUNT` identity would override real workspace identities, because command
   scope beats local config).
2. The first-panel fix to the `.git` guard (a one-pass kernel-order resolver, replacing a `realpath`-the-deepest-ancestor
   helper) fixed the reported dangling-symlink bypass and was itself narrower than its predecessor in two ways the
   predecessor did not have: a `..` after a missing component skipped the symlink that followed it, and a symlink whose
   NAME contains a backslash was never looked up because the walk split on `\` as well as `/`. Both were found by the
   fix-round seats, not by the author's tests, and both existed only because the rewrite judged ONE reading of the
   path (the kernel's) where the old code judged another (lexical). Fix: judge both readings and deny if either hits.
3. A verification seat then ran a 200,000-path differential fuzz of the final guard against a real-filesystem oracle
   (where would the write actually land?) and found no escape. That is the instrument that would have caught (2) a
   round earlier.

## Key Insight

**When a fix REWRITES a guard rather than extending it, grade the rewrite against its predecessor, not only against the
finding.** The finding's repro passes by construction; what regresses is every input the old code handled by
accident. Cheapest form: keep the old implementation as a test oracle for one run (or a reference function in the
test), run both over the old suite's rows plus a generated corpus, and require `new denies ⊇ old denies` except for
named, reviewed over-denials. A second, independent oracle (the real filesystem: create the file, see where it landed)
is stronger still.

Related, same session: a security PR's ADR/plan prose carried three claims that review falsified in minutes
("git ignores a bare dir" — it dies with a fatal; "sandbox-contained, not cross-tenant" — five host-side git consumers
run in the tenant workspace with server env; "after symlink resolution" — true only for the kernel reading). Each had a
one-command falsifier; none was run when the sentence was written.

## Session Errors

1. **The technical-ruling gate failed on the first plan file** (CPO-attributed and `pending - assumed` rows). Recovery:
   one batched CTO spawn plus reshaping two lead-brief rows. **Prevention:** a planning subagent that records a ruling
   must use the `Ruled by CTO agent, <date>:` shape from the first write; the gate's shape is documented, and the plan
   skill should emit it.
2. **Two Bash calls ended with the shell in the bare repo root** (a `cd ..`-style path error, then a tool-state reset),
   producing a "no such file" read of a log and a stray cwd. Recovery: re-`cd` to the worktree with an absolute path in
   the same call. **Prevention:** already covered by `hr-when-in-a-worktree-never-read-from-bare`; chain
   `cd <abs-worktree> && <cmd>` in every call (done after the second slip).
3. **A new test file tripped the repo-wide containment ratchet** (`repo-wide-containment`) because a fixture spelled
   `"m1/m2/../../x"` and `"../.git"` literally; the sibling test avoids this with a `const UP = ".."`. It was caught by
   the combined-tree run, not by the file's own suite. **Prevention:** after adding a test file under
   `apps/web-platform/test/`, run `test/repo-wide-containment.test.ts` with it (the ratchet counts a property across the
   tree and references no file, so a file-selected run cannot see it).
4. **Test D's first oracle claimed flags were "inert" that were not** (`--no-ext-diff`, `--no-textconv`, `--no-color`
   executed a helper on a patch-producing diff). The author's own real-git test falsified the author's grammar; the
   flags were removed and the rule restated as "adds no channel the bare verb lacks". **Prevention:** an admission rule
   must name its baseline; the test must compare against the bare verb, not against "nothing".
5. **Test fixtures and plan prose asserted behavior never measured:** a hand-copied pin literal in the real-git fixture
   (could drift from the shipped pin), a "pinned env refuses the bare dir" comment (it dies, not ignores), a `printenv`
   probe offered as proof the identity file is readable. **Prevention:** import the shipped constant; run the command
   that falsifies each added sentence (the existing rule, applied late).
6. **`rm -rf` on a scratch directory under `/var/tmp` was blocked by the protected-location hook**, aborting the whole
   command; a review seat's `/tmp` sandbox was left behind for the same reason. Recovery: re-ran without the `rm`.
   **Prevention:** `mktemp -d` sandboxes under the session scratchpad, which needs no cleanup approval.
7. **Collision pre-check exited 10** because other worktrees were running `test-all.sh`. Reported and continued; the
   hits were other issues' runs, not a duplicate of this work. **Prevention:** none needed (the hook's message was
   accurate); the one-line report is the contract.

## Tags
category: security-issues
module: apps/web-platform/server (git-carrier-guard, safe-bash, agent-env, permission-callback)

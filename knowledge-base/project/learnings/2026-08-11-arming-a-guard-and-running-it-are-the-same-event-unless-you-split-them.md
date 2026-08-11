---
date: 2026-08-11
category: logic-errors
module: git-worktree / session-state
issue: 7409
pr: 7426
tags: [destructive-operations, guards, mutation-testing, marketplace-install, tautology, rollout]
---

# Arming a destructive guard and running it are the same event unless you split them

## Problem

`worktree-manager.sh` resolved its lock/lease library by walking five directories up
to `.claude/hooks/lib/session-state.sh` — a path that exists only in the Soleur repo.
The marketplace ships `./plugins/soleur` alone, so for **every installed user** the walk
missed, no-op stubs loaded, and the entire concurrency layer was absent. `create` never
acquired a lease; `cleanup-merged` failed closed and reaped nothing.

The fix is small and boring: move the library inside the plugin, resolve it
`$SCRIPT_DIR`-relative. What was not boring was everything the fix implied.

## The insight

**A change that makes a safety mechanism *functional* also makes everything that
mechanism gates *reachable*. If the gated thing is destructive, the first correct run is
a bulk run.**

Pre-fix, an installed user's `is_lease_active` was the stub that returns "active" for
everything, so `cleanup-merged` refused to reap *anything, ever*. Post-fix the real
predicate runs — and every worktree already on that user's disk was created by a `create`
that could not acquire a lease, so **none of them can hold one**. `cleanup-merged` runs at
session start. So the first post-upgrade session would have swept the entire accumulated
backlog in a single pass: worktree removed, local branch deleted, remote branch deleted
(which closes the PR), and any gitignored file taken with it — `git status --porcelain`
does not list ignored paths, so a worktree holding only `.env.local` reads clean and the
reap's `--force` retry deletes it anyway.

Every one of those reaps might be individually correct. That is what makes the class hard
to see: there is no bug to find. The objection is not correctness, it is that **arming the
capability and exercising it in bulk were the same event**, so the user's first notice of
the feature would have been its aftermath.

The plan had already recorded "this PR arms the reaper" and tested the *refusal* direction
in a cache layout with a mutation arm. That covers the steady state and says nothing about
the transition — the one state every user passes through exactly once.

**Generalise:** when a change makes a previously-inert guard live, ask *what is the
population it now applies to, and what state is that population in on day one?* If the
answer is "a backlog that structurally cannot satisfy the guard", the transition needs its
own handling.

### The fix, and why the obvious shape is wrong

A one-time dry pass per store: report what would be reaped, emit
`SOLEUR_WORKTREE_REAPER_ARMED`, delete nothing, stamp the store.

The stamp is the load-bearing part. The intuitive design is a **condition-based** hold —
"hold while the lease store is empty" — and it is wrong in a way that only shows up later:
a machine whose sessions run `cleanup-merged` but never `create` never writes a lease, so
the condition never clears and the reaper is **permanently inert**. That is a worse failure
than the bulk reap, and it is silent. A hold needs an exit condition it controls itself.

## What review found, and the pattern in it

Eleven agents, report-only. They found **more defects in the PR's guards than in the fix**
— 9 P1. That is not an accident: a PR whose subject is a safety mechanism has its
dangerous surface in the *verification*, where a bug fails open and certifies the broken
thing as fine.

Four are worth naming because each is a documented class that recurred anyway:

**1. A proof-of-red pinned to a moving ref consumes its own fix.** The old/new interop
scenario recovered its "pre-move library" fixture from `origin/main`. That works for
exactly as long as the PR is unmerged; the moment it lands, `origin/main` *is* the new
tree, the lookup returns empty, and the suite fails permanently on main for every branch
cut from it. It fires when the rollout **succeeds**. The fixture's own comment defended the
empty lookup as anti-vacuity — loudness with no expiry is not a regression detector. Fixed
by pinning the immutable blob SHA (reachable from history forever), FAIL under CI where
full depth is contractual, skip locally where a blobless clone is ordinary.

**2. An expected set derived from the artifact under test is a tautology — and I shipped
one while fixing that exact class.** Three agents found that the A1 membership assertion
matched `*/lib/session-state.sh` from *any* root, so dropping a different root kept it
green. I made it per-root, ran the mutation — and it **survived**, because my "expected"
roots were the array the walk itself uses. Deleting an entry shrinks both sides. The fix is
an independently-pinned literal list. I would not have caught this by reading; only by
mutating my own fix.

**3. A marker asserted present-when-expected and never absent-when-not.** Hoisting the
`..._LIB_OK` echo above its own `if` — making it unconditional — left the entire suite
green while the marker claimed protection was on with the layer absent. For a signal whose
whole purpose is making silence unambiguous, on a population whose only observability is
their own terminal, that is the worst possible direction to fail in.

**4. Adding a second copy of a command broke a consumer that extracted "the" one.** The
degrade-open snippets put `gh pr merge <number>` in the command twice (locked arm + else
arm). `pre-merge-rebase.sh` extracted the PR number with an unbounded grep, so it yielded
`"7409\n7409"`, the search phrase became `"PR #7409\n7409"`, and the review-evidence gate
denied on PRs that *have* evidence. A hook broken by prose, invisible to every test.

## Session Errors

1. **Scenario 10's fixture never used the cache root it was testing.** Written as
   `CLAUDE_PLUGIN_ROOT=X bash "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…"` — a
   command-prefix assignment populates the command's environment, but every expansion on
   that line is performed first, against the current shell. It silently took the default
   arm and the run failed with `No such file or directory`, while the negative assertion
   below it still reported `pass`. **Recovery:** `export` on its own line, plus a
   precondition that fails if the anchor did not resolve to a real script.
   **Prevention:** for any test of a `${VAR:-default}` anchor, assert the resolved path is
   the one intended — a negative assertion that passes when the command never ran is not a
   test.

2. **My own fix for a tautology was a tautology.** See #2 above. **Recovery:** mutation
   caught it; pinned the required set as independent literals. **Prevention:** for every
   `∀ x ∈ S` guard, ask where `S` comes from — and if it comes from the thing being
   checked, the comparison is `S == S`.

3. **`MIN_ASSERTIONS` set to 36 against a 35-assertion suite** (off-by-one when adding one
   assertion). **Recovery:** the floor failed loudly and I corrected it. **Prevention:**
   derive the floor from a green run's printed count, never from arithmetic in your head.

4. **A cardinality assertion counted prose, not invocations.** `grep -c 'gh pr merge'`
   returns 12 in `ship/SKILL.md` because the file *discusses* the command. The assertion
   false-failed a correct file. **Recovery:** removed the leg and recorded why, rather than
   silently dropping it. **Prevention:** before asserting a count over a doc file, print the
   count — prose mentions and code occurrences share a token.

5. **Committed during a running full-suite.** The first run was launched against a clean
   tree, then I committed four times while it executed, making its 288/289 a measurement of
   no single tree. **Recovery:** clean re-run against a pinned SHA with no edits.
   **Prevention:** the exit gate describes the tree you launched it against; if an edit
   cannot wait, kill the run rather than reinterpreting its output.

6. **A `python3` edit script had one wrong path, so *both* its edits silently no-op'd** —
   including an import change, which then made a follow-up `sed` a no-op too. **Recovery:**
   the vitest run failed on the missing import. **Prevention:** the script already asserted
   `count == 1` per anchor; the failure was that an assertion error aborts *before* the
   file write, so earlier successful replacements in the same script are lost. Write each
   file's edits in their own script, or assert all anchors before mutating any.

7. **A vestigial `git stash list` in a probe command was denied by the guardrail hook**,
   taking the whole compound command with it. **Recovery:** removed the line, re-ran.
   **Prevention:** the hook is correct; a read-only-looking `git stash list` is still
   `git stash`.

8. **The first `Monitor` script exited 1** — `grep -c … || echo 0` can emit two lines, so
   `$((n - last))` got malformed input. **Recovery:** `| head -1` plus a `${n:-0}` default.
   **Prevention:** the same two-line-count shape had already produced a visibly wrong
   `"0\n0 failing"` progress line earlier in the session and I did not generalise from it.

9. **Did not anticipate that relocating the file made it a new entrant for a
   changed-files-scoped lint.** `lint-trap-tempfile-ownership` rule (c) is scoped to files
   changed vs the merge base, so moving the library made a pre-existing `mktemp` leak newly
   mine. **Recovery:** annotated with the real reason — an `EXIT` trap is documented-harmful
   in this specific file, because `create_worktree` acquires the lease and registers its
   trap in the same shell that exits normally on success, so arming one would re-introduce
   the release-on-success bug. **Prevention:** when moving a file, ask which lints are
   diff-scoped; a move is a change to every line.

10. **The `mktemp` annotation I wrote to explain #9 contained a false claim.** It said
    INT/TERM/HUP were "already covered by the multi-signal trap; only SIGKILL reaches this
    window". No trap is armed there at all — it is registered by the *caller*, after the
    function returns — and its body releases `<name>.lease`, never `<name>.lease.XXXXXX`.
    **Recovery:** corrected; the consequence claim was right, the mechanism claim was not.
    **Prevention:** a comment explaining why a guard is absent is itself a claim; the
    reviewer who checked it (`data-integrity-guardian`) read the trap's registration site,
    which I had not.

**Forwarded from `session-state.md` (plan phase, pre-compaction):** six defects found in
the plan itself before implementation — a vacuous AC (`expected_duration_min=240` is the
default at both layers), an AC that would have failed a correct implementation, a
non-bulleted threshold line that would have hard-failed `/soleur:preflight` Check 6, an AC
that went red on a file the plan never listed, two factually wrong rationale grounds, and a
misclassification of `acquire_lease` as advisory.

**Not attributable:** `.claude/.rule-incidents.jsonl` shows 766 deny/bypass rows since
branch init, but the file is repo-global and three sibling worktrees ran concurrently; 506
are `hr-all-infrastructure-provisioning-servers`, and this diff touches no infra. I am not
claiming those as this session's.

## Prevention

- When a change makes an inert guard live, enumerate the population it newly applies to and
  the state that population is in on day one.
- Separate arming from exercising with a **self-clearing** mechanism (a stamp), never a
  condition that the normal workflow may never satisfy.
- Mutate your own review fixes, not just the original code. Two of mine were wrong and both
  were caught that way, not by reading.
- On a guard-building PR, spawn the panel **report-only** and apply every fix yourself from
  a known SHA — with a fix-inline default and ten concurrent agents, one agent reads
  another's uncommitted edit and reports it as already-fixed.

## Tags

category: logic-errors
module: git-worktree / session-state

---
module: git-worktree
date: 2026-08-06
problem_type: workflow_issue
component: soleur-go
tags: [worktree, concurrent-sessions, branch-safety, data-loss, brainstorm]
severity: high
---

# An empty worktree is not an abandoned one

## Problem

A brainstorm session routed via `/soleur:go` found an existing worktree,
`.worktrees/feat-alpha-onboarding-motion`, whose name matched the session's
topic. Every available signal said "abandoned scaffold, safe to reuse":

- exactly one commit, `chore: initialize feat-alpha-onboarding-motion`
- that commit sat directly on top of current `main`
- `git status --short` was completely clean
- an open draft PR titled `WIP: feat-alpha-onboarding-motion`
- the name matched the session's topic

The session reused it. It was in fact a **live concurrent session** working a
different feature — the alpha-onboarding validation record and per-tester
runbook (#7329), not the KB blueprint manifest (#7332).

Consequences:

1. The concurrent session hard-reset the branch (`reset: moving to b63bab198`),
   **discarding commit `4943757d7`** which held this session's brainstorm doc
   and spec.
2. Both sessions wrote `knowledge-base/project/specs/feat-alpha-onboarding-motion/spec.md`.
   The other session's spec overwrote this one at the shared path.
3. A spawned `ux-design-lead` agent had its `.pen` files destroyed mid-task and
   had to recover them from a dangling commit.

## Root cause

**An empty worktree and a just-created worktree are indistinguishable from
commit count and working-tree cleanliness.** Both present as one initialize
commit and a clean status. The signals that felt like evidence of abandonment
are actually evidence of *recency* — which is the opposite conclusion.

The existing `/soleur:go` guards did not fire, and could not have:

| Guard | Keys on | Why it missed |
|---|---|---|
| NAME-relative worktree detection | a `SOL-\d+` Linear ID in the user input | input had no Linear ID |
| Worktree-plan-vs-issue alignment | a `#N` issue ref in the user input | input had no `#N` |
| Step 1 worktree context | whether `pwd` is *inside* a worktree | CWD was the bare root |

All three are input-keyed or CWD-keyed. None evaluates a **name-matching sibling
worktree** when the input is free prose. A brainstorm entered as a plain-English
request — the single most common entry shape — has no guard at all.

## Solution

Two discriminators, both cheap, either of which would have caught it:

```bash
# 1. Is the existing draft PR recently active?
gh pr view <n> --json updatedAt,createdAt,author
#    A PR updated minutes ago is a live session, not an abandoned one.

# 2. Does any artifact under that worktree's name target a DIFFERENT issue?
grep -rl "closes\|issue:" <worktree>/knowledge-base/project/specs/*/spec.md
grep -l "#[0-9]" <worktree>/knowledge-base/project/plans/*
#    A spec whose frontmatter names another issue is a different feature.
```

Recovery, once the reset had already happened:

```bash
# The discarded commit survives in the reflog even after a hard reset.
git reflog                                   # find the orphaned SHA
git show <sha>:<path> > /scratchpad/file.md  # extract each file
git archive <sha> <dir> | tar -x -C /scratchpad/  # or a whole subtree

# Then attach a worktree to a NEW branch and replay.
git worktree add .worktrees/feat-<new> feat-<new>
```

## Key insight

**Never reuse a worktree whose draft PR exists but whose topic you did not
create.** Create a sibling branch instead. An extra worktree costs a few hundred
milliseconds and some disk; two sessions racing one branch costs discarded
commits, destroyed binary artifacts, and silent path collisions between
unrelated specs.

The generalization beyond worktrees: **when a state could have been produced
either by abandonment or by recency, "it looks untouched" is evidence for
recency, not for abandonment.** Ask what a *live* actor in that state would look
like before concluding the actor is gone.

## Prevention

- Add a name-match probe to `/soleur:go` Step 1 that runs regardless of whether
  the input carries a Linear ID or `#N` — the two existing guards are
  input-keyed and leave free-prose entry uncovered.
- Treat an open draft PR on a candidate worktree as a **liveness signal**, not a
  leftover. Check `updatedAt` before reuse.
- Never let two features share a `specs/feat-<name>/` directory. The spec path is
  derived from the branch name, so branch reuse silently aliases spec paths.

## Session Errors

1. **Reused a concurrently-active worktree.** Recovery: recovered
   `4943757d7` from reflog, extracted files to scratchpad, attached a worktree to
   the already-split `feat-kb-blueprint-manifest` branch, replayed. Prevention:
   the name-match probe above.
2. **Wrote the spec into the other feature's spec directory.** Recovery:
   `git mv` to `specs/feat-kb-blueprint-manifest/`. Prevention: consequence of
   #1; fixed by not sharing the branch.
3. **`worktree-manager.sh feature kb-blueprint-manifest` failed** with
   `fatal: a branch named 'feat-kb-blueprint-manifest' already exists` — the
   branch had already been split off by the concurrent session's recovery
   attempt. Recovery: `git worktree add <path> <existing-branch>` instead of
   `feature`. Prevention: one-off; the script has no "attach to existing branch"
   mode, which is correct behavior.
4. **FR numbering collision** — appended an `FR12` when `FR12` already existed.
   Recovery: `grep -n "^\*\*FR"` caught it, renumbered to FR13. Prevention:
   one-off; grep before appending a numbered requirement.
5. **A domain leader returned a wrong load-bearing claim.** See
   [[2026-08-06-read-the-generated-artifact-not-the-generators-spec]].
6. **Playwright MCP server disconnected mid-session.** No impact — no browser
   work was in flight. Prevention: none needed.

## See Also

- [[2026-08-06-read-the-generated-artifact-not-the-generators-spec]]
- `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`
  — the adjacent failure mode: a concurrent `cleanup-merged` sweep wiping an
  *unpushed* branch. This learning is its mirror image: a concurrent session
  wiping a *pushed* one.
- `knowledge-base/project/learnings/workflow-patterns/2026-05-19-worktree-recovery-check-pr-merge-status-first.md`

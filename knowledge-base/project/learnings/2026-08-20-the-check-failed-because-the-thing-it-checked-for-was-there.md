---
title: The check failed because the thing it checked for was there
date: 2026-08-20
category: workflow-issues
module: plugins/soleur/skills/git-worktree/scripts
tags: [sigpipe, pipefail, shell, grep, worktree, fail-open, guard-vacuity, test-isolation, fixture-size]
related_issues: [7498, 1932]
related_prs: [7646]
related_learnings:
  - knowledge-base/project/learnings/2026-04-18-worktree-manager-silent-registration-failure.md
  - knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md
---

# Learning: the check failed because the thing it checked for was there

## Problem

`/soleur:go 7498` could not get past worktree creation. `worktree-manager.sh create`
checked out all 13,815 files, then reported

```
SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=unregistered branch=feat-one-shot-7498-vitest-project-split
Error: Worktree directory exists but is not registered after repair
```

and deleted the worktree it had just built. A plain `git worktree add` of the same
path worked and showed up in `git worktree list` immediately.

## Root cause

`worktree-manager.sh` runs under `set -euo pipefail`, and asked "is this line in the
porcelain listing?" the obvious way:

```bash
git worktree list --porcelain | grep -qxF "worktree $worktree_path"
```

`grep -q` exits at the **first match** and closes the pipe. If the needle is not near
the end of the listing, `git` is still writing, takes **SIGPIPE**, exits 141, and
`pipefail` promotes 141 to the pipeline's status. The test therefore reports ABSENT
**precisely when the needle is present and early**.

```
rc=141                    (141 = SIGPIPE)
no-pipefail EARLY: MATCH
pipefail    EARLY: NOMATCH
```

An instrumented run made it explicit: the entry *was* at line 49 of 120, and the same
`grep -qxF` still said no.

## Why it read as flaky rather than broken

Porcelain order follows `.git/worktrees` readdir order, not creation or alphabetical
order. So whether a given branch name breaks is effectively arbitrary — and stable per
name. `feat-one-shot-7498-vitest-project-split` landed at slot 49 and failed **100% of
the time**; a probe worktree created seconds later landed last and passed. Two runs,
opposite outcomes, same code, no race visible to the operator. It presented as
infrastructure flakiness, which is the most expensive way for a deterministic bug to
present.

The scale dependency matters too: this only became reachable as the worktree count
grew. With a handful of worktrees git finishes writing before `grep` can quit.

## The second, worse consequence

The same idiom guarded a **destructive** path. `heal_stale_branch` opens with:

> A branch checked out in ANY worktree is ACTIVE, not a stale orphan — never heal it.

That guard is **fail-open**: a false negative falls through to
`git push origin --delete "$branch"`. So a live session's remote branch gets deleted
exactly when it appears early in the listing. The local prune below it is annotated
*"the not-checked-out condition is already guaranteed by the early return at the top"* —
one guard's correctness was load-bearing for another's safety, and the SIGPIPE broke it.

A regression arm demonstrates it: with the piped idiom restored, `heal_stale_branch`
deletes `origin/wt1` while `wt1` is checked out in a live worktree.

## Fix

Capture first, match second — no pipeline, so no reader that can quit early:

```bash
_porcelain_has_line() {
  local needle="$1" listing
  listing="$(git worktree list --porcelain)" || return 2
  [[ $'\n'"$listing"$'\n' == *$'\n'"$needle"$'\n'* ]]
}
```

Verified equivalent to `grep -qxF` over 10 cases including glob (`*`, `[e]`) and regex
(`.`) metacharacters and substring near-misses — the quoted `"$needle"` inside the
pattern is literal.

Tri-state on purpose: **0 = present, 1 = absent, 2 = listing unreadable.** A caller
gating a delete must distinguish "absent" from "could not tell"; `heal_stale_branch`
now requires a definite `1`.

## Transferable rules

1. **`producer | grep -q` is unsafe under `pipefail`.** It fails when the match is
   early — the opposite of the intuition that an early match is the easy case. Anywhere
   a script sets `pipefail` and pipes a multi-line producer into a short-circuiting
   consumer (`grep -q`, `head -n1`, `read`), capture to a variable first.
2. **A fixture too small to fill the pipe buffer cannot reproduce it.** ~14 lines of
   porcelain fit in the 64 KiB buffer, git exits before the consumer closes, and the
   **buggy script passes**. An earlier revision of this suite went green against the
   unfixed code for exactly that reason. The regression test pads the listing past
   64 KiB with a stub `git`, converting a timing lottery into a deterministic arm. When
   a bug depends on a producer still being live, the fixture must *make* it still live.
3. **When one guard's comment says another guard already guarantees a precondition,
   both are one bug.** Grep for that phrasing during review of a destructive path.

## Drive-by found on the way

Four `worktree-manager-*.test.sh` suites were not isolated from the operator's git
config and failed `rc=128` on any machine with `commit.gpgsign=true`: fixture
`git commit` fails, and `git clone` then only **warns** "you appear to have cloned an
empty repository". The arms go red for a *missing fixture* while reading as genuine SUT
failures — which cost real time in this session before the cause was spotted. They
already unset every `GIT_*` var, so a caller-supplied override is wiped; the exports
have to come *after* that loop.

**A warning that should have been an error is how a broken fixture becomes a false
verdict about the code under test.**

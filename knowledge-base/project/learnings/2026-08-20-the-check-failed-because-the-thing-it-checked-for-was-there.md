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

## Second incident, same session: the gate committed into the real repo

Running `scripts/test-all.sh` from inside a worktree put four synthetic commits
onto **real branches** — `victim change`, `victim2 change`, `v9 change`,
`v12 change`, author `t <t@t>`, files `a.txt`–`d.txt` — and switched the worktree
onto `main`. Local `main` gained three of them; the feature branch gained one.
`origin` was untouched and no other worktree was harmed, but nothing in the run
said so: the gate exited 1 with its log **deleted**, and the only visible symptom
was that a fix verified minutes earlier had vanished from the working tree.

Chain:

1. The run was launched with `TMPDIR=/var/tmp`.
2. `test-all.sh` runs suites in parallel, and one of them sweeps stale tmp
   directories. It deleted a sibling suite's **live** fixture mid-run — and the
   gate's own log, which is what made the failure unreadable.
3. `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` runs
   `set -uo pipefail` **without `-e`**, and builds its fixture with errors
   suppressed (`git worktree add … >/dev/null 2>&1`).
4. With the fixture gone the guarded `cd` failed, execution continued, and the
   following `git commit` calls ran **in the current directory** — the real repo.

Run in isolation with CWD pointed at a throwaway repo, the same suite is
**40/40 green and pollutes nothing**. The bug is not in the assertions; it is
that the suite's writes are only correct while its `cd` is.

### Rules

1. **A test that runs `git commit` without `-e` is a loaded gun aimed at `$PWD`.**
   Fixture setup whose failure is suppressed, plus no `set -e`, means every
   subsequent write lands wherever the shell happens to be. Either `set -e`, or
   make each mutation absolute (`git -C "$fixture"`), so a lost `cd` cannot
   redirect it. Never let a suite's write target be implicit.
2. **A sweeper and a fixture must not share a directory.** `TMPDIR=/var/tmp`
   put live fixtures where a parallel sweep suite cleans. Pick a fixture root
   the sweep cannot reach, or make the sweep age-gate on the *run*, not the file.
3. **A gate that deletes its own log cannot be diagnosed.** Write the log
   somewhere the suites under test do not clean; here `/var/tmp` erased the
   only evidence and left `GATE_EXIT=1` alone in a 12-byte file.
4. **Recover with `git update-ref`, not `reset --hard`.** The shared root
   carried 10 staged changes and 127 untracked files belonging to other
   sessions. Moving the branch ref restored `main` and touched neither.

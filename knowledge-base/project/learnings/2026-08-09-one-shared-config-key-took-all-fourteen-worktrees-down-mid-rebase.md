---
date: 2026-08-09
issue: "#7332"
pr: 7336
category: workflow-issues
tags: [git, worktrees, rebase, generated-artifacts, exit-status, session-errors]
---

# One shared config key took all fourteen worktrees down mid-rebase

Session errors from resuming #7332 / PR #7336. The first is infrastructure and cost the
most time; the rest are a family — **things that only became visible once history moved.**

## 1. `extensions.worktreeConfig` wedged every worktree at once

Mid-rebase, every git write command started failing:

```
fatal: this operation must be run in a work tree
```

`git rev-parse --is-inside-work-tree` returned `false` **from inside the worktree**, whose
`.git` file and `gitdir`/`commondir` pointers were all intact.

**Mechanism.** The shared bare-repo `.git/config` had gained
`extensions.worktreeConfig = true` while every linked worktree's
`.git/worktrees/<name>/config.worktree` was **0 bytes**. Enabling that extension makes git
read `config.worktree` per worktree; with those files empty, nothing overrode
`core.bare = true` from the common config, so all **14** worktrees inherited "this is a
bare repo" simultaneously. The config's mtime landed inside the session window.

**This repo already classes that key as harmful.** `#4826`,
`apps/web-platform/server/worktree-config-seed.ts` (whose load-bearing step is
`git config --unset-all extensions.worktreeConfig`), and the regression guards in
`apps/web-platform/test/workspace.test.ts` all exist for it. But that heal is scoped to
**Concierge workspace provisioning** and never runs against an operator's local bare repo.

**Recovery** (both halves, deliberately):

```bash
git config -f "$BARE/.git/config" --unset-all extensions.worktreeConfig
# belt-and-braces: a re-add cannot re-break them
printf '[core]\n\tbare = false\n' > "$BARE/.git/worktrees/<name>/config.worktree"
```

The second half matters more than the first. Unsetting alone restores the status quo, but
leaves 14 worktrees one stray `git config` away from the same outage; writing
`core.bare = false` is what git itself does when provisioning a bare repo's worktrees, and
it makes the extension's presence harmless either way.

**Attribution is a hypothesis, not a fact.** A sibling `/ship` session was running
concurrently in another worktree, and it was one of only three whose `config.worktree` was
already non-empty — consistent with a session that healed itself by enabling the extension
and broke everyone else. Recorded as evidence, not as a finding.

**Prevention:** verify `git rev-parse --is-inside-work-tree` before trusting a worktree,
and treat a repo-wide `.git/config` write as a blast-radius-14 action. A local-bare-repo
counterpart to the `#4826` heal would close it mechanically.

## 2. Rebasing a stacked branch replays commits that already merged

The branch was cut on top of `feat-alpha-onboarding-motion`, whose 8 commits had since
merged as the **squashed** #7328. `git rebase origin/main` tried to replay all 8 and
conflicted repeatedly — each conflict an add/add against content main already had.

The fix is to rebase only the branch's own commits:

```bash
git rebase --onto origin/main <last-commit-of-the-borrowed-prefix> <branch>
```

**Prevention:** before rebasing, check whether the branch's merge-base ancestry contains
another feature's commits (`git log --oneline $(git merge-base HEAD origin/main)..HEAD`).
A squash-merged parent is invisible by SHA and only recognisable by *subject*.

## 3. Dropping merged commits exposed a deletion that had been hidden

The branch had **deleted** main's `feat-alpha-onboarding-motion/spec.md` as part of reusing
a worktree for a new feature. That deletion was invisible while the commits that *created*
the file were still in the branch's own history — the two cancelled out. Rebasing dropped
the creating commits as already-merged, and the deletion stood alone: the PR diff showed a
file main legitimately owns going to `/dev/null`.

**Prevention:** after any `rebase --onto` that drops commits, diff the result against the
base and read the **deletions** specifically:

```bash
git diff --name-status origin/main...HEAD | grep '^D'
```

## 4. A generated artifact must never be conflict-resolved by picking a side

`model.likec4.json` conflicted with **1149** `"id"` occurrences on main and **1163** on the
branch, and **neither was a superset** — both sides had legitimately regenerated it from
their own `.c4` sources. Choosing either produces an artifact matching neither source tree,
and `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs it against a fresh render,
so it would have failed on first CI run.

**Re-derive, never merge:** `bash scripts/regenerate-c4-model.sh`.

## 5. Editing a source file silently staled its generated derivatives

The layer-7 edit to `observability-coverage-reviewer.md` left `.grok/agents/*.md` and
`plugins/soleur/.claude-plugin/agents.manifest.json` stale. `grok-inspect-contract.test.ts`
caught it — but only on the **first full local suite run**, because the PR had been a draft
throughout and no `pull_request` workflow had ever run on any of its 40+ commits.

**Prevention:** after editing a file with generated derivatives, run the repo's own
regenerator and its `--check`. A draft PR buys review time at the cost of *all* CI signal;
run the full suite locally before marking ready.

## 6. I read a wrapper's exit code as the suite's verdict

The suite was launched as `bash scripts/test-all.sh > log 2>&1; echo "EXIT=$?"; tail -30 log`
and reported **exit code 0** — which was `tail`'s status, not `test-all.sh`'s. The run
actually ended `269/271` with two `[FAIL]` shards.

This is the same class as the lint shipped in this PR
([[2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint]]):
**a status read from a position where it cannot survive.** It is recorded because it
happened *while capturing the learning about it*, and because the failure mode is a false
green — the most expensive direction.

**Prevention:** make the status the last thing the command yields, or read the summary line
rather than the exit code. `269/271` was in the log the whole time.

## Key insight

Four of these six were invisible until something **moved** — a rebase, a squash-merge, a
concurrent session, a first CI run. Cancelling pairs (a create and a delete), stale
derivatives, and inherited config all read as correct right up until the thing they
depended on shifted underneath. After any history rewrite, re-derive what is generated and
re-read what was deleted; do not assume the diff you reviewed is the diff you now have.

## Related

- [[2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint]]
- [[2026-08-06-an-empty-worktree-is-not-an-abandoned-one]]
- [[2026-08-06-read-the-generated-artifact-not-the-generators-spec]]

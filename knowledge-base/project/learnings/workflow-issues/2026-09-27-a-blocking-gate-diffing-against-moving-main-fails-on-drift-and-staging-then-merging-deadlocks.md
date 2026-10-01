---
module: Development Workflow
date: 2026-09-27
problem_type: workflow_issue
component: development_workflow
symptoms:
  - tests/scripts/infra-privileged-tier-census failed G4c on a .tf resource my diff never touched
  - Commit rejected by the gate until origin/main was merged, but `git merge` refused over 43 overlapping staged files
  - eslint baseline counted a return-inside-finally (no-unsafe-finally, new rule) and an unused import
root_cause: config_error
resolution_type: workflow_improvement
severity: medium
status: open
tags: [test-all-affected, merge-drift, git-apply-3way, commit-gate, infra-census, worktree]
---

# Troubleshooting: A blocking gate diffing against moving `main` fails on drift — and staging then merging deadlocks

## Problem

The lefthook `bun-test` commit gate runs `test-all.sh --affected`, which diffs **HEAD
against the moving `origin/main` tip** — not the merge-base. Between my feature merge and
the review-fix commit, main gained `apps/web-platform/infra/web-host-birth-environment.tf`
with a `github_repository_environment_deployment_policy` resource. The census' Guard 4c
("every resource the base ref declares and HEAD no longer declares must have a `removed`
block") read main's new resource as an orphan my branch deleted → gate red → commit
rejected.

The recovery had its own trap: `git merge origin/main` refuses to run while 43 of my
staged files overlap the merge's file set, and `git stash` is forbidden in worktrees.

## Environment

- Module: `scripts/test-all.sh --affected` + lefthook `bun-test` hook
- Date: 2026-09-27 (PR #8904, ~6h of wall time across three commit attempts)

## Symptoms

- `[FAIL] tests/scripts/infra-privileged-tier-census` — `orphans=['apps/web-platform/infra github_repository_environment_deployment_policy.web_platform_infra_apply_main_adopted']`
- `error: Your local changes to the following files would be overwritten by merge:` listing all 43 staged files.
- Contention preamble: `test-all` runs in 6-8 sibling worktrees serialize on one advisory lock — each gate run is a ~2-2.5h wall wait.

## What Didn't Work

**Attempted Solution 1:** Commit the fix batch, then merge.

- **Why it failed:** the census's base is `origin/main` tip — the orphan is present until
  the merge lands, so the gate fails first. Ordering was inverted.

**Attempted Solution 2:** `git merge` over the dirty tree.

- **Why it failed:** merge refuses to update any file with local (staged) changes; the
  43-file overlap between my batch and main's drift made a dirty merge impossible. `git stash` is banned by `hr-never-git-stash-in-worktrees`.

**Attempted Solution 3:** Check overlap with `git diff --name-only` (unstaged).

- **Why it failed:** my changes were STAGED (`git add -A`), so the unstaged diff is empty —
  the check was vacuous and reported zero overlap. Use `git diff --cached --name-only`.

## Solution

Patch-checkpoint → reset → merge → reapply. Merge commits skip the `bun-test` battery
(`skip: - merge` in lefthook.yml — the merge gate is separate), so the merge lands cheaply
and the fix batch's commit then runs the battery on a HEAD that contains main's `.tf` files.

```bash
git diff --cached --binary > /tmp/batch.patch   # index lines enable --3way
git reset --hard HEAD
git merge --no-ff origin/main                  # resolve taste-profile.md union
git apply --3way --index /tmp/batch.patch      # 49 clean, 4 direct-fallback
npx tsc --noEmit && targeted vitest            # verify reapplication
git commit                                      # gate re-runs, now green
```

## Why This Works

1. The census (and likely sibling guards) is correct by design: it measures the PR as it
   would land. A branch behind main simply reports drift it can't distinguish from deletion
   — the remedy is currency, not a waiver.
2. `git apply --3way` uses the patch's index lines to reconstruct a merge against blob
   objects instead of context lines — far fewer rejects than plain `git apply` over a moved
   target.

## Prevention

- On a long-lived feature branch, before a commit that will hit the affected battery:
  `git fetch origin main && git merge-tree --write-tree HEAD origin/main` — a conflict-free
  read of what the gate will see. If main moved into your paths, merge FIRST.
- When you can't stash and merge refuses: `git diff --cached --binary` checkpoint +
  `git apply --3way` is the sanctioned substitute.
- Overlap checks between staged work and a merge head must diff `--cached`, not the
  working tree.
- Budget two gate-hours per commit on this box: 6-8 sibling worktrees share the advisory
  lock; consolidate review fixes into as few commits as possible.
- `no-unsafe-finally`: never `return` inside a `finally` — restructure as a guarded block.
- `happy-dom` lacks `window.confirm`/`window.alert` — use `vi.stubGlobal`, not `vi.spyOn`.
- React effect races in tests: `findByRole` resolves before mount effects flush; a
  mount-effect `setState` can land after the query and wipe interactions — `await act(async () => {})` before simulating.

## Related Issues

- The code-level findings from the same session:
  ../logic-errors/2026-09-27-resolution-is-not-terminality-and-a-zombie-episode-can-kill-the-retry.md
- Sibling gate-drift learnings: `2026-09-21-a-conflict-starved-merge-ref-reads-as-ci-never-ran.md`,
  `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md`

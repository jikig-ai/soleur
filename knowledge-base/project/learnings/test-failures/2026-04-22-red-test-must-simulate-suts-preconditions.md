---
name: RED test must simulate SUT preconditions, not just assertion shape
description: A negative-space assertion can pass vacuously if the SUT's buggy code path cannot fire in the test harness — the harness must preseed every precondition the bug requires
type: test-failure
date: 2026-04-22
related_pr: 2828
related_issue: 2815
tags: [tdd, bash-tests, test-fidelity, red-verification, worktree-manager]
---

# RED test must simulate SUT preconditions, not just assertion shape

## Problem

Issue #2815: `worktree-manager.sh create_for_feature()` was creating spec dirs at `$GIT_ROOT/knowledge-base/project/specs/$branch_name` (bare repo root) instead of inside the worktree. Fix is a one-line `$GIT_ROOT` → `$worktree_path` swap, paired with a guard update.

The first version of the regression test (`plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh`) set up a synthetic bare repo via `git clone --bare` and asserted:

- Test 1: `[[ -d "$worktree_spec" ]]` — expect true (FAILED, correct RED)
- Test 2: `[[ -d "$bare_spec" ]]` — expect false (PASSED, **wrong** — passed vacuously)

Test 2's pass was a false confirmation: the buggy code at line 439 had `if [[ -d "$GIT_ROOT/knowledge-base" ]]` as a guard before `mkdir -p`. In the synthetic `git clone --bare` repo, no `knowledge-base/` directory exists at the bare root, so the guard short-circuited and `mkdir -p` was never called. The bug couldn't manifest — making Test 2's "no spec at bare root" assertion meaningless.

In the real soleur repo, `knowledge-base/` *does* exist at the bare root (created by previous runs of the buggy code itself), so the guard passes and the bug fires every time. The test failed to replicate this.

## Solution

Seed the synthetic bare repo with the directory the SUT's guard requires:

```bash
git clone -q --bare "$TEST_DIR/seed" "$TEST_DIR/bare.git"

# Simulate real-world bare repo state: knowledge-base/ sits at the bare root
# as a stale on-disk copy (originally created by the pre-fix code path itself).
# Without this, the current buggy `[[ -d "$GIT_ROOT/knowledge-base" ]]` guard
# silently skips spec creation in the synthetic test bare repo, masking the bug.
mkdir -p "$TEST_DIR/bare.git/knowledge-base/project/specs"
```

After the seed, RED produced 4 failures (Test 1 missing-at-worktree + Test 2 present-at-bare-root + Test 3 idempotency × 2). After the GREEN fix, 4 passes — and meaningfully, because Test 2 now exercises the path the bug actually traverses.

## Key Insight

`cq-write-failing-tests-before` / the work-skill TDD Gate already says: "the test must distinguish gate-absent from gate-present." That covers assertion shape — the `expected vs actual` pair must collapse if the SUT's guarded path is removed.

This learning extends that rule to **test-environment fidelity**: the harness must preseed every precondition the SUT requires to enter the buggy code path. If the SUT has a guard like `[[ -d "$X" ]]` (or `if (user.exists)`, or `if (cache.has(key))`), and the buggy code is *inside* the guard, the test must seed `$X` (or the user, or the cache entry) — otherwise both buggy and fixed code short-circuit identically and the negative-space assertion passes vacuously.

The rule of thumb: before declaring RED, walk the SUT's control flow from entry to the bug. For each branch/guard, confirm the test sets up the conditions to take the same path the bug-triggering production case takes.

## Tags

category: test-failure
module: worktree-manager / shell-tests
subcategory: test-environment-fidelity
related-rule: cq-write-failing-tests-before
related-learning: 2026-04-18-red-verification-must-distinguish-gated-from-ungated.md

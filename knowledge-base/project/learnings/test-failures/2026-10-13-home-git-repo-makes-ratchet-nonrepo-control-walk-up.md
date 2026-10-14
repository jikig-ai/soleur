---
title: "A git repo at HOME makes the ratchet non-repository control resolve"
date: 2026-10-13
category: test-failures
module: scripts/pre-push-ratchet-lane.sh
issues: [10233]
---

# HOME as a git repo false-reds fixture-dir-operand-assert

## Problem

`scripts/pre-push-ratchet-lane.sh` pins `TMPDIR` to `$HOME/.cache/soleur/tmp/prepush-lane.*/lane-tmp` so a member temp dir does not sit inside the lane scratch worktree. That stops the temp dir from resolving as the scratch repo. It does not stop `git rev-parse` from walking further up. When `$HOME` itself has a `.git`, the non-repository control in `plugins/soleur/test/fixture-dir-operand-assert.test.sh` exits 0 and names `$HOME/.git`. The floor then fails (69 passed, floor 71) on every branch, including `main`.

## What was measured

On 2026-10-13, `/home/jean/.git` existed and `git -C /home/jean rev-parse --is-inside-work-tree` printed `true`. The lane log `.git/ratchet-lane/20261013-180856-fixture-dir-operand-assert.log` reported:

- `FAIL: GUARD 3 pre/control: a non-repository resolved as a repository (/home/jean/.git)`
- `FAIL: GUARD 3 pre/control: failure text did not name the condition: /home/jean/.git`

The branch diff at that run was only npm manifests and lockfiles. The test file matched `origin/main`.

## Prevention

- Treat a red `fixture-dir-operand-assert` that names `$HOME/.git` as this environment, and confirm the test file is unchanged versus `origin/main`, before calling it a regression.
- The fix is `GIT_CEILING_DIRECTORIES` on the lane `env -i` allowlist, set to the lane temp directory, so discovery cannot walk into `$HOME`. Tracked in #10233. Do not "fix" it by deleting `$HOME/.git`.

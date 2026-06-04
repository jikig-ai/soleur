# Learning: `chmod +x .claude/hooks/*.sh` flips tracked file modes — scope it to the script under test

## Problem

While hardening `test-pretooluse-hooks.yml` (issue #4818), Phase 0 of `/work` needed
`prod-write-defer-gate.sh` executable to run live probes. I ran the workflow's own
idiom verbatim:

```bash
chmod +x .claude/hooks/*.sh
```

The glob touched **every** hook script, flipping `.claude/hooks/incidents.test.sh`
from `100644`→`100755`. Git tracks the executable bit, so that mode change appeared
as a modified file in `git status` / `git diff origin/main...HEAD` — an out-of-scope
entry that violated the PR's AC7 ("diff touches ONLY the workflow file"). The diff
content was a pure mode change (`old mode 100644 / new mode 100755`), no byte change.

## Solution

Restore the mode on the file the change does not own:

```bash
git checkout .claude/hooks/incidents.test.sh   # reverts the 100644→100755 mode flip
```

Then re-verify scope: `git diff origin/main...HEAD --name-only` should list only the
intended files.

## Key Insight

When a probe/test needs ONE script executable, `chmod` exactly that script —
`chmod +x .claude/hooks/prod-write-defer-gate.sh` — not the `*.sh` glob. The CI
workflow can safely `chmod +x .claude/hooks/*.sh` because the ephemeral runner's
working tree is never committed; an operator worktree IS committed, so a glob chmod
silently widens the diff. If a glob chmod already happened, `git checkout <file>` on
each unintended path restores the tracked mode (cheaper than `git update-index
--chmod=-x`, which also works but is less obvious).

## Session Errors

1. **`chmod +x .claude/hooks/*.sh` flipped `incidents.test.sh` mode (100644→100755),
   producing an out-of-scope diff entry.** — Recovery: `git checkout
   .claude/hooks/incidents.test.sh`. — Prevention: scope `chmod` to the single script
   the probe needs (`chmod +x .claude/hooks/prod-write-defer-gate.sh`), or restore
   modes after probing. The CI workflow's `chmod +x .claude/hooks/*.sh` idiom is safe
   only because its runner working tree is never committed.

## Tags
category: best-practices
module: git-worktree, hooks
related: [[2026-06-02-env-default-flip-breaks-implicit-ci-consumer]]

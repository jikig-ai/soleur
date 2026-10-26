---
title: Discover recovery helpers before probing and preserve each command verdict
date: 2026-10-26
category: workflow-patterns
module: codex-recovery
---

## Problem

Recovery exploration guessed several helper paths that did not exist, attempted
to read a directory as a file, and used a diagnostic line window beyond EOF.
The latter raised `IndexError` while identifying a scanner finding without
printing its value. Chaining subsequent successful reads hid those failures
behind the shell's final exit code. A mise `gh` shim also attempted installation
in the restricted filesystem, as the existing same-day CLI learning describes.

## Prevention

Discover names with `rg --files`, check the object type, and read the discovered
path. Bound diagnostic slices by the available line count. Keep independent
commands' exit statuses separate; inspect stderr even when the outer command
returns zero. Use the installed GitHub binary from the existing CLI learning
and request sandbox escalation for actual network or lock-file restrictions.
The same restriction applies to synthetic suites using `/var/tmp`: rerun their
exact command with escalation, rather than treating fixture setup failure as a
test result.

The focused protocol run also exposed stale pre-existing nonce-free success
fixtures and non-discriminating rejection fixtures. Ref issue #11221: a valid
base frame must satisfy every other required field before mutating one field.
The recovery ran those fixtures RED before updating them, then verified missing
and malformed nonce rejection alongside the valid cases. Strict runtime schemas
were preserved.

A later commit was refused as main/master even though `pwd`, branch and Git
top-level all identified the recovery feature worktree. The installed harness
guidance already documents the missing-envelope-CWD failure mode. Pass the
absolute worktree through `git -C` so the guard inspects the intended branch;
do not disable or bypass the main-branch guard.

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

For the later collector hardening, the npm cache held the package tarball
object but not the registry packument; `npm pack --offline` therefore failed
with `ENOTCACHED`. Do not turn that into an implicit online install. Fetch only
the exact lockfile URL after network approval, verify the tarball's SRI against
the committed lock, and extract/import only those verified bytes. The focused
Vitest fixture also hit sandbox `EPERM` when it spawned synthetic tar/git
helpers; rerun the exact local suite with subprocess escalation rather than
counting fixture setup errors as test results.

The focused `tsc --noEmit` also caught two test-only type errors: the project
narrows `ProcessEnv` to require `NODE_ENV`, and the preview/execute result union
does not narrow from a runtime boolean. Supply the fixture's test environment
and assert the preview result structurally with `toMatchObject`.

A later commit was refused as main/master even though `pwd`, branch and Git
top-level all identified the recovery feature worktree. The installed harness
guidance already documents the missing-envelope-CWD failure mode. Pass the
absolute worktree through `git -C` so the guard inspects the intended branch;
do not disable or bypass the main-branch guard.

The harness shell still ran from the main checkout, so a worktree-relative
`git add` hit the main-branch guard. Use absolute `git -C <worktree>` for both
staging and commit. The linked-worktree Git index also lives below the shared
`.git` metadata path, which the sandbox mounts read-only; after confirming the
exact path allowlist, request escalation for that Git metadata write instead
of copying metadata or changing the worktree layout. The initial merge from
the newly fetched main had one expected source conflict: preserve both sides'
distinct migration filenames in the exact-name refusal fixture, then rerun its
synthetic parity suite before committing the merge.

After the session environment refreshed, Node 22.23.4 was no longer installed;
the app's `.nvmrc` still specifies 22.3.0 while global mise selected Node 26.
Do not reuse a remembered executable path. Read the app pin, inspect installed
versions, install that pin when needed, and rerun the failed validation before
reporting a result.

---
title: "Cloning/extracting into a temp SUBDIR requires ensuring the parent dir exists first"
date: 2026-06-15
category: bug-fixes
module: apps/web-platform/server/ensure-workspace-repo.ts
tags: [git-clone, workspace-provisioning, self-heal, mkdir, concierge]
pr: 5367
related:
  - knowledge-base/project/learnings/best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md
---

# Learning: clone-into-temp-subdir must ensure the parent exists first

## Problem

The Concierge / leader re-provision self-heal failed with **"the configured CWD `/workspaces/<uuid>` doesn't exist on disk"** and **"No Git repository found"** after a sandbox/host reclaim. Recovery never converged — every agent turn dead-ended until manual intervention.

`realGraftRepoClone()` cloned into a temp subdir of the workspace root:

```ts
const tmp = join(workspacePath, `.ensure-repo-tmp-${randomUUID()}`);
await gitWithInstallationAuth(["clone", "--depth", "1", "--", repoUrl, tmp], …);
```

When `workspacePath` itself was gone (reclaimed host), `git clone <tmp>` failed because **git creates only the final leaf component of the destination, not missing intermediate parents.** The parent (`workspacePath`) didn't exist → ENOENT → clone failed → self-heal returned "failed" forever.

A prior fix (PR #5352, CWE-22 UUID-shape validation in `workspace-resolver.ts`) was mistaken for the fix for this — but it only validates the `workspaceId` *shape* before `join()`; it never creates the directory.

## Solution

Add `await mkdir(workspacePath, { recursive: true })` as the **first statement** of `realGraftRepoClone()`, before computing `tmp` and outside the `try` — mirroring the operative behavior the signup path (`workspace.ts:111` → `ensureDir(workspacePath)`) already had. The signup path ensured the dir; the re-provision self-heal path silently did not.

Placement at `realGraftRepoClone`'s top is the tightest correct scope: it's the **shared chokepoint** reached by BOTH the leader (`agent-runner.ts`) and Concierge (`cc-reprovision.ts`) callers, only after the connected / `.git`-absent / valid-URL guards pass.

## Key Insight

**Whenever code clones/extracts/writes into a temp SUBDIR of a path X (so the real work lands at `X/child`), X must be guaranteed to exist first — `git clone`, `tar -x`, and most extract tools create only the leaf of the destination, never missing parents.** A "the parent already exists" assumption is invisible until the parent is reclaimed/deleted out from under the process. When one code path (signup) ensures the dir and a sibling path (self-heal) clones into a subdir of it, the sibling inherits a latent ENOENT that only fires post-reclaim.

Corollary: inline the *operative* call (`mkdir(p,{recursive:true})`), not the whole hardened wrapper, when the wrapper (here `ensureDir`'s symlink-rejection / TOCTOU contract) carries semantics irrelevant to the new call site — exporting it widens the source surface for a one-liner. recursive mkdir is idempotent, so it introduces no new race against the existing per-attempt-unique-temp-dir concurrency hardening.

## Session Errors

1. **Plan AC5 cited a non-existent test file** (`test/workspace-resolver.test.ts`; only `test/workspace-resolver-id-shape-guard.test.ts` exists). vitest silently ran the 3 files that matched the arg list, so the UUID-guard preservation check still ran green and there was no backtracking. **Prevention:** the work-skill already says "plan-quoted numbers/paths are preconditions to verify, not facts" — when a verification AC lists explicit test-file paths, a `ls test/<file>` before trusting the count would have caught the phantom. One-off; no new rule warranted.

## Tags
category: bug-fixes
module: ensure-workspace-repo

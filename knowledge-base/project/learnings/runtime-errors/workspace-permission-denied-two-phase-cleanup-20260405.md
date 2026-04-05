---
module: WebPlatform
date: 2026-04-05
problem_type: runtime_error
component: tooling
symptoms:
  - "rm: cannot remove '.../knowledge-base/plans': Permission denied"
  - "provisionWorkspaceWithRepo fails when re-setting up a project with existing workspace"
  - "Account deletion (GDPR Art. 17) silently fails to delete workspace directory"
root_cause: missing_permission
resolution_type: code_fix
severity: medium
tags: [workspace, permissions, bubblewrap, uid-remapping, rm-rf, find-delete]
---

# Learning: Workspace directory permission denied during project re-setup

## Problem

When a user attempts to re-setup a project (connecting a new repo when a workspace already exists), `provisionWorkspaceWithRepo` fails with permission denied errors. The workspace directory contains files owned by root (UID 0) created by the bubblewrap sandbox's user namespace UID remapping. The container runs as UID 1001 (`soleur` user) and cannot delete root-owned files with `rm -rf`.

Two verified causes for root-owned files:

1. Legacy root-user containers from before the non-root migration (Dockerfile `USER soleur` added later)
2. Kernel-specific user namespace behavior on certain configurations where the mapping is incomplete

Note: The original hypothesis that bwrap UID remapping (`--uid 0 --gid 0`) causes root-owned files was debunked by the #1546 investigation. Bwrap's user namespace always maps writes back to the host UID regardless of in-sandbox appearance. See `knowledge-base/project/plans/2026-04-05-investigate-bwrap-uid-remap-root-owned-files-plan.md`.

## Investigation

- `rm -rf` aborts on the first permission error without deleting accessible siblings
- `chmod -R u+rwX` succeeds on user-owned files but fails on root-owned files without `CAP_FOWNER`
- `find -delete` continues past individual permission errors (partial cleanup)
- `Node.js fs.rm({ recursive: true, force: true })` respects same POSIX permissions as shell `rm`

## Solution

Replaced bare `rm -rf` with a two-phase `removeWorkspaceDir` helper function in `apps/web-platform/server/workspace.ts`:

**Phase 1:** Direct `rm -rf` (fast path, works for user-owned files)
**Phase 2:** `chmod -R u+rwX` to fix restrictive permission bits (git pack files mode 444, dirs mode 555), then `find -delete` which continues past root-owned files, then `rmdir`.

If both phases fail, throw a sanitized error (no filesystem paths leaked to caller) and log full details server-side.

```typescript
export function removeWorkspaceDir(workspacePath: string): void {
  if (!existsSync(workspacePath)) return;
  try {
    execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
    return;
  } catch {
    log.warn({ workspacePath }, "Direct rm -rf failed, attempting partial cleanup");
  }
  try {
    execFileSync("chmod", ["-R", "u+rwX", workspacePath], { stdio: "pipe" });
  } catch {}
  try {
    execFileSync("find", [workspacePath, "-mindepth", "1", "-delete"], { stdio: "pipe" });
    execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
  } catch (err) {
    const stderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    log.error({ workspacePath, stderr }, "Workspace cleanup failed");
    throw new Error("Workspace cleanup failed. Some files may be owned by root. Manual cleanup required: sudo rm -rf <workspace-path>");
  }
}
```

## Key Insight

When dealing with mixed-ownership directories (user + root files), `find -delete` is preferable to `rm -rf` because it continues past individual permission errors instead of aborting the entire tree. The `chmod -R u+rwX` pre-pass fixes user-owned files with restrictive permission bits (git creates pack files with mode 444) without requiring `CAP_FOWNER`.

## Session Errors

1. **npx vitest rolldown binding stale cache** -- `npx vitest` failed with `Cannot find module '../rolldown-binding.linux-x64-gnu.node'` due to a stale npx cache. Recovery: used `./node_modules/.bin/vitest` directly. **Prevention:** Use project-local binaries (`./node_modules/.bin/vitest`) instead of npx for test runners.

2. **Leftover restrictive-permission test directories** -- Tests that set `chmodSync(dir, 0o555)` left directories that subsequent runs couldn't clean up via `rmSync`, causing `EEXIST` errors on `mkdirSync`. Recovery: added `beforeEach`/`afterEach` with `execFileSync("chmod", ["-R", "u+rwX"])` before `rmSync`. **Prevention:** When writing filesystem tests that modify permissions, always include permission-restoring cleanup in `beforeEach` (not just `afterEach`) to handle crashes and leftover state from prior runs.

## Tags

category: runtime-errors
module: WebPlatform

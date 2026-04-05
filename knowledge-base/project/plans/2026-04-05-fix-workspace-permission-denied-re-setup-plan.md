---
title: "fix: workspace directory permission denied during project re-setup"
type: fix
date: 2026-04-05
issue: 1534
---

# fix: workspace directory permission denied during project re-setup

## Problem

When a user attempts to re-setup a project (connecting a new repository when a workspace already exists), `provisionWorkspaceWithRepo` fails with permission denied errors at the cleanup step:

```text
Command failed: rm -rf /workspaces/<user-id>
rm: cannot remove '.../knowledge-base/plans': Permission denied
rm: cannot remove '.../knowledge-base/brainstorms': Permission denied
rm: cannot remove '.../.git/config': Permission denied
```

The container runs as UID 1001 (`soleur` user, set in `apps/web-platform/Dockerfile` line 63-65), but workspace files created by the bubblewrap sandbox (used by Claude Code CLI via the Agent SDK) may be owned by root (UID 0) due to user namespace UID remapping. The `rm -rf` at `apps/web-platform/server/workspace.ts:153` runs as UID 1001 and cannot delete root-owned files.

The same bug affects `deleteWorkspace` (line 252 of `workspace.ts`), which is called during GDPR account deletion via `apps/web-platform/server/account-delete.ts:54`.

### Impact

- Users cannot re-connect to a different repository once a workspace has been provisioned
- Account deletion (GDPR Art. 17) silently fails to delete the workspace directory (non-fatal, but leaves orphaned files)

### Root Cause Analysis

The bubblewrap sandbox creates a user namespace where the sandboxed process sees itself as UID 0 (root) internally. When bubblewrap bind-mounts the workspace directory, files created by the sandboxed process appear as UID 0 on the host filesystem if the kernel's user namespace implementation maps the inner UID 0 back to the outer calling user's UID -- but this mapping can fail or behave differently depending on the kernel version and bwrap flags. Files created with inner UID 0 that are NOT remapped to outer UID 1001 end up owned by root on the persistent volume.

Additionally, files may have been created by a prior container deployment that ran as root (before the non-root user migration in the Dockerfile).

## Proposed Solution

Replace the bare `rm -rf` with a two-phase cleanup that handles permission denied errors gracefully.

> **[Updated 2026-04-05 -- Plan Review]** Original three-phase approach (rm, chmod+rm, find+delete) was simplified to two phases after review identified that `chmod -R u+rwX` cannot change ownership of root-owned files without `CAP_FOWNER`. The chmod phase was dropped.

### Phase 1: Attempt direct removal

Try `rm -rf` as the current user (UID 1001). If this succeeds, done.

### Phase 2: Partial cleanup with find+delete

If Phase 1 fails, use `find <workspace> -mindepth 1 -delete` which processes files individually and continues past individual failures (deleting UID 1001-owned files while skipping root-owned ones), then attempt `rmdir` on the workspace directory. If root-owned files remain, throw a clear error with actionable information.

Log a warning when Phase 2 activates so operations can track frequency and investigate the root cause.

### Implementation

#### `apps/web-platform/server/workspace.ts`

Extract a `removeWorkspaceDir(workspacePath: string): void` helper function used by both `provisionWorkspaceWithRepo` (line 152-154) and `deleteWorkspace` (line 252):

```typescript
function removeWorkspaceDir(workspacePath: string): void {
  if (!existsSync(workspacePath)) return;

  // Phase 1: Direct removal (works when all files owned by current user)
  try {
    execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
    return;
  } catch {
    log.warn({ workspacePath }, "Direct rm -rf failed, attempting partial cleanup");
  }

  // Phase 2: Individual file deletion (continues past permission errors)
  try {
    execFileSync(
      "find",
      [workspacePath, "-mindepth", "1", "-delete"],
      { stdio: "pipe" },
    );
    execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
  } catch (err) {
    throw new Error(
      `Workspace cleanup failed: ${(err as Error).message}. ` +
      `Some files in ${workspacePath} may be owned by root. ` +
      `Manual cleanup required: sudo rm -rf ${workspacePath}`,
    );
  }
}
```

#### Changes to `provisionWorkspaceWithRepo`

Replace lines 152-154:

```typescript
// Before (broken):
if (existsSync(workspacePath)) {
  execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
}

// After (fixed):
removeWorkspaceDir(workspacePath);
```

#### Changes to `deleteWorkspace`

Replace lines 252-254:

```typescript
// Before (broken):
if (existsSync(workspacePath)) {
  execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
  log.info({ userId }, "Workspace deleted");
}

// After (fixed):
removeWorkspaceDir(workspacePath);
log.info({ userId }, "Workspace deleted");
```

### Future Investigation: Prevent Root-Owned Files

The application-level fix above is a defensive workaround. The upstream fix is to prevent root-owned files from being created in the first place by investigating whether the Agent SDK's bubblewrap sandbox configuration (`--uid`/`--gid` flags) can be tuned to preserve the outer UID when writing through bind mounts. This should be tracked as a separate investigation issue.

### Files Changed

| File | Change |
|---|---|
| `apps/web-platform/server/workspace.ts` | Add `removeWorkspaceDir` helper; update `provisionWorkspaceWithRepo` and `deleteWorkspace` to use it |
| `apps/web-platform/test/workspace-error-handling.test.ts` | Add test for permission-denied cleanup scenario |

## Acceptance Criteria

- [ ] `provisionWorkspaceWithRepo` succeeds when workspace contains files with restrictive permissions
- [ ] `deleteWorkspace` succeeds when workspace contains files with restrictive permissions
- [ ] When both cleanup phases fail, a clear error message is thrown with actionable manual cleanup instructions
- [ ] A warning log is emitted when the Phase 2 fallback activates
- [ ] Existing tests continue to pass (no regression on normal workspace provisioning)
- [ ] The fix is contained to `workspace.ts` -- no Dockerfile, cloud-init, or CI changes required

## Test Scenarios

- Given a workspace with all files owned by UID 1001, when `provisionWorkspaceWithRepo` runs, then Phase 1 succeeds and the workspace is replaced (existing behavior preserved)
- Given a workspace with files that have restrictive permissions (mode 000), when `provisionWorkspaceWithRepo` runs, then Phase 2 (find -delete) removes accessible files
- Given a workspace that cannot be deleted at all, when `provisionWorkspaceWithRepo` runs, then an error is thrown with a message containing "Workspace cleanup failed"
- Given a workspace with restrictive-permission files, when `deleteWorkspace` runs during account deletion, then the workspace cleanup is attempted with both phases
- Given no existing workspace, when `provisionWorkspaceWithRepo` runs, then the removal step is a no-op and cloning proceeds normally

## Alternative Approaches Considered

| Approach | Why Not |
|---|---|
| Run container as root | Reverses the security hardening from the non-root migration; violates principle of least privilege |
| Add `sudo` to container and use `sudo rm -rf` | Requires installing sudo, adding sudoers config, and increases attack surface |
| Fix file ownership at creation time (prevent root-owned files) | Cannot control bubblewrap's user namespace UID mapping; would require patching Claude Code CLI |
| Use Docker `--user root` only for cleanup | Requires stopping/restarting the container; operationally complex |
| Node.js `fs.rm({ recursive: true, force: true })` | Respects same POSIX permissions as shell `rm`; would fail identically |

## Context

- Discovered during follow-through verification for #1498
- The error was triggered by attempting to set up `torvalds/linux` when an existing workspace existed from a previous `shelter-me` setup
- Related learning: `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`
- Related learning: `knowledge-base/project/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix.

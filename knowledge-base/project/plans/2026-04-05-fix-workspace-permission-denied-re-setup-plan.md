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

Replace the bare `rm -rf` with a two-phase cleanup that handles permission denied errors gracefully:

### Phase 1: Attempt direct removal

Try `rm -rf` as the current user (UID 1001). If this succeeds, done.

### Phase 2: Chmod-then-remove fallback

If Phase 1 fails, recursively fix permissions with `chmod -R u+rwX` on the workspace directory, then retry `rm -rf`. The `chmod` works because:

- On files owned by UID 1001: already has permission, no-op
- On files owned by root in a user namespace: the `soleur` user may have `CAP_FOWNER` equivalent within the user namespace, allowing `chmod` on files it doesn't own
- If even `chmod` fails on some files: the error is caught and reported clearly

### Phase 3: Last-resort find+delete

If Phase 2 still fails, use `find <workspace> -mindepth 1 -delete` which processes files individually and continues past individual failures, then remove the now-empty directory.

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
    // Fall through to Phase 2
  }

  // Phase 2: Fix permissions, then retry removal
  try {
    execFileSync("chmod", ["-R", "u+rwX", workspacePath], { stdio: "pipe" });
    execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
    return;
  } catch {
    // Fall through to Phase 3
  }

  // Phase 3: Individual file deletion (continues past individual failures)
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
      `Some files in ${workspacePath} may be owned by root.`,
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

### Files Changed

| File | Change |
|---|---|
| `apps/web-platform/server/workspace.ts` | Add `removeWorkspaceDir` helper; update `provisionWorkspaceWithRepo` and `deleteWorkspace` to use it |
| `apps/web-platform/test/workspace-error-handling.test.ts` | Add test for permission-denied cleanup scenario |

## Acceptance Criteria

- [ ] `provisionWorkspaceWithRepo` succeeds when workspace contains root-owned files
- [ ] `deleteWorkspace` succeeds when workspace contains root-owned files
- [ ] When all three cleanup phases fail, a clear error message is thrown with actionable information
- [ ] Existing tests continue to pass (no regression on normal workspace provisioning)
- [ ] The fix is contained to `workspace.ts` -- no Dockerfile, cloud-init, or CI changes required

## Test Scenarios

- Given a workspace with all files owned by UID 1001, when `provisionWorkspaceWithRepo` runs, then Phase 1 succeeds and the workspace is replaced (existing behavior preserved)
- Given a workspace with some files owned by root (UID 0), when `provisionWorkspaceWithRepo` runs, then Phase 2 (chmod + rm) or Phase 3 (find -delete) succeeds
- Given a workspace that cannot be deleted at all, when `provisionWorkspaceWithRepo` runs, then an error is thrown with a message containing "Workspace cleanup failed"
- Given a workspace with root-owned files, when `deleteWorkspace` runs during account deletion, then the workspace is fully removed
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

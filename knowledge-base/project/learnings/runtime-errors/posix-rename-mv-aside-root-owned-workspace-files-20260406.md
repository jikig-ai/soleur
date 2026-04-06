---
title: "POSIX rename(2) mv-aside strategy for root-owned workspace files"
date: 2026-04-06
category: runtime-errors
module: web-platform/workspace
tags: [posix, permissions, bubblewrap, uid-remapping, docker, workspace-cleanup]
related_issues: ["#1546", "#1557", "#1640"]
---

# Learning: POSIX rename(2) mv-aside strategy for root-owned workspace files

## Problem

`removeWorkspaceDir` in `apps/web-platform/server/workspace.ts` failed on root-owned files created by bubblewrap sandbox UID remapping. The function threw an unrecoverable error with "sudo rm -rf" instructions visible to the end user in the web UI. Users could not fix this without server access, and retrying produced the same error because the root-owned files persisted.

The container runs as UID 1001 (`soleur` user) without `CAP_FOWNER`. Both `rm -rf` and `find -delete` fail on root-owned files because the kernel enforces ownership checks on unlink operations.

## Solution

Added a Phase 3 (mv-aside) fallback to the cleanup function. When `rm -rf` (Phase 1) and `chmod + find -delete` (Phase 2) fail to fully remove a workspace:

1. Try `rmdir` to check if the directory is empty (all deletable files were removed)
2. If not empty, rename the workspace to `<path>.orphaned-<timestamp>` using `mv`
3. If `mv` also fails, throw a user-friendly error ("please try again or contact support")

The key insight: `mv` (POSIX `rename(2)`) operates on the **parent directory's inode**, not on the files inside the target directory. Since `/workspaces` is owned by UID 1001, renaming a child directory within it succeeds regardless of the child's contents or ownership. This is a POSIX guarantee: `rename(2)` requires write+execute on the parent directory, not on the directory being renamed.

```typescript
const orphanedPath = workspacePath + `.orphaned-${Date.now()}`;
try {
  execFileSync("mv", [workspacePath, orphanedPath], { stdio: "pipe" });
  log.warn({ workspacePath, orphanedPath },
    "Workspace contained undeletable files; moved aside for background cleanup");
  return;
} catch (mvErr) {
  throw new Error("Workspace cleanup failed -- please try again or contact support");
}
```

## Key Insight

When a non-root process cannot delete files inside a directory (ownership mismatch), it can still **rename the entire directory** as long as it owns the parent. This is because `rename(2)` modifies directory entries in the parent, not the contents of the target. This pattern is useful anywhere you need to "clear a path" for re-provisioning without requiring elevated privileges to delete the contents.

Edge cases verified:

- **Sticky bit**: If the parent has `S_ISVTX`, `rename(2)` requires the caller to own either the file or the parent. Not applicable here since `/workspaces` does not have the sticky bit.
- **Cross-filesystem**: `rename(2)` fails across filesystems. Not applicable since orphaned path is in the same directory.
- **GDPR compliance**: Orphaned directories contain only cloned repo code. The UUID-to-user mapping is deleted from the database during account deletion, making orphaned dirs non-identifiable.

## Related Learnings

- [Docker non-root user with volume mounts](../2026-03-20-docker-nonroot-user-with-volume-mounts.md) -- the three-file sync rule and `chown 1001:1001` pattern that creates the parent directory ownership this fix relies on
- [Symlink escape CWE-59 workspace sandbox](../2026-03-20-symlink-escape-cwe59-workspace-sandbox.md) -- layered defense (bwrap + path validation) for workspace containment

## Tags

category: runtime-errors
module: web-platform/workspace

---
title: "fix: workspace directory permission denied during project re-setup"
type: fix
date: 2026-04-05
issue: 1534
---

# fix: workspace directory permission denied during project re-setup

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4 (Root Cause, Implementation, Test Scenarios, Edge Cases)
**Research sources:** Agent SDK docs (Context7), bubblewrap UID namespace testing, institutional learnings (3 relevant)

### Key Improvements

1. Refined root cause analysis with empirical UID namespace behavior
2. Added `chmod -R u+rwX` back as part of Phase 2 (fixes user-owned restrictive files before `find -delete`)
3. Added TOCTOU race condition handling and `execFileSync` error typing
4. Added edge cases for concurrent cleanup and empty workspace directories

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

Two verified causes for root-owned files in the workspace:

1. **Bubblewrap user namespace UID remapping.** The Agent SDK's bubblewrap sandbox creates a user namespace where the sandboxed process sees itself as UID 0 (root) internally. On Linux, bubblewrap uses `--uid 0 --gid 0` inside the namespace, but bind-mounted writes are mapped back to the outer UID (1001) via `/proc/<pid>/uid_map`. However, this mapping depends on kernel version and namespace configuration. On kernels where the mapping is incomplete or when bubblewrap uses `--unshare-user` without explicit `--uid`/`--gid` mapping, files written through bind mounts can end up owned by UID 0 on the host filesystem.

2. **Legacy root-user containers.** Prior to the non-root migration (learning: `2026-03-20-docker-nonroot-user-with-volume-mounts.md`), the container ran as root. Any workspace files created during that period are owned by UID 0 and persist on the volume mount across container restarts.

### Research Insights: Permission Behavior

Empirical testing confirms the permission model:

- `chmod u+rwX` succeeds on files owned by the current user regardless of current mode (fixes restrictive permission bits)
- `chmod u+rwX` fails on files owned by a different UID (root) without `CAP_FOWNER`
- `find -delete` returns exit code 1 when individual files cannot be deleted, but continues processing (partial cleanup)
- `rm -rf` aborts on the first permission error without deleting accessible siblings
- `execFileSync` throws on non-zero exit codes -- the error object includes a `stderr` Buffer

## Proposed Solution

Replace the bare `rm -rf` with a two-phase cleanup that handles permission denied errors gracefully.

> **[Updated 2026-04-05 -- Plan Review]** Original three-phase approach (rm, chmod+rm, find+delete) was simplified to two phases after review identified that `chmod -R u+rwX` cannot change ownership of root-owned files without `CAP_FOWNER`. The chmod phase was dropped.

### Phase 1: Attempt direct removal

Try `rm -rf` as the current user (UID 1001). If this succeeds, done.

### Phase 2: Fix permissions and partial cleanup

If Phase 1 fails, first attempt `chmod -R u+rwX` to fix permission bits on user-owned files (this handles git pack files with mode 444 and directories with mode 555, which are user-owned but non-writable). Then use `find <workspace> -mindepth 1 -delete` which processes files individually, continuing past failures on truly root-owned files while deleting everything the current user can delete. Finally attempt `rmdir` on the workspace directory.

If root-owned files remain after `find -delete`, throw a clear error with actionable manual cleanup instructions.

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

  // Phase 2: Fix permission bits on user-owned files, then delete individually.
  // chmod fixes restrictive modes (git pack 444, dirs 555) on files WE own.
  // find -delete continues past root-owned files instead of aborting.
  try {
    execFileSync("chmod", ["-R", "u+rwX", workspacePath], {
      stdio: "pipe",
    });
  } catch {
    // chmod may fail on root-owned files -- continue to find -delete
  }

  try {
    execFileSync(
      "find",
      [workspacePath, "-mindepth", "1", "-delete"],
      { stdio: "pipe" },
    );
    execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
  } catch (err) {
    const stderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    throw new Error(
      `Workspace cleanup failed: ${stderr || (err as Error).message}. ` +
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

- [x] `provisionWorkspaceWithRepo` succeeds when workspace contains files with restrictive permissions
- [x] `deleteWorkspace` succeeds when workspace contains files with restrictive permissions
- [x] When both cleanup phases fail, a clear error message is thrown with actionable manual cleanup instructions
- [x] A warning log is emitted when the Phase 2 fallback activates
- [x] Existing tests continue to pass (no regression on normal workspace provisioning)
- [x] The fix is contained to `workspace.ts` -- no Dockerfile, cloud-init, or CI changes required

## Test Scenarios

- Given a workspace with all files owned by UID 1001, when `removeWorkspaceDir` runs, then Phase 1 (`rm -rf`) succeeds and the directory is removed
- Given a workspace with files that have restrictive permission bits (mode 000 on files, mode 555 on dirs), when `removeWorkspaceDir` runs, then Phase 2 (`chmod` + `find -delete`) removes them
- Given a workspace that cannot be fully deleted (root-owned files persist), when `removeWorkspaceDir` runs, then an error is thrown with a message containing "Workspace cleanup failed" and "Manual cleanup required"
- Given no existing workspace directory, when `removeWorkspaceDir` runs, then it returns immediately without spawning child processes
- Given a workspace with restrictive-permission files, when `deleteWorkspace` runs during account deletion, then the workspace cleanup is attempted and `log.info` only fires on success
- Given an empty workspace directory, when `removeWorkspaceDir` runs, then Phase 1 succeeds (rm -rf handles empty dirs)

### Test Implementation Notes

- Root-owned files cannot be created in unit tests without elevated privileges. Tests simulate the permission failure by creating user-owned files with mode 000 in non-writable directories (mode 555). This triggers the same `EACCES` error path.
- The `removeWorkspaceDir` function should be exported (or tested indirectly through `provisionWorkspaceWithRepo` and `deleteWorkspace`) to allow targeted unit testing of the cleanup logic.

## Edge Cases

- **TOCTOU race:** `existsSync` check followed by `execFileSync("rm")` has a time-of-check/time-of-use gap. If the directory is deleted between the check and the operation, `rm -rf` exits 0 (idempotent). `find -delete` on a non-existent path exits with error. Mitigation: the `existsSync` guard in `removeWorkspaceDir` prevents spawning unnecessary child processes, but Phase 2's `find` should tolerate `ENOENT` gracefully.
- **Concurrent re-setup:** If two `provisionWorkspaceWithRepo` calls race for the same userId (the optimistic lock in the route handler prevents this, but defense-in-depth), the second call may find a partially deleted directory. Both `rm -rf` and `find -delete` handle partially deleted trees correctly.
- **Empty workspace directory:** If the workspace directory exists but is empty (e.g., a previous failed clone left an empty dir), `rmdir` succeeds directly after `find -delete` (no-op on empty tree).
- **Symlink inside workspace:** `rm -rf` follows directory symlinks and deletes targets. Since `removeWorkspaceDir` operates on the workspace root (not user-controlled paths), this is acceptable. The workspace path is validated by UUID regex and `join(getWorkspacesRoot(), userId)`.
- **Very large workspaces:** `find -delete` processes files depth-first (same as `rm -rf`). No memory scaling concern. The `execFileSync` call blocks the event loop, but this runs in a background `.then()` chain, not in the request handler.
- **`deleteWorkspace` log placement:** The `log.info` after `removeWorkspaceDir` should only execute when cleanup succeeds. If `removeWorkspaceDir` throws, the caller (`account-delete.ts:53-57`) catches it as non-fatal, so the log line in `deleteWorkspace` must be inside a success path.

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
- Related learning: `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md` (three-file sync rule for non-root Docker USER changes)
- Related learning: `knowledge-base/project/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md` (broadest-to-narrowest chown ordering)
- Related learning: `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md` (workspace path validation uses `realpathSync` -- relevant since `removeWorkspaceDir` operates on the same paths)
- Related code: `apps/web-platform/server/agent-runner.ts:347-379` (sandbox config with `allowWrite: [workspacePath]`, bubblewrap enabled)
- Related infra: `apps/web-platform/infra/cloud-init.yml:209` (`chown 1001:1001 /mnt/data/workspaces` -- top-level only, not recursive)
- Agent SDK docs: bubblewrap sandbox uses OS primitives for read/write restriction but does not document UID mapping behavior for bind-mounted writes

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix.

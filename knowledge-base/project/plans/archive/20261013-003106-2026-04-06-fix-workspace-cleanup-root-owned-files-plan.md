---
title: "fix: workspace cleanup fails on root-owned files with unhelpful error"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix: workspace cleanup fails on root-owned files with unhelpful error

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Implementation Detail, Technical Considerations, Test Scenarios, References)
**Research sources:** POSIX `rename(2)` man page, project learnings (Sentry integration, silent setup failure, Docker non-root user), account-delete.ts GDPR analysis

### Key Improvements

1. Added sticky bit edge case analysis for `rename(2)` -- confirmed not applicable
2. Added GDPR Art. 17 alignment analysis for `deleteWorkspace` caller path
3. Added Sentry integration detail -- workspace.ts uses pino logger, not Sentry directly; callers handle Sentry capture
4. Added warning about Sentry DSN reliability concern (may not reach container per learning)

## Overview

When a user re-connects a repository or deletes their account, `removeWorkspaceDir` fails to remove root-owned files and throws an error that surfaces in the web UI as "Project Setup Failed" with the message: "Some files may be owned by root. Manual cleanup required: sudo rm -rf workspace-path". This error is unrecoverable from the user's perspective -- they cannot fix it without server access, and retrying produces the same error.

## Problem Statement

The `removeWorkspaceDir` function in `apps/web-platform/server/workspace.ts` implements a two-phase cleanup:

1. **Phase 1:** `rm -rf` (fast path for user-owned files)
2. **Phase 2:** `chmod -R u+rwX` then `find -delete` then `rmdir`

Both phases fail on root-owned files because the container runs as UID 1001 (`soleur` user) without `CAP_FOWNER`. The function throws an error that propagates to the web UI as a `repo_error` displayed in the `FailedState` component.

**Root causes of root-owned files** (from #1546 investigation):

1. Legacy root-user containers from before the `USER soleur` Dockerfile migration
2. Kernel-specific user namespace behavior on certain configurations

**Current error flow:**

1. `removeWorkspaceDir` throws: `"Workspace cleanup failed. Some files may be owned by root. Manual cleanup required: sudo rm -rf <workspace-path>"`
2. `provisionWorkspaceWithRepo` propagates the error (line 152)
3. `POST /api/repo/setup` catch handler writes the raw error message to `users.repo_error`
4. `GET /api/repo/status` returns the error as `errorMessage`
5. `connect-repo/page.tsx` renders `FailedState` with the message

**User impact:** The error message tells the user to run `sudo rm -rf`, which they cannot do. Retrying produces the same error because the root-owned files persist.

## Proposed Solution

Replace the "throw and give up" behavior with a **skip-and-continue** strategy. When root-owned files cannot be deleted, the function should:

1. Log the undeletable files for ops visibility (pino warning)
2. Delete everything it can (user-owned files)
3. Move the remaining root-owned directory aside (rename with a `.orphaned-<timestamp>` suffix)
4. Return successfully so the new workspace can be provisioned

### Implementation Detail

#### 1. Modify `removeWorkspaceDir` in `apps/web-platform/server/workspace.ts`

The Phase 2 catch block currently throws. Instead:

```typescript
// After find -delete, check if workspace dir is now empty
try {
  execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
  return; // fully cleaned
} catch {
  // Directory not empty -- root-owned files remain
}

// Phase 3: Move aside so provisioning can proceed
const orphanedPath = workspacePath + `.orphaned-${Date.now()}`;
try {
  execFileSync("mv", [workspacePath, orphanedPath], { stdio: "pipe" });
  log.warn(
    { workspacePath, orphanedPath },
    "Workspace contained undeletable files; moved aside for background cleanup",
  );
  return; // provisioning can now use the original path
} catch (mvErr) {
  // mv failed too -- this is a genuine infrastructure problem
  const stderr = (mvErr as { stderr?: Buffer })?.stderr?.toString() ?? "";
  log.error({ workspacePath, stderr }, "Workspace cleanup failed: cannot move aside");
  throw new Error("Workspace cleanup failed — please try again or contact support");
}
```

**Why `mv` works when `rm` does not:** `mv` (rename) operates on the parent directory's inode, not on the files inside the target directory. Since `getWorkspacesRoot()` (`/workspaces`) is owned by UID 1001 and has write permission, renaming a child directory within it succeeds regardless of the child directory's contents or ownership. This is a POSIX guarantee: `rename(2)` requires write+execute on the parent directory of both old and new names, not on the directory being renamed itself.

**Edge case -- sticky bit:** POSIX `rename(2)` has a special case: if the parent directory has the sticky bit (`S_ISVTX`), the caller must own either the file being renamed or the parent directory. This is not applicable here because `/workspaces` (created via `mkdir -p` in cloud-init.yml and `chown 1001:1001`) does not have the sticky bit set. No Terraform or cloud-init config sets it.

**Edge case -- orphanedPath already exists:** `mv` will fail if a directory with the orphaned name already exists. Since the timestamp suffix is millisecond-granular, collisions are extremely unlikely. But as defense-in-depth, the catch block will still produce a clear error.

**Observability note:** `workspace.ts` does not import Sentry -- it uses the pino child logger (`createChildLogger("workspace")`). The `log.warn` call in the mv-success path provides structured logging via pino. Sentry capture happens at the caller level: `setup/route.ts:123` calls `Sentry.captureException(err)` in its `.catch()` handler, and `disconnect/route.ts:103` does the same. Since the mv-aside path does NOT throw, the callers will NOT call `Sentry.captureException` -- which is correct behavior (the operation succeeded). The pino warning is the primary observability signal for orphan creation.

**Sentry DSN reliability warning:** Per the learning at `knowledge-base/project/learnings/integration-issues/sentry-zero-events-production-verification-20260405.md`, the Sentry server-side SDK may not be receiving events in production (DSN may not be reaching the container). The pino log is the reliable observability path regardless. This makes the decision to use `log.warn` (pino) rather than `Sentry.captureMessage` even more appropriate.

#### 2. Improve the error message for the final fallback

If `mv` also fails (e.g., filesystem full, permissions on parent dir changed), the error message should be user-friendly, not tell them to run `sudo`:

```
"Workspace cleanup failed — please try again or contact support"
```

The server-side log retains full diagnostic detail (paths, stderr).

#### 3. Update `FailedState` component (optional improvement)

No changes required to the component itself. The fix prevents the error from reaching the UI at all. However, the generic "usually a temporary issue" message is already appropriate for the rare case where `mv` fails too.

## Technical Considerations

### Security

- **Path validation unchanged:** The existing `resolved.startsWith(root + "/")` guard prevents any directory traversal. The orphaned path is always within the workspace root.
- **No privilege escalation:** The fix uses only standard POSIX operations (`mv`/`rename`) available to the non-root user.
- **Orphaned directories retain original permissions:** Root-owned files inside orphaned dirs are not accessible to the app user (read or write). They are inert artifacts.

### GDPR Art. 17 (Right to Erasure) Alignment

The `deleteWorkspace` function in `account-delete.ts` calls `removeWorkspaceDir` as a best-effort step (lines 53-57: catch logs warning, does not block account deletion). After this fix:

- **Successful mv-aside:** Workspace is renamed to `*.orphaned-<timestamp>`. The account (auth.users + public.users + all FK children) is fully deleted. The orphaned directory contains repository files (code, configs) but no user identity link -- the UUID workspace name is gone from the database.
- **Failed mv (fallback):** Same as current behavior -- error is logged, account deletion proceeds. GDPR compliance is maintained because auth data deletion is the critical path, not filesystem cleanup.

Orphaned directories are **not a GDPR concern** because: (1) they contain cloned repository code, not personal data; (2) the UUID linking them to a user is deleted from the database; (3) the directory name is `<UUID>.orphaned-<timestamp>` which is not identifiable without the database mapping.

### Performance

- `mv` (rename within same filesystem) is O(1) -- it modifies directory entries, not file contents. No data is copied.

### Disk space

- Orphaned directories consume disk space until cleaned up. The `/mnt/data/workspaces` volume is 20 GB (`apps/web-platform/infra/variables.tf:50-53`). Each workspace is typically 50-200 MB (shallow clone). Even 10 orphaned workspaces would use ~2 GB.
- A pino warning is logged at orphan creation time so ops has visibility via structured logs. If orphans accumulate, a host-level cron job running as root is the correct cleanup mechanism (tracked via follow-up issue).

### Attack Surface Enumeration

This fix does not introduce new security surfaces. It modifies the error-handling path of an existing operation:

1. **`mv` target path:** Constructed from `workspacePath + ".orphaned-" + Date.now()`. The `workspacePath` is already validated against the workspace root. The suffix contains only a numeric timestamp.
2. **No new runtime processes:** The fix adds a `mv` call in the existing error path. No background timers, no new filesystem scanning.

## Acceptance Criteria

- [x] Given a workspace with root-owned files, when `removeWorkspaceDir` is called, then user-owned files are deleted, root-owned files are moved to an orphaned directory, and the function returns without error
- [x] Given a workspace with only user-owned files, when `removeWorkspaceDir` is called, then the workspace is fully deleted (no orphan created)
- [x] Given a non-existent workspace path, when `removeWorkspaceDir` is called, then the function returns without error
- [x] Given `mv` also fails (e.g., parent dir permissions changed), when `removeWorkspaceDir` is called, then a user-friendly error is thrown (no `sudo rm -rf` instructions)
- [x] When an orphan is created, a pino warning is logged with both the original and orphaned paths (Sentry capture is NOT needed -- the operation succeeded; pino is the reliable observability path)
- [x] The error message `"sudo rm -rf"` no longer appears in any code path reachable by users
- [x] Existing path validation tests continue to pass (traversal, root, prefix collision)

## Test Scenarios

### Unit Tests (`apps/web-platform/test/workspace-cleanup.test.ts`)

- Given a workspace where `rm -rf` fails and `find -delete` leaves undeletable files, when `removeWorkspaceDir` is called, then the workspace is renamed to `*.orphaned-<timestamp>` and the function returns without throwing
- Given a workspace where `rm -rf` fails, `find -delete` leaves files, and `mv` also fails, when `removeWorkspaceDir` is called, then it throws with message matching `/please try again or contact support/` (not matching `/sudo/`)
- Given a workspace with restrictive permissions (mode 444/555) but owned by current user, when `removeWorkspaceDir` is called, then the workspace is fully deleted via Phase 2 (chmod + find -delete)

#### Testing approach for mv-aside scenarios

Real root-owned files cannot be created in tests without elevated privileges. The existing test pattern (line 84-114 of workspace-cleanup.test.ts) uses `vi.doMock("child_process")` to simulate permission-denied failures. The new tests should follow the same pattern:

- Mock `execFileSync` to fail on `rm`, `find`, and `rmdir` (simulating undeletable files)
- Allow `chmod` to succeed (no-op) and `mv` to succeed (simulating the rename)
- Verify the function returns without throwing
- For the mv-failure test: also mock `mv` to throw
- Use `vi.doMock("fs")` with `existsSync: () => true` to bypass the early-exit check

**Learning applied:** Per `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`, permission-restoring cleanup must be in `beforeEach` (not just `afterEach`) to handle crashes and leftover state from prior runs.

### Integration

- Given a user with an existing workspace containing root-owned files, when they click "Try Again" in the web UI, then the setup proceeds to clone and succeeds (the orphaned workspace is moved aside)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling fix in server-side workspace management code.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Add `CAP_FOWNER` to Docker container | Rejected | Grants ability to bypass ownership checks on ALL files in the container, excessive privilege escalation |
| Run container as root | Rejected | Security regression; non-root was added deliberately |
| Add a sidecar container running as root for cleanup | Over-engineered | Complex for a rare edge case; `mv` + background cleanup is simpler |
| Use `fakeroot` to simulate root permissions | Rejected | `fakeroot` wraps libc calls, doesn't provide actual kernel capabilities for deletion |
| Delete via Docker exec as root from the host | Rejected | Requires orchestration between app and host; AGENTS.md prohibits manual SSH/server modifications |
| Ignore the error and let user retry | Rejected | This IS the current behavior; retrying fails the same way because root-owned files persist |
| Add a cron job on the host to clean orphaned dirs | Deferred (follow-up) | The correct cleanup mechanism for root-owned files -- runs as root on the host. Create a follow-up issue if orphans accumulate. Pino warning at orphan creation provides visibility |
| In-process background cleanup timer | Rejected (per review) | The app user cannot delete root-owned files, so a periodic timer scanning for orphans it cannot remove is a no-op. Cleanup belongs at the infrastructure level |

## References

- **Error source:** `apps/web-platform/server/workspace.ts:301-303`
- **Callers:** `provisionWorkspaceWithRepo` (line 152), `deleteWorkspace` (line 251)
- **UI error display:** `apps/web-platform/components/connect-repo/failed-state.tsx`
- **API routes:** `apps/web-platform/app/api/repo/setup/route.ts`, `apps/web-platform/app/api/repo/disconnect/route.ts`
- **Existing tests:** `apps/web-platform/test/workspace-cleanup.test.ts`
- **Learning:** `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`
- **Prior investigation:** `knowledge-base/project/plans/2026-04-05-investigate-bwrap-uid-remap-root-owned-files-plan.md`
- **Related closed issues:** #1546 (bwrap UID remapping investigation), #1557 (Docker sandbox availability)
- **Docker config:** `apps/web-platform/Dockerfile` (USER soleur, UID 1001)
- **Deploy config:** `apps/web-platform/infra/ci-deploy.sh` (volume mounts, seccomp)
- **Account deletion:** `apps/web-platform/server/account-delete.ts` (GDPR Art. 17 cascade, best-effort workspace deletion)
- **Learning (Sentry DSN):** `knowledge-base/project/learnings/integration-issues/sentry-zero-events-production-verification-20260405.md`
- **Learning (silent setup failure):** `knowledge-base/project/learnings/integration-issues/silent-setup-failure-no-error-capture-20260403.md`
- **Learning (Docker non-root):** `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md`
- **POSIX reference:** `man 2 rename` -- sticky bit exception for `S_ISVTX` directories

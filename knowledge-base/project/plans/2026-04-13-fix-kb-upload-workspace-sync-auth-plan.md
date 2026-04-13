---
title: "fix: KB upload workspace sync fails due to missing git credential helper"
type: fix
date: 2026-04-13
---

# fix: KB upload workspace sync fails due to missing git credential helper

## Overview

The KB file upload feature (`POST /api/kb/upload`) successfully commits files to GitHub via the Contents API but then fails on the workspace sync step (`git pull --ff-only`) because the pull command runs without authentication. The user sees: "File committed to GitHub but workspace sync failed. Try refreshing." The file is committed to the remote but invisible in the KB Tree until the next session sync.

**Related issue:** #1974 (KB file upload feature)
**Archived plan:** `knowledge-base/project/plans/archive/20260412-194039-2026-04-12-feat-kb-file-upload-plan.md`

## Root Cause

`apps/web-platform/app/api/kb/upload/route.ts:227` runs:

```typescript
await execFileAsync("git", ["pull", "--ff-only"], {
  cwd: userData.workspace_path,
  timeout: 30000,
});
```

This has no credential helper. User workspaces are cloned from private GitHub repos using a temporary credential helper (see `workspace.ts:163`), but the credential helper is deleted immediately after cloning (line 180). Subsequent git operations that contact the remote (pull, push, fetch) must generate a fresh installation token and create a new temporary credential helper.

The correct pattern already exists in `server/session-sync.ts:238-248` (`syncPull`):

```typescript
execFileSync(
  "git",
  [
    "-c", `credential.helper=!${helperPath}`,
    "pull",
    "--no-rebase",
    "--autostash",
  ],
  { cwd: workspacePath, stdio: "pipe", timeout: 60_000 },
);
```

And in `server/push-branch.ts:130`:

```typescript
"-c", `credential.helper=!${helperPath}`,
```

The upload route is the only git-remote operation that skips the credential helper.

## Proposed Solution

Add authenticated `git pull` to the upload route using the same credential helper pattern as `session-sync.ts`. The upload route already has `github_installation_id` available from the user record (line 82), so token generation is straightforward.

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/api/kb/upload/route.ts:6-7` | Add imports for `generateInstallationToken`, `randomCredentialPath` from `@/server/github-app` and `writeFileSync`, `unlinkSync` from `node:fs` |
| `apps/web-platform/app/api/kb/upload/route.ts:226-230` | Replace bare `git pull --ff-only` with authenticated pull using temporary credential helper (generate token, write helper, pull with `-c credential.helper=!${helperPath}`, cleanup helper in finally block) |
| `apps/web-platform/test/kb-upload.test.ts:47-49` | Add mock for `generateInstallationToken` from `@/server/github-app` (already partially mocked at line 47) |
| `apps/web-platform/test/kb-upload.test.ts:145-146` | Update `mockExecFile` assertion to verify credential helper is passed to git pull |
| `apps/web-platform/test/kb-upload.test.ts:316-327` | Add test case: git pull fails due to auth error (credential helper present but token expired) |

### Fix Implementation

The workspace sync block (lines 225-244) changes from:

```typescript
// Current (broken): no authentication
try {
  await execFileAsync("git", ["pull", "--ff-only"], {
    cwd: userData.workspace_path,
    timeout: 30000,
  });
} catch (syncError) { ... }
```

To:

```typescript
// Fixed: use credential helper for authentication
let helperPath: string | null = null;
try {
  const token = await generateInstallationToken(userData.github_installation_id);
  helperPath = randomCredentialPath();
  writeFileSync(
    helperPath,
    `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
    { mode: 0o700 },
  );

  await execFileAsync(
    "git",
    ["-c", `credential.helper=!${helperPath}`, "pull", "--ff-only"],
    { cwd: userData.workspace_path, timeout: 30_000 },
  );
} catch (syncError) {
  logger.error(
    { err: syncError, userId: user.id },
    "kb/upload: workspace sync failed after successful commit",
  );
  Sentry.captureException(syncError);
  return NextResponse.json(
    {
      error: "File committed to GitHub but workspace sync failed. Try refreshing.",
      code: "SYNC_FAILED",
    },
    { status: 500 },
  );
} finally {
  if (helperPath) {
    try { unlinkSync(helperPath); } catch { /* best-effort cleanup */ }
  }
}
```

### Why Not Extract a Shared Helper

`session-sync.ts` already has `writeCredentialHelper()` and `cleanupCredentialHelper()` as private functions. Extracting them to a shared module would be cleaner, but the scope of this bug fix should stay minimal. A refactor to DRY up the credential helper pattern across `upload/route.ts`, `session-sync.ts`, and `push-branch.ts` can follow as a separate PR. The inline approach matches the existing pattern in `workspace.ts` (lines 144-148).

## Acceptance Criteria

- [x] Uploading a file through the KB Tree commits to GitHub AND syncs to the local workspace
- [x] After upload, `refreshTree()` shows the newly uploaded file without page reload
- [x] The temporary credential helper is deleted after the pull completes (success or failure)
- [x] If token generation fails, the error is logged and SYNC_FAILED is returned (not a 201 pretending success)
- [x] Existing security tests (CSRF, path traversal, size limits) continue to pass

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- single-file bug fix in existing upload route adding missing authentication to a git pull command.

## Test Scenarios

### Acceptance Tests

- Given a user with a connected private repo, when they upload a PNG through the KB Tree, then the file is committed to GitHub AND appears in the KB Tree after refreshTree
- Given a successful GitHub Contents API PUT, when the workspace sync runs, then `git pull` is invoked with `-c credential.helper=!<path>` argument
- Given a successful workspace sync, when the pull completes, then the temporary credential helper file is deleted from the filesystem

### Error Scenarios

- Given the installation token generation fails (e.g., expired App credentials), when the upload completes the GitHub PUT, then the response is 500 with code SYNC_FAILED and the error is logged with Sentry
- Given the credential helper is written but git pull times out (30s), when the timeout fires, then the credential helper file is still cleaned up in the finally block

### Regression Tests

- Given all existing upload tests (CSRF, auth, type validation, size validation, path traversal, duplicate detection, overwrite), when run with the new credential helper logic, then all continue to pass
- Given the `mockExecFile` mock resolves successfully, when the upload flow completes, then the response is 201 with path, sha, and commitSha (no regression in success path)

### Integration Verification (for `/soleur:qa`)

- **Browser:** Navigate to /dashboard/kb, hover over a directory, click upload, select a test PNG, verify it appears in the tree after upload completes (no "workspace sync failed" error)

## References

### Internal References

- Upload route: `apps/web-platform/app/api/kb/upload/route.ts:227` (the bug)
- Session sync (correct pattern): `apps/web-platform/server/session-sync.ts:238-248`
- Push branch (correct pattern): `apps/web-platform/server/push-branch.ts:114-151`
- Workspace provisioning (credential helper pattern): `apps/web-platform/server/workspace.ts:142-186`
- Token generation: `apps/web-platform/server/github-app.ts` (`generateInstallationToken`, `randomCredentialPath`)

### Learnings Applied

- Repo connection implementation: `2026-03-29-repo-connection-implementation.md`
- GitHub App auth patterns: `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`

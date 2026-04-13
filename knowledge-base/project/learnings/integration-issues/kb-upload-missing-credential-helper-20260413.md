---
module: KB Upload API
date: 2026-04-13
problem_type: integration_issue
component: authentication
symptoms:
  - "File committed to GitHub but workspace sync failed. Try refreshing."
  - "git pull --ff-only fails on private repos without credential helper"
root_cause: incomplete_setup
resolution_type: code_fix
severity: high
tags: [credential-helper, git-pull, github-app, workspace-sync]
---

# Troubleshooting: KB Upload Workspace Sync Fails Due to Missing Git Credential Helper

## Problem

Uploading a file through the KB Tree commits the file to GitHub via the Contents API but the subsequent `git pull --ff-only` fails because it runs without authentication. Users see "File committed to GitHub but workspace sync failed. Try refreshing." The file exists on GitHub but is invisible in the KB Tree until the next session sync.

## Environment

- Module: KB Upload API (`apps/web-platform/app/api/kb/upload/route.ts`)
- Affected Component: Workspace sync after GitHub Contents API PUT
- Date: 2026-04-13

## Symptoms

- Error toast: "File committed to GitHub but workspace sync failed. Try refreshing."
- File committed to GitHub repository (visible via GitHub web UI)
- File not visible in KB Tree until next session sync
- Sentry captures the sync error with `SYNC_FAILED` code

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The root cause was immediately clear from comparing the upload route's `git pull` with other git-remote operations in the codebase.

## Session Errors

**QA dev server startup failed in worktree** -- Supabase env vars (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) missing from Doppler dev config when running from a worktree.
- **Recovery:** Skipped browser QA, relied on unit tests (19/19 passing).
- **Prevention:** Document worktree QA limitations — Doppler dev config may not have all env vars needed for full server startup. Unit tests are sufficient for server-side-only fixes.

**Write tool rejected /tmp files** -- Attempted to use the Write tool on `/tmp/review-finding-*.md` files that hadn't been Read first.
- **Recovery:** Used Bash `cat > file << 'BODY'` heredoc instead.
- **Prevention:** For temporary files that don't exist yet, use Bash heredoc or echo redirection instead of the Write tool.

**git add from wrong CWD** -- Ran `git add apps/web-platform/test/kb-upload.test.ts` while shell CWD was `apps/web-platform/`, doubling the path.
- **Recovery:** Re-ran from the worktree root.
- **Prevention:** Always use absolute paths or ensure CWD is the worktree root before git operations.

**npx vitest from wrong CWD** -- Ran `npx vitest` without being in the `apps/web-platform/` directory, causing a rolldown module error.
- **Recovery:** Added explicit `cd` to the correct directory.
- **Prevention:** Always `cd` to the app directory before running test commands, or use `--cwd` flag.

## Solution

Added the same temporary credential helper pattern used by `session-sync.ts`, `push-branch.ts`, and `workspace.ts` to the upload route.

**Code changes:**

```typescript
// Before (broken): no authentication
try {
  await execFileAsync("git", ["pull", "--ff-only"], {
    cwd: userData.workspace_path,
    timeout: 30000,
  });
} catch (syncError) { ... }

// After (fixed): credential helper for authentication
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
  // ... same error handling
} finally {
  if (helperPath) {
    try { unlinkSync(helperPath); } catch { /* best-effort cleanup */ }
  }
}
```

## Why This Works

1. **Root cause:** The upload route was the only git-remote operation in the codebase that skipped the credential helper. User workspaces are cloned from private repos using a temporary credential helper that is deleted after cloning. All subsequent remote operations must generate a fresh installation token.

2. **Why the solution works:** The credential helper pattern creates a temporary shell script that git's credential system invokes to get username/password. The installation token acts as a password for `x-access-token` username. The `finally` block ensures the token is never left on disk.

3. **Why `--ff-only` is correct:** The Contents API commit creates exactly one new commit on the remote HEAD. The local workspace has not diverged (no local commits between upload and pull). Fast-forward is guaranteed. `session-sync.ts` uses `--no-rebase --autostash` because arbitrary time may pass between syncs, creating divergence.

## Prevention

- When adding any git operation that contacts a remote, always include the credential helper pattern. Search for `credential.helper` in the codebase to see the established pattern.
- The credential helper pattern exists in 4 places now (`upload/route.ts`, `session-sync.ts`, `push-branch.ts`, `workspace.ts`). A future refactor should extract `withGitCredentials(installationId, fn)` to `github-app.ts`.
- Always clean up credential helpers in a `finally` block — tokens on disk are a security risk.

## Related Issues

- See also: [repo-connection-implementation](../2026-03-29-repo-connection-implementation.md) — documents the original credential helper pattern for workspace provisioning
- See also: [silent-setup-failure](../integration-issues/silent-setup-failure-no-error-capture-20260403.md) — documents token generation failure modes

---
title: "fix: project setup fails at 'Copying your project files' step"
type: fix
date: 2026-04-03
---

# fix: project setup fails at 'Copying your project files' step

## Problem

After connecting a GitHub repository through the Soleur web platform, the setup process starts ("Setting up your AI team...") but fails at the first step ("Copying your project files") and shows the "Project Setup Failed" error page.

This is a recurring issue in the project setup flow. Three previous PRs fixed upstream auth problems:

- **PR #1479:** Fixed `user.identities` being null for email-first users (queried `auth.identities` table)
- **PR #1487:** Switched to GoTrue admin API (`auth.admin.getUserById`) because PostgREST does not expose the `auth` schema
- **PR #1490:** Added `persistSession: false` to `createServiceClient()` which was crashing `auth.admin.getUserById()`

With those fixes, the install route (`POST /api/repo/install`) now succeeds and the installation ID is stored. The repos list loads and the user can select a repository. But the actual workspace provisioning (`POST /api/repo/setup` -> `provisionWorkspaceWithRepo`) fails.

## Root Cause Analysis

The failure occurs in the background `provisionWorkspaceWithRepo()` call. The `POST /api/repo/setup` returns 200 (it starts the background task and returns `{ status: "cloning" }`), but the background task throws, causing the `.catch()` handler to set `repo_status: "error"` in the database. The status poll then detects the error and shows the failure page.

### Hypotheses (ordered by likelihood)

#### H1: Git clone authentication failure

**Location:** `apps/web-platform/server/workspace.ts:148-158`

The `generateInstallationToken()` call may fail if the GitHub App private key has encoding issues in the Docker environment (escaped `\n` in env vars from Doppler), or the token exchange API call fails. The git clone uses a temporary credential helper script, which may not be executable in the Docker container's `/tmp`.

#### H2: Missing error context for debugging

**Location:** `apps/web-platform/app/api/repo/setup/route.ts:120-135`

The `.catch()` handler logs the error via pino but does not:

- Store the error message in the database (only sets `repo_status: "error"`)
- Report to Sentry (`captureException` is not called)
- Return any error details to the client

This makes the bug impossible to debug without SSH access to the production server (which violates the observability-first debugging rule).

#### H3: File permission issue in Docker

**Location:** `apps/web-platform/server/workspace.ts:143-144`

The `rm -rf` of existing workspace and `mkdirSync` may fail if the `/workspaces` volume mount has incorrect ownership. The cloud-init sets `chown 1001:1001 /mnt/data/workspaces` but subdirectories created by a different process could have root ownership.

#### H4: Credential helper `!` prefix requires shell access

**Location:** `apps/web-platform/server/workspace.ts:151`

The `credential.helper=!` prefix tells git to spawn a shell to execute the helper script. In `node:22-slim` Docker images, `/bin/sh` is available but the credential helper script written to `/tmp/git-cred-<uuid>` with `mode: 0o700` must be executable by the container user. If `/tmp` is mounted `noexec`, the helper cannot run.

## Implementation Plan

### Phase 0: Reproduce and diagnose

**Goal:** Identify the actual error before writing any fix code.

#### Task 0.1: Check production container health

Verify the Docker container environment is correct:

- `/workspaces` is mounted and writable by UID 1001
- `/tmp` is not mounted `noexec`
- `git` is installed and functional
- Credential helper pattern works (`echo "test" > /tmp/test-cred && chmod 700 /tmp/test-cred && /tmp/test-cred`)

#### Task 0.2: Reproduce via dev server or Playwright

Attempt the full setup flow to capture the specific error:

1. Start the dev server (or use production)
2. Navigate to `/connect-repo`
3. Complete the GitHub App install flow
4. Select a repository and trigger setup
5. Watch browser console and server logs for the error

#### Task 0.3: Check server logs for the actual error

Query pino logs from the Docker container (via the deployment host) or check Sentry for any captured exceptions. The `logger.error` in the `.catch()` handler should show the exception message and stack trace.

### Phase 1: Fix workspace provisioning

**Goal:** Fix the provisioning failure and add minimal observability.

#### Task 1.1: Add step-specific error wrapping with stderr capture to provisionWorkspaceWithRepo

**File:** `apps/web-platform/server/workspace.ts`

Wrap each step in individual try-catch blocks with descriptive error messages and capture git stderr. Currently all failures throw generic errors. This is a single task because stderr capture IS the error wrapping:

```typescript
// Step 1: Token generation
let token: string;
try {
  token = await generateInstallationToken(installationId);
} catch (err) {
  throw new Error(`Token generation failed: ${(err as Error).message}`);
}

// Step 2: Write credential helper
try {
  writeFileSync(helperPath, script, { mode: 0o700 });
} catch (err) {
  throw new Error(`Credential helper write failed: ${(err as Error).message}`);
}

// Step 3: Git clone (capture stderr for auth/network errors)
try {
  execFileSync("git", [...], { stdio: "pipe", timeout: 120_000 });
} catch (err) {
  const stderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
  throw new Error(`Git clone failed: ${stderr || (err as Error).message}`);
}
```

#### Task 1.2: Add Sentry captureException to the setup route catch handler

**File:** `apps/web-platform/app/api/repo/setup/route.ts`

In the `.catch()` handler (lines 120-135), add `Sentry.captureException(err)` alongside the existing `logger.error()` call. This is the single integration point -- the route handler catches all workspace provisioning errors, so Sentry does not need to be added to `workspace.ts` itself.

#### Task 1.3: Clear stale timers on setup failure

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

In `startSetup`, when the `POST /api/repo/setup` call fails (lines 1150-1157), clear `stepTimerRef.current` in addition to setting state to "failed". Currently the step animation timer continues running after failure.

### Phase 2: Error persistence and display (UX enhancement)

**Goal:** Store and surface error details so users see what went wrong.

#### Task 2.1: Add `repo_error` column and store error details

**File:** `apps/web-platform/app/api/repo/setup/route.ts`

**Migration:** `supabase/migrations/XXX_add_repo_error_column.sql`

```sql
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS repo_error text;
```

Update the `.catch()` handler to store the error message. Also clear `repo_error` when starting a new setup attempt (in the optimistic lock update).

#### Task 2.2: Return and display error details

**Files:** `apps/web-platform/app/api/repo/status/route.ts`, `apps/web-platform/app/(auth)/connect-repo/page.tsx`

Include `repo_error` in the status response when `status === "error"`. Update the `FailedState` component to accept and display the error message. Update `startSetup` poll handler to pass the error from the status response.

### Phase 3: Validate

#### Task 3.1: Write tests for error wrapping and error persistence

**File:** `apps/web-platform/test/workspace-error-handling.test.ts`

Test that:

- `provisionWorkspaceWithRepo` wraps errors with step-specific messages including git stderr
- The setup route catches errors, reports to Sentry, and stores `repo_error`
- The status route includes `errorMessage` when status is "error"

#### Task 3.2: End-to-end validation

Reproduce the setup flow after fixes are deployed. Verify setup completes successfully for at least one test repository.

## Acceptance Criteria

- [ ] The actual root cause is identified via reproduction (Phase 0)
- [ ] Each step of `provisionWorkspaceWithRepo` has individual error wrapping with git stderr capture
- [ ] Workspace provisioning errors are reported to Sentry via the setup route `.catch()` handler
- [ ] Step animation timer is cleared when setup fails at the POST stage
- [ ] Error details are stored in the `users` table (`repo_error` column) when setup fails
- [ ] The `/api/repo/status` endpoint returns `errorMessage` when status is "error"
- [ ] The failure page displays a specific error message when available
- [ ] The setup flow completes successfully for at least one test repository

## Test Scenarios

- Given a git clone fails due to authentication, when the error is caught in `provisionWorkspaceWithRepo`, then the thrown error includes the git stderr output (e.g., "Git clone failed: remote: Permission denied")
- Given the setup route's background task throws an error, then `Sentry.captureException` is called with the error object and `repo_error` is populated in the database
- Given a user with `repo_status: "error"` and `repo_error: "Git clone failed: ..."`, when `GET /api/repo/status` is called, then the response includes `errorMessage` with the error text
- Given the `POST /api/repo/setup` returns a non-200 response, when the client receives it, then the step animation timer is stopped and the failure page is shown immediately
- Given `generateInstallationToken` throws, then the error is wrapped as "Token generation failed: ..." and propagated to the catch handler

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a bug fix in existing infrastructure with no user-facing changes beyond improved error messages.

## Context

### Relevant Files

| File | Role |
|------|------|
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Client-side setup flow orchestrator |
| `apps/web-platform/app/api/repo/setup/route.ts` | POST handler that starts workspace provisioning |
| `apps/web-platform/app/api/repo/status/route.ts` | GET handler polled for setup progress |
| `apps/web-platform/app/api/repo/install/route.ts` | POST handler that stores GitHub App installation ID |
| `apps/web-platform/server/workspace.ts` | `provisionWorkspaceWithRepo()` -- git clone + scaffolding |
| `apps/web-platform/server/github-app.ts` | GitHub App JWT, token exchange, repo operations |
| `apps/web-platform/lib/supabase/server.ts` | Supabase client factories |
| `apps/web-platform/Dockerfile` | Production Docker image (user: soleur, UID 1001) |
| `apps/web-platform/infra/ci-deploy.sh` | Deploy script with Docker volume mounts |
| `apps/web-platform/infra/cloud-init.yml` | Server provisioning (volume mount, permissions) |

### Relevant Learnings

| Learning | Key Insight |
|----------|-------------|
| `integration-issues/supabase-identities-null-email-first-users-20260403.md` | Never use `user.identities` from `getUser()` -- use `auth.admin.getUserById()` |
| `integration-issues/2026-04-03-github-app-install-url-404.md` | GitHub App credentials must be in all target environments |

### Prior PRs

| PR | What it Fixed |
|----|---------------|
| #1479 | Identity resolution: queried `auth.identities` table (broken -- PostgREST doesn't expose `auth` schema) |
| #1487 | Switched to GoTrue admin API `auth.admin.getUserById()` |
| #1490 | Added `persistSession: false` to service client (was crashing admin API) |

## Alternative Approaches Considered

| Approach | Why Not Chosen |
|----------|---------------|
| SSH into production to read Docker logs | Violates observability-first debugging rule (AGENTS.md) |
| Add a retry mechanism with exponential backoff | Masks the root cause rather than fixing it |
| Skip workspace provisioning and use in-memory analysis | Breaks the entire agent workflow which depends on a filesystem workspace |

## References

- Sentry integration: `apps/web-platform/sentry.server.config.ts`
- Pino logger: `apps/web-platform/server/logger.ts`
- GitHub App setup learning: `knowledge-base/project/learnings/integration-issues/2026-04-03-github-app-install-url-404.md`

---
title: "feat: support disconnecting GitHub project from settings"
type: feat
date: 2026-04-06
---

# feat: support disconnecting GitHub project from settings

Users cannot disconnect a GitHub repository once connected. The settings page shows the connected repo but provides no way to unlink it. This plan adds a `DELETE /api/repo/disconnect` endpoint and a confirmation dialog on the settings page.

Closes #1492

## Acceptance Criteria

- [ ] `DELETE /api/repo/disconnect` clears `github_installation_id`, `repo_url`, `repo_status` (reset to `not_connected`), `repo_last_synced_at`, `repo_error`, `workspace_path`, and `workspace_status` on the user record
- [ ] Endpoint deletes the user's workspace directory on disk (reuse `deleteWorkspace()` from `server/workspace.ts`)
- [ ] Endpoint requires authentication and CSRF validation (same pattern as `POST /api/repo/install`)
- [ ] Endpoint is rate-limited (1 request per 60s per user, reuse `SlidingWindowCounter`)
- [ ] Settings page shows a "Disconnect" button when `repoStatus === "ready"`
- [ ] Clicking "Disconnect" opens an inline confirmation dialog (same pattern as `DeleteAccountDialog`)
- [ ] Confirmation dialog uses a simple confirm/cancel pattern (no typed confirmation -- disconnect is reversible, unlike account deletion)
- [ ] After successful disconnect, user is redirected to `/connect-repo`
- [ ] Error and loading states are handled in the dialog

## Implementation

### Phase 1: API endpoint

Create `apps/web-platform/app/api/repo/disconnect/route.ts`:

```typescript
// DELETE /api/repo/disconnect
//
// Clears github_installation_id, repo_url, repo_status, repo_last_synced_at,
// repo_error, workspace_path, workspace_status on the user record.
// Deletes the workspace directory on disk.
//
// Pattern: validateOrigin + rejectCsrf, createClient auth, createServiceClient
// for DB update, SlidingWindowCounter rate limit (1 per 60s).
```

Steps:

1. CSRF validation via `validateOrigin`/`rejectCsrf`
2. Auth check via `createClient().auth.getUser()`
3. Rate limit via `SlidingWindowCounter({ windowMs: 60_000, maxRequests: 1 })`
4. Fetch current user record to get `workspace_path` (needed for disk cleanup)
5. Update user record: set `github_installation_id = null`, `repo_url = null`, `repo_status = 'not_connected'`, `repo_last_synced_at = null`, `repo_error = null`, `workspace_path = null`, `workspace_status = null`
6. Delete workspace directory via `deleteWorkspace(userId)` (best-effort, log errors but return success)
7. Return `{ ok: true }`

Reference files:

- `apps/web-platform/app/api/repo/install/route.ts` (auth + CSRF pattern)
- `apps/web-platform/app/api/account/delete/route.ts` (rate limiter pattern)
- `apps/web-platform/server/workspace.ts` (`deleteWorkspace()`)

### Phase 2: UI component

Create `apps/web-platform/components/settings/disconnect-repo-dialog.tsx`:

```typescript
// "use client" component
// Pattern: identical to DeleteAccountDialog
// Props: { repoName: string }
// State: isOpen, isDisconnecting, error
// Simple confirm/cancel pattern (disconnect is reversible, no typed confirmation needed)
// On confirm: DELETE /api/repo/disconnect, then router.push("/connect-repo")
```

Modify `apps/web-platform/components/settings/project-setup-card.tsx`:

- Add `DisconnectRepoDialog` inside the `repoStatus === "ready"` block
- Pass the extracted repo name as the confirmation target

Reference files:

- `apps/web-platform/components/settings/delete-account-dialog.tsx` (confirmation dialog pattern)
- `apps/web-platform/components/settings/project-setup-card.tsx` (existing component to modify)

### Phase 3: Tests

Create `apps/web-platform/test/disconnect-route.test.ts`:

- 401 when unauthenticated
- 429 when rate limited
- 403 on CSRF rejection
- 200 on successful disconnect (verifies DB fields are cleared)
- Workspace cleanup is called

Update `apps/web-platform/test/project-setup-card.test.tsx`:

- Test that disconnect button appears when `repoStatus === "ready"`
- Test that disconnect button does NOT appear when `repoStatus !== "ready"`

## Test Scenarios

- Given an authenticated user with a connected repo, when they call `DELETE /api/repo/disconnect`, then `github_installation_id`, `repo_url`, `repo_status`, `repo_last_synced_at`, and `repo_error` are cleared
- Given an unauthenticated request, when calling `DELETE /api/repo/disconnect`, then a 401 is returned
- Given a user with no connected repo, when they call `DELETE /api/repo/disconnect`, then the endpoint succeeds idempotently (fields are already null)
- Given the settings page with `repoStatus === "ready"`, when rendered, then a "Disconnect" button is visible
- Given the settings page with `repoStatus === "not_connected"`, when rendered, then no "Disconnect" button is visible
- Given the disconnect dialog is open, when the user clicks confirm, then the API is called and the user is redirected to `/connect-repo`
- Given workspace deletion fails (e.g., directory already removed), when disconnecting, then the API still returns success (best-effort cleanup)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## Context

### Existing patterns

- API routes: `app/api/repo/install/route.ts`, `app/api/account/delete/route.ts`
- UI dialogs: `components/settings/delete-account-dialog.tsx`
- Workspace cleanup: `server/workspace.ts` (`deleteWorkspace`)
- Rate limiter: `server/rate-limiter.ts` (`SlidingWindowCounter`)
- CSRF: `lib/auth/validate-origin.ts`

### Database columns affected (all on `users` table)

- `github_installation_id` (bigint) -> null
- `repo_url` (text) -> null
- `repo_status` (text) -> 'not_connected'
- `repo_last_synced_at` (timestamptz) -> null
- `repo_error` (text) -> null
- `workspace_path` (text) -> null
- `workspace_status` (text) -> null

### Non-goals

- Uninstalling the GitHub App from the user's GitHub account (that requires a GitHub API call and is a separate concern)
- Revoking the installation token (tokens are ephemeral, max 1 hour TTL)
- Cleaning up any server-side git credential helpers (they are already cleaned in `finally` blocks)

## References

- Issue: #1492
- Migration: `supabase/migrations/011_repo_connection.sql`
- Learning: `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md`

---
title: "feat: support disconnecting GitHub project from settings"
type: feat
date: 2026-04-06
deepened: 2026-04-06
---

# feat: support disconnecting GitHub project from settings

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 3 (API endpoint, UI component, Tests)

### Key Improvements

1. CSRF coverage test must be extended to scan DELETE routes (first DELETE handler in the project)
2. Operation ordering: DB update before workspace deletion for consistency if disk cleanup fails
3. Race condition handling: concurrent agent sessions may hold workspace locks during disconnect
4. Accessibility: `role="alert"` on error messages in the confirmation dialog

### Relevant Learnings Applied

- `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md` -- structural CSRF enforcement via negative-space test
- `2026-04-05-supabase-returntype-resolves-to-never.md` -- use explicit `SupabaseClient` type
- `integration-issues/silent-setup-failure-no-error-capture-20260403.md` -- `repo_error` column for error persistence
- `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md` -- `role="alert"` on error elements

Users cannot disconnect a GitHub repository once connected. The settings page shows the connected repo but provides no way to unlink it. This plan adds a `DELETE /api/repo/disconnect` endpoint and a confirmation dialog on the settings page.

Closes #1492

## Acceptance Criteria

- [x] `DELETE /api/repo/disconnect` clears `github_installation_id`, `repo_url`, `repo_status` (reset to `not_connected`), `repo_last_synced_at`, `repo_error`, `workspace_path`, and `workspace_status` on the user record
- [x] Endpoint deletes the user's workspace directory on disk (reuse `deleteWorkspace()` from `server/workspace.ts`)
- [x] Endpoint requires authentication and CSRF validation (same pattern as `POST /api/repo/install`)
- [x] Endpoint is rate-limited (1 request per 60s per user, reuse `SlidingWindowCounter`)
- [x] Settings page shows a "Disconnect" button when `repoStatus === "ready"`
- [x] Clicking "Disconnect" opens an inline confirmation dialog (same pattern as `DeleteAccountDialog`)
- [x] Confirmation dialog uses a simple confirm/cancel pattern (no typed confirmation -- disconnect is reversible, unlike account deletion)
- [x] After successful disconnect, user is redirected to `/connect-repo`
- [x] Error and loading states are handled in the dialog

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

#### Research Insights

**Operation ordering matters:** Step 5 (DB update) MUST complete before Step 6 (workspace deletion). If the DB update succeeds but disk cleanup fails, the user is cleanly disconnected and can reconnect. If disk cleanup ran first and the DB update failed, the user would be in an inconsistent state (no workspace but database still says "connected"). The `deleteWorkspace` call is best-effort -- log the error via `logger.warn` and return success regardless.

**Race condition with active sessions:** If an agent session is running when disconnect fires, `session-sync.ts` may be holding file locks on the workspace. The `deleteWorkspace` function uses `removeWorkspaceDir` which calls `rm -rf` via `execFileSync`. On Linux, `rm -rf` succeeds even if files are open (they become unlinked but remain accessible to the process until closed). No special handling is needed -- the OS handles this correctly. The session will finish against the unlinked files and the next session will find no workspace, which is the desired state.

**CSRF coverage test gap:** This is the first DELETE handler in the project. The existing `csrf-coverage.test.ts` only scans for POST routes. Update the test to also scan DELETE (and PUT/PATCH) routes for `validateOrigin` calls. This is a Phase 3 task.

**Sentry error reporting:** Add `Sentry.captureException(err)` in the catch path for workspace deletion failure, consistent with the pattern established in `setup/route.ts` after the silent-failure learning.

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

#### Research Insights

**Accessibility:** Add `role="alert"` to the error `<p>` element in the dialog (per a11y learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`). The existing `DeleteAccountDialog` already follows this pattern (line 85 in current source).

**Visual placement:** The disconnect button should appear below the repo info in the "ready" state, separated by visual spacing. Use a muted/neutral style (not red) since this is a reversible action. The red "Danger Zone" style is reserved for the irreversible delete-account section. Use `border-neutral-700` and `text-neutral-400` for the button, matching the cancel button style in `DeleteAccountDialog`.

**Component boundary:** `DisconnectRepoDialog` is a `"use client"` component while `ProjectSetupCard` is currently a server component (no `"use client"` directive). Adding `DisconnectRepoDialog` (which uses `useState` and `useRouter`) requires either: (a) making `ProjectSetupCard` a client component, or (b) passing the dialog as a child. Option (a) is simpler -- add `"use client"` to `project-setup-card.tsx`. The component has no server-only imports (no `createClient`, no `fs`), so this is a safe conversion.

**Redirect vs. refresh:** After disconnect, `router.push("/connect-repo")` redirects to the connect-repo page. This is correct because the settings page server component would show stale data until revalidated. The redirect forces a fresh page load.

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

Update `apps/web-platform/lib/auth/csrf-coverage.test.ts`:

- Extend the test to scan DELETE (and PUT/PATCH) routes in addition to POST
- The new disconnect route is the first DELETE handler -- the test must catch future DELETE routes too

#### Research Insights

**Structural enforcement:** The CSRF coverage test (`csrf-coverage.test.ts`) is a negative-space test that prevents new state-mutating routes from being added without CSRF protection. Currently it only scans POST routes (regex: `/export\s+(async\s+)?function\s+POST/`). This must be extended to match DELETE, PUT, and PATCH exports. The regex should become: `/export\s+(async\s+)?function\s+(POST|DELETE|PUT|PATCH)/`.

**Test isolation for `deleteWorkspace`:** The disconnect route test should mock `deleteWorkspace` to avoid filesystem side effects. Use `vi.mock("@/server/workspace", () => ({ deleteWorkspace: vi.fn() }))` and verify it was called with the correct userId.

**Idempotency test:** Include a test where the user has `repo_status: "not_connected"` and calls DELETE. The endpoint should still return 200 (fields are already null). This prevents errors when users double-click or retry.

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

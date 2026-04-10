---
title: "fix: Create project 'Start Fresh' shows import screen and vision.md gets sync command text"
type: fix
date: 2026-04-10
deepened: 2026-04-10
---

# fix: Create Project Start Fresh Flow

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 5 (Technical Approach, Implementation Details, Test Scenarios, Edge Cases, References)
**Research sources:** 6 institutional learnings, existing test patterns (vision-creation.test.ts, workspace-error-handling.test.ts, start-fresh-onboarding.test.tsx), source code analysis of connect-repo page, workspace.ts, agent-runner.ts, vision-helpers.ts

### Key Improvements

1. Discovered that the `/api/repo/status` endpoint already returns `repo_status` as a string field -- no new API needed for the ready-status check in connect-repo. The auto-detect guard can call this existing endpoint.
2. Identified that `provisionWorkspace()` (Start Fresh path without a repo) and `provisionWorkspaceWithRepo()` (Connect Existing path) are separate functions -- the sentinel file can be precisely placed only in the Start Fresh path without any conditional logic.
3. Found concrete test patterns from existing test files: `vision-creation.test.ts` uses `vi.mock("fs")` with dynamic imports for module reset; `workspace-error-handling.test.ts` uses `vi.doMock()` for server-side module testing; `start-fresh-onboarding.test.tsx` uses `buildMockTree()` helper for KB tree mocking.
4. Applied learning from `2026-04-02-defensive-state-clear-on-useeffect-remount`: the auto-detect effect should clear any stale state (repos, loading) before proceeding, preventing flash of old repo list on remount.
5. Applied learning from `2026-04-06-vitest-module-level-supabase-mock-timing`: test mocks for route handlers must use the `vi.mock()` factory hoisting pattern, not inline overrides that run after module initialization.
6. The new `POST /api/vision` route MUST include `validateOrigin` CSRF protection -- structural test enforces this (learning from 2026-03-20 CSRF coverage).

## Overview

Two bugs in the "Start Fresh" project creation flow:

1. After creating a new project via the "Start Fresh" card, users see the repository import screen (select existing repos) instead of being redirected to the dashboard where the guided onboarding (first-run vision prompt) awaits them.
2. `vision.md` gets populated with `### Vision /soleur:sync --headless` instead of the founder's actual startup idea, because the welcome hook suggests `/soleur:sync` and the agent runs it as its first action, which `tryCreateVision()` captures as the "first message."

## Problem Statement

### Bug 1: Import Screen Shown After Start Fresh

When a founder creates a new project via the "Start Fresh" card on `/connect-repo`, the expected flow is:

1. Choose state -> Create project state -> GitHub redirect (if needed) -> Setup -> Ready -> Dashboard
2. On dashboard, the first-run view prompts "Tell your organization what you're building"

The actual flow breaks when:

- **Scenario A (sessionStorage lost):** The user goes through GitHub redirect for app installation. On return, the callback useEffect checks `sessionStorage` for `soleur_create_project`. If sessionStorage was cleared (private browsing, browser restart, cross-domain redirect), the pending create intent is lost. The effect falls through to `fetchRepos()`, which lists the user's repositories and transitions to `select_project` state -- the import screen.

- **Scenario B (auto-detect on revisit):** After project creation completes and the user reaches the "Ready" state, if they navigate away and return to `/connect-repo` (e.g., via the login callback which checks `repo_status`), the auto-detect-installation effect (line 97-123) fires on mount. Since the GitHub App is now installed and repos exist (including the just-created one), it transitions to `select_project` state -- showing the import screen for a project that was just created fresh.

- **Scenario C (race condition):** The setup flow calls `startSetup()` which fires `POST /api/repo/setup` and polls for completion. During the polling window, if the user refreshes or the page re-mounts, the auto-detect effect fires and shows the repo list.

### Bug 2: Vision.md Gets Sync Command Text

The `tryCreateVision(workspacePath, userMessage)` function in `agent-runner.ts` writes the user's first message verbatim to `vision.md`. The welcome hook (`plugins/soleur/hooks/welcome-hook.sh`) outputs a suggestion to run `/soleur:sync` on first session. When the web platform agent session starts, the hook fires and the agent may execute `/soleur:sync --headless` as its first action. If this happens before the founder sends their own message, or if the agent's response to the hook gets captured as the "user message," `vision.md` ends up containing `### Vision /soleur:sync --headless` instead of the founder's actual vision.

The root cause is that `tryCreateVision` is called in `startAgentSession()` with the `userMessage` parameter, but it does not validate that the message is an actual user-authored startup idea versus an automated command invocation. Additionally, the welcome hook fires for fresh workspaces created via "Start Fresh" even though these workspaces already have the guided onboarding flow.

## Proposed Solution

### Fix 1: Skip Auto-Detect When Returning From Start Fresh Setup

**Approach:** After the "Start Fresh" flow creates a repo and setup completes (repo_status = "ready"), the user should be redirected to `/dashboard` and never see the connect-repo page again. The fix has two parts:

**1a. Add a `source` flag to connect-repo state tracking.**

When the user clicks "Create Project" from the choose state, set a sessionStorage flag `soleur_create_flow=true`. The auto-detect effect (line 97-123) should check for this flag and skip auto-detection when the user is in the create flow -- the create flow handles its own state transitions.

**1b. After setup completes, redirect directly to dashboard.**

In the `handleOpenDashboard` handler (and the Ready state's "Open Dashboard" button), the redirect already goes to `/dashboard`. The issue is if the user returns to `/connect-repo` after setup is "ready". The auto-detect effect should check if the user's `repo_status` is already "ready" and redirect to `/dashboard` immediately instead of showing the repo list.

**1c. Guard the callback useEffect against lost sessionStorage.**

When the GitHub callback fires (`installation_id` in URL) and no `soleur_create_project` data exists in sessionStorage, check `repo_status` before falling through to `fetchRepos()`. If `repo_status === "ready"`, redirect to `/dashboard`. If `repo_status === "not_connected"` AND no pending create data, THEN fall through to `fetchRepos()`.

### Fix 2: Guard Vision.md Creation Against Non-User Content

**Approach:** Filter out messages that are command invocations or automated content before writing to vision.md.

**2a. Add content validation in `tryCreateVision()`.**

Skip vision creation if the message content:

- Starts with `/` (slash command)
- Starts with `@` (leader mention that is just routing, not content)
- Is shorter than 10 characters (too short to be a meaningful vision)
- Contains only a command pattern (e.g., matches `/soleur:*` or `### Vision`)

**2b. Suppress welcome hook for Start Fresh workspaces.**

The welcome hook fires based on the absence of `.claude/soleur-welcomed.local`. For "Start Fresh" workspaces, the `provisionWorkspace()` function should create this sentinel file during provisioning, so the hook never fires. Start Fresh users get the guided onboarding flow instead.

Alternatively, the workspace provisioning in `provisionWorkspaceWithRepo()` (used for both Start Fresh and Connect Existing) can conditionally create the sentinel. For Start Fresh (empty repo just created), create it. For Connect Existing (existing repo with code), skip it so the user gets the sync suggestion.

**2c. Move vision creation to the dashboard first-run handler.**

Currently, `tryCreateVision` fires in `startAgentSession()`. A more robust approach: create vision.md from the first-run form submission on the dashboard (`handleFirstRunSend` in `page.tsx`). This guarantees the content is the founder's typed idea, not an agent-generated or hook-suggested command. The server-side API endpoint that handles the first message can create vision.md from the request body before starting the agent session.

## Technical Approach

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Add `soleur_create_flow` sessionStorage flag in `handleCreateNew`/`handleStartOver`/`handleOpenDashboard`; add repo status check to auto-detect effect (line 97-123) and callback effect (line 125-185); pass `source` param to `startSetup()` |
| `apps/web-platform/server/vision-helpers.ts` | Add content validation to `tryCreateVision()` -- reject slash commands, bare mentions, content < 10 chars, malformed sync output |
| `apps/web-platform/server/workspace.ts` | Add `options?: { suppressWelcomeHook?: boolean }` parameter to `provisionWorkspaceWithRepo()`; create `.claude/soleur-welcomed.local` sentinel when flag is true. Also create sentinel in `provisionWorkspace()` (auth callback path). |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Add fire-and-forget `POST /api/vision` call in `handleFirstRunSend` before navigating to chat |
| `apps/web-platform/app/api/repo/setup/route.ts` | Accept optional `source` field in request body; pass `{ suppressWelcomeHook: source === "start_fresh" }` to `provisionWorkspaceWithRepo()` |

### Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/app/api/vision/route.ts` | POST endpoint to create vision.md from dashboard first-run form. Includes CSRF via `validateOrigin`, auth via supabase, workspace path lookup, delegates to `tryCreateVision()`. |

### Files to Extend (Tests)

| File | New Tests |
|------|-----------|
| `apps/web-platform/test/vision-creation.test.ts` | Content validation: slash command rejected, short content rejected, malformed sync output rejected, mention-with-content accepted |
| `apps/web-platform/test/workspace-error-handling.test.ts` | Sentinel file: created by `provisionWorkspace()`, created by `provisionWorkspaceWithRepo({ suppressWelcomeHook: true })`, NOT created by default `provisionWorkspaceWithRepo()` |
| New: `apps/web-platform/test/connect-repo-guards.test.tsx` | Auto-detect guards: skips when `soleur_create_flow` set, redirects when repo_status is ready, callback falls through to fetchRepos when not ready |
| New: `apps/web-platform/test/vision-route.test.ts` | Vision API: creates file with valid content, rejects slash commands (400), rejects unauthenticated (401), rejects missing content (400), CSRF validation |

### Key Implementation Details

**1. Auto-detect guard in connect-repo (`page.tsx` line 97-123):**

The auto-detect effect runs on mount when no GitHub callback params are present. It must be guarded in two ways: (a) skip when user is actively in the create flow, and (b) redirect when project is already ready.

```typescript
// In the auto-detect effect (line 97-123), add at the top:
useEffect(() => {
  if (searchParams.get("installation_id")) return;
  if (detectAttemptedRef.current) return;
  detectAttemptedRef.current = true;

  // Guard 1: Skip if user is in create flow (sessionStorage flag)
  try {
    if (sessionStorage.getItem("soleur_create_flow") === "true") return;
  } catch { /* sessionStorage unavailable */ }

  (async () => {
    // Guard 2: Check repo status first -- redirect if already ready
    // Uses existing GET /api/repo/status endpoint (returns { status: string })
    try {
      const statusRes = await fetch("/api/repo/status");
      if (statusRes.ok) {
        const statusData = await statusRes.json();
        if (statusData.status === "ready") {
          router.push("/dashboard");
          return;
        }
      }
    } catch { /* continue to auto-detect */ }

    try {
      const res = await fetch("/api/repo/detect-installation", {
        method: "POST",
      });
      // ... existing auto-detect logic ...
    } catch { /* ... */ }
  })();
}, []);
```

**Important:** The status check uses the existing `GET /api/repo/status` endpoint which returns `{ status: "ready" | "not_connected" | "cloning" | "error", ... }`. No new API endpoint needed.

**Learning applied (2026-04-02-defensive-state-clear-on-useeffect-remount):** Clear stale repo/loading state at the top of the effect to prevent flash of old repo list if the component remounts via bfcache or soft navigation.

**2. Create-flow sessionStorage flag:**

```typescript
// In handleCreateNew():
function handleCreateNew() {
  try {
    sessionStorage.setItem("soleur_create_flow", "true");
  } catch { /* sessionStorage unavailable */ }
  setState("create_project");
}

// In handleOpenDashboard() and handleStartOver():
function handleOpenDashboard() {
  try {
    sessionStorage.removeItem("soleur_create_flow");
  } catch { /* sessionStorage unavailable */ }
  router.push(consumeReturnTo());
}

function handleStartOver() {
  try {
    sessionStorage.removeItem("soleur_create_flow");
  } catch { /* sessionStorage unavailable */ }
  setPendingCreate(null);
  setState("choose");
}
```

**3. Callback effect guard against lost sessionStorage (line 125-185):**

When the GitHub callback fires with `installation_id` but sessionStorage has no `soleur_create_project` data, the effect currently falls through to `fetchRepos()`. Add a repo status check before falling through:

```typescript
// After the pendingCreateData check (line 160-178):
if (pendingCreateData) {
  // ... existing create logic ...
} else {
  // SessionStorage may have been lost. Check if project is already ready
  // before falling through to the import screen.
  try {
    const statusRes = await fetch("/api/repo/status");
    if (statusRes.ok) {
      const statusData = await statusRes.json();
      if (statusData.status === "ready") {
        router.push("/dashboard");
        return;
      }
    }
  } catch { /* fall through to fetchRepos */ }
  await fetchRepos();
}
```

**4. Vision content validation in `tryCreateVision()` (`vision-helpers.ts`):**

```typescript
export async function tryCreateVision(
  workspacePath: string,
  content: string,
): Promise<void> {
  // Content validation: reject non-user content
  const trimmed = content.trim();
  if (trimmed.length < 10) return;          // Too short to be a vision
  if (trimmed.startsWith("/")) return;       // Slash command (e.g., /soleur:sync)
  if (trimmed.startsWith("@") && !trimmed.includes(" ")) return; // Bare leader mention
  if (/^###?\s/.test(trimmed) && /\/soleur:/.test(trimmed)) return; // Malformed sync output

  // ... existing implementation unchanged ...
}
```

**Edge case:** The `@` check uses `!trimmed.includes(" ")` to allow messages like `@cpo I'm building a marketplace` (which is a genuine vision with a mention prefix) while rejecting bare `@cpo` (just routing, no content).

**5. Sentinel file in `provisionWorkspace()` (`workspace.ts`):**

```typescript
// In provisionWorkspace() (Start Fresh path), after line 70 (writing settings.json):
// Suppress welcome hook for Start Fresh workspaces -- guided onboarding handles first run
writeFileSync(join(claudeDir, "soleur-welcomed.local"), "");
```

**Important:** This goes ONLY in `provisionWorkspace()` (no-repo path, used for Start Fresh). The `provisionWorkspaceWithRepo()` function (used for Connect Existing) must NOT create this file, because Connect Existing users benefit from the welcome hook's `/soleur:sync` suggestion.

Verification: `provisionWorkspace()` is called from `callback/route.ts` line 152 (fallback workspace creation for new users) and from `ensureWorkspaceProvisioned()`. The `provisionWorkspaceWithRepo()` is called only from `setup/route.ts` for repo cloning. Both Start Fresh and Connect Existing go through `provisionWorkspaceWithRepo()` for the clone step, but Start Fresh first provisions an empty workspace. Wait -- tracing the actual flow:

- **Start Fresh:** `handleCreateSubmit` -> `POST /api/repo/create` -> creates GitHub repo -> returns `repoUrl` -> `startSetup(repoUrl, fullName)` -> `POST /api/repo/setup` -> `provisionWorkspaceWithRepo()`
- **Connect Existing:** `handleSelectProject` -> `startSetup(repoUrl, fullName)` -> `POST /api/repo/setup` -> `provisionWorkspaceWithRepo()`

Both paths use `provisionWorkspaceWithRepo()`. The `provisionWorkspace()` is only for the initial workspace creation in the auth callback (before any repo is connected).

**Revised approach:** Since both Start Fresh and Connect Existing use `provisionWorkspaceWithRepo()`, the sentinel cannot be placed there unconditionally. Instead, pass a `suppressWelcomeHook` flag:

```typescript
// In provisionWorkspaceWithRepo(), add optional parameter:
export async function provisionWorkspaceWithRepo(
  userId: string,
  repoUrl: string,
  installationId: number,
  userName?: string,
  userEmail?: string,
  options?: { suppressWelcomeHook?: boolean },
): Promise<string> {
  // ... existing implementation ...

  // Step 8: Create .claude directory and settings (existing)
  const claudeDir = join(workspacePath, ".claude");
  ensureDir(claudeDir);
  writeFileSync(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_SETTINGS, null, 2) + "\n",
  );

  // Step 8b: Suppress welcome hook for Start Fresh workspaces
  if (options?.suppressWelcomeHook) {
    writeFileSync(join(claudeDir, "soleur-welcomed.local"), "");
  }

  // ... rest of implementation ...
}
```

The caller in `setup/route.ts` needs to know whether this is a Start Fresh or Connect Existing setup. The `POST /api/repo/setup` endpoint could accept an optional `source: "start_fresh" | "connect_existing"` field in the request body. Or simpler: check if the repo was just created (empty repo) vs. has existing commits. The simplest approach: the `POST /api/repo/create` endpoint already creates the repo and returns the URL. After creation, it can set a flag in the DB (`repo_source: "start_fresh"`), and the setup route reads it.

**Simplest implementation:** Add `source` to the `POST /api/repo/setup` request body. The connect-repo page passes `source: "start_fresh"` from the create flow and `source: "connect_existing"` from the select-project flow.

```typescript
// In setup/route.ts:
const isStartFresh = body.source === "start_fresh";

provisionWorkspaceWithRepo(
  user.id,
  repoUrl,
  userData.github_installation_id,
  userName,
  userEmail,
  { suppressWelcomeHook: isStartFresh },
)
```

```typescript
// In connect-repo page.tsx, update startSetup to accept source:
const startSetup = useCallback(
  async (repoUrl: string, repoName: string, source?: "start_fresh" | "connect_existing") => {
    // ... existing setup ...
    const res = await fetch("/api/repo/setup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ repoUrl, source: source ?? "connect_existing" }),
    });
    // ...
  },
  [],
);

// Update callers:
// In handleCreateSubmit (line 444): startSetup(data.repoUrl, data.fullName, "start_fresh")
// In callback effect (line 176): startSetup(data.repoUrl, data.fullName, "start_fresh")
// In handleSelectProject (line 525): startSetup(..., "connect_existing")
```

**6. Vision API endpoint (`app/api/vision/route.ts`):**

```typescript
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { tryCreateVision } from "@/server/vision-helpers";

/**
 * POST /api/vision
 *
 * Creates vision.md from the dashboard first-run form.
 * Called fire-and-forget from the client -- errors are non-blocking.
 *
 * Body: { content: string }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/vision", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.content || typeof body.content !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid content" },
      { status: 400 },
    );
  }

  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select("workspace_path")
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path) {
    return NextResponse.json(
      { error: "Workspace not provisioned" },
      { status: 503 },
    );
  }

  try {
    await tryCreateVision(userData.workspace_path, body.content);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json(
      { error: "Failed to create vision" },
      { status: 500 },
    );
  }
}
```

**CSRF note (learning: 2026-03-20):** The `validateOrigin` call is mandatory for all POST routes. The existing structural test at `test/csrf.test.ts` verifies every route handler file exports a POST function that calls `validateOrigin`. Adding the route without CSRF protection will fail CI.

**7. Dashboard first-run form update (`page.tsx`):**

```typescript
const handleFirstRunSend = useCallback(
  (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = e.currentTarget;
    const input = form.elements.namedItem("idea") as HTMLInputElement;
    const message = input?.value?.trim();
    if (!message) return;
    completeOnboarding();

    // Create vision.md server-side from the typed idea (fire-and-forget)
    fetch("/api/vision", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: message }),
    }).catch(() => { /* non-blocking -- agent will create via tryCreateVision fallback */ });

    const params = new URLSearchParams();
    params.set("msg", message);
    router.push(`/dashboard/chat/new?${params.toString()}`);
  },
  [router, completeOnboarding],
);
```

This dual-write strategy provides belt-and-suspenders reliability: the dashboard creates vision.md from user input (guaranteed correct content), and `tryCreateVision` in agent-runner.ts serves as a fallback (content-validated to reject commands). If both fire, the `wx` flag in `tryCreateVision` ensures only the first write wins.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Remove auto-detect entirely | Auto-detect serves a valid purpose for users who installed the GitHub App outside the connect-repo flow. Removing it breaks that use case. |
| Server-side redirect in middleware | Would require an additional DB query on every page load. The client-side approach is sufficient and cheaper. |
| Disable welcome hook globally | Welcome hook provides value for "Connect Existing" projects that benefit from `/soleur:sync`. Only Start Fresh should suppress it. |
| Block all first messages from vision.md | Too aggressive -- the first message SHOULD become vision.md when it is a genuine startup description from the first-run form. |

## Acceptance Criteria

### Functional Requirements

- [ ] "Start Fresh" flow completes without showing the import screen (repo list)
- [ ] After Start Fresh setup completes, user lands on dashboard first-run view
- [ ] Vision.md created from first-run form contains the founder's typed idea, not a slash command
- [ ] `tryCreateVision()` rejects slash commands (`/soleur:sync`, etc.) and very short messages
- [ ] Welcome hook does not fire for Start Fresh workspaces (sentinel created during provisioning)
- [ ] "Connect Existing" flow continues to work unchanged (auto-detect, repo list, sync suggestion)
- [ ] Returning to `/connect-repo` after project is "ready" redirects to `/dashboard`
- [ ] SessionStorage loss during GitHub redirect does not show import screen for Start Fresh users

### Non-Functional Requirements

- [ ] No new Supabase migrations
- [ ] No changes to the tag-and-route system
- [ ] Backward compatible with existing Connect Existing flow

## Test Scenarios

### Acceptance Tests

- Given a new user on the choose screen, when they click "Create Project" and complete the Start Fresh flow, then they see the "Ready" state followed by the dashboard first-run view (not the repo list)
- Given a Start Fresh project that is already set up (repo_status=ready), when the user navigates to `/connect-repo`, then they are redirected to `/dashboard`
- Given a Start Fresh workspace, when an agent session starts, then the welcome hook does NOT suggest `/soleur:sync` (sentinel already exists)
- Given the first-run dashboard form, when the founder types "I'm building a marketplace for freelance designers" and submits, then `vision.md` contains that text
- Given an agent session where the first message is `/soleur:sync --headless`, when `tryCreateVision` is called, then no vision.md is created (slash command rejected)

### Edge Cases

- Given the GitHub redirect callback with lost sessionStorage (no `soleur_create_project`), when the auto-detect finds repos, then the system checks `repo_status` and redirects to `/dashboard` if ready
- Given a user who chose "Start Fresh" but the GitHub App install fails, when they return, then they see the interrupted state (not the repo list)
- Given a "Connect Existing" project, when the user visits `/connect-repo`, then auto-detect still works normally (sentinel not created, welcome hook fires)
- Given a vision.md content that is just `@cpo` (too short), when `tryCreateVision` is called, then no file is created
- Given a founder who refreshes during setup polling, when the page re-mounts, then setup continues (not interrupted by auto-detect)
- Given a vision.md content of `@cpo I'm building a marketplace for designers`, when `tryCreateVision` is called, then the file IS created (mention with content passes validation)
- Given a `POST /api/vision` request without Origin header, then the request returns 403 (CSRF rejection)

### Research Insights: Test Implementation Patterns

**Pattern 1: Vision content validation tests** (extend existing `test/vision-creation.test.ts`)

Follow the existing test pattern which uses `vi.mock("fs")` with dynamic `import()` and `beforeEach` module reset:

```typescript
// Add to the existing "tryCreateVision" describe block:
it("rejects slash commands", async () => {
  await tryCreateVision(WORKSPACE, "/soleur:sync --headless");
  expect(mockWriteFile).not.toHaveBeenCalled();
});

it("rejects content shorter than 10 characters", async () => {
  await tryCreateVision(WORKSPACE, "@cpo");
  expect(mockWriteFile).not.toHaveBeenCalled();
});

it("rejects malformed sync output", async () => {
  await tryCreateVision(WORKSPACE, "### Vision /soleur:sync --headless");
  expect(mockWriteFile).not.toHaveBeenCalled();
});

it("accepts mention with content (user message with leader prefix)", async () => {
  mockMkdir.mockResolvedValueOnce(undefined);
  mockWriteFile.mockResolvedValueOnce(undefined);

  await tryCreateVision(WORKSPACE, "@cpo I'm building a marketplace for designers");
  expect(mockWriteFile).toHaveBeenCalled();
});
```

**Pattern 2: Workspace sentinel tests** (extend existing `test/workspace-error-handling.test.ts`)

Follow the existing pattern which sets `process.env.WORKSPACES_ROOT` before imports and uses `vi.doMock()`:

```typescript
import { existsSync } from "fs";
import { join } from "path";

describe("provisionWorkspace sentinel file", () => {
  test("creates soleur-welcomed.local sentinel in .claude/", async () => {
    const { provisionWorkspace } = await import("../server/workspace");
    const userId = randomUUID();
    const workspacePath = await provisionWorkspace(userId);

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(true);
  });
});

describe("provisionWorkspaceWithRepo sentinel file", () => {
  test("does not create sentinel when suppressWelcomeHook is false/omitted", async () => {
    // ... mock github-app, clone successfully ...
    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();
    const workspacePath = await provisionWorkspaceWithRepo(
      userId, "https://github.com/test/repo", 12345,
    );

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(false);
  });

  test("creates sentinel when suppressWelcomeHook is true", async () => {
    // ... mock github-app, clone successfully ...
    const workspacePath = await provisionWorkspaceWithRepo(
      userId, "https://github.com/test/repo", 12345,
      undefined, undefined, { suppressWelcomeHook: true },
    );

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(true);
  });
});
```

**Pattern 3: Connect-repo auto-detect guard tests** (extend or new file `test/connect-repo-guards.test.tsx`)

Follow the existing `start-fresh-onboarding.test.tsx` pattern with `vi.mock("next/navigation")` and `globalThis.fetch` mocking:

```typescript
// Key assertions:
it("skips auto-detect when soleur_create_flow is in sessionStorage", async () => {
  sessionStorage.setItem("soleur_create_flow", "true");
  render(<ConnectRepoPage />);
  // Verify fetch was not called with /api/repo/detect-installation
  expect(fetchCalls.find(c => c.url.includes("detect-installation"))).toBeUndefined();
});

it("redirects to /dashboard when repo_status is ready", async () => {
  mockFetch("/api/repo/status", { status: "ready" });
  render(<ConnectRepoPage />);
  await waitFor(() => {
    expect(mockPush).toHaveBeenCalledWith("/dashboard");
  });
});
```

**Learning applied (2026-04-06-vitest-module-level-supabase-mock-timing):** Route handler tests must define tracked mocks inside the `vi.mock()` factory to survive module initialization. The vision API route test should follow this pattern.

**Learning applied (2026-03-30-tdd-enforcement-gap):** Test files for `.tsx` components use `happy-dom` environment (configured in `vitest.config.ts` via `environmentMatchGlobs`). Server-side `.ts` test files use `node` environment. The vision API route test is server-side (node), while the connect-repo guard test is a React component test (happy-dom).

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Both bugs are in the web platform frontend and server-side agent pipeline. Fix 1 is purely client-side state management in the connect-repo page. Fix 2 touches vision-helpers.ts (content validation), workspace.ts (sentinel creation), and potentially a new API route. All changes are low-risk and well-scoped. The sentinel file approach for suppressing the welcome hook is clean -- it uses the same mechanism the hook already checks.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

No new UI surfaces. The fix ensures users reach the EXISTING first-run dashboard view that was already built and reviewed in #1751. The only UX change is removing the wrong screen (import screen) from the Start Fresh flow.

## Dependencies and Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Start Fresh onboarding already implemented (#1751) | LOW -- all checked off in tasks.md | Code exists and is tested (633 passing tests) |
| sessionStorage availability | MEDIUM -- private browsing, cross-domain | Server-side fallback via `/api/repo/status` check before falling through to fetchRepos |
| Welcome hook sentinel mechanism | LOW -- simple file existence check | Same mechanism already used by the hook. Verified: hook checks `[[ -f "$SENTINEL_FILE" ]] && exit 0` |
| `provisionWorkspaceWithRepo` API change | LOW -- adding optional parameter | Optional `options` parameter with default `undefined` -- all existing callers continue to work unchanged |
| New `POST /api/vision` route | LOW -- simple endpoint | Follows existing route patterns. Structural CSRF test will enforce `validateOrigin`. Content validation delegates to existing `tryCreateVision` |
| Dual-write vision.md (dashboard + agent-runner) | LOW -- `wx` flag prevents overwrite | `tryCreateVision` uses `O_EXCL` flag, so only the first write wins. Both paths create identical content format. If dashboard write succeeds, agent-runner write silently returns. |
| `startSetup` signature change (adding `source` param) | LOW -- backward compatible | Optional parameter with default `"connect_existing"`. Three existing callers updated in the same file. |

## References and Research

### Internal References

- Plan: `knowledge-base/project/plans/2026-04-07-feat-start-fresh-onboarding-plan.md`
- Spec: `knowledge-base/project/specs/feat-start-fresh-onboarding/spec.md`
- Connect-repo page: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- Choose state component: `apps/web-platform/components/connect-repo/choose-state.tsx`
- Vision helpers: `apps/web-platform/server/vision-helpers.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`
- Workspace provisioning: `apps/web-platform/server/workspace.ts`
- Welcome hook: `plugins/soleur/hooks/welcome-hook.sh`
- Dashboard page: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- Auth callback: `apps/web-platform/app/(auth)/callback/route.ts`
- Setup API: `apps/web-platform/app/api/repo/setup/route.ts`
- Onboarding tests: `apps/web-platform/test/start-fresh-onboarding.test.tsx`
- Vision tests: `apps/web-platform/test/vision-creation.test.ts`

### Institutional Learnings Applied

- **Fire-and-forget promises need `.catch()`** (2026-03-20) -- already applied in `tryCreateVision` call site; also applies to the new `fetch("/api/vision", ...)` call in `handleFirstRunSend`
- **Agent context-blindness and vision misalignment** (2026-02-22) -- the root cause of bug 2; agents that produce artifacts consumed by downstream must read canonical sources first. Here, `tryCreateVision` must validate content source, not blindly trust the `userMessage` parameter
- **Defensive state clear on useEffect remount** (2026-04-02) -- the auto-detect effect in connect-repo should clear stale `repos` and `reposLoading` state before proceeding, preventing flash of old repo list on bfcache restore or soft navigation
- **Vitest module-level mock timing** (2026-04-06) -- test mocks for the vision API route handler must use the `vi.mock()` factory hoisting pattern, not inline overrides. The supabase client is created at module level.
- **SessionStart hook API contract** (2026-03-04) -- the welcome hook's `additionalContext` field is the mechanism by which `/soleur:sync` is suggested; suppressing it via sentinel is the correct approach per the hook spec
- **TDD enforcement and React test setup** (2026-03-30) -- use `happy-dom` for `.tsx` component tests, `node` for server-side `.ts` tests; run via vitest not bun test; `esbuild: { jsx: "automatic" }` for JSX transform

### Related Issues

- #1872 -- This issue (Create Project Issues)
- #1751 -- Start Fresh onboarding (guided first-run, already implemented)
- #1645 -- CA certificates fix for Docker (related setup failure, merged)

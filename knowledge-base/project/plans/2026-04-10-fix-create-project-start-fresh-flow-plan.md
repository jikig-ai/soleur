---
title: "fix: Create project 'Start Fresh' shows import screen and vision.md gets sync command text"
type: fix
date: 2026-04-10
---

# fix: Create Project Start Fresh Flow

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
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Add create-flow sessionStorage flag; guard auto-detect effect against ready status; guard callback effect against lost sessionStorage |
| `apps/web-platform/server/vision-helpers.ts` | Add content validation to `tryCreateVision()` -- reject slash commands and too-short content |
| `apps/web-platform/server/workspace.ts` | In `provisionWorkspace()`, create `.claude/soleur-welcomed.local` sentinel so welcome hook does not fire for Start Fresh workspaces |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Add API call in `handleFirstRunSend` to create vision.md server-side from the form input, ensuring the content is user-authored |

### Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/app/api/vision/route.ts` | POST endpoint to create vision.md from dashboard first-run form (validates content, calls `tryCreateVision`) |

### Key Implementation Details

**1. Auto-detect guard in connect-repo:**

```typescript
// In the auto-detect effect (line 97-123):
// Skip if user is in create flow
try {
  if (sessionStorage.getItem("soleur_create_flow") === "true") return;
} catch { /* sessionStorage unavailable */ }
```

**2. Ready-status redirect:**

```typescript
// After auto-detect finds repos, check if user already has a ready project
const statusRes = await fetch("/api/repo/status");
if (statusRes.ok) {
  const statusData = await statusRes.json();
  if (statusData.status === "ready") {
    router.push("/dashboard");
    return;
  }
}
```

**3. Vision content validation:**

```typescript
// In tryCreateVision, before writing:
const trimmed = content.trim();
if (trimmed.length < 10) return;
if (trimmed.startsWith("/")) return;
if (/^###?\s/.test(trimmed) && trimmed.includes("/soleur:")) return;
```

**4. Sentinel file in provisionWorkspace:**

```typescript
// In provisionWorkspace() (Start Fresh path), after creating .claude/:
writeFileSync(join(claudeDir, "soleur-welcomed.local"), "");
```

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
| Start Fresh onboarding already implemented (#1751) | LOW -- all checked off in tasks.md | Code exists and is tested |
| sessionStorage availability | MEDIUM -- private browsing, cross-domain | Server-side fallback via repo_status check |
| Welcome hook sentinel mechanism | LOW -- simple file existence check | Same mechanism already used by the hook |

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

- Fire-and-forget promises need `.catch()` (2026-03-20) -- already applied in `tryCreateVision` call site
- Agent context-blindness and vision misalignment (2026-02-22) -- relevant to ensuring vision.md contains actual user content

### Related Issues

- #1872 -- This issue (Create Project Issues)
- #1751 -- Start Fresh onboarding (guided first-run, already implemented)
- #1645 -- CA certificates fix for Docker (related setup failure, merged)

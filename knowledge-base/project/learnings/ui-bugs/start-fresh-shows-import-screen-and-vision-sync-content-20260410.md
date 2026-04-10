---
module: Web Platform
date: 2026-04-10
problem_type: ui_bug
component: authentication
symptoms:
  - "Start Fresh project creation shows import/repo-list screen instead of dashboard"
  - "vision.md populated with '### Vision /soleur:sync --headless' instead of founder's idea"
  - "Returning to /connect-repo after setup shows repo list for already-completed project"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [connect-repo, start-fresh, vision, onboarding, sessionstorage, welcome-hook, sentinel]
synced_to: []
---

# Fix: Start Fresh Shows Import Screen and Vision Gets Sync Command Text

## Problem

Two bugs in the "Start Fresh" project creation flow:

1. After creating a new project via "Start Fresh," users see the repository import screen (select existing repos) instead of being redirected to the dashboard first-run view.
2. `vision.md` gets populated with `### Vision /soleur:sync --headless` instead of the founder's actual startup idea.

## Environment

- Module: Web Platform (connect-repo onboarding flow + vision creation)
- Affected files: `connect-repo/page.tsx`, `vision-helpers.ts`, `workspace.ts`, `setup/route.ts`, `dashboard/page.tsx`
- Date: 2026-04-10
- Issue: #1872

## Symptoms

- New "Start Fresh" user sees "Select a Project" page with repo list after setup completes
- `vision.md` contains `### Vision /soleur:sync --headless` instead of typed idea
- Returning to `/connect-repo` after project is "ready" shows import screen instead of redirecting to dashboard

## Investigation

1. **Auto-detect effect fires unconditionally**: The connect-repo page has a mount-time effect that calls `/api/repo/detect-installation`. After Start Fresh creates a GitHub repo, the app is installed and repos exist, so this effect transitions to `select_project` state -- the import screen.

2. **Callback effect loses sessionStorage**: When the GitHub redirect callback returns after app installation, if `sessionStorage` was cleared (private browsing, browser restart), the `soleur_create_project` pending data is lost. The effect falls through to `fetchRepos()` instead of completing the create flow.

3. **tryCreateVision writes blindly**: The function writes the `userMessage` parameter verbatim to `vision.md` without validating content source. The welcome hook suggests `/soleur:sync`, the agent runs it, and the command text becomes the "vision."

## Root Cause

**Bug 1**: Missing flow-state guards on mount-time effects. Both the auto-detect effect and the callback effect assumed they were the only active flow, with no mechanism to detect "user is in create flow" or "project already set up."

**Bug 2**: `tryCreateVision()` trusted that `userMessage` was always user-authored content. The welcome hook introduces agent-generated content into the first-message path.

## Solution

### Fix 1: Guard auto-detect and callback effects

- Added `sessionStorage.setItem("soleur_create_flow", "true")` in `handleCreateNew()`, cleared in `handleOpenDashboard()` and `handleStartOver()`
- Auto-detect effect checks for the flag and skips when set
- Both effects check `/api/repo/status` before proceeding -- if status is "ready", redirect to `/dashboard` instead of showing repo list
- Added `source` parameter to `startSetup()` callback, passed through `POST /api/repo/setup` to distinguish Start Fresh from Connect Existing

### Fix 2: Content validation in tryCreateVision

```typescript
const trimmed = content.trim();
if (trimmed.length < 10) return;          // Too short
if (trimmed.startsWith("/")) return;       // Slash command
if (trimmed.startsWith("@") && !trimmed.includes(" ")) return; // Bare mention
if (/^###?\s/.test(trimmed) && /\/soleur:/.test(trimmed)) return; // Malformed sync
```

### Fix 3: Welcome hook sentinel for Start Fresh

- `provisionWorkspace()` creates `.claude/soleur-welcomed.local` sentinel unconditionally (Start Fresh path)
- `provisionWorkspaceWithRepo()` accepts `options?: { suppressWelcomeHook?: boolean }` and creates sentinel conditionally
- Setup route passes `{ suppressWelcomeHook: source === "start_fresh" }`

### Fix 4: Dashboard vision API (dual-write strategy)

- New `POST /api/vision` endpoint with CSRF, auth, workspace lookup
- Dashboard `handleFirstRunSend` calls it fire-and-forget before navigation
- `tryCreateVision` uses `O_EXCL` flag, so first write wins (no corruption)

## Prevention

- When adding mount-time effects that change page state, always check if another flow is active (sessionStorage flags, URL params, or server-side status)
- Never write user-facing artifacts (vision.md, brand guide, etc.) without validating content source -- automated/agent content should be filtered
- Use defense-in-depth: client-side sessionStorage for fast path + server-side status check as fallback

## Session Errors

1. **npx vitest rolldown binding error** -- Stale npx cache caused `Cannot find native binding @rolldown/binding-linux-x64-gnu`. Recovery: used project-local `./node_modules/.bin/vitest`. **Prevention:** Use project-local binary (`./node_modules/.bin/vitest`) instead of `npx vitest` in worktrees.

2. **connect-repo test ordering failure** -- `sessionStorage.setItem("soleur_create_flow")` from `handleCreateNew()` in earlier tests leaked to later tests via shared jsdom environment. Recovery: added `sessionStorage.clear()` to `beforeEach`. **Prevention:** When adding sessionStorage usage to components, always add `sessionStorage.clear()` to the test file's `beforeEach` block.

3. **git add wrong CWD** -- Shell CWD drifted from worktree root, causing `pathspec did not match` error. Recovery: prefixed `git add` with `cd` to worktree root. **Prevention:** Always use absolute paths or ensure CWD is the worktree root before `git add`.

4. **ralph-loop setup script wrong path** -- Used `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` instead of `./plugins/soleur/scripts/setup-ralph-loop.sh`. Recovery: corrected path. **Prevention:** The ralph-loop script lives at repo root `plugins/soleur/scripts/`, not inside any skill directory.

## Related

- [GitHub App Install Loop](../integration-issues/github-app-install-loop-auto-detection-connect-repo-20260407.md) -- related auto-detect issue in connect-repo
- Issue #1872 -- original bug report
- Issue #1751 -- Start Fresh onboarding (guided first-run, already implemented)

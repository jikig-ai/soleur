---
module: Dashboard
date: 2026-04-14
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Custom icons uploaded via team settings show only on settings page and chat, not dashboard"
  - "ConversationRow, foundation cards, and LeaderStrip always show default lucide-react icons"
root_cause: missing_include
resolution_type: code_fix
severity: medium
tags: [leader-avatar, custom-icon, useTeamNames, prop-wiring, test-mock]
---

# Troubleshooting: Custom Icons Not Showing on Dashboard Surfaces

## Problem

After PR #2130 added `LeaderAvatar` with `customIconPath` prop support, custom icons uploaded via team settings only displayed on the settings page and chat messages. The Command Center dashboard (conversation list, foundation cards, leader strip) always showed default lucide-react domain icons.

## Environment

- Module: Dashboard UI
- Framework: Next.js 15 + React + Supabase
- Affected Component: `LeaderAvatar` wiring across `ConversationRow`, `DashboardPage`, `LeaderStrip`
- Date: 2026-04-14

## Symptoms

- Custom icons uploaded via team settings show only on settings page and chat conversation messages
- `ConversationRow` (mobile + desktop layouts) shows default lucide-react icon instead of uploaded custom icon
- Foundation cards in Command Center show default icons
- "YOUR ORGANIZATION" leader strip shows default icons for all domain leaders

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. Root cause was clear from inspecting the `LeaderAvatar` call sites — `customIconPath` was simply not passed.

## Session Errors

**Worktree creation race condition** — Initial worktree created by `worktree-manager.sh` was cleaned by a parallel session running cleanup-merged.

- **Recovery:** Manually recreated via `git worktree add`
- **Prevention:** Avoid running cleanup-merged and worktree creation concurrently across sessions

**Draft PR creation failed (GitHub 504/GraphQL errors)** — Two attempts to create draft PR failed with transient GitHub API errors.

- **Recovery:** Deferred PR creation to `/ship` phase which handles retry
- **Prevention:** Transient — no code change needed. Pipeline already handles this gracefully.

**Test mock pattern error (`vi.mocked().mockReturnValue` not a function)** — Initial custom icon test used `vi.mocked(useTeamNames).mockReturnValue()` on a `vi.mock` factory that returns a plain object, not a mock function.

- **Recovery:** Switched to `vi.hoisted` pattern with a hoisted `vi.fn()` for `getIconPath`
- **Prevention:** When overriding per-test mock return values in Vitest, always use `vi.hoisted` to declare the mock function, then reference it in the `vi.mock` factory. `vi.mock` factories return plain objects — `vi.mocked().mockReturnValue()` only works if the exported function is itself a `vi.fn()`.

**Missing `afterEach` import from vitest** — `ReferenceError: afterEach is not defined` because only `describe, it, expect, vi` were imported.

- **Recovery:** Added `afterEach` to the import statement
- **Prevention:** Standard iteration — no workflow change needed.

**Missing test mocks in 3 additional test files** — Plan only mentioned `conversation-row.test.tsx` but 3 other test files (`status-badge-interaction.test.tsx`, `command-center.test.tsx`, `start-fresh-onboarding.test.tsx`) also render components that now import `useTeamNames` and crashed without the mock.

- **Recovery:** Added `vi.mock("@/hooks/use-team-names")` to all 3 files
- **Prevention:** When adding a React context hook to a shared component, grep all test files that render that component (not just its direct test file) to find all files needing the mock. Filed #2169 to extract a shared mock utility.

**QA browser auth failed** — Supabase SSR middleware uses cookie-based auth via `@supabase/ssr`; Playwright cannot inject httpOnly cookies. Magic link `redirect_to` was overridden by Supabase site URL config to production.

- **Recovery:** Skipped browser QA; relied on unit test coverage (1255 tests pass)
- **Prevention:** Need a Supabase auth callback route or test-only session injection endpoint for local QA. Known limitation.

## Solution

Wire `getIconPath` from `useTeamNames()` hook to every `LeaderAvatar` instance that was missing `customIconPath`.

**Code changes in `components/inbox/conversation-row.tsx`:**

```tsx
// Before (broken):
<LeaderAvatar leaderId={conversation.domain_leader} size="md" />

// After (fixed):
import { useTeamNames } from "@/hooks/use-team-names";
const { getIconPath } = useTeamNames();
<LeaderAvatar leaderId={conversation.domain_leader} size="md"
  customIconPath={getIconPath(conversation.domain_leader as DomainLeaderId)} />
```

**Code changes in `app/(dashboard)/dashboard/page.tsx`:**

```tsx
// DashboardPage: added useTeamNames() call, passed customIconPath to foundation cards
<LeaderAvatar leaderId={card.leaderId} size="sm" customIconPath={getIconPath(card.leaderId)} />

// LeaderStrip: receives getIconPath as prop from parent
<LeaderAvatar leaderId={leader.id} size="sm"
  customIconPath={getIconPath(leader.id as DomainLeaderId)} />
```

**Test mock added to 4 test files:**

```tsx
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({
    names: {}, iconPaths: {}, getIconPath: () => null,
    // ... full mock shape
  }),
}));
```

## Why This Works

1. **Root cause:** PR #2130 implemented `LeaderAvatar` with `customIconPath` and wired it on the two surfaces being actively developed (team settings and chat), but missed 5 other `LeaderAvatar` call sites that existed prior.
2. **Solution:** `TeamNamesProvider` already wraps the entire `(dashboard)` layout, so `useTeamNames()` and its `getIconPath` method are accessible everywhere. The fix just connects the existing data layer to the presentation layer on the missed surfaces.
3. **No new API calls:** `getIconPath` reads from the context already fetched by `TeamNamesProvider` on mount. Additional `useTeamNames()` consumers add zero network overhead.

## Prevention

- When adding an optional prop to a shared component, grep for ALL existing usages of that component and verify each call site has been updated (not just the ones in the active PR)
- When adding a React context hook to a component, grep all test files that render that component to add the mock
- Consider a shared test mock utility for widely-used hooks to prevent mock duplication and drift (tracked in #2169)

## Related Issues

- GitHub issue: #2161 (Agent team icon not showing in command center or conversations)
- Parent PR: #2130 (feat(dashboard): agent identity badges and team icon customization)
- Related learning: `knowledge-base/project/learnings/2026-04-12-silent-rls-failures-in-team-names.md`
- Related learning: `knowledge-base/project/learnings/2026-04-13-vitest-mock-sharing-and-issue-batching.md`
- Tech debt: #2169 (extract shared useTeamNames test mock utility)

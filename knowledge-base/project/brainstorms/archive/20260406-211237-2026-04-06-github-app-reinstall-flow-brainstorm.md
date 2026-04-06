# GitHub App Reinstall Flow Improvement

**Date:** 2026-04-06
**Status:** Decided
**Participants:** Founder, Claude

## What We're Building

Improve the `/connect-repo` flow so that users who already have the Soleur GitHub App installed don't get needlessly redirected to GitHub. Three changes:

1. **Skip GitHub redirect when installation exists** -- If the user already has a `github_installation_id` stored, both "Connect Existing" and "Create New" flows bypass the GitHub redirect and operate directly via API.

2. **Handle `setup_action=update` callback** -- The callback handler currently only processes `setup_action=install`. When a user goes to GitHub to update repo access on an already-installed app, GitHub redirects back with `setup_action=update`, which is silently ignored. Accept both values.

3. **Auto-refresh + manual Refresh on repo list** -- Add a `visibilitychange` listener to auto-refresh the repo list when the user returns to the Soleur tab, plus a manual "Refresh" button on both `SelectProjectState` and `NoProjectsState`.

## Why This Approach

The current flow always forces a full GitHub round-trip regardless of whether the app is installed. This creates two problems:

- **Unnecessary friction:** Users who already installed the app see a "Continue to GitHub" screen that adds no value -- we already have their installation ID and can list repos directly.
- **Broken return flow:** GitHub's installation configure page redirects with `setup_action=update` (not `install`), which the callback ignores. Users who change repo access get stranded on the choose screen instead of seeing their updated repo list.

The fix is minimal: check for existing installation before redirecting, and broaden the callback to accept both `install` and `update` actions.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Skip redirect when installed | Yes, for both Create and Connect flows | Installation ID is already stored; no need for GitHub round-trip |
| Handle `setup_action=update` | Yes | GitHub sends `update` when permissions change on an already-installed app |
| Re-check mechanism | Auto-refresh on window focus + manual Refresh button | Covers both seamless return and explicit re-check scenarios |
| Choose screen | Keep as-is | Users still pick Create vs Connect; the redirect is what's skipped |
| Installation detection | Check via `GET /api/repo/repos` response (400 = no installation) | Avoids adding a new endpoint; repos endpoint already validates installation |

## Open Questions

None -- scope is well-defined.

---
title: "feat: Configure GitHub App OAuth callback URL"
type: feat
date: 2026-04-07
---

# Configure GitHub App OAuth Callback URL

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 3 (Implementation, Verification, Context)
**Research sources:** 6 institutional learnings on Playwright MCP patterns

### Key Improvements

1. Added pre-flight API verification confirming no REST API path exists (PATCH /app requires JWT auth and does not expose callback URL fields)
2. Incorporated Playwright MCP operational learnings: fresh snapshots after state changes, `browser_close` mandatory cleanup, worktree-aware screenshot paths
3. Added fallback strategy for authentication redirect and singleton lock recovery

### New Considerations Discovered

- GitHub App settings page may have multiple callback URL slots (general "Callback URL" vs OAuth-specific fields) -- snapshot verification step distinguishes them
- Playwright MCP resolves paths from repo root, not worktree -- absolute paths required for any screenshots

## Problem

PR #1769 (GitHub identity resolution for email-only users) added a new OAuth callback route at `/api/auth/github-resolve/callback`. The code is deployed, but the GitHub App settings page has not been updated to include this callback URL. Without it, GitHub will reject OAuth redirects to this endpoint, breaking the email-only user identity resolution flow.

The GitHub API does not expose an endpoint for updating App callback URLs -- this must be done through the browser settings page. Verified: the `GET /apps/soleur-ai` public endpoint returns `callback_url: null`, and `PATCH /app` requires JWT authentication via the App's private key and does not document callback URL as an updatable field.

## Acceptance Criteria

- [ ] GitHub App `soleur-ai` (owned by `jikig-ai` org, App ID `3261325`) has callback URL set to `https://app.soleur.ai/api/auth/github-resolve/callback`
- [ ] Verified via browser screenshot that the callback URL appears in the App settings
- [ ] GitHub issue #1784 closed after verification

## Implementation

### Pre-flight: API Exhaustion Check

Before launching Playwright, confirm no automated path exists (per learning: `2026-03-25-check-mcp-api-before-playwright.md`):

1. **MCP tools:** `ToolSearch` for "github app settings" -- no matching MCP tool exists
2. **CLI tools:** `gh api /apps/soleur-ai` returns public data but callback URL is not updatable via `gh`
3. **REST API:** `PATCH /app` requires JWT auth and does not document `callback_url` as a writable field
4. **Conclusion:** Playwright is the correct path -- GitHub App settings configuration is browser-only

### Phase 1: Configure Callback URL via Playwright

Navigate to the GitHub App settings page and add the callback URL.

**Target URL:** `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`

**Steps:**

1. Use Playwright MCP `browser_navigate` to open `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`
2. **Authentication gate:** If GitHub redirects to login, the user handles the OAuth consent gate (genuinely manual per AGENTS.md -- only CAPTCHAs and OAuth consent are manual). After login, call `browser_navigate` again to the target URL
3. Use `browser_snapshot` to capture the current page state and locate the "Callback URL" input field
4. Use `browser_click` on the callback URL input field (use the ref from the snapshot)
5. Use `browser_type` to enter `https://app.soleur.ai/api/auth/github-resolve/callback`
6. **Fresh snapshot required:** Take a new `browser_snapshot` after typing to verify the URL is entered correctly -- per learning (`2026-04-03-playwright-browser-cleanup-on-session-exit.md`): after any action that changes page state, take a fresh snapshot to get updated refs
7. Scroll to the bottom and use `browser_click` on the "Save changes" button
8. Use `browser_snapshot` to capture confirmation that settings were saved

### Research Insights

**Playwright MCP Operational Patterns (from institutional learnings):**

- **Fresh snapshots after state changes:** Element refs from previous snapshots become stale after clicks, form fills, or navigation. Always `browser_snapshot` after each action before interacting with new elements (learning: `2026-04-03`)
- **Worktree path awareness:** Playwright MCP resolves paths from the repo root, not the worktree CWD. Use absolute paths for any screenshot filenames (learning: `2026-02-17`)
- **Singleton lock recovery:** If `browser_navigate` fails with "Browser is already in use", kill stale Chrome processes: `pkill -f "chrome.*mcp-chrome"`, then retry. The `--isolated` flag in `.mcp.json` should prevent this, but stale processes from prior sessions can trigger it (learning: `2026-04-02`)
- **Viewport gotcha:** Input fields or buttons may be outside the viewport on settings pages. If `browser_click` fails, try scrolling first or clicking the parent container element (learning: `2026-03-21-cloudflare-api-token-permission-editing`)

**Edge Cases:**

- GitHub App settings page may distinguish between "Callback URL" (general app callback) and OAuth-specific callback URLs -- use the snapshot to identify the correct field
- If the field already contains a value, clear it first with `browser_click` + select-all + delete before typing
- Multiple callback URLs may be supported (comma-separated or "Add callback URL" button) -- check via snapshot

### Phase 2: Verification

1. Take a final `browser_snapshot` of the saved settings page confirming the callback URL
2. **Mandatory cleanup:** Close the browser session with `browser_close` (per AGENTS.md hard rule and learning: `2026-04-03`). Skipping this leaves orphaned Chrome processes
3. Close issue #1784: `gh issue close 1784 --comment "Callback URL configured and verified via Playwright"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling configuration change.

## Test Scenarios

- **Browser:** Navigate to `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`, verify "Callback URL" field contains `https://app.soleur.ai/api/auth/github-resolve/callback`
- **API verify (post-configuration):** `gh api /apps/soleur-ai --jq '.callback_url'` -- may still return null if the API does not expose this field publicly; browser verification is the authoritative check

## Context

- **GitHub App slug:** `soleur-ai`
- **GitHub App ID:** `3261325`
- **Owner:** `jikig-ai` (organization)
- **GitHub Client ID:** `Ov23liHI6NLGiS50tOUI`
- **Source PR:** #1769 (feat: GitHub identity resolution for email-only users)
- **API limitation:** No PATCH /app endpoint exists in the GitHub REST API for updating callback URLs -- browser automation is required
- **Playwright MCP config:** `--isolated` mode via project `.mcp.json` (ensures parallel session safety)

## References

- Source issue: #1784
- Source PR: #1769
- GitHub App settings: `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`
- GitHub Apps REST API docs: [GitHub REST API - Apps](https://docs.github.com/en/rest/apps/apps)
- Learning: [Playwright MCP isolated mode](../learnings/2026-04-02-playwright-mcp-isolated-mode-for-parallel-sessions.md)
- Learning: [Browser cleanup on session exit](../learnings/workflow-issues/2026-04-03-playwright-browser-cleanup-on-session-exit.md)
- Learning: [Check MCP/API before Playwright](../learnings/2026-03-25-check-mcp-api-before-playwright.md)
- Learning: [Screenshots land in main repo](../learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md)
- Learning: [Cloudflare API token editing via Playwright](../learnings/2026-03-21-cloudflare-api-token-permission-editing.md)
- Learning: [Buttondown multi-account Playwright](../learnings/2026-04-07-buttondown-onboarding-multi-account-playwright.md)

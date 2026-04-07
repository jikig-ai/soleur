---
title: "feat: Configure GitHub App OAuth callback URL"
type: feat
date: 2026-04-07
---

# Configure GitHub App OAuth Callback URL

## Problem

PR #1769 (GitHub identity resolution for email-only users) added a new OAuth callback route at `/api/auth/github-resolve/callback`. The code is deployed, but the GitHub App settings page has not been updated to include this callback URL. Without it, GitHub will reject OAuth redirects to this endpoint, breaking the email-only user identity resolution flow.

The GitHub API does not expose a PATCH endpoint for updating App callback URLs -- this must be done through the browser settings page.

## Acceptance Criteria

- [ ] GitHub App `soleur-ai` (owned by `jikig-ai` org, App ID `3261325`) has callback URL set to `https://app.soleur.ai/api/auth/github-resolve/callback`
- [ ] Verified via browser screenshot that the callback URL appears in the App settings
- [ ] GitHub issue #1784 closed after verification

## Implementation

### Phase 1: Configure Callback URL via Playwright

Navigate to the GitHub App settings page and add the callback URL.

**Target URL:** `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`

**Steps:**

1. Use Playwright MCP `browser_navigate` to open `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`
2. If not authenticated, GitHub will redirect to login -- the user handles the OAuth consent gate (genuinely manual), then Playwright resumes
3. Use `browser_snapshot` to capture the current page state and locate the "Callback URL" input field
4. Use `browser_click` on the callback URL input field
5. Use `browser_type` to enter `https://app.soleur.ai/api/auth/github-resolve/callback`
6. Use `browser_snapshot` to verify the URL is entered correctly
7. Scroll to the bottom and use `browser_click` on the "Save changes" button
8. Use `browser_snapshot` to capture confirmation that settings were saved

### Phase 2: Verification

1. Take a final screenshot of the saved settings page showing the callback URL
2. Close the browser session with `browser_close`
3. Close issue #1784: `gh issue close 1784 --comment "Callback URL configured and verified via Playwright"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling configuration change.

## Test Scenarios

- **Browser:** Navigate to `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`, verify "Callback URL" field contains `https://app.soleur.ai/api/auth/github-resolve/callback`

## Context

- **GitHub App slug:** `soleur-ai`
- **GitHub App ID:** `3261325`
- **Owner:** `jikig-ai` (organization)
- **GitHub Client ID:** `Ov23liHI6NLGiS50tOUI`
- **Source PR:** #1769 (feat: GitHub identity resolution for email-only users)
- **API limitation:** No PATCH /app endpoint exists in the GitHub REST API for updating callback URLs -- browser automation is required

## References

- Source issue: #1784
- Source PR: #1769
- GitHub App settings: `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`
- GitHub Apps REST API docs: `https://docs.github.com/en/rest/apps/apps`

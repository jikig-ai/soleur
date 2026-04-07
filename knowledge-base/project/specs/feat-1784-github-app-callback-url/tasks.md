# Tasks: Configure GitHub App OAuth Callback URL

## Phase 1: Configure Callback URL

- [ ] 1.1 Navigate to GitHub App settings page (`https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`) via Playwright MCP
- [ ] 1.2 Authenticate if redirected to GitHub login (user handles OAuth consent)
- [ ] 1.3 Locate the "Callback URL" input field via `browser_snapshot`
- [ ] 1.4 Enter callback URL: `https://app.soleur.ai/api/auth/github-resolve/callback`
- [ ] 1.5 Save changes
- [ ] 1.6 Capture screenshot confirming saved state

## Phase 2: Verification

- [ ] 2.1 Verify callback URL appears in saved settings via screenshot
- [ ] 2.2 Close browser session with `browser_close`
- [ ] 2.3 Close GitHub issue #1784 with verification comment

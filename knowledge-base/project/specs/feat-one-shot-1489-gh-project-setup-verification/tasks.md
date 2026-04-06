---
title: "chore: production verification of GitHub project setup flow"
branch: feat-one-shot-1489-gh-project-setup-verification
issue: "#1489"
date: 2026-04-06
---

# Tasks: Production Verification of GitHub Project Setup Flow

## Phase 1: Observability Check

- [ ] 1.1 Retrieve `SENTRY_API_TOKEN` from Doppler `prd` config
- [ ] 1.2 Query Sentry API for unresolved issues matching `auth`, `install`, `identity`, `PGRST`, `getUserById` from the last 72 hours
- [ ] 1.3 Verify zero matching errors in Sentry
- [ ] 1.4 Check production health endpoint: `curl -s https://api.soleur.ai/health`
- [ ] 1.5 Query Supabase for users with `github_installation_id IS NOT NULL` to confirm successful installs since deploy

## Phase 2: Browser Verification (Playwright MCP)

- [ ] 2.1 Navigate to web platform login page
- [ ] 2.2 Authenticate (may require OAuth handoff for consent screen)
- [ ] 2.3 Navigate to connect-repo page
- [ ] 2.4 Take screenshot of initial state
- [ ] 2.5 Initiate GitHub App install flow (click "Connect Existing Repository")
- [ ] 2.6 Verify redirect to GitHub App installation page
- [ ] 2.7 After callback: verify page transitions to repo selection (not "interrupted" or "failed")
- [ ] 2.8 Take screenshot of repo selection state
- [ ] 2.9 Select a repository and observe setup progress
- [ ] 2.10 Take screenshot of final state (ready or setting_up)

## Phase 3: Close Issue

- [ ] 3.1 Compile verification evidence (Sentry query results, Supabase query results, screenshots)
- [ ] 3.2 Post summary comment on #1489 with evidence
- [ ] 3.3 Close #1489 if all verifications pass; otherwise create follow-up fix issue

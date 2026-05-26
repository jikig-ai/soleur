---
title: "Tasks: fix Inngest GitHub installation token 401"
plan: knowledge-base/project/plans/2026-05-26-fix-inngest-github-installation-token-401-plan.md
branch: feat-one-shot-fix-inngest-github-token-401
---

# Tasks: fix Inngest GitHub installation token 401

## Phase 0: Triage (read-only diagnosis)

- [ ] 0.1 Query Sentry event `4324b0b7671a4682994043249d210abd` for `inngest.fn_id`, `inngest.run_id`, `inngest.event_name` tags and `installationId` from error context
- [ ] 0.2 Check for open `[ci/auth-broken]` drift-guard issues: `gh issue list --search "[ci/auth-broken]" --state open`
- [ ] 0.3 Verify App JWT validity from operator machine using Doppler `prd` credentials against `GET /app` and `POST /app/installations/{id}/access_tokens`
- [ ] 0.4 If 0.3 returns 401: cross-check App ID and PEM in Doppler vs GitHub App admin page
- [ ] 0.5 If 0.3 returns 200: check for env staleness (Doppler audit log vs last deploy timestamp), clock skew, transient GitHub outage, or installation-specific issue

## Phase 1: Fix (conditional on Phase 0 diagnosis)

- [ ] 1.1 Apply the credential fix identified in Phase 0 (Doppler update + redeploy, or installation ID fix, etc.)
- [ ] 1.2 Verify fix by re-running the Phase 0.3 diagnostic from the production container's perspective

## Phase 2: Hardening (code changes)

- [ ] 2.1 Enhance error logging in `generateInstallationToken()` at `apps/web-platform/server/github-app.ts:477-485`: add App ID, PEM fingerprint (first 8 hex chars SHA-256), server timestamp
- [ ] 2.2 Add PEM shape validation warning in `getPrivateKey()` at `apps/web-platform/server/github-app.ts:97-101`
- [ ] 2.3 Add `reportSilentFallback` call with structured tags before the throw at `github-app.ts:484`
- [ ] 2.4 Add retry-on-401 (1 retry, 1s delay, fresh JWT) to `generateInstallationToken()` to close the resilience gap with `@octokit/auth-app@8.2.0`'s built-in `sendRequestWithRetries`
- [ ] 2.5 Run existing tests: `./node_modules/.bin/vitest run test/github-app*.test.ts test/github-api*.test.ts`
- [ ] 2.6 Add test: mock `githubFetch` to return 401 then 200 -- verify retry succeeds and warn is logged
- [ ] 2.7 Add test: mock `githubFetch` to return 401 twice -- verify throws with `reportSilentFallback`
- [ ] 2.8 Add test: mock `githubFetch` to return 403 -- verify no retry attempted

## Phase 3: Documentation

- [ ] 3.1 Write learning file at `knowledge-base/project/learnings/bug-fixes/` documenting root cause, fix, and prevention

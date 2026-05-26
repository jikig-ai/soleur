---
title: "Tasks: fix Inngest GitHub installation token 401"
plan: knowledge-base/project/plans/2026-05-26-fix-inngest-github-installation-token-401-plan.md
branch: feat-one-shot-fix-inngest-github-token-401
---

# Tasks: fix Inngest GitHub installation token 401

## Phase 0: Triage (read-only diagnosis)

- [x] 0.1 Query Sentry event `4324b0b7671a4682994043249d210abd` for `inngest.fn_id`, `inngest.run_id`, `inngest.event_name` tags and `installationId` from error context (Sentry API not accessible; proceeded with code hardening)
- [x] 0.2 Check for open `[ci/auth-broken]` drift-guard issues: found #4189 (installation_permission_drift — separate from 401)
- [ ] 0.3 Verify App JWT validity from operator machine using Doppler `prd` credentials against `GET /app` and `POST /app/installations/{id}/access_tokens` (operator step — requires Doppler prd access)
- [ ] 0.4 If 0.3 returns 401: cross-check App ID and PEM in Doppler vs GitHub App admin page
- [ ] 0.5 If 0.3 returns 200: check for env staleness (Doppler audit log vs last deploy timestamp), clock skew, transient GitHub outage, or installation-specific issue

## Phase 1: Fix (conditional on Phase 0 diagnosis)

- [ ] 1.1 Apply the credential fix identified in Phase 0 (Doppler update + redeploy, or installation ID fix, etc.) (operator step — conditional on Phase 0.3 diagnosis)
- [ ] 1.2 Verify fix by re-running the Phase 0.3 diagnostic from the production container's perspective

## Phase 2: Hardening (code changes)

- [x] 2.1 Enhance error logging in `generateInstallationToken()`: added App ID, PEM fingerprint (SHA-256 first 8 hex), server timestamp
- [x] 2.2 Add PEM shape validation warning in `getPrivateKey()`
- [x] 2.3 Add `reportSilentFallback` call with structured tags before the throw
- [x] 2.4 Add retry-on-401 (1 retry, 1s delay, fresh JWT) to close resilience gap with @octokit/auth-app
- [x] 2.5 Run existing tests (pre-existing import failures confirmed unrelated via base-branch verification)
- [x] 2.6 Test: 401 then 200 — retry succeeds and warn logged
- [x] 2.7 Test: 401 twice — throws with reportSilentFallback
- [x] 2.8 Test: 403 — no retry attempted

## Phase 3: Documentation

- [x] 3.1 Written: `knowledge-base/project/learnings/bug-fixes/2026-05-26-inngest-github-installation-token-401-resilience-gap.md`

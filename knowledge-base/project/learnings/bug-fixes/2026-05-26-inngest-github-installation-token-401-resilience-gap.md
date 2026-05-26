---
title: "Inngest GitHub installation token 401 — resilience gap between @octokit/auth-app and hand-rolled JWT"
date: 2026-05-26
tags: [github-app, inngest, auth, resilience]
pr: 4498
sentry_id: 4324b0b7671a4682994043249d210abd
---

# Inngest GitHub installation token 401 — resilience gap

## Symptom

Sentry error on `POST /api/inngest`: `GitHub installation token request failed: 401`.
All Inngest cron functions that call `generateInstallationToken()` (via `_cron-shared.ts:mintInstallationToken()`) were affected.

## Root cause analysis

Two distinct JWT minting paths exist in the codebase:

1. **`createAppJwt()` in `github-app.ts`** — hand-rolled RS256 signing. Used by `generateInstallationToken()` for the installation token exchange.
2. **`@octokit/app`** — used by `createGitHubAppClient()` and `createProbeOctokit()` for App-level operations and installation discovery.

Both paths read the same PEM from `GITHUB_APP_PRIVATE_KEY` and apply identical `\n` normalization. However, `@octokit/auth-app@8.2.0` has two resilience features the hand-rolled path lacked:

- **Clock-skew retry** with `timeDifference` compensation (`hook.ts:isNotTimeSkewError`)
- **401 replication-delay retry** (`sendRequestWithRetries` — retries for up to 5s after token creation)

The TR9 Phase 2 migration (#4483) significantly increased `generateInstallationToken()` call volume by moving all GHA scheduled workflows to Inngest, increasing exposure to transient 401 windows.

## Fix

Added hardening to `generateInstallationToken()` regardless of whether the 401 was transient or persistent:

1. **Retry-on-401**: single retry with 1s delay and fresh JWT (mirrors `@octokit/auth-app`'s `sendRequestWithRetries`)
2. **PEM shape validation**: warning log at `getPrivateKey()` if PEM doesn't start with expected header
3. **Enhanced error logging**: appId, PEM fingerprint (SHA-256 first 8 hex chars), server timestamp
4. **`reportSilentFallback`**: structured Sentry tags (`feature: "github-app"`, `op: "generate-installation-token"`) on final failure

## Prevention

The retry closes the resilience gap between the two JWT paths. Future monitoring: the `cron-github-app-drift-guard` function checks App-level JWT validity; the enhanced error logging now makes installation-level failures diagnosable without SSH.

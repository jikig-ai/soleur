---
title: "Inngest GitHub installation token 401 — resilience gap between @octokit/auth-app and hand-rolled JWT"
date: 2026-05-26
module: github-app
problem_type: runtime_error
component: server_auth
symptoms:
  - "GitHub installation token request failed: 401"
  - "POST /api/inngest error in Sentry"
root_cause: missing_resilience
severity: high
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
- **401 replication-delay retry** (`sendRequestWithRetries` — retries for up to 5s on downstream API requests authenticated with an installation token)

Note: `@octokit/auth-app`'s `sendRequestWithRetries` retries downstream authenticated requests, not the token exchange itself. Our retry is on the token exchange — a different layer, but closes the same transient-401 gap.

The TR9 Phase 2 migration (#4483) significantly increased `generateInstallationToken()` call volume by moving all GHA scheduled workflows to Inngest, increasing exposure to transient 401 windows.

## Fix

Added hardening to `generateInstallationToken()` regardless of whether the 401 was transient or persistent:

1. **Retry-on-401**: single retry with 1s delay and fresh JWT, extracted into `mintAndExchange()` helper to avoid duplication
2. **PEM shape validation**: warning log (once per process) at `getPrivateKey()` if PEM doesn't start with expected header; logs safe metadata (length, boolean) not raw content
3. **Enhanced error logging**: appId, PEM fingerprint (SHA-256 first 8 hex chars) computed once at function entry
4. **`reportSilentFallback`**: structured Sentry tags (`feature: "github-app"`, `op: "generate-installation-token"`) on final failure
5. **Response body drain**: first 401 response drained before retry delay (consistency with `github-api.ts` pattern)

## Prevention

The retry closes the resilience gap between the two JWT paths. Future monitoring: the `cron-github-app-drift-guard` function checks App-level JWT validity; the enhanced error logging now makes installation-level failures diagnosable without SSH.

## Session Errors

1. **vi.mock hoisting error** — `ReferenceError: Cannot access 'mockLogWarn' before initialization` because mock variables were declared as `const` but referenced inside `vi.mock()` factories (which are hoisted). Recovery: switched to `vi.hoisted()` pattern. **Prevention:** already documented in work skill Sharp Edges (use `vi.hoisted()` from the start when mock factories reference shared variables).

2. **CWD drift after `cd` in Bash tool** — `npx tsc --noEmit` ran from a `cd` subshell, then the next vitest command failed with "No such file or directory" because Bash CWD doesn't persist across calls. Recovery: used absolute paths. **Prevention:** always chain `cd <path> && <command>` in a single Bash call.

3. **`replace_all` missed second occurrence** — A filter pattern appeared twice with different surrounding indentation; `replace_all` caught only one. Recovery: manual second edit. **Prevention:** always `grep` the file after `replace_all` to verify zero remaining matches.

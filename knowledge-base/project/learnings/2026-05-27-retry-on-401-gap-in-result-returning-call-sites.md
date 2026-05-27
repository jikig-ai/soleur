---
title: "Retry-on-401 gap in result-returning call sites"
date: 2026-05-27
category: runtime-errors
module: server/inngest/functions/cron-github-app-drift-guard
tags: [github-app, jwt, retry, octokit, inngest, sentry]
triggered_by: "Sentry: HttpError: A JSON web token could not be decoded"
---

# Learning: Retry-on-401 gap in result-returning call sites

## Problem

PR #4498 hardened `createProbeOctokit()` and `generateInstallationToken()` with retry-on-401 for transient GitHub JWT verification failures, but missed `createAppJwtOctokit()` used by the drift-guard cron. The gap was invisible because:

1. `@octokit/auth-app` does NOT internally retry "JWT could not be decoded" 401s (only clock-skew and installation-token 401s)
2. `probeDriftGuard()` catches the 401 internally and returns a classified `DriftResult` with `failureMode: "github_app_401"` — it does not throw
3. The handler accepted the failure result without retrying, filed a `ci/guard-broken` issue, and paged the operator for a self-healing condition

Sentry error at `2026-05-27T00:00:01Z` confirmed the gap in production.

## Solution

Added retry-on-401 in the drift-guard handler's `step.run("drift-check")` callback. When `probeDriftGuard()` returns `failureMode === "github_app_401"`, retry once after 1s with a fresh `createAppJwtOctokit()` call (fresh JWT via new `App` instance).

## Key Insight

When hardening retry logic across multiple call sites, the retry mechanism must match the call site's error-handling pattern. The two sibling patterns (`createProbeOctokit`, `generateInstallationToken`) retry on *caught exceptions* (`.status === 401`). The drift-guard site required retry on a *returned result* (`failureMode === "github_app_401"`) because the inner function classifies errors rather than propagating them. A sweep that only greps for `catch (err)` + `401` patterns will miss result-returning call sites.

## Tags

category: runtime-errors
module: server/inngest/functions/cron-github-app-drift-guard

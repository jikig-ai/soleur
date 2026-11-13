# Graceful Degradation — postmerge prerequisites

Which postmerge phase degrades, and how, when a prerequisite is absent. Read this when a
phase reports a missing prerequisite and you need to know whether to skip, warn or abort;
it is a lookup table, not per-invocation instruction, so it is loaded on demand rather than
carried in every `soleur:postmerge` body (ADR-229).

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No production URL | Skip health check with warning |
| No `SENTRY_AUTH_TOKEN` | Skip the Sentry cron monitor check with warning (it is the monitors-only token; the error-count delta does not use it — its issue GET 403s, re-measured 2026-11-13) |
| No `SENTRY_ISSUE_RW_TOKEN` | Skip the auto-resolve PUT only; the error-count-delta GET runs on `SENTRY_ISSUE_RO_TOKEN`. With neither RO nor RW set, the error-count delta is `SKIPPED`; recommend manual resolution as today |
| Sentry API unreachable | Skip Sentry cron monitor check with warning |
| No Sentry issue identified in PR/linked issue | Skip error-count delta silently (nothing to measure) |
| Sentry issue not found via API | Skip error-count delta with warning |
| Playwright MCP unavailable | Skip browser verification with warning |
| CI run not found | Poll up to 5 minutes, then warn and proceed |
| No UI files in diff | Skip browser verification entirely |
| No linked issue | Skip issue comment |
| No `doppler`, no `BETTERSTACK_API_TOKEN_READONLY` in `prd_terraform`, or Better Stack API unreachable (Phase 3.9) | Report `Alert-channel sweep: SKIPPED (<cause>)` — advisory; the `ci/` issue half needs no token and always runs |
| No `doppler`, or no `HCLOUD_TOKEN_READONLY` in `prd_terraform`, or no `apply-web-platform-infra.yml` run for the merge SHA (Phase 5.7) | Report `Sole-copy read-back: <missing-token / no word / not delivered>`; never dispatch an apply on a missing read; `missing-token` also files the O5 issue; no run within about 50 min is "not delivered or superseded": read back anyway |

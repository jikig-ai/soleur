---
title: "Tasks: obs(auth) synthetic OAuth probe + Sentry alert rules"
plan: knowledge-base/project/plans/2026-04-29-obs-oauth-probe-sentry-alerts-plan.md
issue: 2997
date: 2026-04-29
---

# Tasks — obs(auth): OAuth probe + Sentry alerts

## Phase 1 — Workflow + ops runbook

- 1.1 Create `.github/workflows/scheduled-oauth-probe.yml` with `*/15 * * * *` cron and `workflow_dispatch:`.
  - 1.1.1 Pin `actions/checkout` to the same commit SHA used by `scheduled-cf-token-expiry-check.yml`.
  - 1.1.2 Implement four-step probe (login / google authorize / github authorize / settings) with `--max-time 10` on every curl.
  - 1.1.3 Sanitize `failure_detail` via `${var//[$'\n\r']/}` before writing to `$GITHUB_OUTPUT`.
  - 1.1.4 File-or-comment on `ci/auth-broken` issue using stable title `[ci/auth-broken] Synthetic OAuth probe failed` (mirror `scheduled-cf-token-expiry-check.yml` lines 130-188).
  - 1.1.5 Pre-create `ci/auth-broken` label defensively (`gh label create ... || true`).
  - 1.1.6 Invoke `./.github/actions/notify-ops-email` on failure with `RESEND_API_KEY` from secrets.
  - 1.1.7 On clean run, find any open `ci/auth-broken` issue and auto-close with green-probe comment.
  - 1.1.8 Set `concurrency: scheduled-oauth-probe / cancel-in-progress: false`, `permissions: { contents: read, issues: write }`, `timeout-minutes: 5`.
- 1.2 Create `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` with one section per `failure_mode` + diagnostic recipes.
- 1.3 Verify the runbook cross-links PR #2975, PR #2994, PR #3007, Issue #2982.

## Phase 2 — Sentry alert configurator

- 2.1 Create `apps/web-platform/scripts/configure-sentry-alerts.sh`.
  - 2.1.1 Validate `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` (`: "${VAR:?...}"`).
  - 2.1.2 Detect Sentry region via `/users/me/` probe against both `sentry.io` and `de.sentry.io`.
  - 2.1.3 Resolve email action target: `GET /api/0/organizations/{org}/teams/`, prefer slug `ops` then `engineering`; fall back to `targetType: "IssueOwners", fallthroughType: "ActiveMembers"` if no team. Log which mode was chosen.
  - 2.1.4 Implement `upsert_rule()` helper: `GET /rules/` → match by name → `PUT` if found else `POST`. On non-2xx, log response body and exit 1.
  - 2.1.5 Configure rule `auth-exchange-code-burst`: `EventFrequencyCondition value=5 interval="15m"` (NOT `10m` — Sentry rejects; valid set is `1m|5m|15m|1h|1d|1w|30d`), filters `feature:auth` + `op:exchangeCodeForSession`, `frequency: 60` (re-fire cap, minutes).
  - 2.1.6 Configure rule `auth-callback-no-code-burst`: `EventFrequencyCondition value=3 interval="15m"`, filters `feature:auth` + `op:callback_no_code`, `frequency: 60`.
  - 2.1.7 Configure rule `auth-per-user-loop`: `EventUniqueUserFrequencyCondition value=3 interval="5m"`, filter `feature:auth`, `frequency: 30`.
  - 2.1.8 Bound every curl with `--max-time 10`; `set -euo pipefail`.
- 2.2 Verify the JSON shape (`conditions` / `filters` / `actions`) against Sentry docs at <https://docs.sentry.io/api/alerts/create-an-issue-alert-rule-for-a-project/> — the plan's "Live API verification (2026-04-29)" table is the source of truth.

## Phase 3 — Drift-guard test

- 3.1 Create `apps/web-platform/test/auth/sentry-tag-coverage.test.ts`.
  - 3.1.1 Use `fs.readdirSync` + `fs.statSync` recursive — verified no glob dep available in `apps/web-platform/package.json`. Pattern from `apps/web-platform/lib/auth/csrf-coverage.test.ts`.
  - 3.1.2 Walk `app/(auth)` and `components/auth` for `.ts`/`.tsx` files; skip `*.test.tsx?` files.
  - 3.1.3 First `it()`: per-dir sanity — each `AUTH_DIRS` entry yields ≥1 source file (catches a directory rename).
  - 3.1.4 Second `it()`: assert files calling any auth verb contain `feature: "auth"`.
  - 3.1.5 Third `it()`: assert each verb has matching `op: "<verb>"` in same file.
- 3.2 Run `bun test apps/web-platform/test/auth/sentry-tag-coverage.test.ts` locally; expect all green on current `main`.
- 3.3 Locally remove `feature: "auth"` from `oauth-buttons.tsx` and confirm test fails — proves the guard is active.

## Phase 4 — Runbook + spec wrap

- 4.1 Fill diagnostic recipes (gh secret view, dig +time=5 +tries=2, Sentry API curl with no boolean).
- 4.2 Add 60-day re-evaluation note tied to `/soleur:schedule` follow-up.
- 4.3 Add re-evaluation criteria: stable for 60 days AND sign-in MAU > 100 → ratchet thresholds (5→3, 3→2, 3→2).

## Pre-merge verification

- V1 Run `bun typecheck` from `apps/web-platform/`.
- V2 Run full `bun test` for the web-platform package.
- V3 Run `actionlint` on the new workflow file (if available); manually review YAML for indentation and `if:` correctness.
- V4 Visually verify the workflow file vs `scheduled-cf-token-expiry-check.yml` for skeleton parity.
- V5 PR body uses `Closes #2997`. Domain Review and User-Brand Impact sections present.

## Post-merge (operator)

- PM1 Run `apps/web-platform/scripts/configure-sentry-alerts.sh` locally with `SENTRY_AUTH_TOKEN/SENTRY_ORG/SENTRY_PROJECT` exported. Confirm three rules visible in Sentry UI.
- PM2 `gh workflow run scheduled-oauth-probe.yml`; poll `gh run view <id> --json status,conclusion`. Expect green probe.
- PM3 Sanity-fire: temporarily set `auth-callback-no-code-burst` threshold=1, hit prod `/callback` (no `code` query) once, confirm ops email arrives, restore threshold via re-running `configure-sentry-alerts.sh`.
- PM4 Confirm #2997 auto-closed at merge (was `Closes #2997` in PR body).

## Captured at compound

- Whether Sentry's `NotifyEmailAction` reaches `ops@jikigai.com` in practice (R4) — record the answer.
- The exact API class paths the live Sentry instance accepts vs the docs (R1) — paste into the runbook for future reference.
- Whether the GHA-runner egress IPs are stable enough that the probe doesn't false-fire on Cloudflare/Supabase rate limits.

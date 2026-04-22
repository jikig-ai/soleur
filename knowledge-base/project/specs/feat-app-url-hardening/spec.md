# Feature: APP_URL Hardening

Bundled cleanup of the five `NEXT_PUBLIC_APP_URL` follow-ups from PR #2767 (issues `#2768`, `#2769`, `#2770`, `#2773`, `#2774`).

## Problem Statement

PR #2767 fixed one symptom: `NEXT_PUBLIC_APP_URL` was missing from Doppler `prd`, causing a Sentry error. The underlying class of bug is still open:

1. Two env vars (`NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_SITE_URL`) represent the same logical value and can drift independently.
2. Two API routes (`checkout`, `billing/portal`) still degrade silently with `?? "https://app.soleur.ai"` — no Sentry signal when misconfig recurs.
3. No pre-deploy CI gate asserts that required `NEXT_PUBLIC_*` secrets exist in Doppler `prd`.
4. Post-deploy verification of PR #2767 (`#2773`, `#2774`) is outstanding.

## Goals

- Single canonical var for app origin; zero code reading `NEXT_PUBLIC_SITE_URL`; no `NEXT_PUBLIC_SITE_URL` secret in Doppler `prd`.
- Every `NEXT_PUBLIC_APP_URL` read site either throws, returns an error, or calls `reportSilentFallback` — no undisguised `??` fallback.
- CI fails before deploy when any required `NEXT_PUBLIC_*` secret is absent from Doppler `prd`.
- `#2773` and `#2774` closed with cited passive Sentry evidence.

## Non-Goals

- Preview-env per-branch URLs (see `#2768` re-evaluation criterion).
- Migrating away from build-time `NEXT_PUBLIC_*` injection.
- Guard coverage for non-`NEXT_PUBLIC_*` secrets.
- Auto-computing the required-secrets list from Dockerfile / code grep (YAGNI — deferred unless hand-maintained list drifts twice).

## Functional Requirements

### FR1: Sentry-mirror both silent URL fallbacks (`#2770`)

`apps/web-platform/app/api/checkout/route.ts` and `apps/web-platform/app/api/billing/portal/route.ts` must, when `process.env.NEXT_PUBLIC_APP_URL` is unset:

- Call `reportSilentFallback(null, { feature: "checkout" | "billing", op: "appOrigin", message: "NEXT_PUBLIC_APP_URL unset; origin fallback to https://app.soleur.ai" })` from `@/server/observability`.
- Proceed with the literal fallback `"https://app.soleur.ai"` (unchanged behavior).

Pattern reference: `apps/web-platform/server/agent-runner.ts` (look up the `reportSilentFallback` call there).

### FR2: Consolidate `NEXT_PUBLIC_APP_URL` as canonical (`#2768`)

- Migrate `apps/web-platform/app/api/auth/github-resolve/route.ts` and `apps/web-platform/app/api/auth/github-resolve/callback/route.ts` to read `NEXT_PUBLIC_APP_URL` instead of `NEXT_PUBLIC_SITE_URL`.
- After the code change ships and the prod container restarts, delete `NEXT_PUBLIC_SITE_URL` from Doppler `prd` via explicit per-command ack (per `hr-menu-option-ack-not-prod-write-auth`).
- No other consumers of `NEXT_PUBLIC_SITE_URL` may remain — verified via `rg NEXT_PUBLIC_SITE_URL` after the migration (zero hits in `apps/`, `server/`, `lib/`).

### FR3: Pre-deploy required-secrets CI guard (`#2769`)

A CI job that runs **before** the web-platform deploy step and fails the deploy if any secret in a hand-maintained required-list is absent from Doppler `prd`:

```bash
REQUIRED=(
  NEXT_PUBLIC_APP_URL
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  NEXT_PUBLIC_SENTRY_DSN
  NEXT_PUBLIC_VAPID_PUBLIC_KEY
  NEXT_PUBLIC_GITHUB_APP_SLUG
)
```

(The final list is determined at plan time after grepping current `process.env.NEXT_PUBLIC_*` usage; `NEXT_PUBLIC_SITE_URL` is omitted because FR2 removes it.)

Failing the job must emit a `::error::` line naming the missing secret and exit non-zero.

### FR4: Close `#2773` / `#2774` with passive evidence

- `#2773`: Close with a comment citing the Sentry query result — `count` unchanged at 1, `firstSeen == lastSeen == 2026-04-22T07:44:03Z` (pre-deploy), queried ≥8h post-deploy.
- `#2774`: Close with a comment noting redundancy per the issue's own body ("if `#2773` confirms silence, this check is redundant and can be closed").
- If the plan opts to do an active trigger (authenticated session → `POST /api/repo/setup`) for extra assurance, the Sentry re-query must occur ≥10 minutes after the trigger before closing `#2773`.

## Technical Requirements

### TR1: PR split

- **PR-A** implements FR1 + FR2. Closes `#2770`, `#2768`.
- **PR-B** implements FR3. Closes `#2769`.
- `#2773` / `#2774` close out of band with comment-only updates (FR4), not tied to either PR.

### TR2: Doppler `prd` write ordering

The `NEXT_PUBLIC_SITE_URL` deletion (FR2) must happen **after** PR-A merges and the prod container has restarted with the migrated code. Sequence:

1. Merge PR-A.
2. Wait for Web Platform Release workflow to succeed.
3. Verify `docker exec soleur-web-platform printenv NEXT_PUBLIC_SITE_URL` still returns the current value (container running with old env injection but new code that doesn't read it).
4. Run `doppler secrets delete NEXT_PUBLIC_SITE_URL --project soleur --config prd` — show verbatim, wait for per-command go-ahead (`hr-menu-option-ack-not-prod-write-auth`).
5. Next deploy propagates the deletion; verify absence via a subsequent `printenv` check.

### TR3: CI guard wiring

- New job in `.github/workflows/reusable-release.yml` or a dedicated `verify-doppler-secrets.yml` called as a prerequisite. Exact location decided at plan time.
- Uses `DOPPLER_TOKEN_PRD` (per-config service token — `cq-doppler-service-tokens-are-per-config`). Must not use bare `DOPPLER_TOKEN`.
- Must block the deploy job via `needs:` dependency, not run in parallel.

### TR4: Tests

- FR1: Unit tests for `checkout/route.ts` and `billing/portal/route.ts` asserting `reportSilentFallback` is called when `NEXT_PUBLIC_APP_URL` is unset. Follow existing mirror-pattern tests from PR #2480/#2484.
- FR2: Unit tests for the migrated `github-resolve` routes verifying they read from `NEXT_PUBLIC_APP_URL`.
- FR3: A shell-level sanity test (local dry-run of the guard script with a known-present secret) is sufficient; the workflow itself is the acceptance test on the next deploy run.

### TR5: Rules compliance

- `cq-silent-fallback-must-mirror-to-sentry` — FR1 is the primary remediation.
- `hr-menu-option-ack-not-prod-write-auth` — TR2 step 4.
- `cq-doppler-service-tokens-are-per-config` — TR3.
- `hr-exhaust-all-automated-options-before` — FR4 uses Sentry API (automated), not SSH.
- `cq-for-production-debugging-use` — Sentry API is the primary verification surface for FR4.

## Acceptance Criteria

- [ ] PR-A merged; `rg NEXT_PUBLIC_SITE_URL apps/ server/ lib/` returns zero.
- [ ] `reportSilentFallback` grep in `checkout/route.ts` and `billing/portal/route.ts` each return ≥1 hit.
- [ ] `NEXT_PUBLIC_SITE_URL` absent from `doppler secrets --project soleur --config prd --only-names`.
- [ ] PR-B merged; manually trigger the new workflow; `gh run view` shows the guard job passed.
- [ ] `#2770`, `#2768`, `#2769` closed via PR body `Closes #N`.
- [ ] `#2773`, `#2774` closed with comment citing Sentry passive evidence.

## Risks

- **Doppler delete fires before container restart** → 500s on `github-resolve` routes if old code is still running. Mitigated by TR2 step ordering.
- **CI guard required-list drifts** (future `NEXT_PUBLIC_*` added without array update). Accepted: next missing-secret firing reveals the drift, same signal as auto-compute.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-22-app-url-hardening-brainstorm.md`
- Prior PR: #2767
- Prior session-state: `knowledge-base/project/specs/feat-one-shot-next-public-app-url-unset/session-state.md`
- Issues: `#2768`, `#2769`, `#2770`, `#2773`, `#2774`

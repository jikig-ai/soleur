---
title: "fix: resolve GitHub installation token 401 in Inngest function execution"
type: fix
date: 2026-05-26
classification: ops-only-prod-write
lane: single-domain
brand_survival_threshold: none
sentry_id: 4324b0b7671a4682994043249d210abd
---

# fix: resolve GitHub installation token 401 in Inngest function execution

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** 4 (Hypotheses, Phase 2 Hardening, Research Insights, Risks)
**Research agents used:** codebase grep, `@octokit/auth-app` source analysis, `universal-github-app-jwt` source analysis, learnings scan

### Key Improvements
1. Added H7 (transient GitHub token replication delay) -- discovered by reading `@octokit/auth-app@8.2.0` source showing built-in 401 retry logic that the hand-rolled path lacks
2. Corrected PEM-handling divergence hypothesis -- both paths use identical `replace(/\\n/g, '\n')` normalization (verified in `universal-github-app-jwt/index.js:17`)
3. Added Phase 2.4 retry-on-401 hardening to close the resilience gap between the `@octokit/app` and hand-rolled JWT paths
4. Elevated H6 (clock skew) from "unlikely" to "viable differential cause" -- `@octokit/auth-app` silently self-heals clock skew; hand-rolled path does not

### New Considerations Discovered
- `@octokit/auth-app` has two resilience features the hand-rolled path lacks: clock-skew retry with `timeDifference` compensation, and 401 replication-delay retry
- The TR9 Phase 2 migration (#4483) increased `generateInstallationToken()` call volume, increasing exposure to transient 401 windows

## Overview

Production Sentry error on 2026-05-26 at 4:27:02 PM CEST: `POST /api/inngest` returns error `GitHub installation token request failed: 401`. The error originates at `apps/web-platform/server/github-app.ts:484` in `generateInstallationToken()` when the GitHub API rejects the App JWT with HTTP 401 on `POST /app/installations/{installationId}/access_tokens`.

The `POST /api/inngest` route is the Inngest SDK serve endpoint. The Inngest server calls this endpoint to execute registered functions (cron jobs, event-driven functions). When a function's step calls `generateInstallationToken()` (directly or via `mintInstallationToken()` / `gitWithInstallationAuth()` / `syncWorkspace()`), the JWT-signed request to GitHub fails with 401.

### Error chain

1. Inngest server POSTs to `/api/inngest` to execute a function step
2. The step calls a code path that needs a GitHub installation token
3. `generateInstallationToken()` mints an App JWT via `createAppJwt()` (hand-rolled RS256 at `github-app.ts:108-127`)
4. The JWT is sent as `Authorization: Bearer <jwt>` to `POST /app/installations/{id}/access_tokens`
5. GitHub responds HTTP 401 ("Bad credentials")
6. The function throws `Error("GitHub installation token request failed: 401")`
7. Sentry captures the exception via the `sentryCorrelationMiddleware` at `server/inngest/middleware/sentry-correlation.ts:129`

### Candidate callers (any of these could trigger the 401)

Functions that call `generateInstallationToken` directly or transitively:

- **Cron functions via `_cron-shared.ts:mintInstallationToken()`**: `cron-bug-fixer`, `cron-skill-freshness`, `cron-weekly-analytics`, `cron-growth-audit`, `cron-growth-execution`, `cron-agent-native-audit`, `cron-content-publisher`, `cron-compound-promote`, `cron-nag-4216-readiness`, `cron-linkedin-token-check`, `cron-community-monitor`, `event-ship-merge`, and all other crons migrated in TR9 Phase 2 (#4483)
- **`workspace-reconcile-on-push`** via `syncWorkspace()` -> `gitWithInstallationAuth()` -> `generateInstallationToken()`
- **`oneshot-gdpr-gate-50d-eval`** via direct `generateInstallationToken()` call

## User-Brand Impact

- **If this lands broken, the user experiences:** all Inngest-driven cron functions (daily triage, bug fixer, content publisher, community monitor, etc.) silently fail. Workspace reconciliation on push stops syncing. The operator sees `missed` Sentry cron monitor alerts but no user-facing error.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A -- this is an auth failure, not a data leak. The private key is server-only and never reaches the client.
- **Brand-survival threshold:** `none` -- this is an operator-only infrastructure issue affecting automated internal workflows. No founder-facing surface is impacted (the dashboard, auth, and manual KB operations use `createGitHubAppClient()` from `app-client.ts` which uses `@octokit/app` with its own JWT minting, independent of `createAppJwt()`).
- `threshold: none, reason: the edit adds defensive logging and PEM-shape warnings to an existing server-only auth helper; no new code paths reach founders and the private key never leaves server scope`

## Hypotheses

The 401 on `POST /app/installations/{id}/access_tokens` with an App JWT means one of:

### H1: PEM private key corrupted or rotated in Doppler (MOST LIKELY)

`GITHUB_APP_PRIVATE_KEY` in Doppler `prd` may have been corrupted (literal `\n` instead of real newlines, partial paste, BOM prefix) or rotated on the GitHub App admin page without updating Doppler. The `getPrivateKey()` function at `github-app.ts:97-101` does `raw.replace(/\\n/g, "\n")` which handles the `\n`-escape case but not other corruption modes.

**Note:** The `@octokit/app` path (used by `createGitHubAppClient()` and `createProbeOctokit()`) does its own internal PEM parsing that may tolerate different corruption patterns than the hand-rolled `createSign("RSA-SHA256")` path. If `createProbeOctokit()` succeeds for `mintInstallationToken()`'s installation discovery step but `createAppJwt()` fails for the token exchange, this points to a PEM handling divergence between the two code paths.

### H2: GITHUB_APP_ID mismatch

The App ID in Doppler doesn't match the private key. This would cause a JWT whose `iss` claim doesn't match any GitHub App, yielding a 401.

### H3: Installation ID stale or uninstalled

The `installationId` stored in the database (from `users.github_installation_id` or discovered via `GET /repos/{owner}/{repo}/installation`) may reference a deleted/suspended/reinstalled installation. GitHub returns 401 when the installation no longer exists for the given App.

### H4: GitHub App suspended or deleted

The App itself may have been suspended by GitHub or the org admin. All JWT operations would return 401.

### H5: Env not reloaded after Doppler change

Per `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`, Doppler values are baked at container start. If the key was rotated in Doppler but no redeploy happened, the running container still holds the old key.

### H6: Clock skew

The JWT `iat` (issued-at) is `now - 60` and `exp` is `now + 10*60`. If the server clock drifted more than 60 seconds into the future relative to GitHub's clock, the JWT would be rejected. Unlikely on Hetzner (NTP-synced), but worth ruling out.

**Deepen-pass finding:** `@octokit/auth-app@8.2.0` has built-in clock-skew detection and retry (`hook.ts:isNotTimeSkewError` + `timeDifference` re-mint). The hand-rolled `createAppJwt()` has no equivalent. If `createProbeOctokit()` succeeds (installation discovery via `@octokit/app`) but `generateInstallationToken()` fails (hand-rolled JWT), clock skew is a viable differential cause -- `@octokit/app` silently self-heals while `createAppJwt()` fails through.

### H7: Transient GitHub token replication delay (ADDED BY DEEPEN-PASS)

`@octokit/auth-app@8.2.0` retries 401 responses for up to 5 seconds after installation token creation (`sendRequestWithRetries` in `hook.ts`), accounting for GitHub's internal token replication lag between datacenters. The hand-rolled `generateInstallationToken()` does NOT retry -- a transient 401 during replication would succeed via `@octokit/app` but fail via `createAppJwt()`. This is particularly relevant given the TR9 Phase 2 migration (#4483) significantly increased the rate of `generateInstallationToken()` calls, increasing exposure to transient replication windows.

## Diagnostic Plan

### Phase 0: Triage (read-only, no code changes)

**Goal:** Identify which hypothesis is correct before writing any fix.

0.1. **Check Sentry event details.** Look at the Sentry event `4324b0b7671a4682994043249d210abd` for:
   - `inngest.fn_id` tag -- which function was executing
   - `inngest.run_id` tag -- correlate with Inngest dashboard
   - `inngest.event_name` tag -- what triggered it
   - The `extra.inngest.event_data` -- installationId used
   - The error body logged at `github-app.ts:479-482` (`status`, `body`, `installationId`)

0.2. **Check if the drift guard cron caught it.** The `cron-github-app-drift-guard` function (migrated in TR9 PR-4, #4303) runs periodically and checks `GET /app` with the JWT. If it also 401'd, it would have filed a `[ci/auth-broken]` issue. Check:
   ```bash
   gh issue list --search "[ci/auth-broken]" --state open --json number,title --limit 5
   ```

0.3. **Verify App JWT validity from operator machine.** Mint a JWT locally and test against GitHub API:
   ```bash
   # Read credentials from Doppler
   APP_ID=$(doppler secrets get GITHUB_APP_ID --plain -p soleur -c prd)
   PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd)

   # Write PEM to temp file and validate shape
   PEM_FILE=$(mktemp)
   printf '%s\n' "$PEM" > "$PEM_FILE"
   openssl rsa -in "$PEM_FILE" -check -noout 2>&1
   # Expected: "RSA key ok"

   # Mint JWT and test GET /app
   NOW=$(date +%s)
   HEADER=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64 -w 0 | tr '+/' '-_' | tr -d '=\n')
   PAYLOAD=$(jq -nc --argjson iss "$APP_ID" --argjson iat "$((NOW-60))" --argjson exp "$((NOW+540))" '{iss:$iss,iat:$iat,exp:$exp}' | base64 -w 0 | tr '+/' '-_' | tr -d '=\n')
   SIGNATURE=$(printf '%s' "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -sign "$PEM_FILE" -binary | base64 -w 0 | tr '+/' '-_' | tr -d '=\n')
   JWT="${HEADER}.${PAYLOAD}.${SIGNATURE}"

   # Test App-level endpoint
   curl -sS -w "\n%{http_code}\n" -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" https://api.github.com/app

   # Test installation token exchange
   INSTALL_ID=122213433  # from the Sentry event or Doppler
   curl -sS -w "\n%{http_code}\n" -X POST -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" "https://api.github.com/app/installations/${INSTALL_ID}/access_tokens"

   rm -f "$PEM_FILE"
   ```

0.4. **If 0.3 returns 401:** The PEM or App ID in Doppler is wrong. Cross-check:
   - App ID in Doppler vs GitHub App settings page (`https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`)
   - PEM in Doppler vs password manager / original generation source
   - Check if the PEM was recently rotated on GitHub's App admin page

0.5. **If 0.3 returns 200:** The credentials are valid from the operator machine. The issue is runtime-specific:
   - **Clock skew:** Check server time via `date -u` on the production container (if accessible via the deploy webhook pattern, NOT SSH per `hr-no-ssh-fallback-in-runbooks`)
   - **Env staleness:** Check if a Doppler change was made after the last deploy (compare Doppler audit log timestamps with last deploy timestamp)
   - **Transient GitHub outage:** Check `https://www.githubstatus.com/` for the time window (2026-05-26 14:27 UTC)
   - **Installation-specific:** Test with the specific `installationId` from the Sentry event (it may differ from the operator's installation)

### Phase 1: Fix (conditional on diagnosis)

The fix depends on which hypothesis is confirmed:

**If H1 (PEM corrupted):**
1. Re-download the PEM from GitHub App settings or password manager
2. Update in Doppler: `doppler secrets set GITHUB_APP_PRIVATE_KEY="$(cat <pem-file>)" -p soleur -c prd`
3. Trigger redeploy via deploy webhook (per learning `2026-05-19-doppler-env-hot-reload-limitation.md`)
4. Verify via Sentry cron monitors returning to `ok` status

**If H2 (App ID mismatch):**
1. Verify correct App ID from GitHub App settings page
2. Update in Doppler: `doppler secrets set GITHUB_APP_ID=<correct-id> -p soleur -c prd`
3. Redeploy

**If H3 (Installation ID stale):**
1. Query the specific installation ID that failed (from Sentry event)
2. If it's a founder's installation that was uninstalled/reinstalled: update the `users.github_installation_id` column
3. If it's the operator installation (`jikig-ai/soleur`): check if the App was reinstalled and update the installation ID

**If H4 (App suspended):**
1. Check GitHub App settings page for suspension status
2. If suspended by org admin: unsuspend
3. If suspended by GitHub: contact GitHub support

**If H5 (Env stale):**
1. Trigger redeploy only (no Doppler changes needed)

**If H6 (Clock skew):**
1. Verify NTP status on the production host
2. If drift detected: fix NTP configuration in Terraform / cloud-init

### Phase 2: Hardening (code changes, if applicable)

Regardless of root cause, add defensive improvements to `generateInstallationToken()`:

2.1. **Improve error logging.** Currently, `github-app.ts:479-482` logs `status` and `body.slice(0, 500)`. Add:
   - The `iss` (App ID) from the JWT payload -- helps distinguish H1 vs H2
   - A truncated hash of the PEM (first 8 chars of SHA-256) -- helps distinguish "wrong key" from "corrupted key" across deploys without logging the key itself
   - Server timestamp at JWT creation -- helps detect clock skew (H6)

2.2. **Add PEM shape validation at module load.** In `getPrivateKey()`, after the `\n` replacement, verify the PEM starts with `-----BEGIN RSA PRIVATE KEY-----` (or `-----BEGIN PRIVATE KEY-----` for PKCS#8). Log a warning (not throw, per existing convention) if the shape is unexpected. This catches H1 at startup rather than at first token request.

2.3. **Mirror 401 to Sentry with structured tags.** The current code throws a generic `Error("GitHub installation token request failed: 401")`. Enhance to include structured Sentry tags (`feature: "github-app"`, `op: "generate-installation-token"`, `installationId`) so the error is filterable in Sentry without relying on the middleware's generic tags.

2.4. **(ADDED BY DEEPEN-PASS) Add retry-on-401 for transient GitHub replication delay.** Mirror `@octokit/auth-app@8.2.0`'s `sendRequestWithRetries` pattern: on 401, wait 1s and retry once (max 1 retry, 1s delay). This closes the resilience gap between the `@octokit/app` path and the hand-rolled `createAppJwt()` path identified in the deepen-pass research. The retry must be scoped to 401 only -- other 4xx/5xx codes should fail immediately. Implementation: wrap the `githubFetch` call at `github-app.ts:467-475` in a retry loop with `response.status === 401` as the retry predicate.

    ```typescript
    // Retry once on 401 — mirrors @octokit/auth-app's
    // sendRequestWithRetries for GitHub token replication delay.
    if (response.status === 401 && !retried) {
      retried = true;
      log.warn({ installationId }, "401 on installation token — retrying once after 1s");
      await new Promise((r) => setTimeout(r, 1_000));
      // Re-mint JWT (fresh iat/exp) for the retry
      const retryJwt = createAppJwt();
      response = await githubFetch(
        `${GITHUB_API}/app/installations/${installationId}/access_tokens`,
        { method: "POST", headers: { Authorization: `Bearer ${retryJwt}` } },
      );
    }
    ```

## Files to Edit

- `apps/web-platform/server/github-app.ts` -- Phase 2 hardening (improved logging, PEM validation, structured Sentry tags)

## Files to Create

None.

## Open Code-Review Overlap

None.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitors for each Inngest function (e.g. scheduled-daily-triage, scheduled-bug-fixer)
  cadence: per-function schedule (varies: hourly to daily)
  alert_target: operator email via Sentry alerts
  configured_in: each cron function's postSentryHeartbeat() call

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN
  fail_loud: Sentry exception with inngest.fn_id / inngest.run_id tags + Inngest dashboard failed-run entry

failure_modes:
  - mode: GitHub App JWT rejected (401)
    detection: Sentry exception "GitHub installation token request failed: 401" + Sentry cron monitor "missed" alerts
    alert_route: operator email + Sentry issue stream
  - mode: Inngest function step fails
    detection: Inngest dashboard shows failed run + Sentry exception via sentry-correlation middleware
    alert_route: operator via Sentry alert rules

logs:
  where: journalctl -u soleur-web.service on Hetzner VM + Vector-shipped to external aggregator
  retention: journald 30d on disk, Vector-shipped logs per aggregator retention

discoverability_test:
  command: |
    doppler run -p soleur -c prd -- bash -c 'curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $(node -e "
      const {createSign}=require(\"crypto\");
      const now=Math.floor(Date.now()/1000);
      const b64u=b=>b.toString(\"base64\").replace(/=/g,\"\").replace(/\\+/g,\"-\").replace(/\\//g,\"_\");
      const h=b64u(Buffer.from(JSON.stringify({alg:\"RS256\",typ:\"JWT\"})));
      const p=b64u(Buffer.from(JSON.stringify({iss:process.env.GITHUB_APP_ID,iat:now-60,exp:now+540})));
      const s=createSign(\"RSA-SHA256\");s.update(h+\".\"+p);s.end();
      const sig=b64u(s.sign(process.env.GITHUB_APP_PRIVATE_KEY.replace(/\\\\n/g,\"\\n\")));
      process.stdout.write(h+\".\"+p+\".\"+sig)
    ")" -H "Accept: application/vnd.github+json" https://api.github.com/app'
  expected_output: "200"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix scoped to the GitHub App authentication layer used by Inngest cron functions.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Root cause identified and documented in a learning file under `knowledge-base/project/learnings/bug-fixes/`
- [ ] AC2: `generateInstallationToken()` at `github-app.ts:477-485` logs the App ID (from `getAppId()`) and a truncated PEM fingerprint (first 8 hex chars of SHA-256 of the PEM) alongside the existing `status`, `body`, and `installationId` fields
- [ ] AC3: `getPrivateKey()` at `github-app.ts:97-101` logs a warning if the PEM does not match `/^-----BEGIN (RSA )?PRIVATE KEY-----/` after newline replacement
- [ ] AC4: The error thrown at `github-app.ts:484` is captured via `reportSilentFallback` with structured tags `{ feature: "github-app", op: "generate-installation-token" }` in addition to the existing throw (belt-and-suspenders with the sentry-correlation middleware)
- [ ] AC5: `generateInstallationToken()` retries once on 401 with a 1s delay and a fresh JWT, logging `warn` on the first 401. Second 401 throws as before. Verified by mocking `githubFetch` to return 401 then 200 in test.
- [ ] AC6: Existing tests pass: `./node_modules/.bin/vitest run test/github-app*.test.ts test/github-api*.test.ts`

### Post-merge (operator)

- [ ] AC7: If root cause is Doppler credential issue (H1/H2/H5): credentials corrected in Doppler `prd` and redeploy triggered
- [ ] AC8: Sentry cron monitors for at least 3 Inngest functions show `ok` status within 2 hours of fix deployment
- [ ] AC9: No new `GitHub installation token request failed: 401` Sentry events for 24 hours post-fix

## Test Scenarios

- Given the PEM in env starts with `-----BEGIN RSA PRIVATE KEY-----`, when `getPrivateKey()` is called, then no warning is logged
- Given the PEM in env starts with `CORRUPTED_PREFIX`, when `getPrivateKey()` is called, then a warning is logged but the function does not throw
- Given `generateInstallationToken()` receives a 401 from GitHub on the first attempt, when the retry succeeds (200 on second attempt), then the function returns the token and logs a warn-level message for the initial 401
- Given `generateInstallationToken()` receives a 401 from GitHub on both attempts, when the retry also returns 401, then the function throws with `reportSilentFallback` and structured Sentry tags
- Given `generateInstallationToken()` receives a 403 from GitHub, when the error occurs, then NO retry is attempted (retry is scoped to 401 only)
- Given a valid App JWT, when `POST /app/installations/{id}/access_tokens` returns 200, then the token is cached with the correct expiry

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Diagnosis takes longer than expected (transient issue already resolved) | Phase 0 triage is entirely read-only; if the error doesn't reproduce, document as transient and ship Phase 2 hardening (including the retry-on-401) anyway -- the resilience gap is real regardless |
| PEM rotation required but original lost | Download new PEM from GitHub App admin page; existing PEM can be regenerated |
| Multiple Inngest functions affected simultaneously | All functions share the same `generateInstallationToken()` path; fixing the root cause fixes all |
| Retry-on-401 (Phase 2.4) masks a real credential failure | The retry is scoped to exactly 1 retry with 1s delay, and the log.warn ensures the retry is visible in structured logs. A real credential failure fails on both attempts and surfaces as before. The warn-level log on first 401 provides early signal even when the retry succeeds |
| Clock-skew self-heal in `@octokit/app` masks the root cause | Phase 0.5 explicitly checks server time if Phase 0.3 succeeds from the operator machine. The `createAppJwt()` hardening (server timestamp logging in Phase 2.1) makes future skew incidents diagnosable without SSH |

## Research Insights

- **Two distinct JWT minting paths exist but handle PEM identically:** `github-app.ts:createAppJwt()` (hand-rolled RS256) and `@octokit/app` (used by `app-client.ts` and `probe-octokit.ts`). Deepen-pass verified that `universal-github-app-jwt/index.js:17` does `privateKey.replace(/\\n/g, '\n')` -- the same replacement as `github-app.ts:getPrivateKey():101`. Both paths normalize literal `\n` escapes. PEM-handling divergence is NOT a viable hypothesis for differential behavior between the two paths.
- **`@octokit/auth-app` has built-in time-skew detection and retry that `createAppJwt()` lacks.** The `hook.ts` function in `@octokit/auth-app@8.2.0` catches `'Expiration time' claim ('exp') is too far in the future` and `'Issued at' claim ('iat')` errors, parses the GitHub `Date` response header, computes the skew delta, and retries with `timeDifference` compensation. The hand-rolled `createAppJwt()` path has NO equivalent -- a clock-skew-induced 401 would propagate as-is. This makes H6 (clock skew) more plausible than initially estimated for the `generateInstallationToken` path specifically, even if `@octokit/app` callers silently self-heal.
- **`mintInstallationToken()` in `_cron-shared.ts:31-42` chains both paths:** first `createProbeOctokit()` (uses `@octokit/app`) for installation discovery, then `generateInstallationToken()` (uses hand-rolled JWT) for token exchange. If `createProbeOctokit()` succeeds (meaning the App JWT is valid per `@octokit/app`'s path) but `generateInstallationToken()` fails, the cause is NOT PEM corruption (both paths use the same PEM) but could be clock-skew (only `@octokit/app` retries with compensation) or a transient GitHub-side 401 (only `@octokit/app` retries installation tokens on 401).
- **`@octokit/auth-app` retries 401s on installation tokens.** The `sendRequestWithRetries` function in `hook.ts` retries up to 5 seconds after token creation on 401 responses, accounting for GitHub's token replication delay. The hand-rolled `generateInstallationToken()` path does NOT retry -- a transient 401 during token replication would succeed via `@octokit/app` but fail via `createAppJwt()`. This is a significant resilience gap.
- **The Inngest substrate was recently expanded:** TR9 Phase 2 (#4483, merged 2026-05-26) migrated all remaining GHA scheduled workflows to Inngest. This significantly increased the number of functions calling `generateInstallationToken()`, increasing the probability of hitting a transient or latent credential issue.
- **Token cache margin learning applies:** Per `knowledge-base/project/learnings/2026-05-24-token-cache-margin-vs-consumer-budget-envelope.md`, the `minRemainingMs` parameter was added to `generateInstallationToken()` in TR9 PR-5. Long-running cron functions pass a floor. If the error occurs during the token exchange itself (not cache retrieval), the `minRemainingMs` parameter is irrelevant -- the JWT creation is the failing step, not the cache check.
- **Prior precedent:** `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` documents a 3-plane permission drift where installation grants lagged behind App declarations. The 401 could be a similar class -- credentials valid at App-level but not at installation-level.
- **Doppler env bake limitation:** Per `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`, any Doppler change requires a container redeploy to take effect.

## References

- Sentry event: `4324b0b7671a4682994043249d210abd`
- Error source: `apps/web-platform/server/github-app.ts:477-485`
- Inngest serve route: `apps/web-platform/app/api/inngest/route.ts`
- Token minting shared helper: `apps/web-platform/server/inngest/functions/_cron-shared.ts:31-42`
- GitHub App drift guard: `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`
- Prior learning (three-plane drift): `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`
- Prior learning (Inngest substrate bugs): `knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md`
- Prior learning (Doppler env bake): `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`
- Prior learning (JWT inline mint): `knowledge-base/project/learnings/2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md`
- ADR-030: self-hosted Inngest substrate architecture

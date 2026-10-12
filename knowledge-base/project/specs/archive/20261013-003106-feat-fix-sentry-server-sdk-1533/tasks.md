# Tasks: fix Sentry server-side SDK not sending events

## Phase 1: Diagnose

- [x] 1.1 SSH into production server (`root@135.181.45.178` or `root@app.soleur.ai`)
- [x] 1.2 Run `docker exec soleur-web-platform printenv SENTRY_DSN` to check container env — **EMPTY (confirmed missing)**
- [x] 1.3 SENTRY_DSN missing: checked all env vars — zero SENTRY_* vars in container despite 32 in Doppler
- [x] 1.4 Doppler download on server includes SENTRY_DSN — confirmed with server's service token
- [x] 1.5 N/A (Doppler download succeeded)
- [x] 1.6 esbuild preserves sentry side-effect import — confirmed via --metafile (sentry.server.config.ts in inputs)
- [x] 1.7 N/A (SENTRY_DSN not in container — Scenario A)
- [x] 1.8 N/A (SENTRY_DSN not in container — Scenario A)
- [x] 1.9 Root cause: container was deployed with stale env set missing newer Doppler secrets (SENTRY_DSN added after last env refresh). A redeploy with current Doppler secrets will inject SENTRY_DSN.

## Phase 2: Fix

- [x] 2.1 Root cause: stale env set. Fix: redeploy (triggered by this PR's merge) downloads fresh Doppler secrets
- [x] 2.2 Add SENTRY_DSN startup diagnostic log in `apps/web-platform/server/index.ts`
- [x] 2.3 Add `sentry` field to `/health` endpoint — extracted to `server/health.ts` with tests
- [x] 2.4 Add startup test event gated by SENTRY_DSN
- [x] 2.5 Add conditional `debug: process.env.SENTRY_DEBUG === "1"` to sentry.server.config.ts
- [x] 2.6 Add SIGTERM handler with `Sentry.flush(2000)` in server/index.ts
- [x] 2.7 esbuild preserves sentry import — verified via --metafile (5 require calls in bundle)

## Phase 3: Deploy and Verify

- [x] 3.1 Dependencies verified (no new dependencies added)
- [ ] 3.2 Run `npm run build && npm run build:server` to verify build succeeds
- [x] 3.3 Tests: 442 passed, 1 skipped, 0 failed
- [ ] 3.4 Commit and push changes
- [ ] 3.5 Create PR with `Closes #1533` in body
- [ ] 3.6 After merge and deploy: verify SENTRY_DSN in container env via SSH
- [ ] 3.7 After deploy: query Sentry API for startup event within 60s
  - `curl -sH "Authorization: Bearer $SENTRY_API_TOKEN" "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/events/?query=Server+startup&statsPeriod=24h" | jq 'length > 0'`
- [ ] 3.8 After deploy: verify health endpoint includes `sentry: "configured"`
  - `curl -sf https://app.soleur.ai/health | jq -r '.sentry'`
- [ ] 3.9 After deploy: trigger an actual error and verify it appears in Sentry

# Tasks: fix Sentry server-side SDK not sending events

## Phase 1: Diagnose

- [ ] 1.1 SSH into production server (`root@135.181.45.178` or `root@app.soleur.ai`)
- [ ] 1.2 Run `docker exec soleur-web-platform printenv SENTRY_DSN` to check container env
- [ ] 1.3 If SENTRY_DSN missing: run `docker inspect soleur-web-platform --format='{{range .Config.Env}}{{println .}}{{end}}' | grep SENTRY` to check all Sentry env vars
- [ ] 1.4 If SENTRY_DSN missing: check Doppler download on server -- `doppler secrets download --no-file --format docker --project soleur --config prd | grep SENTRY_DSN`
- [ ] 1.5 If Doppler download fails: check `/etc/default/webhook-deploy` for DOPPLER_TOKEN presence and scope
- [ ] 1.6 If SENTRY_DSN present: verify esbuild preserves side-effect import -- run `npx esbuild server/index.ts --bundle --platform=node --target=node22 --outfile=/tmp/test.cjs --external:@sentry/nextjs --metafile=/tmp/meta.json` and check for sentry.server.config in the metafile inputs
- [ ] 1.7 If SENTRY_DSN present: test network egress from container -- `docker exec soleur-web-platform node -e "fetch('https://ingest.de.sentry.io/').then(r => console.log('Status:', r.status)).catch(e => console.error('Error:', e.message))"`
- [ ] 1.8 If SENTRY_DSN present: verify `@sentry/nextjs` is importable -- `docker exec soleur-web-platform node -e "try{require('@sentry/nextjs');console.log('OK')}catch(e){console.error('FAIL:',e.message)}"`
- [ ] 1.9 Document diagnosis result

## Phase 2: Fix

- [ ] 2.1 Fix root cause based on Phase 1 findings (env injection, SDK init, or network)
- [ ] 2.2 Add SENTRY_DSN startup diagnostic log in `apps/web-platform/server/index.ts`
  - Log: `log.info({ sentryConfigured: !!process.env.SENTRY_DSN, sentryEnvironment: process.env.NODE_ENV }, "Sentry status")`
- [ ] 2.3 Add `sentry` field to `/health` endpoint response in `apps/web-platform/server/index.ts`
  - Value: `process.env.SENTRY_DSN ? "configured" : "not-configured"`
  - NEVER expose the actual DSN value
- [ ] 2.4 Add startup test event in `apps/web-platform/server/index.ts`
  - `if (process.env.SENTRY_DSN) { Sentry.captureMessage("Server startup v" + (process.env.BUILD_VERSION || "dev"), "info"); }`
  - Gate behind SENTRY_DSN check to avoid noise in dev
- [ ] 2.5 Add conditional `debug` option to `apps/web-platform/sentry.server.config.ts`
  - `debug: process.env.SENTRY_DEBUG === "1"`
  - Allows enabling debug mode via Doppler without code changes
- [ ] 2.6 Add SIGTERM handler with `Sentry.flush()` in `apps/web-platform/server/index.ts`
  - `process.on("SIGTERM", async () => { log.info("SIGTERM received"); await Sentry.flush(2000); process.exit(0); });`
  - Ensures events in transport buffer are sent before Docker stops the container
- [ ] 2.7 Verify `sentry.server.config.ts` side-effect import is preserved in esbuild bundle
  - Check with `--metafile` or grep bundle output for `Sentry.init`

## Phase 3: Deploy and Verify

- [ ] 3.1 Run `npm install` in `apps/web-platform/` to verify no dependency issues
- [ ] 3.2 Run `npm run build && npm run build:server` to verify build succeeds
- [ ] 3.3 Run tests: `cd apps/web-platform && npx vitest run`
- [ ] 3.4 Commit and push changes
- [ ] 3.5 Create PR with `Closes #1533` in body
- [ ] 3.6 After merge and deploy: verify SENTRY_DSN in container env via SSH
- [ ] 3.7 After deploy: query Sentry API for startup event within 60s
  - `curl -sH "Authorization: Bearer $SENTRY_API_TOKEN" "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/events/?query=Server+startup&statsPeriod=24h" | jq 'length > 0'`
- [ ] 3.8 After deploy: verify health endpoint includes `sentry: "configured"`
  - `curl -sf https://app.soleur.ai/health | jq -r '.sentry'`
- [ ] 3.9 After deploy: trigger an actual error and verify it appears in Sentry

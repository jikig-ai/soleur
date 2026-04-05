# Tasks: fix Sentry server-side SDK not sending events

## Phase 1: Diagnose

- [ ] 1.1 SSH into production server (`root@135.181.45.178` or `root@app.soleur.ai`)
- [ ] 1.2 Run `docker exec soleur-web-platform printenv SENTRY_DSN` to check container env
- [ ] 1.3 If SENTRY_DSN missing: run `docker inspect soleur-web-platform --format='{{range .Config.Env}}{{println .}}{{end}}' | grep SENTRY` to check all Sentry env vars
- [ ] 1.4 If SENTRY_DSN missing: check Doppler token scope on server -- verify the service token can access prd config
- [ ] 1.5 If SENTRY_DSN present: check esbuild bundle output for Sentry.init call presence
- [ ] 1.6 If SENTRY_DSN present: test network egress from container -- `docker exec soleur-web-platform node -e "fetch('https://ingest.de.sentry.io').then(r => console.log(r.status)).catch(e => console.error(e))"`
- [ ] 1.7 Document diagnosis result

## Phase 2: Fix

- [ ] 2.1 Fix based on Phase 1 findings (env injection, SDK init, or network)
- [ ] 2.2 Add SENTRY_DSN startup diagnostic log in `apps/web-platform/server/index.ts`
  - Log: `log.info({ sentryConfigured: !!process.env.SENTRY_DSN }, "Sentry status")`
- [ ] 2.3 Add `sentry` field to `/health` endpoint response in `apps/web-platform/server/index.ts`
  - Value: `process.env.SENTRY_DSN ? "configured" : "not-configured"`
  - NEVER expose the actual DSN value
- [ ] 2.4 Add startup test event: `Sentry.captureMessage("Server startup", "info")` after Sentry init
  - Conditional: only send if `SENTRY_DSN` is set (avoid noise in dev)
- [ ] 2.5 Verify `sentry.server.config.ts` side-effect import is not tree-shaken by esbuild
  - Check bundle output or add explicit reference if needed

## Phase 3: Deploy and Verify

- [ ] 3.1 Run `npm install` in `apps/web-platform/` to verify no dependency issues
- [ ] 3.2 Run `npm run build && npm run build:server` to verify build succeeds
- [ ] 3.3 Run tests: `cd apps/web-platform && npx vitest run`
- [ ] 3.4 Commit and push changes
- [ ] 3.5 Create PR with `Closes #1533` in body
- [ ] 3.6 After merge and deploy: verify SENTRY_DSN in container env via SSH
- [ ] 3.7 After deploy: query Sentry API for startup event within 60s
- [ ] 3.8 After deploy: verify health endpoint includes `sentry: "configured"`
- [ ] 3.9 After deploy: trigger an actual error and verify it appears in Sentry

# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-next-public-app-url-unset/knowledge-base/project/plans/2026-04-22-fix-next-public-app-url-unset-in-prod-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause confirmed via Doppler CLI: `NEXT_PUBLIC_APP_URL` is absent from ALL four Doppler configs (`dev`, `prd`, `ci`, `prd_terraform`). Sentry error fires because `resolve_env_file` has nothing to inject. `NEXT_PUBLIC_SITE_URL` exists in `prd` with the same value but is a separate env var.
- Fix is config-only, not code. Set `NEXT_PUBLIC_APP_URL=https://app.soleur.ai` in Doppler `prd` and `NEXT_PUBLIC_APP_URL=http://localhost:3000` in `dev`. Existing `reportSilentFallback` + literal-fallback is correct behavior.
- Prior plan at 2026-04-17-feat-agent-user-parity-kb-share-plan.md:443 asserted the secret was "already configured" — contradicted by current state. Captured in plan's Research Reconciliation section.
- Explicit ack gate for prod Doppler write per `hr-menu-option-ack-not-prod-write-auth`: show the `doppler secrets set ... -c prd` command verbatim and wait for per-command go-ahead.
- Two injection paths analyzed: runtime `--env-file` (Doppler `prd`) vs build-time `build-args` (GHA secrets → Dockerfile `ARG`). `agent-runner.ts` is server-side so only runtime path needs fixing. Invariant captured as scope-out.
- Three deferrals filed per `wg-when-deferring-a-capability-create-a`: (a) `APP_URL`/`SITE_URL` consolidation refactor, (b) CI regression-guard for required `NEXT_PUBLIC_*` presence in Doppler `prd`, (c) mirror silent `??` fallbacks in `checkout/route.ts` + `billing/portal/route.ts` to Sentry.
- Post-merge verification via Sentry API per `cq-for-production-debugging-use`. Explicitly waits ≥10 min after deploy and actively triggers `POST /api/repo/setup`.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash investigation: `doppler secrets get` / `doppler secrets -p soleur -c prd --only-names`, repo grep for `NEXT_PUBLIC_APP_URL`
- Read: `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/server/observability.ts`, `apps/web-platform/infra/ci-deploy.sh`, `.github/workflows/reusable-release.yml`
- `npx markdownlint-cli2 --fix` on the plan file (0 errors)

# Tasks: /sys sandbox denyRead + report-only cross-workspace isolation canary probe

Plan: knowledge-base/project/plans/2026-10-09-feat-sys-denyread-isolation-deploy-gate-plan.md
Issues: #1285, #2640

## Phase 1: /sys denyRead (#1285)

- [ ] 1.1 RED(unit): update literal `toEqual` deny-list pins in `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` and `apps/web-platform/test/agent-runner-helpers.test.ts` to include `"/sys"` immediately after `"/proc"` — run to confirm RED
- [ ] 1.2 GREEN: add `"/sys"` to the constant deny set in `buildAgentSandboxConfig` (`apps/web-platform/server/agent-runner-sandbox-config.ts`) after `"/proc"`; update adjacent comment
- [ ] 1.3 Run `npx vitest run test/agent-sandbox-tenant-deny.test.ts test/agent-runner-helpers.test.ts test/agent-runner-query-options.test.ts` — green

## Phase 2: vitest tooling in the runner image (#2640, part 1)

- [ ] 2.1 RED(unit): create `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` asserting the Dockerfile `cli-tools` stage carries `npm install -g vitest@<lockfile-version> --before=<date> --ignore-scripts` — run to confirm RED
- [ ] 2.2 GREEN: `apps/web-platform/Dockerfile` — vitest global install in `cli-tools` stage; `runner` stage COPYs the 3-file test payload; `apps/web-platform/.dockerignore` — three exact-path `!test/…` bangs
- [ ] 2.3 Create `apps/web-platform/test/vitest.canary.config.ts` (node env, include only `test/sandbox-isolation.test.ts`, `cacheDir: "/tmp/vitest-cache"`, no globalSetup/setupFiles)
- [ ] 2.4 RED(unit)+GREEN: `SOLEUR_ISOLATION_TIERS` env filter in `apps/web-platform/test/sandbox-isolation.test.ts` (`direct` skips query-tier probe evaluation; FR9 unchanged)
- [ ] 2.5 Verify: pin test + `docker-context-import-containment.test.ts` green; `docker build` viability if docker available

## Phase 3: report-only deploy probe + surfaces (#2640, part 2)

- [ ] 3.1 RED(integration): `apps/web-platform/infra/ci-deploy.test.sh` — mock-docker vitest exec arm (`MOCK_CWI_LOG`, `MOCK_CWI_PROBE_OUT`/`MOCK_CWI_PROBE_RC`, `MOCK_DOCKER_EXEC_FAIL_CANARY_VITEST`) + `assert_cross_workspace_isolation` (ordering, dark-launch continuation, per-rc verdicts) — run to confirm RED
- [ ] 3.2 GREEN: `apps/web-platform/infra/ci-deploy.sh` — `WORKSPACE_ISOLATION_STATE_FILE`, `write_workspace_isolation_state` (atomic, consecutive_pass/first_pass_at accumulation), `workspace_isolation_sentry_event`, `run_workspace_isolation_probe`, call site `|| true` after `run_faithful_sandbox_canary` inside `CANARY_HEALTHY`
- [ ] 3.3 `apps/web-platform/infra/cat-deploy-state.sh` — `workspace_isolation_json` reader + `.workspace_isolation` field
- [ ] 3.4 `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` 50 → 51 with PLACEMENT/TRUTH/NO-SUBSTITUTE comment
- [ ] 3.5 `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` — document the new probe layer
- [ ] 3.6 Create `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md` — design note (image strategy + size delta, gate-vs-report decision, promotion criteria)
- [ ] 3.7 Create `scripts/followthroughs/workspace-isolation-verdict-2640.sh` — modeled on `canary-promotion-5875.sh`; exit 0 when `consecutive_pass >= 5` AND span since `first_pass_at` >= 3 days; exit 1 on recorded `workspace_isolation_failed`; TRANSIENT (2) otherwise

## Phase 4: verification + docs

- [ ] 4.1 `bash apps/web-platform/infra/ci-deploy.test.sh` — new arms green (note: suite exceeds ~5min in constrained env; pre-existing mock-canary FAILs on untouched tree are environmental — verify new arms specifically; authoritative gate is `infra-validation.yml` deploy-script-tests)
- [ ] 4.2 `npx markdownlint-cli2` on new/edited markdown — green
- [ ] 4.3 Final AC sweep: run each Acceptance Criteria command literally; PR body notes image-size delta; `Closes #1285` / `Closes #2640` on own lines; promotion issue reminder with followthrough directive

# Tasks — feat-one-shot-9294-deploy-creds-tier-move

Plan: `knowledge-base/project/plans/2026-11-16-9294-deploy-channel-creds-tier-move.md`
Issue: #9294 (G1 of ADR-241 D10 residual; gates #8609)

## Phase 1 — PR-A: carrier + loader + census constants

- [x] 1.1 Create `apps/web-platform/infra/deploy-channel-environment.tf`
  - [x] 1.1.1 `doppler_project.deploy_channel` (`soleur-deploy-channel`, `prevent_destroy`, <=255-char description; header carries the D11 no-secret/no-token/no-data-source warning)
  - [x] 1.1.2 `doppler_environment.deploy_channel_prd` (`slug = "prd"`, `prevent_destroy`)
  - [x] 1.1.3 `github_repository_environment.deploy_channel` — `deployment_branch_policy { protected_branches = false; custom_branch_policies = true }`, NO reviewers
  - [x] 1.1.4 `github_repository_environment_deployment_policy.deploy_channel_main` (`branch_pattern = "main"`)
  - [x] 1.1.5 Add all four resources to the `-target=` allow-list in `.github/workflows/apply-web-platform-infra.yml`
- [x] 1.2 Loader narrow mode in `.github/actions/infra-credentials/action.yml`
  - [x] 1.2.1 `doppler-project` input (default `soleur-infra-privileged`; allowlist `{soleur-infra-privileged, soleur-deploy-channel}`; fail closed otherwise)
  - [x] 1.2.2 `doppler-token-deploy-channel` input; narrow + empty token fails closed with named verdict
  - [x] 1.2.3 Narrow arm: whole-project `doppler secrets download -p soleur-deploy-channel -c prd`, exports plain names + `TF_VAR_` spellings; skips legacy arm, App-runtime opt-in, state-bucket aliasing; names no trio stem literally
  - [x] 1.2.4 `outputs.source` narrow marker (`tier_b_deploy_channel`)
  - [x] 1.2.5 Loader test fixtures covering allowlist refusal, empty-token refusal, narrow export shape
- [x] 1.3 Census constants in `tests/scripts/test-infra-privileged-tier-census.sh`
  - [x] 1.3.1 `TIER_B_ENVIRONMENTS` += `deploy-channel` (`.tf`-parseable policy)
  - [x] 1.3.2 `ENV_SECRETS` += `DOPPLER_TOKEN_DEPLOY_CHANNEL`
  - [x] 1.3.3 Guard 7 assembly covers `soleur-deploy-channel`
  - [x] 1.3.4 Narrow-mode guard rows + mutation fixtures (allowlist, empty token, never reads `prd_terraform`)
- [x] 1.4 C4 `model.c4` `github -> doppler` edge: add `deploy-channel` + `soleur-deploy-channel` + `DOPPLER_TOKEN_DEPLOY_CHANNEL` clause (D11-clause shape); verify `views.c4`/`spec.c4` need no include change
- [ ] 1.5 PR-A green; merge; apply-on-merge creates the carriers
- [ ] 1.6 OWNER-NAMED seed (operator-authorized, recorded in PR body): verify live `protection_rules` main-only; hash-equal copy trio `soleur-infra-privileged/prd` -> `soleur-deploy-channel/prd`; mint read token; `gh secret set DOPPLER_TOKEN_DEPLOY_CHANNEL` on `deploy-channel` + `inngest-cutover`

## Phase 2 — PR-B: consumer migration + boundary proofs

- [ ] 2.1 Workflow env binds + narrow loader wiring (remove every `secrets.<trio>` reference)
  - [ ] 2.1.1 `web-platform-release.yml` — `deploy`, `verify-peer-deploy` -> `deploy-channel`
  - [ ] 2.1.2 `canary-status.yml` -> `deploy-channel`
  - [ ] 2.1.3 `cutover-inngest.yml` — env expr `(gated ops) && 'inngest-cutover' || 'deploy-channel'`; narrow loader per arm; `if: op == 'backup'` privileged step stays HCLOUD-only
  - [ ] 2.1.4 `deploy-inngest-image.yml` -> `deploy-channel`
  - [ ] 2.1.5 `inngest-key-rotate.yml` `redeploy` -> `deploy-channel`
  - [ ] 2.1.6 `inngest-link-flip.yml` `flip`, `revert` -> `deploy-channel`
  - [ ] 2.1.7 `key-rotate.yml` `redeploy` -> `deploy-channel`
  - [ ] 2.1.8 `restart-inngest-server.yml` -> `deploy-channel`
  - [ ] 2.1.9 `scheduled-inngest-health.yml` `probe` -> `deploy-channel`
  - [ ] 2.1.10 `apply-deploy-pipeline-fix.yml` — remove residual `secrets.<trio>` binds
- [ ] 2.2 Sweeper partition
  - [ ] 2.2.1 `scripts/followthroughs/sweep-followthroughs.sh`: `FT_ONLY_SECRETS` / `FT_EXCLUDE_SECRETS` parse + skip-summary lines + zero-trio-probes coverage refusal
  - [ ] 2.2.2 `scheduled-followthrough-sweeper.yml`: `sweep` gets `FT_EXCLUDE_SECRETS=<trio>`; new `sweep-deploy-channel` job (`environment: deploy-channel` + narrow loader + `FT_ONLY_SECRETS=<trio>,GH_TOKEN`)
  - [ ] 2.2.3 Delete the full #6178 artifact set: `scripts/followthroughs/inngest-soak-6178.sh`, `inngest-soak-6178.test.sh`, `inngest-soak-6178.function-ids.txt`, and the `run_suite "scripts/inngest-soak-6178"` line in `scripts/test-all.sh` (#6178 CLOSED; early delete ≤2026-11-21 costs a daily stderr line only)
- [ ] 2.3 Script/doc de-shaping (counted read shape -> explicit named env reads)
  - [ ] 2.3.1 `apps/web-platform/scripts/github-app-key-status.sh` (recipe + `${!v}` loop)
  - [ ] 2.3.2 `scripts/ensure-doppler.sh` (comment)
  - [ ] 2.3.3 `scripts/key-rotate.sh`, `scripts/inngest-link-flip.sh`, `scripts/cutover-inngest.sh`, `apps/web-platform/infra/infra-config-verify.sh`, `scripts/check-deploy-script-parity.sh`, `scripts/verify-tunnel-ingress-origin.sh`, `apps/web-platform/infra/soleur-host-bootstrap.sh`, `apps/web-platform/infra/cloud-init*.yml` — disposition per counted shape found
  - [ ] 2.3.4 Skill docs: `plugins/soleur/skills/{postmerge,qa,ship}/SKILL.md`, `postmerge/references/deploy-status-debugging.md`, `plan/references/plan-sharp-edges.md` — prose naming `soleur-deploy-channel/prd`, no literal `doppler run` token
  - [ ] 2.3.5 Archived `knowledge-base/project/specs/archive/…/bootstrap.sh` de-shape
- [ ] 2.4 Pinned-shape test updates (cutover/key-rotate/link-flip workflow tests, infra-config-verify tests, `test-argv-bearer-sweep.sh`, dispatch-web-redeploy tests, cloud-init/provisioner-parity tests, check-deploy-script-parity tests)
- [ ] 2.5 Baseline end-state: `tests/scripts/trio-baseline.tsv` — zero `tier-a`/`FALLBACK:*`/`ALIAS:*` rows; each row deleted, forward-classed, or covered by an ADR-241 `Allow:`/`Reclass:`/`Re-date:` line; named ruling for any un-dispositionable row
- [ ] 2.6 Census boundary rows: trio -> `TIER_B_NAMES`, every-job-naming-trio-must-declare-Tier-B-env row, mutation fixtures RED
- [ ] 2.7 ADR-241 dated D1 census-amendment entry
- [ ] 2.8 PR-B green; merge

## Phase 3 — Post-merge (owner-named; agent does not execute)

- [ ] 3.1 Verify canary reports `source=tier_b_deploy_channel`; migrated workflows green on main
- [ ] 3.2 OWNER-NAMED tail: delete trio from `prd_terraform` + repo Actions secrets (+ `CF_TUNNEL_TOKEN` if riding the same path); record postcondition in #9294
- [ ] 3.3 Confirm exclusions untouched: rotation machinery, `cloudflare_zero_trust_access_service_token.deploy` state reconciliation (#7103 B5), credential rotation

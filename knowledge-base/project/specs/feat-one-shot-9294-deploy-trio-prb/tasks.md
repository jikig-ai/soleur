# Tasks — feat-one-shot-9294-deploy-trio-prb (#9294 PR-B)

Plan: `knowledge-base/project/plans/2026-11-20-feat-deploy-trio-consumer-migration-prb-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-9294-deploy-trio-prb/decision-challenges.md`

Phases are ordered contract-first: census constants and guard rows before
consumer edits, baseline regeneration last.

## Phase 0 — Preconditions and fork rulings

- [x] 0.1 Re-run the consumer census: `git grep -nE 'WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET' -- .github/workflows/` and reconcile against the plan's consumer table before editing.
- [x] 0.2 Resolve `pending - assumed` rows D-1 and D-2 in `decision-challenges.md` via the parent's `soleur:engineering:cto` spawn; write the rulings into the file before touching sweeper or scanner code. — DONE 2026-11-20: parent CTO spawn ruled all rows (gate PASS, 9 rows); D-1 derived-`@stems` partition, D-2 pinned scanner refinement (see decision file for the exact exemption shape).
- [x] 0.3 Emit the pre-state baseline: `bash tests/scripts/test-trio-baseline-census.sh --emit-baseline` and save the row inventory as the diff reference.

## Phase 1 — Census constants and boundary guard rows

- [x] 1.1 Add `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` to `TIER_B_NAMES` in `tests/scripts/test-infra-privileged-tier-census.sh`; confirm `DOPPLER_TOKEN_DEPLOY_CHANNEL` in `ENV_SECRETS` and `deploy-channel` in `TIER_B_ENVIRONMENTS`.
- [x] 1.2 Add the Guard-1 boundary rows (naming-the-trio ⇒ literal Tier-B env; `.tf`-policy membership proof; multi-job fixture; every-trio-name fixture) each with its mutation fixture driven RED first.
- [x] 1.3 Run `bash tests/scripts/test-infra-privileged-tier-census.sh` — RED only where the pending workflow edits still bind `secrets.<trio>`; proceed when the new rows' fixtures behave as designed.

## Phase 2 — Workflow consumer migration

- [x] 2.1 `web-platform-release.yml`: `deploy` + `verify-peer-deploy` bind `environment: deploy-channel` + narrow loader step; drop the 4 trio bind sites; rename `WEBHOOK_SECRET` reads to canonical; de-shape both `${!_v}` CF-pair trim loops to explicit per-name expansions.
- [x] 2.2 `canary-status.yml`, `deploy-inngest-image.yml`, `restart-inngest-server.yml`, `scheduled-inngest-health.yml`: `deploy-channel` + narrow loader; drop binds; canonical-name reads (`bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET`, explicit CF expansions).
- [x] 2.3 `inngest-key-rotate.yml` `redeploy`, `inngest-link-flip.yml` `flip` (+ `Revert to http` step), `key-rotate.yml` `redeploy` (track + vector steps): `deploy-channel` + narrow loader; drop binds (scripts read ambient canonical env).
- [x] 2.4 `cutover-inngest.yml`: extend the `environment:` expression to `(rollback || resume || backup) && 'inngest-cutover' || 'deploy-channel'`; narrow loader step serving every arm; keep the `op == 'backup'` privileged-loader step untouched; drop trio binds.
- [x] 2.5 Verify zero `${{ secrets.<trio> }}` remains under `.github/workflows/`; `actionlint` each edited workflow + `bash -c` the extracted `run:` snippets.

## Phase 3 — Sweeper partition

- [x] 3.1 `scripts/sweep-followthroughs.sh`: per the D-1 ruling, add the partition flags (ONLY/EXCLUDE or stems-derived set), the exclusive-partition skip logic with summary lines on both arms, and the zero-trio-probes coverage refusal.
- [x] 3.2 `scheduled-followthrough-sweeper.yml`: `sweep` loses the trio binds and gains the Tier-A flag; add the `sweep-deploy-channel` job (`environment: deploy-channel`, narrow loader, checkout with `persist-credentials: false` + `fetch-depth: 0`, `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`, ONLY-side flag); refresh the :135 comment block.
- [x] 3.3 Update `sweep-followthroughs` test fixtures: trio tracker + absent Tier-B env → coverage RED; partition overlap → RED; declared-superset → skipped-by-both.

## Phase 4 — Script de-shapes and canonical reads

- [x] 4.1 `scripts/cutover-inngest.sh`: `WEBHOOK_SECRET` → `WEBHOOK_DEPLOY_SECRET` (signature var + `${!_sigvar}` dereference stay coherent); leave `doppler … betterstack-query.sh` reads for D-2 disposition.
- [x] 4.2 `scripts/inngest-link-flip.sh`: reword the `:306` `doppler run` recipe print to name `soleur-deploy-channel/prd` in prose.
- [x] 4.3 `apps/web-platform/scripts/github-app-key-status.sh`: `${!v}` loop → three explicit `${VAR:?}` checks; header recipe → `soleur-deploy-channel/prd` prose.
- [x] 4.4 `apps/web-platform/infra/infra-config-verify.sh` + `infra/scripts/verify-tunnel-ingress-origin.sh`: `doppler` reads of `APP_DOMAIN_BASE`/`WEB1_IP`/`CF_API_TOKEN`/`CF_ACCOUNT_ID` → `scripts/derive-app-domain-base.sh` or env reads; `${!_cred}` → explicit; recipe strings → prose; residual → D-2.
- [x] 4.5 `scripts/ensure-doppler.sh`, `scripts/inngest-key-rotate.sh`: correct recipe comments to name `soleur-deploy-channel/prd` as the trio's home.
- [x] 4.6 Apply the D-2 disposition (ruled: the pinned scanner class refinement — targeted non-family `secrets get` not counted; `doppler run`/`download` exempt only with literal `-p`+`-c` outside the pinned trio-carrying set; fail closed otherwise — no `Reclass:` lines) to `apply-deploy-pipeline-fix.yml`, `scripts/key-rotate.sh`, `scripts/cutover-inngest.sh`, `scripts/check-deploy-script-parity.sh`, `apps/web-platform/infra/soleur-host-bootstrap.sh`, and any residual — in the same diff as the ADR-241 amendment that records it.

## Phase 5 — Probe retirement

- [x] 5.1 Delete `scripts/followthroughs/inngest-soak-6178.sh`, `scripts/followthroughs/inngest-soak-6178.test.sh`, `scripts/followthroughs/inngest-soak-6178.function-ids.txt`, and the `test-all.sh` `run_suite` line + comment block (:6548-6551).
- [x] 5.2 Update the stale precedent comment in `.claude/hooks/grep-q-pipe-guard.test.sh:2215`.

## Phase 6 — Pinned-shape test updates

- [x] 6.1 Update `apps/web-platform/infra/{cutover-inngest,inngest-key-rotate,inngest-link-flip,key-rotate}-workflow.test.sh` + `cloud-init-web-zot-seed.test.sh` assertions to the loader-export/canonical-env shapes.
- [x] 6.2 Update `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/test-dispatch-web-redeploy.sh`, `scripts/check-deploy-script-parity.test.sh`, `apps/web-platform/infra/{infra-config-verify,infra-config-repush-mutation,inngest-dedicated-host-classify}.test.sh`, `scripts/followthroughs/{sdk-bash-smoke-verdict-10548,web2-luks-live-6931}.test.sh`, `plugins/soleur/test/preflight-discoverability-test.test.ts`, and any `dispatch-web-redeploy` fixture that pins `secrets.<trio>` binds.

## Phase 7 — Doc de-shapes

- [x] 7.1 `plugins/soleur/skills/postmerge/SKILL.md`, `postmerge/references/deploy-status-debugging.md`, `qa/SKILL.md`, `ship/SKILL.md`, `plan/references/plan-sharp-edges.md`: every `doppler run|secrets get` recipe naming the trio from `prd_terraform` → prose naming `soleur-deploy-channel/prd`.
- [x] 7.2 `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`: narrow-project spelling for trio reads; residual `doppler` arms → D-2 disposition.

## Phase 8 — Baseline end state, ADR-241, C4

- [x] 8.1 Regenerate `tests/scripts/trio-baseline.tsv` via `--emit-baseline`; assert zero `tier-a`, `FALLBACK:*`, `ALIAS:*` rows and scanner agreement on every survivor.
- [x] 8.2 `bash tests/scripts/test-trio-baseline-census.sh` + `bash tests/scripts/test-infra-privileged-tier-census.sh` green incl. mutation fixtures; `bash tests/scripts/test-argv-bearer-sweep.sh` unchanged-green. — argv-sweep 825/0, tier-census 485/0; trio-census 618/1 where the sole failure is T4 pending PR #13087 merge + rebase (new-key @allow lane, by design).
- [x] 8.3 Append the dated D1 census-amendment entry to `ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` (incl. `Allow:`/`Reclass:`/`Re-date:` lines the baseline diff requires + the ruled D-2 scanner refinement).
- [x] 8.4 `model.c4`: rewrite the deploy-channel edge `STATUS (Phase 1)` clause to the migrated state, add `deploy-channel` to the Tier-B edge's environment enumeration, refresh the loader-consumer wording.

## Phase 9 — Final verification

- [x] 9.1 Full sweep: `git grep -nE 'secrets\.(WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET)' -- .github/workflows/` returns zero; every naming job binds a literal Tier-B env.
- [x] 9.2 Run touched test shards + the two census suites + sweeper tests green. — same caveat as 8.2: T4 red until the @allow reservation lands at merge-base.
- [ ] 9.3 Record the post-merge postcondition in the PR body slot the D1 amendment names (owner-named tail: Tier-A copy deletion after green `source=tier_b_deploy_channel` canaries; rotation machinery untouched).

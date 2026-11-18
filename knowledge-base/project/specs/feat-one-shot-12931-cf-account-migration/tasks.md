---
lane: cross-domain
---

# Tasks: migrate Terraform to the new Soleur Cloudflare account and zone (#12931)

Plan: `knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`. Decision log: `decision-challenges.md` (same directory).

Lane note: there is no spec.md for this branch (one-shot entry), so the lane defaults to `cross-domain`. The work is infra (engineering) with operations-owned credential steps.

`Operator-authorizes:` marks a production-mutating step. It runs only after the operator's go, or under a standing delegation recorded on #12931.

## Phase 0: Credentials (no repo change)

- [ ] 0.1 Doppler `prd_terraform` `CF_R2_ACCOUNT_ID` = legacy account id. This must exist before PR1 merges. `Operator-authorizes:` agent write.
- [ ] 0.2 Phase 0a mints: `CF_API_TOKEN`, `CF_API_TOKEN_RULESETS`, `CF_API_TOKEN_PAGES`, each into a `<KEY>_NEXT` staging key with the exact permission groups in the plan table. Use the dashboard via `cf-token-scope`. `Operator-authorizes:`.
- [ ] 0.3 Run the non-mutating `cf-token-scope.sh` new-account profile for `redirects-dns` (invalid-body write probes). Record the verdicts and every pre-existing entrypoint id.
- [ ] 0.4 Read-only dump of new-zone record ids for the 26 non-tunnel, non-`app` records plus `app`. The dump stays outside the repo; only the ids are committed.
- [ ] 0.5 Phase 0b mints (`_ZONE_SETTINGS`, `_BOT_MANAGEMENT`, `_DNS_EDIT`, `_PURGE`) into `_NEXT` keys. These can run in parallel with Phase 2. `Operator-authorizes:`.

## Phase 1: PR1 code (this branch). Tests first.

- [ ] 1.1 RED suites first:
  - [ ] 1.1.1 state-migrate (Guard 2, every declared `cloudflare_*` type in the fixture)
  - [ ] 1.1.2 phase gate (Guard 1, rows 1-11)
  - [ ] 1.1.3 in-progress predicate (Guard 3) and the workflow-grep test over every plan-running job
  - [ ] 1.1.4 tftest `expect_failures` for the old-id validations (Guard 4)
  - [ ] 1.1.5 rehearsal shape (local backend override, zero S3 writes)
  - [ ] 1.1.6 `apps/cla-evidence/infra/main.test.sh` assertion for `CF_R2_ACCOUNT_ID`
- [ ] 1.2 `variables.tf`:
  - add `cf_r2_account_id`, the old-id validations, `cf_load_balancing_enabled`, `cf_zone_plan_pro`, `cf_zone_dnssec_enabled`, `cf_migration_imports_enabled`, `cf_migration_import_app`;
  - delete `adopt_seo_config_entrypoint`;
  - update `tests/web-hosts-eu-pin.tftest.hcl`.
- [ ] 1.3 R2 carve-out: `workspaces-luks-header.tf`, `workspaces-luks-header-web.tf`, `infra-privileged-environment.tf` → `var.cf_r2_account_id`. Also `apps/cla-evidence/infra/bootstrap.sh` reads `CF_R2_ACCOUNT_ID`.
- [ ] 1.4 LB count gate (`cloudflare-lb.tf`) and `[0]` refs; LB-address tests (`rg` sweep); `cf-lb-overlay.yml` refusal; retire `ga-lb-pool-soak-6027` followthrough if still armed.
- [ ] 1.5 `bot-management.tf` `sbfm_*` ternaries; `dns.tf` DNSSEC count gate and `[0]` refs.
- [ ] 1.6 `seo-config-rules.tf`: delete the old-id import block and the TEMPORARY `ssl=full` rule; update `apps/web-platform/test/seo-config-rules.test.ts` and any fixture an assertion reads.
- [ ] 1.7 `cf-account-migration-imports.tf`: 26 records, the Pages project and 2 domains, plus any probe-found entrypoints. The `app` import is gated off by `cf_migration_import_app`.
- [ ] 1.8 `cf-runtime-zone-id.tf`: `doppler_secret.cf_zone_id_prd`; add it to the stage-1 `-target` list.
- [ ] 1.9 `scripts/cf-account-state-migrate.sh`: backup, state-derived candidates, null-safe classification, one atomic `state rm`, serial +1 assertion.
- [ ] 1.10 `scripts/cf-account-migrate-gate.sh`: per-phase list generating `-target`, pure-import check, derived counts, `plan-gate-preamble.sh`, `gate-suite-harness.sh` suite.
- [ ] 1.11 `scripts/cf-account-migration-complete.sh` and its call sites in every plan-capable job except `cf_account_migrate` (with the `web_host_replace web-2` exception).
- [ ] 1.12 `apply-web-platform-infra.yml`:
  - `apply_target=cf-account-migrate`, `migrate_phase`, `confirm`;
  - job `cf_account_migrate` (infra-privileged, shared concurrency group, no SSH, no bridge);
  - rehearsal in a scratch root with remote-serial assertion;
  - post-apply curl verification.
- [ ] 1.13 `scripts/check-cloudflare-token-drift.sh` repoint; `cf-token-scope.sh` new-account profiles.
- [ ] 1.14 `deploy-docs.yml` probe A URL → `soleur-docs-40x.pages.dev`.
- [ ] 1.15 ADR-329 (`status: adopting`, via `soleur:architecture`). `model.c4` edits to the `cloudflare` system description, the `inngest -> api` edge and the `tunnel` description. C4 tests green.
- [ ] 1.16 Runbook `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: phases, expected reds, fix-forward, full revert, branch-config write list.
- [ ] 1.17 Register new suites in `run-registered-suites.sh` inputs. Full local battery green.
- [ ] 1.18 Registry render delta on the PR1 diff = `deliver=false`.
- [ ] 1.19 PR body first line: "Merging this alone mutates no production resource". Use `Ref #12931`. The merge commit carries `[skip-web-platform-apply]`.

## Phase 2: Redirect restore (after PR1 merges)

- [ ] 2.1 `Operator-authorizes:` one sequence:
  - `<KEY>_PREV` copies;
  - flip `CF_ZONE_ID`/`CF_ACCOUNT_ID`;
  - swap the 0a `_NEXT` keys;
  - branch-config writes from the names-only inventory;
  - revoke the old DNS-edit token.
  Read every value back.
- [ ] 2.2 `Operator-authorizes:` the `redirects-dns` rehearsal (`plan_only=true`). Gate `verdict=PASS`, remote serial unchanged. Arm a watch.
- [ ] 2.3 `Operator-authorizes:` the `redirects-dns` apply. Verify: four 301 URLs, `x-robots-tag: noindex` on `app.soleur.ai`, GPTBot 200, four Better Stack redirect monitors `up`.
- [ ] 2.4 Search Console check for indexed `app.soleur.ai` token URLs, and removal requests (operator scope row).
- [ ] 2.5 Swap the 0b keys. `Operator-authorizes:` the `zone-rest` rehearsal, then the apply. Next docs push: probe A and probe B pass.

## Phase 3: PR2 (new branch from main): tunnel and deploy hosts

- [ ] 3.1 PR2 code:
  - `cf-access-deploy-token-mint.sh` and its test;
  - `cf-tunnel-host-predelete.sh` and its test (Guard 5);
  - the `tunnel` phase in the job and the gate (deploy-policy exception plus token-exists GET);
  - the `app` import enabled;
  - `local.deploy_service_token_ids`.
- [ ] 3.2 `Operator-authorizes:` mint the `CF_API_TOKEN_ACCESS_MINT` token, run the mint script, commit the UUID, revoke the mint token.
- [ ] 3.3 Merge PR2 with `[skip-web-platform-apply]`. `Operator-authorizes:` pre-delete dry-run, then apply; `tunnel` rehearsal, then apply; CI-SSH token sync.
- [ ] 3.4 `Operator-authorizes:` the `web-host-replace web_host_key=web-2` rehearsal, then the run.
- [ ] 3.5 `Operator-authorizes:` Origin CA re-mint from the new zone.
- [ ] 3.6 Verify:
  - census shows 1 connector;
  - `verify-tunnel-ingress-origin.sh` passes;
  - CI SSH bridge round-trip;
  - registry push canary;
  - `web-platform-release.yml` redeploy.
- [ ] 3.7 `Operator-authorizes:` `apply_target=manual-rerun`. Expected: green.

## Phase 4: Close the incident

- [ ] 4.1 With all 9 monitors `up` and the deploy hosts serving, flip the post-mortem `status: resolved`, add recovery timestamps, and mark the #12931 action-item row resolved.

## Phase 5: Cleanup PR

- [ ] 5.1 Delete the imports file, the state-migrate script, the predicate and its call sites, the migration variables, the `cf_account_migrate` job, input and option, and the gate. Keep the mint script and the probe profiles.
- [ ] 5.2 `Operator-authorizes:` revoke `CF_API_TOKEN_SOLEUR_ACCT` and the superseded tokens; remove the `_PREV`/`_NEXT` keys.
- [ ] 5.3 `Operator-authorizes:` delete the old tunnel and the other forgotten old-ACCOUNT objects by name (never old-zone objects). Delete the state backup object.
- [ ] 5.4 Re-scope the read-only tokens. Update `infra-security.md` and the 8209 runbook literals. Update the expense ledger.
- [ ] 5.5 Set ADR-329 to `accepted`. The PR body carries `Closes #12931`.
- [ ] 5.6 Follow-up issues to file: DNSSEC re-enable, LB purchase decision plus the `lb-staging` root, the app-level `X-Robots-Tag` fallback.

---
lane: cross-domain
---

# Tasks: migrate Terraform to the new Soleur Cloudflare account and zone (#12931)

Plan: `knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`. Decision log: `decision-challenges.md` (same directory).

Lane note: there is no spec.md for this branch (one-shot entry), so the lane defaults to `cross-domain`. The work is infra (engineering) with operations-owned credential steps.

`Operator-authorizes:` marks a production-mutating step. It runs only after the operator's go, or under a standing delegation recorded on #12931.

## Phase 0: Credentials (no repo change)

- [x] 0.1 Doppler `prd_terraform` `CF_R2_ACCOUNT_ID` = legacy account id. This must exist before PR1 merges. `Operator-authorizes:` agent write. Written and verified 2026-11-19 (prefix `4d5ba6f0`).
- [ ] 0.2 Phase 0a mints: `CF_API_TOKEN`, `CF_API_TOKEN_RULESETS`, `CF_API_TOKEN_PAGES`, each into a `<KEY>_NEXT` staging key with the exact permission groups in the plan table. Use the dashboard via `cf-token-scope`. `Operator-authorizes:`.
  - Scope each token to the new account and the soleur.ai zone, with an expiry.
  - Hand-off per CTO L75: `browser_run_code_unsafe` creates the token and `page.request.post`s it to a 127.0.0.1 one-shot sink (mode 0600, scratchpad, outside every work tree); Bash pipes it to Doppler on stdin and shreds it. Never `browser_evaluate` with `filename`, never a snapshot. After each mint, `git status --porcelain` in the main checkout and the worktree shows no new file.
  - Verify by sha256 compare, never by printing.
- [ ] 0.2b Revoke `CF_API_TOKEN_SOLEUR_ACCT` once 0a is probed, with the runbook's revoke recipe (id, delete, read-back, key delete in every holder the bootstrap `inventory` stage lists). `Operator-authorizes:`.
- [ ] 0.3 Run the non-mutating `cf-token-scope.sh` new-account profile for `redirects-dns`: `--profile redirects-dns --staged`: invalid-body write probes on the new zone and account (one fixed never-valid literal; any 2xx aborts with a read-back; a sibling control token first proves 403-before-400, CTO L49; old ids refused before any request), a whole-list entrypoint audit, and a known-present control. Expected run line `probe=redirects-dns verdict=pass`. Record the verdicts and every pre-existing entrypoint id.
- [ ] 0.3b ~~Optional Phase 0c early noindex~~: withdrawn as a recommendation (CTO ruling D2): the migrate job's entrypoint gate refuses a populated entrypoint until an import block lands in a PR.
- [x] 0.4 Read-only dump of new-zone record ids for the 26 non-tunnel, non-`app` records plus `app`. The dump stays outside the repo; only the ids are committed.
- [ ] 0.5 Phase 0b mints (`_ZONE_SETTINGS`, `_BOT_MANAGEMENT`, `_DNS_EDIT`, `_PURGE`) into `_NEXT` keys. These can run in parallel with Phase 2. `Operator-authorizes:`.

## Phase 1: PR1 code (this branch). Tests first.

- [x] 1.1 RED suites first:
  - [ ] 1.1.1 state-migrate (Guard 2, every declared `cloudflare_*` type in the fixture; assert `Successfully removed N` equals the rm set and zero old ids after, mutation row 7; classify all before any write, an unknown id anywhere aborts with 0 removed, CTO L47/L72)
  - [ ] 1.1.2 phase gate (Guard 1, rows 1-11 including 9b `replace_by_request` and 9c physical-id)
  - [ ] 1.1.3 in-progress predicate (Guard 3) and the workflow-grep test over every plan-running job
  - [ ] 1.1.4 tftest `expect_failures` for the old-id validations (Guard 4)
  - [ ] 1.1.5 rehearsal shape (local backend override, backup to `$RUNNER_TEMP/cf-migrate`, no `aws s3 cp`, remote serial unchanged and no new object under `web-platform/backups/`, CTO L24/L43)
  - [ ] 1.1.6 `apps/cla-evidence/infra/main.test.sh` assertion for `CF_R2_ACCOUNT_ID`
- [x] 1.2 `variables.tf`:
  - add `cf_r2_account_id`, the old-id validations, `cf_load_balancing_enabled`, `cf_zone_plan_pro`, `cf_zone_dnssec_enabled`, `cf_migration_imports_enabled`, `cf_migration_import_app`;
  - delete `adopt_seo_config_entrypoint`;
  - update `tests/web-hosts-eu-pin.tftest.hcl`.
- [x] 1.3 R2 carve-out: `workspaces-luks-header.tf`, `workspaces-luks-header-web.tf`, `infra-privileged-environment.tf` → `var.cf_r2_account_id`. Also `apps/cla-evidence/infra/bootstrap.sh` reads `CF_R2_ACCOUNT_ID`.
- [x] 1.4 LB count gate (`cloudflare-lb.tf`) and `[0]` refs; LB-address tests (`rg` sweep); `cf-lb-overlay.yml` refusal; retire `ga-lb-pool-soak-6027` followthrough if still armed.
- [x] 1.5 `bot-management.tf` `sbfm_*` ternaries; `dns.tf` DNSSEC count gate and `[0]` refs.
- [x] 1.6 `seo-config-rules.tf`: delete the old-id import block (the TEMPORARY `ssl=full` rule is KEPT, CTO L55 re-ruling, #7799); update `apps/web-platform/test/seo-config-rules.test.ts` and any fixture an assertion reads.
- [x] 1.7 `cf-account-migration-imports.tf`: 26 records, the Pages project and 2 domains, plus any probe-found entrypoints. The `app` import is gated off by `cf_migration_import_app`.
- [x] 1.8 `cf-runtime-zone-id.tf`: `doppler_secret.cf_zone_id_prd`; add it to the stage-1 `-target` list.
- [x] 1.9 `scripts/cf-account-state-migrate.sh`: backup, state-derived candidates, null-safe classification, one atomic `state rm`, serial +1 assertion.
- [x] 1.10 `scripts/cf-account-migrate-gate.sh`: per-phase list generating `-target`, pure-import check, derived counts, `plan-gate-preamble.sh`, `gate-suite-harness.sh` suite.
- [x] 1.11 `scripts/cf-account-migration-complete.sh` (call site: last step of `.github/actions/infra-credentials`, CTO L79) and its call sites in every plan-capable job except `cf_account_migrate` (with the `web_host_replace web-2` exception).
- [x] 1.12 (moved to `.github/workflows/cf-account-migrate.yml`, CTO L79) `apply-web-platform-infra.yml` (rehearsal on `infra-privileged`, every apply leg on the reviewer-gated `web-platform-infra-apply`; `$RUNNER_TEMP` with `umask 077`; no `upload-artifact`, no `TF_LOG`; queued-run refusal):
  - `apply_target=cf-account-migrate`, `migrate_phase`, `confirm`;
  - job `cf_account_migrate` (infra-privileged, shared concurrency group, no SSH, no bridge);
  - rehearsal in a scratch root with remote-serial assertion;
  - post-apply curl verification.
- [x] 1.13 `scripts/check-cloudflare-token-drift.sh` repoint; `cf-token-scope.sh` new-account profiles.
- [x] 1.14 `deploy-docs.yml` probe A URL → `soleur-docs-40x.pages.dev`.
- [x] 1.15 ADR-329 (`status: adopting`, via `soleur:architecture`; `amends: [ADR-068, ADR-321]`, related 006/114/143/194/304, with addenda on 068, 321 and 194).
  - `model.c4`: the 7 edits listed in the plan's C4 section.
  - Run `scripts/regenerate-c4-model.sh`.
  - `c4-model-freshness`, `c4-code-syntax`, `c4-render` and `c4-count-parity` all green.
- [x] 1.16 Runbook `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: phases, expected reds, revoke recipe, bootstrap stages, `## Halt` (fix forward; the `_PREV` id restore only before the `redirects-dns` apply; no state push, CTO ruling D4 withdrawing L59), Phase 3 step 6 reopen checks (D5). Text contract: `tests/scripts/test-cf-account-migration-runbook.sh`.
- [x] 1.16b `bootstrap.sh` (this directory, `soleur:operator-bootstrap`, CTO ruling D11) and its suite `tests/scripts/test-cf-account-migration-bootstrap.sh`.
- [ ] 1.17 Register new suites in `run-registered-suites.sh` inputs. Full local battery green. Registered 2026-11-19: `tests/scripts/test-cf-account-migration-bootstrap.sh` (the D11 bootstrap suite; it finds `bootstrap.sh` here by glob, so an archive-kb move breaks nothing) and `tests/scripts/test-cf-account-migration-runbook.sh`.
- [x] 1.18 Registry render delta on the PR1 diff = `deliver=false`. Verified 2026-11-19: the dispatcher gate renders only when `cloud-init-registry.yml` or `zot-registry.tf` changes and otherwise compares `registry_server_type|registry_location|registry_volume_size`; PR1 touches none of them.
- [ ] 1.19 PR body first line: "Merging this alone mutates no production resource". Use `Ref #12931`. The merge commit carries `[skip-web-platform-apply]`.

## Phase 2: Redirect restore (after PR1 merges)

- [ ] 2.1 `Operator-authorizes:` each `bootstrap.sh` stage prompt (D11): `inventory`, `prev-0a`, `flip-ids`, `swap-0a`, `branch-copies-zone-id`. Each stage reads its writes back; `swap-0a` deletes `_NEXT` only after the digest compare. Once 2.3 is verified, revoke the three superseded 0a tokens with the revoke recipe (which deletes their `_PREV` keys).
- [ ] 2.2 `Operator-authorizes:` the `redirects-dns` rehearsal (`rehearsal=true`). Gate `verdict=PASS`, remote serial unchanged. Arm a watch.
- [ ] 2.3 `Operator-authorizes:` the `redirects-dns` apply. Verify: four 301 URLs, `x-robots-tag: noindex` on `app.soleur.ai`, GPTBot 200, four Better Stack redirect monitors `up`.
- [ ] 2.4 Search Console check for indexed `app.soleur.ai` token URLs, and removal requests (operator scope row).
- [ ] 2.5 `Operator-authorizes:` the `prev-0b`, `swap-0b` and `branch-copies-tokens` stages, then `verify` (`SOLEUR_CFAM_VERIFY verdict=ok`); revoke the old DNS-edit token. `Operator-authorizes:` the `zone-rest` rehearsal, then the apply. `gh workflow run deploy-docs.yml --ref main`: probe A and probe B pass.

## Phase 3: PR2 (new branch from main): tunnel and deploy hosts

- [ ] 3.1 PR2 code:
  - `cf-access-deploy-token-mint.sh` and its test;
  - `cf-tunnel-host-predelete.sh` and its test (Guard 5);
  - the `tunnel` phase in the job and the gate (deploy-policy exception: token name, expiry, `non_identity`, a single include, app id, read-only GET);
  - the `app` import enabled;
  - `local.deploy_service_token_ids`.
- [ ] 3.2 `Operator-authorizes:` mint the `CF_API_TOKEN_ACCESS_MINT` token, run the mint script, commit the UUID, revoke the mint token.
- [ ] 3.3 Merge PR2 with `[skip-web-platform-apply]`. `Operator-authorizes:` pre-delete dry-run, then apply; `tunnel` rehearsal, then apply; CI-SSH token sync.
- [ ] 3.4 `Operator-authorizes:` the `web-host-replace web_host_key=web-2` rehearsal, then the run.
- [ ] 3.5 `Operator-authorizes:` Origin CA re-mint from the new zone, before the release redeploy in 3.6.
- [ ] 3.6 Verify:
  - census shows 1 connector;
  - `verify-tunnel-ingress-origin.sh` passes;
  - CI SSH bridge round-trip;
  - registry push canary;
  - `web-platform-release.yml` redeploy.
- [ ] 3.7 Post the D5 checks on #12931 (`git log <PR1-merge-sha>..origin/main -- apps/web-platform/infra`, the latest drift plan summary, the owner's review comment). `Operator-authorizes:` `apply_target=manual-rerun`. Expected: green, with one `cloudflare_ruleset.cache_shared_binaries` create (D3). The merge freeze ends here.

## Phase 4: Close the incident

- [ ] 4.1 With all 9 monitors `up` and the deploy hosts serving, flip the post-mortem `status: resolved`, add recovery timestamps, and mark the #12931 action-item row resolved.

## Phase 5: Cleanup PR

- [ ] 5.1 Delete the imports file, the state-migrate script, the predicate and its call sites, the migration variables, `cf-account-migrate.yml` and its job script, the gate, and `bootstrap.sh` with its suite (and its `run_suite` line). Keep the mint script and the probe profiles.
- [ ] 5.2 `Operator-authorizes:` revoke `CF_API_TOKEN_SOLEUR_ACCT` and the superseded tokens; remove the `_PREV`/`_NEXT` keys.
- [ ] 5.3 `Operator-authorizes:` delete the old tunnel and the other forgotten old-ACCOUNT objects by name (never old-zone objects).
  - Include the old deploy service token `d9204def…`.
  - Revoke the old-zone Origin CA certificate.
  - Delete every version of every `web-platform/backups/pre-cf-account-migration-*` object (D4); post the empty re-list.
- [ ] 5.4 Re-scope the read-only tokens. Update `infra-security.md` and the 8209 runbook literals. Update the expense ledger.
- [ ] 5.5 Set ADR-329 to `accepted`. The PR body carries `Closes #12931`.
- [ ] 5.6 Follow-up issues: DNSSEC re-enable (filed, #12982), LB purchase decision plus the `lb-staging` root (filed, #12983); still to file: the app-level `X-Robots-Tag` fallback.

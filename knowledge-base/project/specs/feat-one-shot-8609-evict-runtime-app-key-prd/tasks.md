# Tasks: evict the soleur-ai runtime App key from branch-reachable Doppler `prd` (#8609)

Plan: `knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md`
(deepened 2026-09-30). PR-A carries `Ref #8609`; PR-B (the ADR-241 D2 flip) carries `Closes #8609`.

## Phase 0: Settle the facts

- [ ] 0.1 Measure `WEB_GZIP_BUDGET` headroom with a synthesized token line (`plugins/soleur/test/cloud-init-user-data-size.test.ts`); if over, move the template's comment lines into `server.tf` prose; if still over, stop and report
- [ ] 0.2 Re-count the Doppler docker-format PEM encoding with CLI v3.75.3 (counts only)
- [ ] 0.3 Confirm `.terraform.lock.hcl` still pins `hetznercloud/hcloud` 1.63.0 (`user_data` stored as a hash)
- [ ] 0.4 Read recent releases' image-verify verdicts; fix any warn-mode tag fallback on `main` releases first
- [ ] 0.5 Confirm the canary container can reach `api.github.com`

## Phase 1: Guards first (RED)

- [ ] 1.1 Guard 6 rows G6a–G6p (incl. G6a2/a3, G6c2, G6l, G6m, G6n, dispatch and harness rows) in `tests/scripts/test-infra-privileged-tier-census.sh`
- [ ] 1.2 Guard 7 rows 7.0–7.15 and 7.p1–7.p4 in `apps/web-platform/infra/ci-deploy.test.sh`: path-rewrite harness, per-project doppler stub with a call log, docker mock recording env, a new boot-site driver
- [ ] 1.3 Guard 8 rows 8.1–8.p in `.github/actions/infra-credentials/infra-credentials.test.sh`
- [ ] 1.4 `cat-deploy-state.test.sh`: `github_app_key_source` / `_fetch` / `_probe` fields
- [ ] 1.5 `web-host-provisioner-parity.test.sh`: web-2 credential denylist still holds

## Phase 2: Terraform, loader, alerts

- [ ] 2.1 Create `apps/web-platform/infra/github-app-runtime-project.tf`: project, `prd` environment, `prd_retired` branch config; `prevent_destroy`; no secrets/tokens/data sources
- [ ] 2.2 Add the new addresses to the push apply's `-target=` list in `apply-web-platform-infra.yml`; sweep every suite asserting that list
- [ ] 2.3 `variables.tf`: `github_app_runtime_doppler_token` (sensitive, default `""`)
- [ ] 2.4 `soleur-doppler-token.tmpl` conditional line + `server.tf` templatefile argument (byte-identical when empty); edit no input of `infra_config_handler_bootstrap`
- [ ] 2.5 Shape-gate local + preconditions on `deploy_pipeline_fix` and `hcloud_server.web`; `local.github_app_key_isolated` (false; PR-B flips)
- [ ] 2.6 Loader: unconditional export, opt-in input `github-app-runtime-token` for the two delivering jobs, pinned Doppler CLI version
- [ ] 2.7 Sentry alert rules for the new boot stages and `op=github-app-key` (`issue-alerts.tf`, `alert-reference.json`)

## Phase 3: Host overlay and canary probe

- [ ] 3.1 `ci-deploy.sh`: `GITHUB_APP_DOPPLER_TOKEN` in the credential-file key allowlist, not exported
- [ ] 3.2 `overlay_github_app_key` in the parent shell: hijack-name denylist, signed-image (`@sha256:` `$VERIFIED_REF`) condition, anchored single-name overlay, no new temp file, `github_app_key_emit` per file, deploy-state fields
- [ ] 3.3 Canary presence check + `github-app-key-probe.mjs` (contract in plan 3.3); Dockerfile copy; register in `canary-probe-set.md`
- [ ] 3.4 Boot path: byte-identical sentinel block; per-outcome `soleur-boot-emit` stages + `logger -t` line
- [ ] 3.5 `cat-deploy-state.sh` fields; release workflow `::warning::` on a failed fetch
- [ ] 3.6 `apps/web-platform/scripts/github-app-key-status.sh` (≤ 30 lines)

## Phase 4: Records (PR-A)

- [ ] 4.1 ADR-241 via `soleur:architecture`: new Amendment log, D10 (incl. signed-image condition and residuals), D10 Statuses row, R1 CLOSING, R8, A11 annotation; D2 stays `proposed`
- [ ] 4.2 Runbook: "Runtime App key (#8609)" R-table (R0–R8 incl. R0c, R5b), "Routine rotation (steady state)", dated notes on O0 U1 and O13(b)
- [ ] 4.3 Operator bootstrap script via `soleur:operator-bootstrap`
- [ ] 4.4 C4 `model.c4` edges; run the three C4 tests
- [ ] 4.5 Legal (through the CLO agent): new exposure assessment, #8209 pointer addendum, breach-register row + note, compliance-posture IN-PROGRESS + evidence-limb row
- [ ] 4.6 File deferral issues (webhook/client secrets; web-host metadata drop); comment the deploy-channel finding on #6129
- [ ] 4.7 `BASELINE_DECLARED_PROBES` +1 with PLACEMENT / TRUTH / NO-SUBSTITUTE comment

## Phase 5: Ship PR-A

- [ ] 5.1 Pre-merge checks (AC14): drift-guard trigger, slug/id, last deploy-pipeline run green, plan shape, no queued infra PR, credential-file digest baseline
- [ ] 5.2 PR body first line: the production mutations the merge triggers (incl. the SSH push to web-2)
- [ ] 5.3 Required checks green by name on the exact head SHA; auto-merge (UNTRUSTED-CI); post-merge checks (runs `success`, digest unchanged, `source=prd probe=ok`)

## Phase 6: Operator sequence (each production step individually authorized)

- [ ] 6.1 R0 key inventory + park old key in `prd_retired`; R0b evidence limbs; R0c cross-project reference probe
- [ ] 6.2 Gate: #8209 O10 and O13's `DOPPLER_TOKEN_TF` rotation done
- [ ] 6.3 R1 → R2 → R3 → R4 → R5 → R5b → R6 → R7 per the runbook table
- [ ] 6.4 R8 after #8209 O13's App-key delete

## Phase 7: PR-B

- [ ] 7.1 ADR-241 D2 and D10 `accepted`, R1 CLOSED; ADR-220 Amendment-log entry (re-read its other limbs)
- [ ] 7.2 Flip `local.github_app_key_isolated = true`
- [ ] 7.3 Runbook, compliance-posture CLOSED, assessment closure addendum, Article-30 markers (through the CLO agent); legal sweep for R1 nouns
- [ ] 7.4 `Closes #8609` in the PR body

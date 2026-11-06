# Tasks — feat-one-shot-11923-11920-rotation-gates

Plan: `knowledge-base/project/plans/2026-11-05-feat-rotation-approval-gate-egress-restart-plan.md`
Issues: #11923 (reviewer-gated approval environment), #11920 (no-SSH vector restart + PREVIOUS doppler_secret)

## Phase 1 — Terraform + test harness (RED first)

- [ ] 1.1 RED: `plugins/soleur/test/terraform-target-parity.test.ts` — add `key_rotate_approval` to `REVIEWERS_RATCHET`; add literal `-target` pins for the new env + policy + PREVIOUS secret; extend the gate-table-vs-HCL derivation so `doppler_secret.egress_audit_ingest_token_previous` (`ignore_changes=[value]`) derives flag `replace`.
- [ ] 1.2 RED: `apps/web-platform/infra/key-rotate-workflow.test.sh` — update TOKENS / PREWRITE_TOKENS (remove `egress_rotate_unsupported_no_vector_restart_lever` + `approval_environment_missing`; add `approval_environment_unprotected` + new egress verdicts); update B35/B35b, C2.12-14, C3.4/b, C3.15b/c; re-derive mutation rows D3.5a/b, D5.1, D5.5c/d, D5.16a/d, D6.11a against the new mechanisms; add new scenario rows (approve job, live env verify, full egress rotate, vector leg, clear apply).
- [ ] 1.3 Create `apps/web-platform/infra/key-rotate-approval-environment.tf` — `github_repository_environment.key_rotate_approval` (reviewers `[54279]`, `custom_branch_policies = true`, `protected_branches = false`) + `github_repository_environment_deployment_policy.key_rotate_approval_main` (`branch_pattern = "main"`, `prevent_destroy`).
- [ ] 1.4 `apps/web-platform/infra/egress-audit.tf` — `doppler_secret.egress_audit_ingest_token_previous` (`project=soleur`, `config=prd`, `visibility = "masked"`, `ignore_changes=[value]`); `variables.tf` — sensitive `egress_audit_ingest_token_previous` (`default = ""`).
- [ ] 1.5 `.github/workflows/apply-web-platform-infra.yml` — three `-target=` rows (env, policy, PREVIOUS secret).
- [ ] 1.6 `terraform validate` on the web-platform root.

## Phase 2 — Workflows

- [ ] 2.1 `key-rotate.yml` — `approve` job (`environment: key-rotate-approval`, `if:` dispatch + `mode == 'rotate'`, emits `approval_epoch`); `apply` needs/if extended; `approval_epoch` consumed by `EFF_GUARD_EPOCH`; vector-restart step in `redeploy` (trio env, `key == egress`); `clear` job (egress, `environment: infra-privileged`, `terraform-apply-web-platform-host` group); timeouts + header narrative.
- [ ] 2.2 `inngest-key-rotate.yml` — same `approve` job before `apply1` (`mode != 'plan'`); `apply1` needs/if extended.

## Phase 3 — Scripts + host handler

- [ ] 3.1 `apps/web-platform/infra/ci-deploy.sh` — `ACTION == "restart"` accepts `vector` (quiesce check stays inngest-only); `sudo /usr/bin/systemctl try-restart vector.service` (exact DROPIN_TRY_RESTART argv); verify `is-active` + `ActiveEnterTimestamp` delta; reasons `vector_restart_failed` / `vector_restart_unverified` / `success`; `fan_out_to_peers` on the vector arm.
- [ ] 3.2 `apps/web-platform/infra/ci-deploy.test.sh` — restart-vector rows (argv lockstep, verify, fan-out, component scoping).
- [ ] 3.3 `scripts/key-rotate.sh` — remove `kk_chk_egress` refusal; `kk_chk_approval` → live `protection_rules` verify (`approval_environment_unprotected`); `KK_APPROVAL_ENV_BOUND=true`; verdict list + `--print-contract`; TF_VAR feed of old CURRENT; `redeploy vector` subcommand (dispatch + per-host deploy-status poll); `clear` subcommand (plan+apply `-replace` PREVIOUS with var default); budget-table entries; headers.
- [ ] 3.4 Run `key-rotate-workflow.test.sh` + `ci-deploy.test.sh` + the `terraform-target-parity.test.ts` shard — all green.

## Phase 4 — Docs, ADR, C4

- [ ] 4.1 Amend `ADR-317-…md` `## Decision` (F2 flip + evidence, G6/H2 env bound + live verify) and `## Consequences` (new failure modes).
- [ ] 4.2 `model.c4` — `founder -> github` environment-approval edge; `views.c4` include line if needed; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] 4.3 `runbooks/key-rotation.md` — approval UX, egress sequence, PREVIOUS lifecycle, vector-restart verification, updated verdict table.
- [ ] 4.4 Post-merge verification (documented in PR body): `gh api repos/jikig-ai/soleur/environments/key-rotate-approval` shows `required_reviewers` + `branch_policy` before first dispatch.

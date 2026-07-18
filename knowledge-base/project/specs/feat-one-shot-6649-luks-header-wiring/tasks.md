---
feature: feat-one-shot-6649-luks-header-wiring
issue: 6649
epic: 6604
plan: knowledge-base/project/plans/2026-07-18-fix-6649-workspaces-luks-header-escrow-wiring-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — /workspaces LUKS header-escrow wiring (#6649)

Derived from the finalized (deepen-plan reviewed) plan. `Ref #6649` (close post-mint, NOT `Closes`).
Do NOT touch/close #6604.

## Phase 0 — Preflight / verification (blocking)
- [x] 0.1 Live-probe whether `cf_api_token` (in `prd_terraform`) has R2 (Workers R2 Storage:Edit) scope — scoped `terraform plan -target='cloudflare_r2_bucket.workspaces_luks_header'` on a throwaway branch OR a CF token-verify/permission-groups read. Record the finding. (Do NOT assert scope from the var description — `hr-verify-repo-capability-claim-before-assert`.)
- [x] 0.2 Confirm (learning `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md`) that R2 S3 creds are a dashboard-minted R2 API Token, NOT `sha256(cloudflare_api_token.value)`.
- [x] 0.3 Confirm `aws` CLI absence on web-1 (cloud-init + `soleur-host-bootstrap.sh` show no install); web-1 is `ignore_changes=[user_data]` + unrebuildable, so the live on-demand install is the real delivery.
- [x] 0.4 Confirm the `prd_workspaces_luks` Doppler config exists (merge precondition).

## Phase 1 — Terraform (IaC)
- [x] 1.1 Create `apps/web-platform/infra/workspaces-luks-header.tf` (SEPARATE from `workspaces-luks.tf` — A11 file-cardinality):
  - `cloudflare_r2_bucket.workspaces_luks_header` (`account_id=var.cf_account_id`, `name="soleur-workspaces-luks-header"`, `location="WEUR"`, `prevent_destroy`).
  - `local.r2_s3_endpoint = "https://${var.cf_account_id}.r2.cloudflarestorage.com"` (derive; no hardcoded literal).
  - `doppler_secret.workspaces_luks_header_bucket` (config `prd_workspaces_luks`, name `WORKSPACES_HEADER_BUCKET`, value = `cloudflare_r2_bucket.workspaces_luks_header.name` reference, masked).
  - `doppler_secret.workspaces_luks_header_r2_endpoint` (name `WORKSPACES_HEADER_R2_ENDPOINT`, value = `local.r2_s3_endpoint`, masked).
- [x] 1.2 (Conditional on 0.1) `main.tf`: `provider "cloudflare" { alias = "r2"  api_token = var.cf_api_token_r2 }`; `variables.tf`: no-default sensitive `var.cf_api_token_r2` (Workers R2 Storage:Edit only). Point the bucket + data source at `provider = cloudflare.r2`.
- [x] 1.3 `.github/workflows/apply-web-platform-infra.yml`: append the 3 new managed-resource `-target=` lines to the DEFAULT allow-list (near :361, beside `github_repository_environment.workspaces_luks_cutover`). Do NOT add to `apply_target=workspaces-luks-cutover`.
- [x] 1.4 `terraform validate` (v4 attribute names, mirrors cla-evidence bucket shape).

## Phase 2 — Host-side script (`apps/web-platform/infra/workspaces-cutover.sh`)
- [x] 2.1 Add 4 pinned host-side reads (`doppler secrets get <NAME> --plain --config prd_workspaces_luks`) for `WORKSPACES_HEADER_BUCKET`, `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`, `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY`, `WORKSPACES_HEADER_R2_ENDPOINT`. Reads + `aws` preflight are HOISTED ABOVE the `if [ "$DRY_RUN" != "1" ]` gate (:173) so the dry-run probe has creds. Never argv, never `doppler run`/`download`.
- [x] 2.2 Per-field fail-loud: each read `[ -n ]`-checked → `emit_drift header_creds_unreadable; die` (read_key's `|| true` swallows failures).
- [x] 2.3 In the escrow block: export `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`; set `AWS_DEFAULT_REGION=auto` + `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` + `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`; add `--endpoint-url "$WORKSPACES_HEADER_R2_ENDPOINT"` to BOTH `aws s3 cp` (:196) and `aws s3api head-object` (:198).
- [x] 2.4 `aws` CLI: SHA256-pinned live on-demand install (idempotent, breadcrumb) + `command -v aws` preflight (`emit_drift aws_cli_absent; die`). Add cloud-init install labelled future-host-only.
- [x] 2.5 Update stale die text at :197/:199 (creds now host-side, not workflow env).
- [x] 2.6 Header temp file: mode-0700 dir under `$STATE_DIR` (not shared `/tmp`).
- [x] 2.7 Add DRY_RUN-safe probe-PUT (write→read-back→delete of `.probe/<run-id>`) + NEGATIVE probe (escrow creds DENIED 403 vs `soleur-terraform-state` → else emit_drift+die), both in the dry-run arm.

## Phase 3 — Wiring test
- [x] 3.1 Extend `apps/web-platform/infra/workspaces-luks.test.sh` (or new `workspaces-luks-header.test.sh` registered in `infra-validation.yml`), mirroring `git-data-luks.test.sh` (reads .tf + .sh), mutation-tested:
  - (a) bucket exists, `name=` literal `soleur-workspaces-luks-header` ≠ `soleur-terraform-state`; `WORKSPACES_HEADER_BUCKET.value` is a reference expression, not a literal.
  - (b) escrow-file addition-blind guard: END-ANCHORED `config = "prd"` regex (or false-matches `prd_workspaces_luks`); masked; pin cardinality.
  - (c) script reads bucket + all 3 R2 creds via `doppler secrets get … --config prd_workspaces_luks`.
  - (d) creds never on the `sudo … bash -s` argv; workflow env never carries them.
  - (e) no `doppler run`/`secrets download` for escrow reads.
  - (f) probe NOT lexically inside the `DRY_RUN != 1` block (mutation → RED).
- [x] 3.2 Pre-merge fail-loud harness: source the escrow function with stubbed `aws`/`doppler`; assert empty-cred path exits non-zero + `emit_drift` (makes Test Scenario 6 verifiable at PR time).

## Phase 4 — ADR/C4 + registration sweep
- [x] 4.1 ADR-119 addendum (distinct bucket-scoped R2 token; never reuse tfstate token; residuals: passphrase-in-tfstate, host-token-reads-all-prd #6167, API-delete vs prevent_destroy, C4-doesn't-encode-distinctness).
- [x] 4.2 `model.c4`: add `hetzner → cloudflare` header-escrow edge; amend `doppler → hetzner` desc. `views.c4`: include it. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 4.3 Guard-suite sweep: `terraform-target-parity.test.ts` passes; no destroy-guard scope guard reddens (`2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`).

## Phase 5 — Verify & ship
- [x] 5.1 `terraform validate` clean; infra tests + c4 tests + `terraform-target-parity.test.ts` green.
- [x] 5.2 PR body: `Ref #6649` (NOT Closes); "Part of #6604" (never Closes #6604). Split AC into Pre-merge / Post-merge (operator).

## Post-merge (operator — automation-status UNVERIFIED, /work attempts Playwright first)
- [ ] P.1 (Pre-merge if 0.1 shows no R2 scope) Provision `CF_API_TOKEN_R2` (R2:Edit) into Doppler `prd_terraform` BEFORE merge (ADR-065 — else whole merge-apply bricks).
- [ ] P.2 Confirm merge-apply GREEN (bucket + secrets) before minting creds.
- [ ] P.3 Mint R2 API Token (Object R&W, scoped to `soleur-workspaces-luks-header`); provision `WORKSPACES_HEADER_R2_ACCESS_KEY_ID` + `_SECRET_ACCESS_KEY` (masked) into `prd_workspaces_luks`.
- [ ] P.4 Post-provision assertion: R2 secret present in `prd_workspaces_luks`, ABSENT from `prd` root.
- [ ] P.5 `dry_run=true` dispatch: probe-PUT GREEN + negative probe GREEN → then `gh issue close #6649`.
- [ ] P.6 (residual) Author R2-token revoke/rotate runbook.

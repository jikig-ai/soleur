---
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md
closes: 4150
---

# Tasks — fix(infra) apply-web-platform-infra tf-autonomy (#4150)

## Phase 0 — Preconditions

- [ ] 0.1 Verify `prd_kb_drift_walker` Doppler config exists (`doppler configs --project soleur --json | jq ...`).
- [ ] 0.2 Verify soleur-ai App is installed on jikig-ai with `administration:write` + `secrets:write`; confirm installation_id `122213433`.
- [ ] 0.3 Smoke test plan: `DOPPLER_TOKEN_TF` workplace token has scope to mint config-scoped service tokens — defer verification to Phase 3.
- [ ] 0.4 Re-grep `apps/web-platform/{app,lib,server,src}/` for `GITHUB_APP_CLIENT_ID|GITHUB_APP_CLIENT_SECRET` → must be empty.

## Phase 1 — Terraform code edits

- [ ] 1.1 `apps/web-platform/infra/variables.tf`: delete the 4 variable blocks (lines 168-190). Update PR-H header comment.
- [ ] 1.2 `apps/web-platform/infra/main.tf`: rewrite `provider "github"` block to `app_auth { id, installation_id = "122213433", pem_file }`.
- [ ] 1.3 `apps/web-platform/infra/github-app.tf`: delete `doppler_secret.github_app_client_id` + `..._client_secret` (lines 51-73). Update header.
- [ ] 1.4 `apps/web-platform/infra/kb-drift.tf`: add `resource "doppler_service_token" "kb_drift"` block; rewire `github_actions_secret.doppler_token_kb_drift.plaintext_value = doppler_service_token.kb_drift.key`; remove `lifecycle.ignore_changes` on the secret.
- [ ] 1.5 `.github/workflows/apply-web-platform-infra.yml`: drop 2 `-target=` lines; add `-target=doppler_service_token.kb_drift` to both plan + apply steps.
- [ ] 1.6 `knowledge-base/operations/runbooks/github-app-provisioning.md`: remove `TF_VAR_github_app_client_*` references; document App-auth migration.

## Phase 2 — Doppler secret mirror (read+write, idempotent)

- [ ] 2.1 Mirror `GITHUB_APP_ID` from `prd` to `prd_terraform`.
- [ ] 2.2 Mirror `GITHUB_APP_PRIVATE_KEY` from `prd` to `prd_terraform`.
- [ ] 2.3 Delete `GITHUB_APP_CLIENT_ID` orphan from `prd_terraform` (+ delete any pre-existing `GITHUB_APP_CLIENT_SECRET`, `GITHUB_ACTIONS_TOKEN`, `DOPPLER_TOKEN_KB_DRIFT` if present).
- [ ] 2.4 Verify removal: `doppler secrets -p soleur -c prd_terraform --only-names` does not list the deleted keys.

## Phase 3 — Local terraform plan smoke test

- [ ] 3.1 `cd apps/web-platform/infra && terraform init && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`.
- [ ] 3.2 Diagnose any failures using Phase 3.2 of the plan; iterate.

## Phase 4 — Rule + learning

- [ ] 4.1 Add `hr-tf-variable-no-operator-mint-default` rule to `AGENTS.core.md` (body ≤ 600 bytes per `cq-agents-md-tier-gate`).
- [ ] 4.2 Add pointer line to `AGENTS.md` under `## Hard Rules`.
- [ ] 4.3 Lint: `python3 scripts/lint-rule-ids.py && python3 scripts/lint-agents-rule-budget.py`.
- [ ] 4.4 Write `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md` with YAML frontmatter and 5 body sections per plan.

## Phase 5 — Open PR

- [ ] 5.1 Verify all pre-merge ACs (1-10 in plan §"Acceptance Criteria").
- [ ] 5.2 Push branch, open PR with body containing `Closes #4150` + test plan.
- [ ] 5.3 Wait for review; address feedback inline.

## Phase 6 — Post-merge verification

- [ ] 6.1 `gh run list --workflow=apply-web-platform-infra.yml --branch=main --limit 1 --json conclusion` → `success`.
- [ ] 6.2 `gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_KB_DRIFT --jq '.updated_at'` returns post-merge timestamp.
- [ ] 6.3 `doppler secrets get GITHUB_APP_CLIENT_ID -p soleur -c prd_terraform --plain` returns NotFound.
- [ ] 6.4 Environment protection unchanged (deruelle reviewer + main branch policy).
- [ ] 6.5 No new Sentry events for `apply-web-platform-infra` in 30 min post-merge.

---
lane: cross-domain
issue: 4144
plan: knowledge-base/project/plans/2026-05-20-fix-4144-tf-github-provider-pat-to-app-auth-plan.md
---

# Tasks — fix(infra): migrate TF `integrations/github` provider from PAT to App auth (#4144)

## Phase 0 — Preconditions and discovery

- [ ] 0.1 CWD verification (`pwd` equals worktree path)
- [ ] 0.2 Confirm `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` exist in Doppler `prd`
- [ ] 0.3 Read `apps/web-platform/infra/inngest.tf` for the sudoers-entry resource name + on-disk filename (needed for AC15)
- [ ] 0.4 Baseline budget: `python3 scripts/lint-agents-rule-budget.py` (expect 21962/22000)
- [ ] 0.5 Read `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.x structure

## Phase 1 — Discovery script (TDD)

- [ ] 1.1 Write `apps/web-platform/infra/scripts/get-app-installation-id.test.sh` smoke test (RED)
- [ ] 1.2 Implement `apps/web-platform/infra/scripts/get-app-installation-id.sh` (RS256 JWT mint + `/orgs/jikig-ai/installation`)
- [ ] 1.3 Run against live Doppler; capture numeric installation ID

## Phase 2 — Doppler population

- [ ] 2.1 `doppler secrets set GITHUB_APP_INSTALLATION_ID=<value> -p soleur -c prd_terraform`
- [ ] 2.2 Re-verify presence of `GITHUB_APP_CLIENT_SECRET` + `DOPPLER_TOKEN_KB_DRIFT` in `prd_terraform`

## Phase 3 — Terraform provider migration

- [ ] 3.1 RED: `terraform validate` without the new var → confirm required-var error on `github_actions_token`
- [ ] 3.2 Edit `apps/web-platform/infra/main.tf` provider block to `app_auth { id, installation_id, pem_file }`
- [ ] 3.3 Edit `apps/web-platform/infra/variables.tf` — delete `var.github_actions_token`; add `var.github_app_installation_id`
- [ ] 3.4 Edit `apps/web-platform/infra/kb-drift.tf` comment to reference App-auth path
- [ ] 3.5 GREEN: `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform validate` passes; `terraform plan -target=github_actions_secret.doppler_token_kb_drift` is no-op

## Phase 4 — AGENTS.md rule + index pointer (REVISED post-deepen)

- [ ] 4.1 Confirm baseline budget (38B headroom)
- [ ] 4.2 Trim (revised): body-trim one verbose hr-* rule in `AGENTS.core.md` for ≥400B savings (NOT the originally-proposed core→rest demotion of `wg-block-pr-ready-on-undeferred-operator-steps` — rejected on loader-class-fit grounds for docs-only `/ship` PRs)
- [ ] 4.3 Add `[hr-github-app-auth-not-pat]` rule body to `AGENTS.core.md` under "## Hard Rules" — tight single-line form ≤350B
- [ ] 4.4 Add `[id: hr-github-app-auth-not-pat] → core` pointer to `AGENTS.md`
- [ ] 4.5 Re-run `python3 scripts/lint-agents-rule-budget.py` → `B_ALWAYS < 22000` (≥50B headroom); iterate trim if budget exceeds

## Phase 4.5 — Sudoers entry for inngest-bootstrap (FOLD-IN)

- [ ] 4.5.1 Add `/etc/sudoers.d/deploy-inngest-bootstrap` write_files entry to `apps/web-platform/infra/cloud-init.yml` (`0440 root:root`, command-scoped NOPASSWD)
- [ ] 4.5.2 Add `provisioner "file"` + `provisioner "remote-exec"` (visudo -cf) blocks to `terraform_data.deploy_pipeline_fix` in `apps/web-platform/infra/server.tf`; extend `triggers_replace`
- [ ] 4.5.3 Add the new sudoers source file to `.github/workflows/apply-deploy-pipeline-fix.yml` `paths:` filter and `Capture local hashes` step

## Phase 4.6 — Runbook drift fix

- [ ] 4.6.1 Replace `TF_VAR_github_actions_token` references at `knowledge-base/operations/runbooks/github-app-provisioning.md:64,110` with `TF_VAR_github_app_installation_id` + a one-line note that App-auth eliminated the PAT step

## Phase 5 — Deepen-plan Phase 4.8 gate

- [ ] 5.1 Probe synthetic plan fixture against the new halt (manual)
- [ ] 5.2 Add `### 4.8. PAT-Shaped Variable Halt (Always)` to `plugins/soleur/skills/deepen-plan/SKILL.md`

## Phase 6 — Commit and PR

- [ ] 6.1 Commit (`Ref #4144` in body, NOT `Closes #4144`)
- [ ] 6.2 PR body includes post-merge operator checklist (AC12-AC19) with per-step automation form

## Phase 7 — Post-merge cascade

- [ ] 7.1 AC12 — Doppler `prd_terraform.GITHUB_APP_INSTALLATION_ID` set
- [ ] 7.2 AC13 — App permission probe (`secrets: write`); if missing, surface install-URL
- [ ] 7.3 AC14 — `gh workflow run apply-deploy-pipeline-fix.yml --ref main` green
- [ ] 7.4 AC15 — read-only SSH: `/etc/sudoers.d/deploy-inngest-bootstrap` exists
- [ ] 7.5 AC16 — re-fire v1.0.1 deploy webhook; `exit_code=0`
- [ ] 7.6 AC17 — read-only SSH: `systemctl is-active inngest-heartbeat.service` → `active`
- [ ] 7.7 AC18 — Better Stack PATCH unpause + verify `status=up` within 90s (LAST step)
- [ ] 7.8 AC19 — close #4144 + #4132 with PR cross-reference

## Phase 8 — Compound learning

- [ ] 8.1 Write `knowledge-base/project/learnings/bug-fixes/<topic>.md` — root-cause + generalization (App-auth vs PAT for infra-time GitHub writes); author picks date at write-time

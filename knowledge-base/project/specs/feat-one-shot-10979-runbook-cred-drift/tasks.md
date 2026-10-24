# Tasks — feat-one-shot-10979-runbook-cred-drift

Plan: `knowledge-base/project/plans/2026-10-24-docs-terraform-apply-runbooks-cred-drift-plan.md`
Issue: #10979 (docs-only; no product code, no workflow edits)

## Phase 1 — Canonical reference leg

- [ ] 1.1 `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` §Local Terraform invocation (after ~L916): add a paragraph stating the nested loaders inject `TF_VAR_*` only; the S3 backend reads bare `AWS_*` from ambient env, so a state-WRITING invocation must first export `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd`; the `prd_terraform` pair suffices for read-only commands. (AC-6)

## Phase 2 — Runbook recipe fixes

- [ ] 2.1 `inngest-server.md` Cutover step 0 (~L2455): replace the two `export AWS_*=…prd_terraform…` lines with the canonical recipe (Tier-B `AWS_*` export + nested loader with inner `--preserve-env` for the apply; `terraform init` reads ambient `AWS_*`). Add the one-line why (post-O5b the pair is read-only; PUTs 403). Keep `init` and the `INNGEST_REDIS_PASSWORD` verification lines unchanged. (AC-2, AC-1)
- [ ] 2.2 `grok-build-hetzner-dogfood.md` (~L40-64): rewrite the operator-local apply block to the canonical wrapped-loader form + Tier-B `AWS_*` export (keep `env TF_VAR_enable_grok_dogfood=true` inner and both `-target` sets); reword the caveat note so it explains the form and keeps the §Local Terraform invocation pointer (no longer calls the block "the PRE-cutover one"). (AC-3)
- [ ] 2.3 `inngest-config-refresh.md` step 3 (~L73): name `INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform` explicitly; note the tf-var transformer surfaces it as `TF_VAR_inngest_config_digest` and a literal `TF_VAR_inngest_config_digest` secret lands as `TF_VAR_tf_var_inngest_config_digest` (undeclared-var noise — the observed mis-set); add the state-write credential pointer for the manual apply. (AC-4)
- [ ] 2.4 `inngest-luks-cutover-6894.md` at the `tf()` wrapper (~L457): annotate that ambient `AWS_*` feeds the backend and, for step 5's `tf state push` (a write), must be the Tier-B read/write pair per §Local Terraform invocation; note the Route-B `state pull` (~L509) via `--only-secrets` is a read for which the `prd_terraform` pair is correct. (AC-5)

## Phase 3 — Learnings supersession notes

- [ ] 3.1 `learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — add `> **Superseded in part (2026-10-24, #10979):**` note at the "canonical invocation triplet" block: still correct for read-only invocations; for writes `AWS_*` sources from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd` (O5b/ADR-241). (AC-7)
- [ ] 3.2 `learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md` — same note at its recipe block. (AC-7)
- [ ] 3.3 `learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — same note on the :93 "Canonical pattern" bullet. (AC-7)
- [ ] 3.4 `learnings/workflow-patterns/2026-07-07-agent-runs-terraform-apply-never-route-to-operator.md` — same note at its cred-pattern block. (AC-7)

## Phase 4 — Verification

- [ ] 4.1 `git grep 'secrets get AWS_ACCESS_KEY_ID' -- 'knowledge-base/engineering/operations/runbooks/'` → zero hits. (AC-1)
- [ ] 4.2 `git grep -c 'Superseded in part (2026-10-24, #10979)' -- knowledge-base/project/learnings/` → ≥4 hits. (AC-7)
- [ ] 4.3 `git diff --name-only origin/main...HEAD` — only `*.md` under `knowledge-base/`. (AC-8)
- [ ] 4.4 Read-back pass: each edited block prescribes `AWS_*` from `soleur-infra-privileged/prd` `TF_STATE_AWS_*` (not `prd_terraform` `AWS_*`) wherever a state write is possible; read-only invocations left on `prd_terraform`. (AC-2/3/5/6)

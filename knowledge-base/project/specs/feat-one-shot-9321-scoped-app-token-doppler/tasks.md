# Tasks: scoped Doppler source for the two App-token release jobs (PR-1 of 2)

Plan: `knowledge-base/project/plans/2026-10-01-security-scoped-doppler-source-for-app-token-release-jobs-plan.md`
Issue: #9321 (PR-1 uses `Ref #9321`; PR-2 closes it). Scope of THIS PR: tasks 1 to 5 only.

Standing constraints: no production writes by the pipeline (no apply, no Doppler write, no token mint, no dispatch of an infra/release workflow); the PR is not merged by the pipeline; do not touch the composite, the two release workflows, the two release test suites, `cla.yml`, any legal document or GHCR; mention no issue other than #9321 and #9320 in commits and PR text.

## 1. Terraform container (dormant)

- 1.1 Create `apps/web-platform/infra/infra-app-project.tf` (`doppler_project.infra_app`, `doppler_environment.infra_app_prd`, both `prevent_destroy`, description under 255 characters, header explaining why no secret/token resource may be added). Mirror `github-app-runtime-project.tf`.
- 1.2 Add `-target=doppler_project.infra_app` and `-target=doppler_environment.infra_app_prd` to the push `apply` job's allow-list in `.github/workflows/apply-web-platform-infra.yml` (no `#` comment lines inside the list).
- 1.3 Run `python3 scripts/lint-doppler-description-length.py`, `plugins/soleur/test/workflow-file-size.test.ts`, `plugins/soleur/test/terraform-target-parity.test.ts`.

## 2. Census Guard 7 (write the mutation rows BEFORE the guard)

- 2.1 Add `DOPPLER_TOKEN_INFRA_APP` to `ENV_SECRETS` in `tests/scripts/test-infra-privileged-tier-census.sh`.
- 2.2 Write mutation fixtures M1, M2, M3, M3a, M4, M5, M6 and harness rows H1/H2 (see the plan's Guard Contract); measure each RED.
- 2.3 Implement G7c and G7d (PR-1 half; the target-list check is the existing terraform-target-parity test); bump `CENSUS_ROWS`; add the empty-tree dispatch self-test.

## 3. Bootstrap script (via `soleur:operator-bootstrap`)

- 3.1 Generate `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` from the template; bake the library path.
- 3.2 Stages: preflight (read-only), copy two values (write, go-ahead), prove the copy is the live App (read-only), mint plus prove reach plus store with `--env infra-privileged` (write, go-ahead), final verification and `SOLEUR_BOOTSTRAP_READY_FOR_PR2`; `--rotate-token`.
- 3.2a Record the token slug in the ledger before the store step; "refused" reads must match a recognised access-denied answer (else INCONCLUSIVE); check repository- and org-level secret lists; `READY` means stored-and-scoped, not working.
- 3.3 Never use the library's repository-level secret helper; never echo a value; stdin pipes only.
- 3.4 Run the skill's two verification runs (no TTY): neither performs a write; check the ledger `total_stages`. Run `scripts/lint-shell-trace-credential-refusal.py`.
- 3.5 Confirm the script's `.env` and ledger paths are covered by `.gitignore`.

## 4. ADR, runbook, C4

- 4.1 ADR-241: add D11, an Amendment-log entry, a Statuses row (`adopting`).
- 4.2 Runbook `infra-credential-tiers-8209.md`: new section "Release-job App source (#9321)" (order table, script pointer, verification reads, rotation line for BOTH copies, rollback).
- 4.3 (moved to PR-2) C4 edge edit, regeneration and the dated marker on the 2026-09-30 amendment.
- 4.4 Run `python3 scripts/lint-infra-no-human-steps.py` on every changed markdown file.

## 5. PR hygiene

- 5.1 PR body: `Ref #9321`, the auto-apply statement with the plan's evidence, the order table; no `#N` other than 9321 and 9320; no `[skip-web-platform-apply]` line.
- 5.2 `git diff --stat origin/main...HEAD` shows none of the files the plan marks "Explicitly NOT touched".
- 5.3 CI green (CI is the test gate). Do not merge, do not queue auto-merge.

## PR-2 (separate branch, only after the script printed `SOLEUR_BOOTSTRAP_READY_FOR_PR2`; NOT part of this PR)

- 6.1 Composite argv, error strings and descriptions -> `--project soleur-infra-app --config prd`.
- 6.2 Both release workflows: secret `DOPPLER_TOKEN_INFRA_APP`, step name `Verify DOPPLER_TOKEN_INFRA_APP present`, env, error text, `with`.
- 6.3 Both test suites (exact-step pins S17/S18/S24, mutation rows, argv pin, project mutation).
- 6.4 Census G7d PR-2 half (run the WHOLE census: the first job naming the new secret joins the Tier-B population for G1b/c/d/f/g/h); docs (ADR-232 marker, ADR-241 D11 status, runbook Group-4 and O4c rows, inngest-server.md recovery row, C4 edge).
- 6.5 Run the dispatch from #9320's O4c row after PR-2 merges. `Closes #9321`.

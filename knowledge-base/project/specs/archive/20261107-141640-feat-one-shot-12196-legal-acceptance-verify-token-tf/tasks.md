# Tasks: legal-acceptance verify token secrets (#12196)

Plan: `knowledge-base/project/plans/2026-11-07-chore-legal-acceptance-verify-token-secrets-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12196-legal-acceptance-verify-token-tf/decision-challenges.md`

## Phase 1: Setup and RED

- 1.1 Add the `describe` "the minted token (legal-acceptance-secrets.tf) against the route bound" to `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts` (Test Scenarios 1 to 6 in the plan).
- 1.2 Run it file-selected (`cd apps/web-platform && npx vitest run test/legal-acceptance/cross-layer-limits.test.ts`); it must fail on "extraction found nothing" because the `.tf` does not exist yet.

## Phase 2: Core implementation

- 2.1 Create `apps/web-platform/infra/legal-acceptance-secrets.tf`: header (R6 disclosure), `random_password.legal_acceptance_verify_token_{prd,dev}` (`length = 48`, `special = false` explicit), `doppler_secret.legal_acceptance_verify_token_{prd,dev}` (project `soleur`, config `prd`/`dev`, name `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, masked, value from own generator, no `lifecycle`).
- 2.2 `terraform fmt -check`; `terraform init -backend=false`; `terraform validate` in `apps/web-platform/infra`.
- 2.3 Insert the four `-target=` lines after `-target=doppler_secret.egress_audit_ingest_token_previous` in the plan step of `.github/workflows/apply-web-platform-infra.yml`; no comment prose inside the list.
- 2.4 Re-run the vitest file: green. Drive each Guard 1 mutation row red once on a scratch copy and discard it.

## Phase 3: Docs

- 3.1 `apps/web-platform/server/legal-acceptance/README.md`: replace "to be minted at 48 characters by #12196" with the as-minted statement.
- 3.2 ADR-320 scope note: file landed under #12196; decision-4 review applied; ADR stays `proposed`.
- 3.3 ADR-319 PR-D section: dated "token now minted" line (four-field bound, Tier-A state consequence, no widening).
- 3.4 `python3 scripts/lint-infra-no-human-steps.py` on the edited files.

## Phase 4: Verification (file-selected only)

- 4.1 `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- 4.2 `bash tests/scripts/test-git-data-wipe-wedge.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 4.3 The c4 syntax/render suites and `python3 scripts/lint-encryption-posture.py` only if the selection in 4.4 names them (no `.c4` or ledger edit).
- 4.4 `bash scripts/test-all.sh --print-selection` once; run only what it selects plus the named files above. No full battery.

## Phase 5: Tracking and ship

- 5.1 File one tracking issue for the `verify-migrations` skip on the deploy arm (what, why, re-evaluation criterion, roadmap milestone).
- 5.2 Names-only Doppler re-check of `soleur/dev` and `soleur/prd` (no values) for `LEGAL_ACCEPTANCE_VERIFY_TOKEN` (must be absent) and `LEGAL_ACCEPTANCE_FOUNDER_ID` (report whether present).
- 5.3 Commit with `LEFTHOOK_EXCLUDE=bun-test`; push only after ship's `prepush-secret-scan.sh`; mark draft PR #12307 ready (`Ref #12196`, `Ref #12011`, never `Closes`).
- 5.4 Evaluate the stop rule (literal intersection plus baseline-header diff) on the PR sticky plan comment at the current PR head SHA and on the last main run; re-run it and the Doppler names-only check immediately before merging, with no apply run in flight on `main`; never `gh pr merge --auto`; any deviation or an absent or truncated comment: return the PR to draft, do not merge, report to the operator.
- 5.5 Merge when clean; read the merge-run log for `Plan: 4 to add, 0 to change, 0 to destroy.` and `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.`; boolean-only read that the two values differ and match `^[A-Za-z0-9]{48}$`; post the results as a comment on #12196 (it stays open); report the dark probe status (503 while the founder id is unset), that the merge also triggered the standard web release and deploy, the detective-only residual, and the open `verify-migrations` item.

## Operator-owned (not done by this change)

Enter the founder uuid per project, redeploy the web app, flip the `approval-queue` flag.

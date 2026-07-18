# Tasks — Provision the workspaces-luks-cutover GitHub environment gate

Plan: `knowledge-base/project/plans/2026-07-17-fix-workspaces-luks-cutover-env-gate-plan.md`
Issue: Ref #6604 (do NOT close). Threshold: single-user incident.
Lane: cross-domain.

## Phase 1 — Declare the environment resource (TDD RED anchor)

- [ ] 1.1 Append `resource "github_repository_environment" "workspaces_luks_cutover"`
  to `apps/web-platform/infra/workspaces-luks.tf`, modeled verbatim on
  `github_repository_environment.inngest_cutover` (`inngest-arm-write-token.tf:70-77`):
  `repository = "soleur"`, `environment = "workspaces-luks-cutover"`,
  `reviewers { users = [54279] }`, with the header comment from the plan.
- [ ] 1.2 (RED confirm) Run `terraform-target-parity.test.ts` — expect the
  "every managed resource has a -target line" test RED, listing
  `github_repository_environment.workspaces_luks_cutover` as uncovered.

## Phase 2 — Wire the default-allow-list `-target` (GREEN)

- [ ] 2.1 In `.github/workflows/apply-web-platform-infra.yml`, add
  `-target=github_repository_environment.workspaces_luks_cutover \`
  immediately after line 360 (`-target=github_repository_environment.inngest_cutover \`),
  inside the DEFAULT (push/`manual-rerun`) allow-list block.
- [ ] 2.2 (GREEN confirm) Re-run `terraform-target-parity.test.ts` — the coverage test
  passes.
- [ ] 2.3 Confirm the env `-target` is ABSENT from the scoped `workspaces_luks_cutover`
  job (lines 2448–2600); that job still `-target`s exactly the five workspaces_luks
  resources.
- [ ] 2.4 Run `tests/scripts/test-workspaces-luks-cutover-gate.sh` — T1 PASS + T8 ABORT
  unchanged.

## Phase 3 — Correct the runbook precondition

- [ ] 3.1 In `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
  (lines 19–21), replace the "operator precondition" framing of the environment with the
  Terraform-provisioned framing (provisioned by the default allow-list apply; reviewer
  set must remain non-empty; verify via `gh api`), per the plan's Phase 3 snippet.
- [ ] 3.2 Keep the `prd_workspaces_luks` Doppler-config bullet (lines 17–18) as a
  genuine operator precondition (unchanged).

## Phase 4 — Verification

- [ ] 4.1 `terraform plan` (via `doppler run -p soleur -c prd_terraform
  --name-transformer tf-var -- terraform plan`) shows exactly one added
  `github_repository_environment.workspaces_luks_cutover` `+create` with non-empty
  `reviewers.users = [54279]`, and no other unexpected create.
- [ ] 4.2 Typecheck/tests as applicable for `plugins/soleur/test/*` (bun/vitest per
  `package.json scripts.test`).
- [ ] 4.3 PR body uses `Ref #6604` (NOT `Closes`). No cutover/freeze workflow dispatched.

## Phase 5 — Post-merge (automated)

- [ ] 5.1 Merge-triggered default apply creates the environment (no operator step).
- [ ] 5.2 Verify `gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover`
  returns 200 with a non-empty required-reviewer set (rides `/soleur:ship` post-merge).

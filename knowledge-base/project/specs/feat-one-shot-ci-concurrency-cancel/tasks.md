# Tasks: ci(workflows) cancel-in-progress for uncovered PR workflows

Plan: `knowledge-base/project/plans/2026-09-25-feat-ci-concurrency-cancel-plan.md`
PR: #8891 (draft) · Branch: `feat-one-shot-ci-concurrency-cancel`

The block added everywhere below is byte-for-byte the ADR-217 convention
(ledger test A6 rejects any divergence):

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

## Phase 1: Constraint-gates (template + both emitted copies — ONE commit)

- [ ] 1.1 Add the block to `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template` (top level, between `permissions:` and `jobs:`)
- [ ] 1.2 Add the identical block to `apps/web-platform/.github/workflows/constraint-gates.yml` (emitted copy — parity row 3, byte-identical modulo `__TARGET_DIR__`)
- [ ] 1.3 Add the identical block to `.github/workflows/constraint-gates.yml` (repo-root dogfood — parity row 4 compares comment-stripped bodies)
- [ ] 1.4 Verify: `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` exits 0

## Phase 2: Infra-validation

- [ ] 2.1 Add the identical block at top level of `.github/workflows/infra-validation.yml` (between `permissions:` and `jobs:`)
- [ ] 2.2 Verify the job-level `concurrency: group: terraform-plan-…-${{ matrix.directory }}` (~line 2177) is unchanged
- [ ] 2.3 Verify `on:` triggers unchanged: `push.branches=[main]` + `pull_request.paths` (no `merge_group` exists — do not add one)

## Phase 3: Ledger + guards

- [ ] 3.1 `scripts/pr-fanout-ledger.txt`: flip `constraint-gates.yml` row `cancel` no→yes; replace the `no cancel: the template carries no concurrency block…` tail with the new standing reason (see plan §Proposed Change 3)
- [ ] 3.2 `scripts/pr-fanout-ledger.txt`: flip `infra-validation.yml` row `cancel` no→yes; replace `no cancel: the plan job's per-PR group carries no cancel-in-progress…` with the new standing reason
- [ ] 3.3 Verify: `bash plugins/soleur/test/pr-fanout-ledger.test.sh` exits 0
- [ ] 3.4 Sanity: `git diff origin/main -- .github/workflows/` touches ONLY `constraint-gates.yml` + `infra-validation.yml` (AC5 exclusion list empty diff)

## Phase 4: Ship

- [ ] 4.1 Dogfood check on this branch: confirm a superseded `constraint-gates` run concluded `cancelled` (AC4 evidence for PR body)
- [ ] 4.2 PR body: include `## Changelog`, the before-measurements table (plan §Observability), and the exclusion list with one-line reasons
- [ ] 4.3 Post-merge follow-up (not blocking): confirm two consecutive `main` pushes both complete `Infra Validation` (AC6 — do-not-cancel-main invariant)

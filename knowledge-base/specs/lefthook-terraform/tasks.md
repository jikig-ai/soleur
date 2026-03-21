# Tasks: infra: Add Lefthook Pre-Commit Hooks for Terraform

## Phase 1: Core Implementation

- [ ] 1.1 Add `terraform-fmt` command to `lefthook.yml` with priority 7, glob `apps/*/infra/*.tf` (NOT `**/*.tf` -- gobwas matcher requires 1+ dirs for `**`), `stage_fixed: true`
- [ ] 1.2 Decide on tflint: Option A (skip, defer to CI) or Option B (add with graceful skip)
- [ ] 1.3 If Option B: add `terraform-tflint` command to `lefthook.yml`

## Phase 2: Verification

- [ ] 2.1 Run `lefthook run pre-commit` with all `.tf` files already formatted -- confirm clean pass
- [ ] 2.2 Temporarily misformat a `.tf` file, stage it, run `lefthook run pre-commit` -- confirm auto-fix and re-stage
- [ ] 2.3 Stage only non-`.tf` files, run `lefthook run pre-commit` -- confirm terraform-fmt hook is skipped

## Phase 3: Ship

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit, push, create PR with `Closes #976`
- [ ] 3.3 Set `semver:patch` label via `/ship`

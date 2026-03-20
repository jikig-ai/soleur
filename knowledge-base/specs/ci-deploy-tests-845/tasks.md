# Tasks: Add ci-deploy.test.sh to CI pipeline

## Phase 1: Implementation

- [ ] 1.1 Read `.github/workflows/infra-validation.yml`
- [ ] 1.2 Add `deploy-script-tests` job to `infra-validation.yml`
  - [ ] 1.2.1 Add checkout step with `fetch-depth: 0`
  - [ ] 1.2.2 Add change-detection step scoped to `ci-deploy.sh` and `ci-deploy.test.sh`
  - [ ] 1.2.3 Add conditional step to run `bash apps/web-platform/infra/ci-deploy.test.sh`
- [ ] 1.3 Verify SHA-pinned action references match existing usage in the file

## Phase 2: Testing

- [ ] 2.1 Run `ci-deploy.test.sh` locally to confirm 20/20 pass
- [ ] 2.2 Validate YAML syntax of modified workflow (e.g., `python -c "import yaml; yaml.safe_load(open(...))"` or equivalent)

## Phase 3: Commit and Push

- [ ] 3.1 Run compound skill
- [ ] 3.2 Commit with message: `chore(ci): run ci-deploy.test.sh in infra-validation workflow (#845)`
- [ ] 3.3 Push and create PR with `Closes #845` in body

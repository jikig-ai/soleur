# Tasks: fix(ci) -- add lockfile sync check to PR CI

## Phase 1: Implementation

### 1.1 Add lockfile-sync job to ci.yml

- [ ] 1.1.1 Read existing `.github/workflows/ci.yml` to understand current job structure
- [ ] 1.1.2 Add `lockfile-sync` job with `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
- [ ] 1.1.3 Add `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020` (v4.4.0) with node-version 22
- [ ] 1.1.4 Add `npm install --package-lock-only` step with `working-directory: apps/web-platform`
- [ ] 1.1.5 Add `git diff --exit-code apps/web-platform/package-lock.json` with `::error::` annotations on failure
- [ ] 1.1.6 Use inline `if ! git diff ...; then echo "::error::..."; exit 1; fi` pattern (no heredocs)

## Phase 2: Verification

### 2.1 Local verification

- [ ] 2.1.1 Validate YAML syntax (no heredocs at column 0, proper indentation)
- [ ] 2.1.2 Verify the job passes on the current branch (lockfiles should be in sync)

### 2.2 CI verification

- [ ] 2.2.1 Push branch and verify the new job runs in PR CI
- [ ] 2.2.2 Confirm job passes when lockfiles are in sync

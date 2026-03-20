# Learning: CI job-level change detection is YAGNI when the workflow is already path-filtered

## Problem
When adding a `deploy-script-tests` job to `infra-validation.yml`, the initial plan included a 20-line per-file change-detection filter (git diff to check if `ci-deploy.sh` or `ci-deploy.test.sh` changed, with workflow_dispatch special-casing). This was modeled after the existing `detect-changes` job pattern.

## Solution
The code-simplicity-reviewer identified this as YAGNI: the workflow already triggers only on `apps/*/infra/**` path changes. The test script completes in under 1 second. Spending 20 lines (including `fetch-depth: 0` for a full git clone) to avoid running a sub-second test on the rare occasion an unrelated infra file changes is not a worthwhile tradeoff.

The simplified job went from 30 lines to 9 lines:
```yaml
deploy-script-tests:
  runs-on: ubuntu-24.04
  timeout-minutes: 5
  steps:
    - uses: actions/checkout@SHA # v4.3.1
    - name: Run ci-deploy.sh tests
      run: bash apps/web-platform/infra/ci-deploy.test.sh
```

## Key Insight
Pattern consistency is not always the right goal. The `detect-changes` job exists because `validate` uses a matrix over changed directories — the detection feeds dynamic data into the matrix. When a job just runs a single fast script unconditionally, duplicating the detection pattern adds complexity without proportional value. Match the mechanism to the need, not to the nearest existing pattern.

## Tags
category: ci-cd
module: github-actions

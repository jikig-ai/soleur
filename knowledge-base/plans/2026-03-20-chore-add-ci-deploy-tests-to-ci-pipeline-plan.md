---
title: "chore: add ci-deploy.test.sh to CI pipeline"
type: chore
date: 2026-03-20
issue: "#845"
---

# chore: add ci-deploy.test.sh to CI pipeline

`apps/web-platform/infra/ci-deploy.test.sh` validates the SSH forced-command deploy script's input parsing, allowlist enforcement, and shell-injection defenses (20 test cases). It runs locally but is not wired into any GitHub Actions workflow -- regressions to `ci-deploy.sh` would go undetected.

## Proposed Solution

Add a new job `deploy-script-tests` to the existing `.github/workflows/infra-validation.yml` workflow. This workflow already triggers on `apps/*/infra/**` path changes, so no new path filters are needed. The test script is pure bash with mocks -- no docker, terraform, or cloud credentials required.

### Why `infra-validation.yml` (not `ci.yml` or a new workflow)

- `ci.yml` runs on every PR regardless of paths -- running deploy tests on unrelated PRs wastes runner minutes.
- `infra-validation.yml` already has the correct path trigger (`apps/*/infra/**`) and `contents: read` permissions.
- A dedicated workflow would duplicate the same path filter for a single bash invocation -- unnecessary.
- The new job is independent of the existing `validate` matrix job (terraform/cloud-init), so it runs in parallel without coupling.

### Why a separate job (not a step in the existing `validate` matrix)

The existing `validate` job uses a matrix over changed infra directories and runs terraform-specific validation (cloud-init schema, `terraform fmt`, `terraform validate`). The deploy test script is not directory-generic -- it tests one specific script (`ci-deploy.sh`). Embedding it in the matrix would conflate two unrelated validation concerns and require conditional logic to skip terraform steps when only deploy scripts changed.

## Acceptance Criteria

- [ ] PRs touching `apps/web-platform/infra/ci-deploy.sh` run `ci-deploy.test.sh` automatically in CI
- [ ] PRs touching only `apps/web-platform/infra/ci-deploy.test.sh` also trigger the job (so test refactors are validated)
- [ ] The job fails the PR check if any test case fails (non-zero exit)
- [ ] The job does not require secrets, docker, terraform, or elevated permissions
- [ ] Existing `validate` job continues to work unchanged

## Test Scenarios

- Given a PR that modifies `apps/web-platform/infra/ci-deploy.sh`, when CI runs, then the `deploy-script-tests` job executes and all 20 tests pass.
- Given a PR that modifies `apps/web-platform/infra/ci-deploy.test.sh` only, when CI runs, then the `deploy-script-tests` job executes (validates test refactors).
- Given a PR that modifies `apps/telegram-bridge/infra/main.tf` only, when CI runs, then the `deploy-script-tests` job is skipped (irrelevant directory).
- Given a PR that modifies both `ci-deploy.sh` and a terraform file, when CI runs, then both `deploy-script-tests` and `validate` jobs run in parallel.
- Given the test script exits non-zero (a test fails), when CI reports, then the PR check is marked as failed.

## Context

- Identified during review of #825.
- The test script (`ci-deploy.test.sh`) already exists and passes all 20 cases locally.
- The deploy script (`ci-deploy.sh`) is a security-sensitive SSH forced command -- its validation logic prevents shell injection, image allowlist bypass, and malformed deploy commands.

## MVP

### `.github/workflows/infra-validation.yml` (additions only)

Add a `deploy-script-tests` job after the existing `validate` job. The job needs a change-detection step scoped to `ci-deploy.sh` and `ci-deploy.test.sh`, then conditionally runs the test script.

```yaml
  deploy-script-tests:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0

      - name: Check for deploy script changes
        id: filter
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_REF: ${{ github.base_ref }}
        run: |
          if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
          else
            CHANGED=$(git diff --name-only "origin/${BASE_REF}...HEAD" -- \
              'apps/web-platform/infra/ci-deploy.sh' \
              'apps/web-platform/infra/ci-deploy.test.sh')
            if [[ -n "$CHANGED" ]]; then
              echo "changed=true" >> "$GITHUB_OUTPUT"
            else
              echo "changed=false" >> "$GITHUB_OUTPUT"
            fi
          fi

      - name: Run ci-deploy.sh tests
        if: steps.filter.outputs.changed == 'true'
        run: bash apps/web-platform/infra/ci-deploy.test.sh
```

## References

- Deploy script: `apps/web-platform/infra/ci-deploy.sh`
- Test script: `apps/web-platform/infra/ci-deploy.test.sh`
- Target workflow: `.github/workflows/infra-validation.yml`
- Learning: `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Issue: #845 (identified during #825 review)

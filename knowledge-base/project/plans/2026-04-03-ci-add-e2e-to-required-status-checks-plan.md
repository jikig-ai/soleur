---
title: "ci: add e2e to required status checks"
type: feat
date: 2026-04-03
---

# ci: add e2e to required status checks

## Overview

Add the `e2e` job (Playwright browser tests) to the CI Required ruleset (ID 14145388) so that no PR can merge to main with failing end-to-end tests. Currently only `test` and `dependency-review` are required. The e2e suite covers CSP nonce propagation, OAuth flows, OTP login, auth redirects, and public page smoke tests.

## Problem Statement / Motivation

The `e2e` job runs on every PR but is not a required status check. A PR with failing e2e tests can merge to main, potentially shipping regressions in CSP security headers, auth flows, or page rendering. The e2e tests were deferred from the required set during initial CI gate setup (#1430) because stability had not been assessed.

## Research Findings

### E2E Stability Assessment

- **Pass rate on main: 100%** -- last 20 CI runs on main all have `e2e` conclusion `success`. Expanding to last 100 CI runs (all branches), zero failures found.
- **Execution time: ~90 seconds** -- e2e job consistently completes in 1m 20s to 1m 35s (start-to-complete). Well under the 5-minute threshold.
- **Retry mechanism already exists** -- `playwright.config.ts` sets `retries: process.env.CI ? 1 : 0`, giving each test one automatic retry in CI.
- **No flaky tests detected** -- 3 test files, ~25 test cases. Tests use API requests for header checks (avoiding rendering-dependent flakiness) and `test.skip()` guards for CSS compilation issues that only affect local worktree environments.

### Test Coverage

| File | Tests | What it covers |
|------|-------|----------------|
| `smoke.e2e.ts` | 10 | CSP nonce propagation, hardening directives, x-forwarded-host validation, health endpoint, auth redirects |
| `oauth.e2e.ts` | 6 | OAuth callback error handling, provider button rendering, T&C gate on signup |
| `otp-login.e2e.ts` | 11 | OTP form rendering, error handling, input validation, digit count, maxLength |

### Synthetic Status Impact

Two workflows create PRs using `GITHUB_TOKEN` and need synthetic `e2e` check-runs added:

| Workflow | Current synthetics | Needs `e2e` added |
|----------|-------------------|-------------------|
| `scheduled-content-publisher.yml` | `test`, `cla-check`, `dependency-review` | Yes |
| `scheduled-weekly-analytics.yml` | `test`, `cla-check`, `dependency-review` | Yes |

Seven other scheduled workflows use `claude-code-action` with `github.token`, but those PRs trigger CI workflows because the `claude-code-action` creates commits as `app/claude` which does trigger `on: pull_request` events (confirmed: recent `app/claude` PRs merged with real CI checks).

### Rollout Ordering (Critical)

Per learning `2026-03-20-github-required-checks-skip-ci-synthetic-status.md`: **Bot workflow updates must merge BEFORE ruleset activation** to avoid a blocking window. If the ruleset is activated first, existing bot PRs will be permanently stuck waiting for the `e2e` check that will never run.

Sequence:

1. Add synthetic `e2e` check-runs to both bot workflows
2. Merge to main
3. Update the ruleset via GitHub API to add `e2e` as a required check

## Proposed Solution

### Phase 1: Add synthetic e2e check-runs to bot workflows

Add a synthetic `e2e` check-run to both `GITHUB_TOKEN`-based PR workflows, matching the existing pattern for `test`, `cla-check`, and `dependency-review`.

#### `scheduled-content-publisher.yml`

Add after the existing `dependency-review` synthetic check-run (around line 122):

```yaml
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=e2e \
            -f head_sha="$COMMIT_SHA" \
            -f status=completed \
            -f conclusion=success \
            -f "output[title]=Bot PR" \
            -f "output[summary]=Status metadata only, no code changes"
```

#### `scheduled-weekly-analytics.yml`

Add after the existing `dependency-review` synthetic check-run (around line 132):

```yaml
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=e2e \
            -f head_sha="$COMMIT_SHA" \
            -f status=completed \
            -f conclusion=success \
            -f "output[title]=Bot PR" \
            -f "output[summary]=Analytics snapshot only, no code changes"
```

### Phase 2: Update the CI Required ruleset

After Phase 1 merges to main, update the ruleset via GitHub API:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  --method PUT \
  --input - <<'RULES'
{
  "name": "CI Required",
  "enforcement": "active",
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          {"context": "test", "integration_id": 15368},
          {"context": "dependency-review", "integration_id": 15368},
          {"context": "e2e", "integration_id": 15368}
        ]
      }
    }
  ]
}
RULES
```

The `integration_id: 15368` constraint ensures only `github-actions` (GITHUB_TOKEN) can satisfy the check, preventing third-party spoofing.

**Note:** The ruleset API `PUT` replaces the entire rules array. The request must include all existing checks (`test`, `dependency-review`) alongside the new `e2e` check.

### Phase 3: Verify

1. Confirm the ruleset update: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[].parameters.required_status_checks[].context'` should show `test`, `dependency-review`, `e2e`.
2. Open a test PR to verify `e2e` appears in the required checks section.
3. Verify no existing open bot PRs are stuck (check `gh pr list --search "author:app/github-actions" --state open`).

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Add e2e to `main-health-monitor.yml` | The health monitor runs the unit test suite (`test-all.sh`), not Playwright e2e. Adding e2e there would expand scope; the monitor is for detecting broken main, not gating PRs. Out of scope for this issue. |
| Increase retries from 1 to 2 | Current retry count of 1 is sufficient given 100% pass rate over 100+ runs. Increasing retries masks real failures. |
| Add e2e to `lint-bot-synthetic-statuses.sh` validation | The lint script checks for `[skip ci]`, not synthetic check-run completeness. A separate validator for synthetic check coverage would be useful but is out of scope. |

## Acceptance Criteria

- [ ] `scheduled-content-publisher.yml` includes synthetic `e2e` check-run
- [ ] `scheduled-weekly-analytics.yml` includes synthetic `e2e` check-run
- [ ] CI Required ruleset (ID 14145388) lists `e2e` as a required status check
- [ ] `integration_id: 15368` constraint is set on the `e2e` check
- [ ] Existing open bot PRs are not stuck after activation
- [ ] A real PR shows `e2e` as a required check in the GitHub checks UI

## Test Scenarios

- Given a bot PR from `scheduled-content-publisher.yml`, when the PR is created, then the `e2e` synthetic check-run is posted and the PR can auto-merge.
- Given a bot PR from `scheduled-weekly-analytics.yml`, when the PR is created, then the `e2e` synthetic check-run is posted and the PR can auto-merge.
- Given the updated ruleset, when a PR has failing e2e tests, then the PR cannot merge to main.
- Given the updated ruleset, when a PR has passing e2e tests, then the `e2e` required check is satisfied.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## References

- Issue: #1456
- Deferred from: #1430
- Learning: `2026-03-20-github-required-checks-skip-ci-synthetic-status.md`
- Learning: `2026-03-30-dependency-graph-enablement-and-synthetic-check-coverage.md`
- Learning: `2026-04-01-ci-quality-gates-and-test-failure-visibility.md`
- Playwright config: `apps/web-platform/playwright.config.ts` (retries already configured)
- Current ruleset: `gh api repos/jikig-ai/soleur/rulesets/14145388`

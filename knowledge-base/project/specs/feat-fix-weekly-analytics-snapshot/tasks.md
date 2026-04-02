# Tasks: Fix Weekly Analytics Snapshot

## Phase 1: Test Infrastructure (RED)

- [ ] 1.1 Read existing `scripts/weekly-analytics.sh` and `scripts/test-weekly-analytics.sh`
- [ ] 1.2 Add `validate_json_response()` test cases: valid JSON passes, non-JSON fails with error message, empty file fails
- [ ] 1.3 Run tests -- new tests should FAIL (function does not exist yet)

## Phase 2: Core Implementation (GREEN)

- [ ] 2.1 Add `validate_json_response()` shared function to `weekly-analytics.sh` (outside `main()`)
- [ ] 2.2 Integrate `validate_json_response()` into `api_get()` after HTTP status checks
- [ ] 2.3 Align preflight check parameters with actual data fetch (`period=7d&metrics=visitors,pageviews&compare=previous_period`)
- [ ] 2.4 Add JSON validation to preflight check response
- [ ] 2.5 Run tests -- all tests should PASS

## Phase 3: Verification

- [ ] 3.1 Run `scripts/test-weekly-analytics.sh` -- all tests pass with no regressions
- [ ] 3.2 Run `npx markdownlint-cli2 --fix` on changed markdown files
- [ ] 3.3 Create GitHub issue to track deferred v1→v2 migration

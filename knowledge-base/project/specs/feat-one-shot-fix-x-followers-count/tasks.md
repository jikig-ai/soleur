# Tasks: fix X followers count showing 0

## Phase 1: Setup

- [x] 1.1 Investigate root cause of 0 followers in community digest
- [x] 1.2 Verify X API v2 response returns 0 followers_count directly
- [x] 1.3 Verify X GraphQL endpoint returns 0 followers_count
- [x] 1.4 Verify X profile page shows 0 followers (Playwright snapshot)
- [x] 1.5 Conclude: API data is accurate, account genuinely has 0 followers

## Phase 2: Core Implementation

- [x] 2.1 Add `_check_metrics_anomaly` function to `x-community.sh`
  - [x] 2.1.1 Accept metrics JSON as input parameter
  - [x] 2.1.2 Extract `followers_count`, `tweet_count`, `following_count` via jq
  - [x] 2.1.3 Check for active-account-zero-followers anomaly: followers=0 AND tweets>0 AND following>0
  - [x] 2.1.4 Check for all-zeros anomaly: all public_metrics values are 0 (except possibly tweet_count)
  - [x] 2.1.5 Emit descriptive warning to stderr when anomaly detected (truncate to 200 chars per learning)
  - [x] 2.1.6 Return 0 for anomaly detected, 1 for normal
- [x] 2.2 Integrate anomaly check into `cmd_fetch_metrics`
  - [x] 2.2.1 After API call and jq transform, pipe metrics JSON to `_check_metrics_anomaly`
  - [x] 2.2.2 Preserve stdout JSON output unchanged regardless of anomaly result
  - [x] 2.2.3 Ensure stderr warnings do not corrupt stdout JSON

## Phase 3: Testing

- [x] 3.1 Run `cmd_fetch_metrics` with live API to verify anomaly warning triggers
- [x] 3.2 Verify JSON output schema is unchanged (same keys, same structure)
- [x] 3.3 Verify stderr warning does not corrupt stdout JSON
- [x] 3.4 Test edge case: genuinely new account (all zeros) should not warn

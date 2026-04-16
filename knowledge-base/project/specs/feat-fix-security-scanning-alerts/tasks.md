# Tasks: Dismiss CodeQL Alerts + CI Gate

**Issue:** #2417 | **PR:** #2416
**Plan:** `knowledge-base/project/plans/2026-04-16-sec-dismiss-codeql-alerts-ci-gate-plan.md`

## Phase 1: Dismiss Test/Tooling Alerts

- [ ] 1.1 Verify `gh` CLI token has `security_events` scope
- [ ] 1.2 Test-dismiss alert #107 with `"used in tests"` reason; verify response
- [ ] 1.3 Batch-dismiss remaining 11 test/tooling alerts (#106, #105, #104, #115, #114, #113, #112, #111, #103, #102, #90)
- [ ] 1.4 Verify all 12 test/tooling alerts are dismissed

## Phase 2: Dismiss Production Alerts

- [ ] 2.1 Dismiss 9 production alerts (#116, #117, #92, #93, #100, #95, #88, #96, #89) as `"false positive"` with per-alert defense explanation
- [ ] 2.2 Verify all 9 production alerts are dismissed

## Phase 2.5: Hard Gate — Verify Zero Open Alerts

- [ ] 2.5.1 Confirm `gh api repos/jikig-ai/soleur/code-scanning/alerts --jq '[.[] | select(.state == "open")] | length'` returns `0`
- [ ] 2.5.2 If any remain open, debug and fix before proceeding

## Phase 3: Add CodeQL to CI Required Ruleset

- [ ] 3.1 PUT updated ruleset with CodeQL check (integration_id 57789) preserving conditions
- [ ] 3.2 Re-read ruleset to verify 4 required checks

## Phase 4: Verify

- [ ] 4.1 Confirm zero open alerts via API
- [ ] 4.2 Confirm ruleset shows 4 required checks
- [ ] 4.3 Confirm PR #2416 shows CodeQL as required with status `success`
- [ ] 4.4 If CodeQL shows `expected`, push empty commit to trigger analysis

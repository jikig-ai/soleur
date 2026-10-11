# Tasks: raise merge queue check_response_timeout_minutes 60 to 75

Plan: knowledge-base/project/plans/2026-10-11-fix-merge-queue-check-response-timeout-75-plan.md
Issue: #9454 (Ref only, do not close)

## Phase 1: RED
- 1.1 Make T-mq-1.m8/m11/m12 (tests/scripts/test-audit-ruleset-bypass.sh) and stall M1 (plugins/soleur/test/merge-queue-stall-check.test.sh) value-independent; both suites stay green at 60
- 1.2 Change only the .tf to 75; Guard 2 must go RED on `DR skeleton params != tf`

## Phase 2: Value and guards
- 2.1 infra/github/ruleset-ci-required.tf (value + comment), scripts/create-ci-required-ruleset.sh:121, infra/github/README.md row: all 75
- 2.2 m8 awk `[0-9]+` to 30; m11 sed `[0-9]+` to 30; m12 threshold `'999'`; fix labels and comments
- 2.3 stall M1 expected reason uses `$TF_TIMEOUT`
- 2.3b Confirm whether a timeout-specific README-only mutation row is needed (existing m7 drives `max_entries_to_build`); record the answer (Guard Contract row 5)
- 2.3c Harness row: temporarily restore the hard-coded `60` in m11 and confirm the suite fails with `mutation did not land`, then revert
- 2.4 Re-run both suites green; terraform fmt -check and validate on infra/github

## Phase 3: Documentation sweep
- 3.1 ADR-270 (Parameters row, Stall probe, canary item 10, dated addendum 2026-10-11); merge-queue-stall-check.yml and merge-queue-cla-synthetics.yml comments; cron-merge-queue-stall-dispatch.ts header comment
- 3.2 Residual `60` sweep; classify every remaining hit; markdown-lint clean; c4-count-parity green

## Phase 4: Ship and verify (post-merge)
- 4.1 PR body `Ref #9454`
- 4.2 apply-github-infra.yml run for the merge commit is success
- 4.3 Live read: `curl -s https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388 | jq -r '.rules[] | select(.type=="merge_queue") | .parameters.check_response_timeout_minutes'` prints 75; other six params unchanged; optional drift workflow dispatch
- 4.4 Comment on #9454 (canary item 5 follow-up): value, PR, run URL, reading, evidence, cost; leave #9454 open

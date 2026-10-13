# Tasks: feat-one-shot-10175-git-data-rotate-post-flip-guard

Plan: knowledge-base/project/plans/2026-10-13-fix-git-data-rotate-post-flip-guard-plan.md

## Phase 1: Tests first (RED)
- 1.1 Write scripts/lib/git-data-store-dirty-scan.test.sh: instrument self-test, jq-synthesized fixtures, `gh` shim, Guard 1 mutation matrix, harness rows, row-count floor
- 1.2 Add dt read rows to tests/scripts/test-git-data-boot-signal-poll.sh (Guard 2 matrix)
- 1.3 Add parity-test pins (step order, GH_TOKEN-only binding, no continue-on-error, job permissions)
- 1.4 Add census pin for job-level actions: read

## Phase 2: Core
- 2.1 Create scripts/lib/git-data-store-dirty-scan.sh (store_clean | store_dirty | cutover_in_flight | scan_unreadable)
- 2.2 Add git_data_boot_complete_dt_sql/read to git-data-boot-signal-poll.sh (leave served_empty sql unchanged)
- 2.3 apply-web-platform-infra.yml: job permissions, new step before existing precondition, freshness check with Hetzner created via bc_curl
- 2.4 git-data-cutover.yml: amend d6_replace_stale message + test pin

## Phase 3: Docs and follow-ups
- 3.1 Runbook D6 section: never after the flip, verdict table, corrected served_repos paragraph, web-fed heartbeat sentence, follow-up notes
- 3.2 File/refresh follow-ups: F4 live-proof marker, #9943, #6975 (re-evaluation criteria, milestone)
- 3.3 Run suites, markdownlint, shellcheck; no dispatch/apply

## Deepen additions
- 1.5 Test rows: every-attempt re-run fixture, empty-steps cancelled job must-PASS, no-other-writer parity, census-unchanged pin
- 2.5 Scan: iterate run_attempt via /attempts/{n}/jobs; pin workflow file name and step literal in parity test
- 3.4 Runbook: "When a rotate is needed after the flip" (break-glass, Art. 17 residue date, escalation #10175/#8571), flip-precondition item, d6 age-out deadlock note

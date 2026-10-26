# Tasks: owner-ask probe for Inngest TLS acts A5 and A6

Plan: knowledge-base/project/plans/2026-10-26-feat-inngest-a5-a6-owner-ask-probes-plan.md

## Phase 1 - failing suite first
- 1.1 Write scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh with a stubbed gh and stubbed trusted-verdict view
  - 1.1.1 One case per decision row 1 to 7 (exit code plus one literal output string)
  - 1.1.2 Never-exit-0-or-1 case on malformed gh output
  - 1.1.3 One gh-failure case per read (#11215, #10540, #10543, anchors) expecting exit 3
  - 1.1.4 Guard cases: untrusted-author anchor, fenced anchor, date removed, soak-before-date ordering, all-open stub
  - 1.1.5 Output hygiene grep: no login, host id, key name, CLO-internal text
- 1.2 Run the suite and confirm it fails before the probe exists

## Phase 2 - the probe
- 2.1 Write scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh with the 7-row decision table
- 2.2 Header: purpose, credential posture (GH_TOKEN only), date constants, RETIREMENT list
- 2.3 Suite green

## Phase 3 - tracker and wiring
- 3.1 Add the run_suite line to scripts/test-all.sh
- 3.2 Update the A5 and A6 rows in knowledge-base/engineering/operations/runbooks/inngest-server.md (tracker number, S5-A5-DONE and S6-A6-DONE lines)
- 3.3 File the tracker (follow-through, action-required, meta/machinery, milestone Post-MVP / Later) with the directive earliest=2026-10-28T13:56:10Z secrets=GH_TOKEN
- 3.4 Record the tracker number in the PR body

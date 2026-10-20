# Tasks: queue-armed BEHIND refusal for --step, the pre-merge hook, and the BEHIND rule

Plan: knowledge-base/project/plans/2026-10-20-chore-queue-armed-behind-refusal-step-hook-rule-plan.md
Closes (by Ref, ship step owns the body): #9869, #9868. Draft PR: #10655.

## Phase 0: RED tests first
- [x] 0.1 plugins/soleur/test/sync-pr-behind.test.sh
  - [x] 0.1.1 Add run_step_bare and install_gh_wait (pr-view-mode, calls file); do NOT flip run_step until Phase 1
  - [x] 0.1.2 Re-anchor the existing qw_mutant rows against the planned queue_wait_eval; keep green on the current SUT
  - [x] 0.1.3 Add F1-F8 incl. UNKNOWN rows F1b-d, CLEAN F4b, unreadable x4, --fence skip with no pr view/rules call, mode-flag exclusivity, in-queue (refusal is rc 14)
  - [x] 0.1.4 Add W1-W4 for --queue-wait (verdicts, unreadable, removal-event contract, no marker)
  - [x] 0.1.5 Add mutation rows (a)-(f); reuse the H1 non-recording-shim control
  - [x] 0.1.6 Bump the exact pass-count pin on the last line (122 -> new total)
- [x] 0.2 .claude/hooks/pre-merge-rebase.test.sh
  - [x] 0.2.1 Extend the gh stub: pr view --json state,mergeStateStatus branch (before the STUB-MISS guard, apply --jq), rules endpoint case (default count 0), calls log
  - [x] 0.2.2 Add T-Q17..T-Q22 (ids T-Q1..T-Q16 are taken); register in the case list; raise EXPECTED_CASES by the function count; add case-list structural check
  - [x] 0.2.3 Add calls-log assertions to T-Q1; run the parity and headless suites unchanged
- [x] 0.3 plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh: update call/probe literals and the skew fixture, add has-step-no-fence fixture, fix QGH rules arm glob, add stripped-fence exit-14 row; ratchet MIN_VERDICTS
- [x] 0.4 plugins/soleur/test/pr-merge-poll.test.ts: replace the "unguarded by design" pin, probe pin -> --fence, exit-14 row, no-surface-teaches---fence and no-other---step-caller tests
- [x] 0.5 plugins/soleur/test/workflow-fidelity.test.ts: positive pins for the rule exception
- [x] 0.6 Run all five and record the RED row list

## Phase 1: sync-pr-behind.sh
- [x] 1.1 queue_wait_eval (always returns 0, QW_VERDICT/QW_DETAIL); queue_wait_gate as wrapper
- [x] 1.2 Parse --fence (only with --step) and --queue-wait
- [x] 1.2 Sanitise queue_state_read detail; bounded pr view with strict match
- [x] 1.3 Parse --fence/--queue-wait with mode exclusivity
- [x] 1.4 Flagless --step guard: one pr view snapshot, kind=queue_wait rc=14, fail-closed kind=gh rc=4
- [x] 1.5 --queue-wait mode (queue_wait | proceed; one pr view, no GraphQL read, no marker)
- [x] 1.6 usage/exit-code table (row 14)/header comments
- [x] 1.7 flip run_step to --fence (+ S1 row), shellcheck, suite GREEN

## Phase 2: pre-merge-rebase.sh
- [x] 2.1 Armed + not_queued + OPEN skip via --queue-wait under a 20 s wrapper; exact-line verdict parse; reuse _Q_NOTE for unreadable
- [x] 2.2 Header comment; shellcheck; suites GREEN

## Phase 3: fences
- [x] 3.1 ship/SKILL.md probe -> --fence, call -> --step --fence, exit-14 clause, comments at ~2267 and ~2544
- [x] 3.2 merge-pr/SKILL.md mirror probe and call
- [x] 3.3 Fixtures GREEN; lint-skill-body-budget; ship <= 273955 B

## Phase 4: text surfaces
- [x] 4.1 pr-merge-poll.ts lines ~75 and ~82
- [x] 4.2 queue-mode.md boundary (1), merge-queue-dequeue.md ~15, constitution.md ~177 (one clause each)
- [x] 4.3 bun tests GREEN

## Phase 5: AGENTS rule (#9868)
- [x] 5.1 Edit the tail of the hr-pipeline-skills-never-inline-after-go-route line to the Phase 5.1 wording (before pins/hash/ack)
- [x] 5.2 lint-rule-bodies.py --write
- [x] 5.3 Append the hash-bound ack (PR 10655)
- [x] 5.4 lint-rule-ids / rule-budget / enforcement-tags / rule-bodies --check / workflow-fidelity GREEN

## Phase 6: ADR
- [x] 6.1 ADR-270 addendum 2026-10-20 (decision + four residuals); check-adr-ordinals; c4-count-parity

## Phase 7: validation
- [ ] 7.1 All suites GREEN; scripts/test-all.sh --affected under the lock
- [ ] 7.2 AC-X1 diff-scope check; PR body uses Ref #9869 / Ref #9868

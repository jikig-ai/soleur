# Tasks: queue-armed BEHIND refusal for --step, the pre-merge hook, and the BEHIND rule

Plan: knowledge-base/project/plans/2026-10-20-chore-queue-armed-behind-refusal-step-hook-rule-plan.md
Closes (by Ref, ship step owns the body): #9869, #9868. Draft PR: #10655.

## Phase 0: RED tests first
- [ ] 0.1 plugins/soleur/test/sync-pr-behind.test.sh
  - [ ] 0.1.1 Rename run_step to run_step_fence (passes --fence); add run_step_bare
  - [ ] 0.1.2 Re-anchor the existing qw_mutant rows against the planned queue_wait_eval; keep green on the current SUT
  - [ ] 0.1.3 Add F1-F8 (flagless refusal, no-rule, unarmed, DIRTY, unreadable x3, --fence skip with no extra gh calls, usage, in-queue)
  - [ ] 0.1.4 Add W1-W4 for --queue-wait (verdicts, unreadable, removal-event contract, no marker)
  - [ ] 0.1.5 Add mutation rows (a)-(f); reuse the H1 non-recording-shim control
  - [ ] 0.1.6 Bump the exact pass-count pin on the last line (122 -> new total)
- [ ] 0.2 .claude/hooks/pre-merge-rebase.test.sh
  - [ ] 0.2.1 Extend the gh stub: pr view --json state,mergeStateStatus branch (before the STUB-MISS guard, apply --jq), rules endpoint case (default count 0), calls log
  - [ ] 0.2.2 Add T-Q17..T-Q22 (ids T-Q1..T-Q16 are taken); register in the case list; raise EXPECTED_CASES
  - [ ] 0.2.3 Add calls-log assertions to T-Q1; run the parity and headless suites unchanged
- [ ] 0.3 plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh: update call/probe literals, add expiry-fallback-still-syncs, old-snapshot-disables-sync and selector-parity rows; ratchet MIN_VERDICTS
- [ ] 0.4 plugins/soleur/test/pr-merge-poll.test.ts: replace the "unguarded by design" pin; add exit-11 queue_wait pin
- [ ] 0.5 plugins/soleur/test/workflow-fidelity.test.ts: positive pins for the rule exception
- [ ] 0.6 Run all five and record the RED row list

## Phase 1: sync-pr-behind.sh
- [ ] 1.1 queue_wait_eval (always returns 0, QW_VERDICT/QW_DETAIL); queue_wait_gate as wrapper
- [ ] 1.2 Parse --fence (only with --step) and --queue-wait
- [ ] 1.3 Flagless --step guard: bounded pr view, kind=queue_wait rc=11, fail-closed kind=gh rc=4, self-resolving message without --fence
- [ ] 1.4 --queue-wait mode (queue_wait | proceed | queued; no marker)
- [ ] 1.5 usage/exit-code table/header comments
- [ ] 1.6 shellcheck + suite GREEN

## Phase 2: pre-merge-rebase.sh
- [ ] 2.1 Armed + not_queued + OPEN skip via bounded --queue-wait; explicit verdict table; reuse _Q_NOTE for unreadable
- [ ] 2.2 Header comment; shellcheck; suites GREEN

## Phase 3: fences
- [ ] 3.1 ship/SKILL.md probe -> --fence, call -> --step --fence, exit-11 prose, comment at ~2267
- [ ] 3.2 merge-pr/SKILL.md mirror probe and call
- [ ] 3.3 Fixtures GREEN; lint-skill-body-budget; ship <= 273955 B

## Phase 4: text surfaces
- [ ] 4.1 pr-merge-poll.ts lines ~75 and ~82
- [ ] 4.2 queue-mode.md boundary (1) only
- [ ] 4.3 bun tests GREEN

## Phase 5: AGENTS rule (#9868)
- [ ] 5.1 Edit the tail of the hr-pipeline-skills-never-inline-after-go-route line (wording first)
- [ ] 5.2 lint-rule-bodies.py --write
- [ ] 5.3 Append the hash-bound ack (PR 10655)
- [ ] 5.4 lint-rule-ids / rule-budget / enforcement-tags / rule-bodies --check / workflow-fidelity GREEN

## Phase 6: ADR
- [ ] 6.1 ADR-270 addendum 2026-10-20 (decision + four residuals); check-adr-ordinals; c4-count-parity

## Phase 7: validation
- [ ] 7.1 All suites GREEN; scripts/test-all.sh --affected under the lock
- [ ] 7.2 AC-X1 diff-scope check; PR body uses Ref #9869 / Ref #9868

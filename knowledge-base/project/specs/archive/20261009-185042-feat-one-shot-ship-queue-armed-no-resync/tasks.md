# Tasks: sync-pr-behind.sh queue-armed guard

Plan: knowledge-base/project/plans/2026-10-09-fix-ship-queue-armed-pr-resync-guard-plan.md
Branch: feat-one-shot-ship-queue-armed-no-resync | Draft PR: 9862 | Follow-up: #9868 (operator-gated rule wording)

## Phase 0: RED first
- 0.1 Add the `install_gh` rules arm (`rules-mode`: none|queue|fail|flip, default none) before the `gh-n` counter; log argv to `rules-calls`
- 0.2 Add the per-fixture `git` PATH shim (`git-calls`, then exec real git)
- 0.3 Re-run the whole existing `plugins/soleur/test/sync-pr-behind.test.sh` unchanged-green with the default `none`
- 0.4 Add rows Q1, Q2, R2-R9 (PR 4242, live-shape rules payload, merge_queue second); confirm Q1 and R6 RED on the current script

## Phase 1: script guard (plugins/soleur/scripts/sync-pr-behind.sh)
- 1.1 `queue_wait_gate`: BEHIND and not DIRTY, armed from QS_OUT field 3, then one rules read selecting `.type == "merge_queue"`
- 1.2 Verdicts: >=1 -> `tag queue_wait 0` + exit 0; 0 -> return; unreadable (after retry) -> `tag queue_rule_unread 0` + return
- 1.3 Call site after `queue_gate`, before `tag behind`, every attempt
- 1.4 `usage()` + header comment: queue_wait in exit 0, `--step` is the fence's call; `--step`/`--queue-state` code untouched
- 1.5 Rows Q1-R9 GREEN

## Phase 2: instruction text
- 2.1 ship/SKILL.md line 30 -> the 621 B text in the plan; `wc -c` <= 274000, net negative
- 2.2 pr-merge-poll.ts `behindSyncInstructions` claude/grok/default; keep the substrings existing tests pin
- 2.3 pr-merge-poll.test.ts assertions (anchored on content); queue-mode.md "Standalone guard" paragraph

## Phase 3: ADR
- 3.1 ADR-270 addendum 2026-10-09 via soleur:architecture; C4: none (plan section cites the check)

## Phase 4: verify (targeted only)
- 4.1 sync-pr-behind.test.sh (both copies: test/ and scripts/), ship-phase-7-poll-fixtures.test.sh
- 4.2 bun test pr-merge-poll, harness, workflow-fidelity
- 4.3 Mutation battery rows 1-9 + H1 from an immutable SUT snapshot; count result rows vs the list
- 4.4 lint-skill-body-budget.py --base origin/main; c4-count-parity.test.sh; lint-guard-contract.py on the plan
- 4.5 diff-scope: no .github/workflows|actions, infra/, AGENTS*.md; PR body `Refs` only (#9066 #9377 #8609 #9868)

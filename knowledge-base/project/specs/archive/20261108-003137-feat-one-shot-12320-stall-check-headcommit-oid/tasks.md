# Tasks: feat-one-shot-12320-stall-check-headcommit-oid

Plan: `knowledge-base/project/plans/2026-11-07-fix-stall-check-correlate-run-to-queue-entry-by-headcommit-oid-plan.md`. Issue #12320 (PR body: `Closes #12320`, `Ref #9927`).

## Phase 0 - re-verify live
- 0.1 Re-run the read-only live queue read (state, position, headCommit.oid) and the per-ref Actions read; record queue size, states and head_sha == oid counts with run kind merge_group for the PR body.
- 0.2 After Phase 2, run the exact query text extracted from the edited workflow live once (read-only) to prove GitHub accepts the selection.

## Phase 1 - failing rows first (suite only)
- 1.1 Add TIP_SHA, SHA_A, SHA_B constants plus a 40-lowercase-hex self-check.
- 1.2 Stub: keep headCommit only when the query selects oid (preserve null); update the stub header comment.
- 1.3 Helpers: node() gains headCommit (oid or the null token, default TIP_SHA); mkrun reads head_sha from MKSHA (default TIP_SHA, inline prefix, no wrapper); one_entry takes optional oid and state. Grep every queue_candidate_cause call site first.
- 1.4 L24 driver passes a valid oid as the third argument; confirm C20 stays RED.
- 1.5 Rows L27 (matching, invented shas, chaining-only comment), L28 (stale ref on new entry: a-d), L29 (null / malformed / empty-vs-empty: a-d); register in CAUSE_ROWS, ldesc and the rows loop.
- 1.6 Run the suite foreground (timeout 600000): new rows fail for the right reason, legacy rows pass.

## Phase 2 - workflow edit
- 2.1 Add `headCommit { oid }` to the GraphQL selection.
- 2.2 Append the oid as the last stalled TSV field; `read -r pr age url state enq oid`.
- 2.3 Add `head_sha` to the fetch_runs projection.
- 2.4 queue_candidate_cause: third argument, null/malformed short-circuit first with its own ::notice::.
- 2.5 Naming jq: `(.head_sha // "")` as the last field; loop reads `hs`, mismatch skips with a distinct ::notice:: (notice and continue on one line) before has_mg_history.
- 2.6 Call site passes "$oid"; the cause paragraph and title are unchanged.
- 2.7 Header comment (about 6 lines): correlation, null rule, narrowed caveat, two residuals.
- 2.8 Duplicate-key check and structural rows stay green.

## Phase 3 - mutation rows and floor
- 3.1 Update all three C11 occurrences of the call to the three-argument form.
- 3.2 Add C27-C34 via mutate_lit (anchors unique in the pristine workflow).
- 3.3 Run the suite; set EXPECTED_PASSES to the observed count (expected 153).

## Phase 4 - local gates (before the single push)
- 4.1 ci-pr-affected-replay.py ratchet (add accept rows only if asked).
- 4.2 fixture-env-adoption.test.sh; grep-q-pipe-guard.test.sh; c4-count-parity.test.sh.
- 4.3 lint-guard-contract.py on the plan; check-workflow-duplicate-keys.py.
- 4.4 Confirm the suite's registration (glob, shard leg 5, run-all.sh) and state the result.

## Phase 5/6 - ship, postmerge
- 5.1 PR body: Closes #12320, Ref #9927, live re-verification block, D7 split, residuals, `pipeline-tally.sh show` output; re-read after every edit.
- 5.2 Bare `gh pr merge`; Monitor for polling; no sleep.
- 6.1 Postmerge: merge_group evidence with run kind and leg, deploy arm exact+success, KB archival read-back, first post-merge stall-check run green.
- 6.2 Classification comment on #9927 (Ref only).

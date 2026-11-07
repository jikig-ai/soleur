# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-07-feat-ci-is-the-gate-token-reaches-work-review-grok-gate-plan.md
- Status: complete

### Errors
None blocking. Brief byte ceiling for ship/SKILL.md (273781) matches nothing in the repo; measured ceilings are planned as byte deltas. #12030 is open and the queue is currently green (last 8 merge_group runs succeeded).

### Decisions
- Ruled by CTO agent, 2026-11-07: #12251 does not fold into this PR; this PR carries Ref #12251 (separate PR, fix is -z plus --ignore-submodules=none).
- battery-owed.sh gets a --token-only flag (no token returns OWED immediately); new thin wrapper plugins/soleur/scripts/gate-or-skip.sh serves work step 9, work fan-out lead gate and review lead gate; Grok pre-push gate gets an inline --token-only branch.
- test-fix-loop, ship Phase 4 and lefthook stay token-blind; lefthook deferral tracked as #12297.
- F12: no gate needs the token after Phase 6.45 archival; recorded once in the ADR-242 amendment.
- Closing mechanism: PR body Closes #12247, Ref #12251, Ref #12297, Ref #12246.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (1 spawn), research and review agents per the plan.

## Operator Constraints

- constraint: Rely on CI required test check. Required checks are test, lockfile-sync, markdown-lint, tenant-integration-required. Read infra-validation and sandbox-canary-capture-gate by hand. Do not run the local affected battery to completion.
- constraint: Never push to a PR that is in the merge queue. Never admin merge. Never touch the ruleset. If the queue dequeues a PR a second time, stop and report before re-arming.
- constraint: A PR body citing a follow-through tracker uses Ref, never Closes. Declare net-issue-flow when the PR files issues and closes none.
- constraint: Technical forks go to the CTO agent and legal wording to the CLO agent, never to the operator.
- constraint: Check a push real exit code, no pipe to tail. Run git add and git commit in separate calls. No rm -rf inside the worktree. No SSH.
- constraint: Mutation-battery discipline for any new guard, a green unmutated control, a mutation-landed check, a lead-unique scratchpad file name. Cap fix rounds at two targeted rounds plus one verification pass.
- ci-is-the-gate: Rely on CI required test check, do not run the local affected battery to completion.

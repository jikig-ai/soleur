# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-07-fix-battery-owed-c-quoted-infra-paths-plan.md
- Status: complete (plan reviewed and deepened)

## Operator Constraints

- constraint: Rely on CI required test check. Required checks are test, lockfile-sync, markdown-lint, tenant-integration-required. Read infra-validation and sandbox-canary-capture-gate by hand. Do not run the local affected battery to completion.
- constraint: Never push to a PR that is in the merge queue. Never admin merge. Never touch the ruleset. If the queue dequeues a PR a second time, stop and report before re-arming.
- constraint: A PR body citing a follow-through tracker uses Ref, never Closes. Declare net-issue-flow when the PR files issues and closes none.
- constraint: Technical forks go to the CTO agent and legal wording to the CLO agent, never to the operator.
- constraint: Check a push real exit code, no pipe to tail. Run git add and git commit in separate calls. No rm -rf inside the worktree. No SSH.
- constraint: Mutation-battery discipline for any new guard, a green unmutated control, a mutation-landed check, a lead-unique scratchpad file name. Cap fix rounds at two targeted rounds plus one verification pass.
- ci-is-the-gate: Rely on CI required test check, do not run the local affected battery to completion.

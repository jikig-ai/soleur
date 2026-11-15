# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-09-fix-convert-remaining-changed-path-readers-plan.md
- Status: complete

### Errors

None blocking. Planner ran plan and deepen-plan inline; plan-review was covered by the deepen-plan review panel and a second CTO round. Only plan artifacts were committed.

### Decisions

- Cut line (CTO F1): convert a reader only if its match allows, selects or blocks, a hazard lets it fail open, and the conversion does not open a closed arm. 25 site groups (18 code/workflow, 7 prose/agent).
- Sentinel extends (CTO F2/D1): second code census over tracked scripts with a three-flag predicate, plus a bounded prose census over a closed file list.
- One PR in four waves; accept rows re-derived last. No issue filed unless a size-driven drop happens (one consolidated meta/machinery tracker then).
- affected-tests.sh flags only; rename-guard.sh fail-closed line form; admin-merge classifier stays inline; allowlist-diff suite lives in scripts/.

### Components Invoked

soleur:plan, soleur:deepen-plan, soleur:engineering:cto (two rounds), Explore classifiers, learnings-researcher, code-simplicity-reviewer, test-design-reviewer, security-sentinel.

## Operator Constraints

- constraint: Rely on CI required checks test, lockfile-sync, markdown-lint, tenant-integration-required as the gate, do not run the local affected battery to completion.
- constraint: Read infra-validation and sandbox-canary-capture-gate by hand when they appear.
- constraint: Never push to a PR in the merge queue, never admin merge, never touch the ruleset. If the queue dequeues a PR a second time, stop and report before re-arming.
- constraint: A PR body citing a tracker uses Ref, never Closes, unless that issue is the work target. Declare net issue flow with Filed.
- constraint: Technical forks go to the CTO agent, legal wording to the CLO agent, never to the operator.
- constraint: Check a push real exit code, git add and git commit in separate calls, no SSH, no git stash.
- constraint: Registry rows go in sorted position and accept rows are re-derived last.
- constraint: Run the repo meta-guards on any new suite before pushing.
- constraint: Cap fix rounds at two targeted rounds plus one verification pass.
- ci-is-the-gate: Rely on CI required checks test, lockfile-sync, markdown-lint, tenant-integration-required as the gate, do not run the local affected battery to completion.

# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-15-chore-reprice-cloudflare-readonly-suite-weight-plan.md
- Status: complete
- cto_spawns=2 (vehicle rulings 2026-11-13 and 2026-11-15, both before the pipeline's planning phase)

### Errors

- #12780 filing was blocked twice by a hook (body path in a shell variable; missing machinery label); the third attempt succeeded.
- technical-ruling-gate exit 1 on 5 rows (bad ruling shape); rows reshaped or reclassified, re-run exit 0.

### Decisions

- Only scripts/suite-durations.tsv changes: the cloudflare-readonly.test.sh row becomes 155229 measured, byte-identical to #12698's line.
- No derived file changes; the generator has no single-row mode, so it is a hand edit (CTO ruling 2026-11-15).
- Local gates: scripts-shard-manifest.test.sh, regenerate-shard-manifest.test.sh, test-all-corpus-weight-budget.test.sh, test-all-fast-tier-budget.test.sh.
- PR stays Ref #12441 only; #12698 is never touched.

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto

## Operator Constraints

- constraint: No production write, dispatch, apply or admin bypass without the owner's typed go for each command, naming the command.
- constraint: Ref only, never Closes/Fixes; closingIssuesReferences must be [].
- constraint: Run plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh before every push.
- constraint: Credentials: names and booleans only, never values.
- constraint: Do not change repo settings.
- constraint: The merge queue is serial: do not push syncs while a PR is armed or queued. If arming fails, enqueue only with the owner's go.

# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-feat-host-kernel-marker-stale-kernel-alert-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 in this main context (planning subagent ran two CTO rounds)

### Errors
Plan-write guard rewords and a filing-hook Mandated-By line during planning; the ruling gate needed row-shape fixes in decision-challenges.md, now PASS.

### Decisions
- Shared collector prints one SOLEUR_HOST_KERNEL v=1 line, 6 hourly plus after boot; journald for web-1, web-2, inngest, registry via its existing curl post.
- Dead-man heartbeat per host, born paused, 36 hour beat window; feeder loop membership deferred to the arming change.
- host-state.sh kernel_state becomes observed, stale or unknown; observed needs a valid periodic report at most 48 hours old.
- git-data deferred to a tracked follow-up; grok-dogfood exempt.
- Nothing applied to production; installers held in OPERATOR_APPLIED_EXCLUSIONS pending operator go-ahead.

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:plan-review, CTO agent, terraform-architect, repo-research-analyst, learnings-researcher.

## Operator Constraints

- constraint: Commit with LEFTHOOK_EXCLUDE=bun-test and git commit -F file using the Co-Authored-By trailer; never git stash; PR bodies end with the Claude Code attribution line; batch commits before pushing.
- constraint: CI is the merge gate unless the operator asks for a local battery; ship through the merge queue and finish the post-merge check before reporting done.
- constraint: Production-changing steps need the operator explicit per-command go-ahead.
- ci-is-the-gate: CI is the merge gate unless the operator asks for a local battery.
cto_spawns=1 (dissent batch)

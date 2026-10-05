# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-fix-deploy-bwrap-probe-sigkill-canary-rollback-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. A PreToolUse hook refused the first deferral-issue create (fixed with Mandated-By trailer; filed as #9342); lefthook not on PATH at commit time.

### Decisions
- Cause: `--die-with-parent` arms PR_SET_PDEATHSIG(SIGKILL) on a docker-exec'd process and races runc exec-parent exit -> rc=137, empty stderr (19/19 Better Stack rows; local A/B 3.0% vs 0/7500).
- Fix: drop the flag from the blocking probe in ci-deploy.sh and from audit-bwrap-uid.sh; per-site recorded-argv assertion plus one repo-wide check in existing suites.
- Reason string `canary_sandbox_failed` and marker line shapes unchanged.
- Cut: retry-on-137, new reason string, timeout wrapper, sh -c exec wrapper, ADR-079 addendum, faithful-canary promotion.
- Recurrence alert deferred to #9342.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; research, review and CTO agents.

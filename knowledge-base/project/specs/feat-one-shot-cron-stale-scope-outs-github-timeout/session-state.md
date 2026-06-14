# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-12-fix-cron-stale-scope-outs-github-connect-timeout-plan.md
- Status: complete

### Errors
None. CWD verified equal to the working directory on the first tool call. Both /soleur:plan and /soleur:deepen-plan ran inline; plan + tasks committed and pushed in two commits.

### Decisions
- Root cause: the cron's octokit.request(...) calls (search, comment, close) carry no transient-retry; a single undici connect timeout escalates to an error-level Sentry mirror even though Inngest retries:1 usually self-heals. Fix = in-step transient retry, reusing the canonical github-retry.ts leaf + MAX_RETRIES=2/BASE_DELAY=1000 budget.
- P0 caught at deepen-plan: octokit.request wraps the timeout in a RequestError (HttpError, status:500) with UND_ERR_CONNECT_TIMEOUT buried at .cause.cause — existing top-level isRetryable misses it. Plan adds isRetryableGithubError (cause-chain walk) and AC4 seeds octokit's real thrown shape, not a bare TypeError.
- P1 idempotency over-claim corrected: comment POST is non-idempotent; plan keeps per-call wrapping, tracks pre-existing double-comment-on-replay window as follow-up F2.
- Simplified per YAGNI: dropped withGithubRetry opts param, reused existing budget constants, collapsed redundant test ceremony.
- Scope/gates: threshold none with mandatory sensitive-path scope-out bullet; no UI, no IaC, no GDPR surface; not a new cron; network-outage SSH checklist not applicable (L7 code fix).

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan
- Agents: architecture-strategist, framework-docs-researcher, code-simplicity-reviewer (parallel)

# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-fix-external-watchdog-dispatch-cadence-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- deepen-plan PAT gate false-positive on the Cloudflare `cf_api_token` variable name; reworded, gate passes.
- One sharp-edges reference page was first read from the bare-root mirror instead of the worktree (identical content).

### Decisions
- Trigger: in-process polling loop in the web server on both web hosts; per slot + 30-150 s jitter, dispatches the workflow via an actions:write soleur-only GitHub App token unless the slot already has a run; fail-open to dispatch. Not an Inngest cron (must fire while Inngest is down); lint forbids importing Inngest code. GitHub `schedule:` crons stay as fallback.
- Rejected: Cloudflare Worker (App key custody, hand-minted token; upgrade path tied to #7230), Inngest cron, host timer, Better Stack (PAT / copied secrets), margins-only (~7 h detection).
- Sentry: crontabs unchanged; zot margin 120 -> 30; Inngest stays 15.
- Guards: dispatch-table/workflow/Sentry parity test; tick can never crash the server; WARN-level SOLEUR_WATCHDOG_DISPATCH marker (Vector ships WARN+). ADR-246 + C4 edits ship in the same PR.
- Closes #8495 allowed (merge deploys clock + applies Sentry change); post-merge AC9-AC11 reopen on failure.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, repo-research-analyst, learnings-researcher, best-practices-researcher, cto, spec-flow-analyzer, dhh/kieran/simplicity reviewers, architecture-strategist, security-sentinel, observability-coverage-reviewer, test-design-reviewer

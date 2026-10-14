# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-github-retry-probe-octokit-5230/knowledge-base/project/plans/2026-06-14-feat-withgithubretry-probe-octokit-cron-call-sites-plan.md
- Status: complete

### Errors
None. CWD verified correct; branch feat-one-shot-github-retry-probe-octokit-5230 (not main).

### Decisions
- Path correction: cron files live at server/inngest/functions/cron-*.ts (not server/cron-*.ts); createProbeOctokit is in server/github/probe-octokit.ts. Premise holds, files relocated.
- createProbeOctokit widening: change guard from `status === 401` to `status === 401 || isRetryableGithubError(err)`. Do NOT migrate its loop to withGithubRetry (fresh-App/JWT-per-attempt is load-bearing).
- Non-idempotent re-POST hazard (AC4): wrap each octokit.request() individually, never grouped. 14 call sites enumerated (drift-guard 9, oauth-probe 5).
- Sensitive-path scope-out: apps/web-platform/server/** matches preflight Check-6; threshold: none requires explicit scope-out bullet (added).
- Verify-the-negative: drift-guard handler-level github_app_401 retry is status-driven on returned DriftResult, not thrown — no double-retry with withGithubRetry.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Bash, Read, Write, Edit

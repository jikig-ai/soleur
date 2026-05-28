# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-28-fix-cron-monitor-observability-drift-guard-issue-trail-plan.md
- Status: complete

### Errors
- soleur:plan's Write initially resolved the plan to the BARE ROOT instead of the worktree (Bash CWD per-call resets to bare root). Detected and corrected by the planning subagent: file moved into the worktree, bare-root copy removed, verified clean.
- Inngest/Sentry live run-data not directly queried (no Sentry/Inngest MCP this session); root cause proven via code-path inspection (403 from issues:read token + swallowing catch). Plan instructs /work to confirm via the Sentry checkins API.

### Decisions
- Root cause CONFIRMED via code: manifest declares `issues: read` (github-app-manifest.json:23); probes write issues via createProbeOctokit() (installation-scoped App token) -> 403 -> swallowed by reportSilentFallback. Sentry mirror already exists at level:error; the gap is the lost GitHub-issue trail, fixed by granting `issues:write`.
- Fix #2 = DROP `members:read` (not force re-consent): no code uses GitHub org membership (workspace features read Supabase workspace_members). Dropping clears the #4189 drift with no operator gate.
- Broader blast radius: cron-stale-deferred-scope-outs and cron-community-monitor share the same createProbeOctokit() issue-write blind spot; a single issues:write grant fixes all four crons.
- Fix #3 needs no operator action: scheduled_realtime_probe Terraform field-edit auto-applies via apply-sentry-infra.yml; widen checkin_margin_minutes 180->1440.
- Bundled as ONE PR: fixes 1+2 share a single operator re-consent click (issues:write on install 130018654); fix 3 folds in. Single-user-incident threshold -> CPO sign-off + user-impact-reviewer at review.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan (gates 4.6/4.7/4.8 PASS; Phase 4.4 precedent-diff; Phase 4.45 verify-the-negative)
- Tools: Bash, Read, Write, Edit

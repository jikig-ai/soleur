# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2896-campaign-calendar-watchdog/knowledge-base/project/plans/2026-04-28-fix-campaign-calendar-max-turns-and-overdue-dedup-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause is two-fold: (1) `--max-turns 20` in `scheduled-campaign-calendar.yml` is the lowest of any scheduled workflow (peers 30-80) and starves the 4-step prompt under plugin overhead — 2026-04-27 manual dispatch hit "Reached maximum number of turns (20)"; 2026-04-20 schedule-fire ran at the wall (`num_turns: 21`). (2) STEP 2 of the prompt has no dedup against existing open overdue issues, producing duplicate #2968/#2146 pair and silent zero-issue runs.
- Fix scope: raise `--max-turns` to 40, raise `timeout-minutes` to 30 (preserves 0.75 min/turn ratio per 2026-03-20 budget learning), rewrite STEP 2 with explicit `gh issue list --search` dedup, append STEP 2.5 close-on-create heartbeat issue so the watchdog's label-cadence query always sees recent activity.
- Pin freshness verified live (H5 refuted): v1.0.101 is 10 days old; tip is v1.0.108. Pin bump deferred to a separate PR.
- PR body uses `Ref #2896`, not `Closes #2896`. The watchdog auto-closes #2896 when a fresh audit issue lands within threshold; closing from PR would close before post-merge verification.
- `gh issue create --json` does NOT exist (verified). STEP 2.5 uses URL-on-stdout capture: `URL=$(gh issue create ...) && gh issue close "$URL"`.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh CLI (issue list/view, run list/view --log, api repos/anthropics/claude-code-action/releases, workflow run)
- File reads: AGENTS.md, cloud-scheduled-tasks runbook, scheduled-cloud-task-heartbeat.yml, scheduled-campaign-calendar.yml, campaign-calendar SKILL.md, prior learnings (2026-04-03, 2026-03-20)

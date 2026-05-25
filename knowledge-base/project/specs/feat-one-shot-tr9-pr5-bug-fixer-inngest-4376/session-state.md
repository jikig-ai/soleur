# Session State

## Plan Phase
- Plan file: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-tr9-pr5-bug-fixer-inngest-4376/knowledge-base/project/plans/2026-05-24-feat-tr9-pr5-bug-fixer-inngest-migration-plan.md`
- Status: complete

### Errors
None. All 15 cited KB-ref paths verified at live-check.

### Decisions
- **Q2 Factory:** reuse `createProbeOctokit()` + `generateInstallationToken()` to mint raw `GH_TOKEN` for spawn env. App installation permissions verified to include `contents:write`, `pull_requests:write`, `issues:write`.
- **Q1 Plugin loading (NOVEL):** PR-1..PR-4 do not load plugins. PR-5 introduces ephemeral cron workspace under `/tmp/cron-bug-fixer-<X>/` via `mkdtemp` with `plugins/soleur → /app/shared/plugins/soleur` symlink and `.claude/settings.json` overlay. Spawn cwd = ephemeral dir. Sentinel `existsSync(plugin.json)` check before spawn → abort + Sentry on failure.
- **Q3 Timeout:** issue body's 20-min claim was wrong; GHA workflow is 45 min / 55 turns. Plan sets `MAX_TURN_DURATION_MS = 50 * 60 * 1000`. Total step.run budget ~55min across 6 step.run phases; only `claude-eval` carries the AbortController.
- **Auto-merge gate placement:** synchronous, downstream of `claude-eval` in its own `step.run("auto-merge-gate", ...)` AFTER `detect-pr`. GraphQL `enablePullRequestAutoMerge` mutation requires PR's `node_id` (fetched by detect-pr).
- **Workflow deletion sweep:** delete `.github/workflows/scheduled-bug-fixer.yml` same-commit (TR9 I-13). CODEOWNERS clean (0 matches). Runbook clean (0 `gh workflow run` matches).
- **Sentry monitor:** NEW `scheduled_bug_fixer` resource (no GHA predecessor). Cron `0 6 * * *`, margin=30, max_runtime=55.
- **Q4 Threshold:** `brand_survival_threshold: none` carried from PR-1.
- **Sharp Edge #6 (risk):** `fix-issue` skill's worktree-manager.sh expects cwd to be a git repo; ephemeral workspace is bare. /work Phase 0 must verify whether the Hetzner host has the bare clone OR have the handler `git clone --bare` into the ephemeral workspace.

### Components Invoked
- Skill: `soleur:plan` (#4376)
- Skill: `soleur:deepen-plan` (Phase 4.6 / 4.7 / 4.8 gates, KB-ref live-check)

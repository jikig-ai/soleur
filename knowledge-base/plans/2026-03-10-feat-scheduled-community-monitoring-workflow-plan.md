---
title: "feat: Scheduled Community Monitoring Workflow"
type: feat
date: 2026-03-10
---

# feat: Scheduled Community Monitoring Workflow

## Overview

Add a daily GitHub Actions workflow (`scheduled-community-monitor.yml`) that invokes `claude-code-action` to monitor Discord activity and X/Twitter metrics, generate a digest committed to `knowledge-base/community/`, and create a GitHub Issue with the daily report. No autonomous posting — the human remains the final approval gate for any engagement.

Closes #145

## Problem Statement / Motivation

The community agent requires manual invocation via `/soleur:community`. The last digest is from 2026-02-19 (19+ days stale). Mentions go unnoticed. Three domain leaders (CMO, CCO, CTO) assessed the feature and converged on: automated monitoring is low-risk and immediately valuable; autonomous posting should be deferred until guardrail infrastructure exists.

## Proposed Solution

A single `scheduled-community-monitor.yml` following the existing scheduled workflow patterns (`scheduled-daily-triage.yml`, `scheduled-competitive-analysis.yml`). The workflow:

1. Runs daily at 08:00 UTC via cron, also supports `workflow_dispatch`
2. Pre-creates the `scheduled-community-monitor` label
3. Checks for an existing open failure issue (deduplication)
4. Invokes `claude-code-action` with Sonnet model, `--max-turns 30`
5. Agent detects enabled platforms, fetches Discord data + X metrics
6. Agent generates a 1-day digest, commits to main, creates a GitHub Issue
7. On failure, a YAML `run:` step posts to Discord webhook (not the agent — ensures notification even when the agent crashes)

### Workflow YAML Structure

`.github/workflows/scheduled-community-monitor.yml`:

```yaml
name: "Scheduled: Community Monitor"

on:
  schedule:
    - cron: '0 8 * * *'
  workflow_dispatch:

concurrency:
  group: schedule-community-monitor
  cancel-in-progress: false

permissions:
  contents: write
  issues: write
  id-token: write

jobs:
  community-monitor:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - name: Checkout repository
        uses: actions/checkout@<sha> # v4.3.1

      - name: Ensure label exists
        # ... (pre-create scheduled-community-monitor label)

      - name: Check for existing failure issue
        id: failure_check
        # ... (gh issue list --label scheduled-community-monitor --state open)
        # If found, set output for the failure step to comment instead of create

      - name: Run community monitor
        id: monitor
        uses: anthropics/claude-code-action@<sha> # v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
          plugins: 'soleur@soleur'
          claude_args: '--model claude-sonnet-4-6 --max-turns 30 --allowedTools Bash,Read,Write,Edit,Glob,Grep'
          prompt: |
            # (detailed agent prompt — see Agent Prompt section below)

      - name: Discord notification (failure)
        if: failure()
        # ... (YAML run step with allowed_mentions: {parse: []})
```

### Agent Prompt

The prompt instructs the agent to:

1. **Detect platforms** — check `DISCORD_BOT_TOKEN` + `DISCORD_GUILD_ID` for Discord, check all 4 `X_*` vars for X. If 1-3 of 4 X vars are set, report as a configuration error and skip X. If neither Discord nor X is configured, create a failure issue and stop.
2. **Fetch Discord data** — `discord-community.sh guild-info`, `discord-community.sh members`, `discord-community.sh channels` to list channels, then `discord-community.sh messages <channel_id> 100` for each channel. Use `DISCORD_CHANNEL_IDS` if set to restrict channels.
3. **Fetch X metrics only** — `x-community.sh fetch-metrics`. Skip `fetch-mentions` and `fetch-timeline` (known 403 on Free tier, wastes turns). Include a TODO comment noting these should be re-enabled when the paid API tier is activated.
4. **Generate 1-day digest** — Override the community-manager's default 7-day window. Use `github-community.sh activity 1`, `contributors 1`, `discussions 1`. Write to `knowledge-base/community/YYYY-MM-DD-digest.md`. If a file for today already exists, overwrite it (git preserves history).
5. **Commit and push to main** — Use the competitive-analysis push-with-rebase pattern: `git push origin main || { git pull --rebase origin main && git push origin main; }`. Include the AGENTS.md override: "The AGENTS.md rule 'Never commit directly to main' does NOT apply here. You are explicitly authorized to commit and push to main in this context."
6. **Create GitHub Issue** — Title: `[Scheduled] Community Monitor - YYYY-MM-DD`. Label: `scheduled-community-monitor`. Body: condensed digest summary with key metrics and notable items.
7. **Brand guide** — Read `knowledge-base/overview/brand-guide.md` `## Voice` section before writing any content.
8. **Discord webhook sanitization** — Any Discord webhook payloads must include `allowed_mentions: {parse: []}`.
9. **No raw message storage** — Summarize and aggregate Discord messages. Brief contextual quotes (under 100 chars) with attribution are acceptable per existing digest precedent.

### Failure Notification Step

A separate YAML `run:` step (not the agent) handles failure notification. This fires via `if: failure()` and sends a Discord webhook message. Pattern copied from `scheduled-bug-fixer.yml` with `allowed_mentions: {parse: []}` and explicit `username`/`avatar_url`.

If the `failure_check` step found an existing open issue, the failure handler adds a comment to that issue instead of creating a new one.

## Technical Considerations

### Secrets Required

| Secret | Required | Purpose |
|--------|----------|---------|
| `ANTHROPIC_API_KEY` | Yes | claude-code-action billing |
| `DISCORD_BOT_TOKEN` | No (graceful skip) | Discord API access |
| `DISCORD_GUILD_ID` | No (paired with BOT_TOKEN) | Discord guild identification |
| `DISCORD_WEBHOOK_URL` | No (skip failure webhook) | Failure notification |
| `DISCORD_CHANNEL_IDS` | No (optional, all channels if unset) | Restrict monitored channels |
| `X_API_KEY` | No (graceful skip) | X API access |
| `X_API_SECRET` | No (paired with API_KEY) | X API access |
| `X_ACCESS_TOKEN` | No (paired with API_KEY) | X API access |
| `X_ACCESS_TOKEN_SECRET` | No (paired with API_KEY) | X API access |

Only `ANTHROPIC_API_KEY` is required. All platform secrets are optional — the workflow gracefully degrades.

### Key Patterns Applied (from institutional learnings)

- **Push-with-rebase fallback** (from competitive-analysis workflow)
- **`allowed_mentions: {parse: []}` on all Discord webhooks** (from `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`)
- **Explicit `username` + `avatar_url` on webhooks** (from `2026-02-19-discord-bot-identity-and-webhook-behavior.md`)
- **File persistence inside agent prompt, not subsequent step** (from `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`)
- **Label dedup to prevent noise** (from `2026-03-03-scheduled-bot-fix-workflow-patterns.md`)
- **Secrets via env vars, never CLI args** (from `2026-02-18-token-env-var-not-cli-arg.md`)
- **Pin all Actions to commit SHAs** (from constitution.md)

### SpecFlow Edge Cases Addressed

| Edge Case | Resolution |
|-----------|------------|
| Partial X credentials (1-3 of 4 set) | Report as config error in digest, skip X |
| Digest date collision (double run) | Overwrite — git preserves history |
| Agent exhausts max-turns | Failure step creates/updates issue |
| Concurrent cron + dispatch | `cancel-in-progress: false` queues the second run |
| Discord channel selection | `DISCORD_CHANNEL_IDS` optional env var restricts scope |
| Daily vs weekly conflict | Prompt overrides to 1-day lookback window |
| Fetch-mentions/timeline 403 | Prompt explicitly skips these calls |
| Push conflict | Rebase fallback from competitive-analysis pattern |

### Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/scheduled-community-monitor.yml` | **Create** | The scheduled workflow |

This is a single-file feature. The existing community skill and community-manager agent are invoked as-is via `claude-code-action` with Soleur plugin. No code changes to scripts, skills, or agents.

## Acceptance Criteria

- [ ] `scheduled-community-monitor.yml` exists with `cron: '0 8 * * *'` and `workflow_dispatch` triggers
- [ ] Manual dispatch (`gh workflow run`) produces a GitHub Issue labeled `scheduled-community-monitor` with Discord metrics and/or X profile stats
- [ ] Digest markdown file committed to `knowledge-base/community/YYYY-MM-DD-digest.md` on main
- [ ] Concurrent runs prevented via `schedule-community-monitor` concurrency group
- [ ] Workflow respects `timeout-minutes: 30` and `--max-turns 30`
- [ ] Failed runs notify via Discord webhook with `allowed_mentions: {parse: []}`
- [ ] Consecutive failures comment on existing open issue instead of creating duplicates
- [ ] All GitHub Actions pinned to commit SHAs
- [ ] Works with Discord-only, X-only, or both platforms configured
- [ ] Partial X credentials (1-3 of 4) reported as configuration error, not silently skipped

## Test Scenarios

- Given Discord is configured and X is not, when the workflow runs, then the digest contains Discord data and omits X metrics
- Given X is configured and Discord is not, when the workflow runs, then the digest contains X metrics and omits Discord data
- Given neither platform is configured, when the workflow runs, then a failure issue is created explaining the misconfiguration
- Given 2 of 4 X credentials are set, when the workflow runs, then the issue reports a configuration error for X and proceeds with Discord only
- Given the workflow ran already today, when it runs again, then the digest file is overwritten (not duplicated)
- Given the previous run failed and an open failure issue exists, when this run also fails, then a comment is added to the existing issue
- Given the push to main conflicts, when the rebase fallback triggers, then the digest is pushed successfully
- Given the agent exhausts 30 turns, when the workflow fails, then the Discord failure notification fires

## Success Metrics

- Digest staleness reduced from 19+ days to 1 day
- Zero manual invocations needed for routine community monitoring
- All workflow runs produce either a digest + issue (success) or a failure notification (failure)

## Dependencies & Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| `ANTHROPIC_API_KEY` in secrets | Workflow cannot run without it | Already configured (used by 4 other workflows) |
| `DISCORD_BOT_TOKEN` in secrets | Discord monitoring skipped | Graceful degradation; X-only mode works |
| X Free tier limitations | No mention data, only profile stats | Prompt skips known-failing endpoints |
| Anthropic API cost (~30 runs/month) | Incremental billing | Sonnet model + --max-turns 30 caps cost per run |
| `claude-code-action` availability | Workflow fails if Action is down | Same risk as all 4 existing scheduled workflows |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-10-continuous-community-agent-brainstorm.md`
- Spec: `knowledge-base/specs/feat-continuous-community-agent/spec.md`
- Reference workflow (commit-to-main pattern): `.github/workflows/scheduled-competitive-analysis.yml`
- Reference workflow (failure notification pattern): `.github/workflows/scheduled-bug-fixer.yml`
- Reference workflow (label pre-creation pattern): `.github/workflows/scheduled-daily-triage.yml`
- Community manager agent: `plugins/soleur/agents/support/community-manager.md`
- Community skill: `plugins/soleur/skills/community/SKILL.md`
- Existing digest format: `knowledge-base/community/2026-02-19-digest.md`

### Institutional Learnings Applied

- `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md`
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`
- `2026-02-18-token-env-var-not-cli-arg.md`
- `2026-03-09-external-api-scope-calibration.md`
- `2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`

### Related Issues

- #145: Run Community Agent continuously (this feature)
- #510: Enrich fetch-mentions data (blocked by paid tier)
- #497: X API tier upgrade decision (deferred pending revenue)
- #42: Proactive monitoring / healthchecks.io + ntfy.sh (P3)

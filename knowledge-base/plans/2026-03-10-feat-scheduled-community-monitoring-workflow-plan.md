---
title: "feat: Scheduled Community Monitoring Workflow"
type: feat
date: 2026-03-10
semver: minor
---

# feat: Scheduled Community Monitoring Workflow

## Overview

Add a GitHub Actions workflow (`scheduled-community-monitor.yml`) that invokes `claude-code-action` to run the existing community skill daily — fetching Discord activity and X/Twitter metrics, generating a digest committed to `knowledge-base/community/`, and creating a GitHub Issue with the report. No autonomous posting.

Closes #145

## Problem Statement

The community agent requires manual invocation via `/soleur:community`. The last digest is from 2026-02-19 (19+ days stale). Three domain leaders (CMO, CCO, CTO) converged on: automated monitoring is low-risk and immediately valuable; autonomous posting deferred until guardrail infrastructure exists.

## Non-goals

- Autonomous reply posting (human approval gate preserved)
- X mention/timeline fetching (Free tier returns 403; deferred until paid API tier)
- Modifications to the community skill or community-manager agent
- Automated guardrail enforcement system
- Multi-platform content suggestions

## Proposed Solution

A single `scheduled-community-monitor.yml` following the `scheduled-competitive-analysis.yml` pattern. Start with `workflow_dispatch` only per constitution convention; add cron (`0 8 * * *`) after validating end-to-end.

### Workflow Steps

1. **Checkout** — pinned to commit SHA
2. **Ensure label** — pre-create `scheduled-community-monitor` label
3. **Run community monitor** — `claude-code-action` with Sonnet, `--max-turns 30`
4. **Discord failure notification** — `if: failure()` YAML `run:` step (not agent)

### Agent Prompt

The prompt delegates to the existing community skill rather than re-specifying its internals:

- AGENTS.md override for direct-to-main commits
- Run community digest with 1-day lookback window (override default 7-day: `activity 1`, `contributors 1`, `discussions 1`)
- X: call only `fetch-metrics` (skip `fetch-mentions`/`fetch-timeline` — known 403 on Free tier)
- Commit digest and push with rebase fallback: `git push origin main || { git pull --rebase origin main && git push origin main; }`
- Create GitHub Issue: `[Scheduled] Community Monitor - YYYY-MM-DD`, label `scheduled-community-monitor`

### Secrets and Env Mapping

Only `ANTHROPIC_API_KEY` is required. Platform secrets are optional — the skill gracefully skips unconfigured platforms. The `claude-code-action` step must map all needed secrets via `env:`:

```yaml
env:
  DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN }}
  DISCORD_GUILD_ID: ${{ secrets.DISCORD_GUILD_ID }}
  DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
  X_API_KEY: ${{ secrets.X_API_KEY }}
  X_API_SECRET: ${{ secrets.X_API_SECRET }}
  X_ACCESS_TOKEN: ${{ secrets.X_ACCESS_TOKEN }}
  X_ACCESS_TOKEN_SECRET: ${{ secrets.X_ACCESS_TOKEN_SECRET }}
```

### Failure Notification

A YAML `run:` step with `if: failure()` posts to Discord webhook. Pattern from `scheduled-bug-fixer.yml` with `allowed_mentions: {parse: []}` and explicit `username`/`avatar_url`. This fires even when the agent crashes or exhausts turns.

## Rollback Plan

Disable or delete `.github/workflows/scheduled-community-monitor.yml`. The workflow is self-contained — no other code depends on it. Digests already committed to `knowledge-base/community/` remain in git history.

## Technical Considerations

### Key Patterns Applied

- **Push-with-rebase fallback** (from competitive-analysis workflow)
- **`allowed_mentions: {parse: []}` on Discord webhooks** (learning: `2026-03-05`)
- **File persistence inside agent prompt** (learning: `2026-03-02` — token revocation)
- **Pin all Actions to commit SHAs** (constitution.md)

### Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/scheduled-community-monitor.yml` | **Create** | The scheduled workflow |

Single-file feature. Existing community skill and community-manager agent invoked as-is.

## Acceptance Criteria

- [x] `scheduled-community-monitor.yml` exists with `workflow_dispatch` trigger (cron added after validation)
- [ ] Manual dispatch produces a GitHub Issue labeled `scheduled-community-monitor` with platform metrics
- [ ] Digest committed to `knowledge-base/community/YYYY-MM-DD-digest.md` on main
- [x] `timeout-minutes: 30` and `--max-turns 30` set
- [x] Failed runs notify via Discord webhook with `allowed_mentions: {parse: []}`
- [x] All GitHub Actions pinned to commit SHAs
- [x] Works with Discord-only, X-only, or both platforms configured

## Test Scenarios

- Given Discord is configured and X is not, when the workflow runs, then the digest contains Discord data and omits X metrics
- Given neither platform is configured, when the workflow runs, then a failure issue is created
- Given the agent exhausts 30 turns, when the workflow fails, then the Discord failure notification fires

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-10-continuous-community-agent-brainstorm.md`
- Spec: `knowledge-base/specs/feat-continuous-community-agent/spec.md`
- Reference workflow: `.github/workflows/scheduled-competitive-analysis.yml`
- Failure notification pattern: `.github/workflows/scheduled-bug-fixer.yml`
- Community skill: `plugins/soleur/skills/community/SKILL.md`
- Related: #145, #510, #497

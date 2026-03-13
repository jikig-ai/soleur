# Spec: Continuous Community Agent

**Issue:** #145
**Branch:** feat-continuous-community-agent
**Date:** 2026-03-10

## Problem Statement

The community agent requires manual invocation via `/soleur:community`. This results in stale digests (last: 2026-02-19), missed mentions, and inconsistent community monitoring. There is no automated cadence for community engagement.

## Goals

- G1: Automate daily community monitoring via GitHub Actions scheduled workflow
- G2: Generate combined Discord + X metrics digest committed to the repo
- G3: Queue drafted mention replies as GitHub Issues for human batch review
- G4: Follow existing scheduled workflow patterns (`claude-code-action`, concurrency groups, timeouts)

## Non-Goals

- NG1: Autonomous reply posting (human approval gate preserved)
- NG2: X mention fetching (Free tier returns 403; deferred until paid API tier)
- NG3: Playwright web fallback for X scraping (fragile in CI)
- NG4: GitHub discussions monitoring
- NG5: Automated guardrail enforcement system (prerequisite for future autonomous posting, not this iteration)

## Functional Requirements

- **FR1:** A new GitHub Actions workflow `scheduled-community-monitor.yml` with `cron` (daily) and `workflow_dispatch` triggers
- **FR2:** The workflow invokes `claude-code-action` with a prompt to run community monitoring
- **FR3:** The agent fetches Discord activity via `discord-community.sh` (message volume, active members, notable conversations)
- **FR4:** The agent fetches X/Twitter metrics via `x-community.sh fetch-metrics` (follower count, tweet count)
- **FR5:** The agent generates a digest and commits it to `knowledge-base/community/YYYY-MM-DD-digest.md`
- **FR6:** The agent creates a GitHub Issue with the daily report (metrics, activity summary, any mentions found)
- **FR7:** If X mentions are available (future paid tier), the agent drafts replies and includes them in the Issue for human review
- **FR8:** The workflow uses a concurrency group to prevent parallel runs
- **FR9:** The workflow has `timeout-minutes` set to cap billing
- **FR10:** Failed runs create a labeled issue or notify via Discord webhook

## Technical Requirements

- **TR1:** Follow the `scheduled-daily-triage.yml` pattern for workflow structure
- **TR2:** Pin all GitHub Actions to commit SHAs with version comments
- **TR3:** Use `--max-turns` to limit agent token spend per run
- **TR4:** Discord secrets (`DISCORD_BOT_TOKEN`, webhook URL) must be available as GitHub Actions secrets
- **TR5:** X API secrets (`X_API_KEY`, etc.) added as GitHub Actions secrets when X mention fetching is enabled
- **TR6:** The agent prompt must reference the brand guide for any content generation
- **TR7:** Digest commits happen inside the agent prompt (not a subsequent step) due to `claude-code-action` token revocation
- **TR8:** Apply `allowed_mentions: {parse: []}` on any Discord webhook payloads
- **TR9:** All API calls must use depth-limited retries (max 3)

## Acceptance Criteria

- [ ] `scheduled-community-monitor.yml` exists with cron + workflow_dispatch triggers
- [ ] Manual dispatch produces a GitHub Issue with Discord metrics and X profile stats
- [ ] Digest markdown file is committed to `knowledge-base/community/`
- [ ] Concurrent runs are prevented
- [ ] Workflow respects timeout and max-turns limits
- [ ] Failed runs surface visibly (label or notification)

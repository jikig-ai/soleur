# Feature: Daily Triage Automation

## Problem Statement

Open issues accumulate without consistent classification. Only 3 of 26 issues have labels. There is no automated triage process, no priority labels, and no domain routing. This makes it difficult to identify which issues are urgent, which are agent-fixable, and which need human attention.

## Goals

- Automatically classify and label all open issues daily across 5 dimensions (severity, domain, type, urgency, agent-actionable)
- Provide triage reasoning as comments on each classified issue
- Skip already-classified issues to prevent label thrashing and respect human overrides
- Fix schedule skill template gaps to unblock this and future scheduled workflows

## Non-Goals

- Autonomous bug fixing (Phase 2 -- separate issue)
- Auto-merging PRs (Phase 3 -- separate issue)
- Real-time triage on issue creation (deferred -- daily batch is sufficient for v1)
- Triage of internal code review findings (that's the `triage` skill's scope, not `daily-triage`)

## Functional Requirements

### FR1: Label Taxonomy Pre-Creation

The workflow must pre-create all triage labels before classification begins. Labels are organized in 5 dimensions:

- **Severity:** `severity/critical`, `severity/major`, `severity/minor`
- **Domain:** `domain/plugin`, `domain/ci`, `domain/docs`, `domain/legal`, `domain/community`
- **Type:** `type/bug`, `type/feature`, `type/chore`, `type/question`
- **Urgency:** `urgency/p0-immediate`, `urgency/p1-today`, `urgency/p2-week`, `urgency/p3-backlog`
- **Agent-actionable:** `agent/fixable`, `agent/needs-human`

### FR2: Issue Classification

For each open issue lacking a severity label, the `ticket-triage` agent classifies it across all 5 dimensions and applies the corresponding GitHub labels via `gh issue edit`.

### FR3: Triage Comments

After classifying an issue, the agent adds a comment explaining its reasoning: why it assigned the severity, what domain it belongs to, and whether it considers the issue agent-fixable.

### FR4: Idempotency

Issues that already have any `severity/*` label are skipped entirely. This prevents re-classification of previously triaged issues and preserves any human label overrides.

### FR5: Daily Schedule

The workflow runs daily at 06:00 UTC via cron. It also supports manual dispatch via `workflow_dispatch`.

## Technical Requirements

### TR1: Schedule Skill Template Fixes

Fix 6 known template gaps before generating the workflow:

1. `--max-turns` parameter support
2. Label pre-creation step in generated YAML
3. `timeout-minutes` on the job
4. `--allowedTools` includes `Task` for subagent delegation
5. `id-token: write` permission
6. Skill-specific argument passthrough

### TR2: Extended ticket-triage Agent

Update the agent to:

- Apply labels via `gh issue edit --add-label`
- Add comments via `gh issue comment`
- Maintain its classification-focused scope (no code changes)
- Update disambiguation sentence to clarify scope vs. `triage` skill

### TR3: daily-triage Skill

Create a new skill that orchestrates:

1. List open issues without severity labels
2. Delegate classification to ticket-triage agent
3. Verify labels were applied
4. Handle errors gracefully (skip issues that fail, continue with remaining)

### TR4: SHA-Pinned Actions

All `uses:` lines in the generated workflow must be pinned to commit SHAs per learnings. No mutable tags.

### TR5: Cost Controls

- `timeout-minutes` set on the job to prevent runaway billing
- `--max-turns` set to a reasonable limit for the agent
- Concurrency group to prevent overlapping runs

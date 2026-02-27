---
title: "feat: Dogfood competitive-intelligence agent via scheduled GitHub Action"
type: feat
date: 2026-02-27
version_bump: PATCH
---

# Dogfood Competitive-Intelligence Agent via Scheduled GitHub Action

## Overview

Create a monthly cron workflow that runs `/soleur:competitive-analysis --tiers 0,3` on the 1st of each month, producing a GitHub Issue with competitive intelligence findings. This dogfoods the agent+skill pair shipped in v3.7.0 (#332) and the schedule skill shipped in v3.5.0 (#321).

## Problem Statement / Motivation

The competitive-intelligence agent and competitive-analysis skill were merged in v3.7.0 but have never run in CI. Without a live scheduled run, we cannot verify:

1. Plugin discovery via `marketplace.json` works end-to-end in `claude-code-action`
2. The `--tiers` argument bypass path works for non-interactive invocation
3. The agent produces a coherent GitHub Issue when `knowledge-base/` is not writable (CI read-only checkout)
4. The cron + `workflow_dispatch` dual trigger pattern from the schedule skill template works

This is the first real consumer of `soleur:schedule create` -- running it validates both the generator and the generated workflow.

## Proposed Solution

Use `soleur:schedule create` with flags to generate `.github/workflows/scheduled-competitive-analysis.yml`:

- **Name:** `competitive-analysis`
- **Skill:** `soleur:competitive-analysis`
- **Cron:** `0 9 1 * *` (9:00 UTC on the 1st of each month)
- **Model:** `claude-sonnet-4-6` (default -- cost-effective for monthly scans)
- **Tiers:** Pass `--tiers 0,3` in the generated prompt

After committing and pushing, trigger the workflow manually via `workflow_dispatch` to validate end-to-end before waiting for the cron.

## Technical Considerations

### Schedule Skill Flag Passthrough

The schedule skill accepts `--name`, `--skill`, `--cron`, and `--model` flags to skip interactive prompts. All four must be provided to avoid AskUserQuestion blocks. The skill will:

1. Resolve SHAs for `actions/checkout@v4` and `anthropics/claude-code-action@v1` via `gh api`
2. Generate the workflow YAML with SHA-pinned actions
3. Validate YAML syntax with `python3 -c "import yaml; ..."`

### CI Plugin Discovery

The generated workflow uses the marketplace pattern from the schedule skill learning:

```yaml
plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
plugins: 'soleur@soleur'
```

This requires `.claude-plugin/marketplace.json` at repo root (already exists at v3.7.0).

### Prompt Customization

The schedule skill template's prompt includes:

```
Run /soleur:competitive-analysis on this repository.
```

The skill needs to receive `--tiers 0,3` as arguments. The generated prompt should be:

```
Run /soleur:competitive-analysis --tiers 0,3 on this repository.
After your analysis is complete, create a GitHub issue titled
"[Scheduled] Competitive Analysis - <today's date in YYYY-MM-DD format>"
with the label "scheduled-competitive-analysis" summarizing your findings.
```

### No Plugin Version Bump

This change adds only a GitHub Actions workflow file (`.github/workflows/`), not a plugin change under `plugins/soleur/`. No version bump is required.

### Secret Prerequisite

`ANTHROPIC_API_KEY` must be set as a repository secret. Verify with:

```bash
gh secret list | grep ANTHROPIC_API_KEY
```

If missing, the workflow will fail with an auth error. This is a prerequisite, not a task for this plan.

## Acceptance Criteria

- [ ] `.github/workflows/scheduled-competitive-analysis.yml` exists with SHA-pinned actions
- [ ] Workflow has both `schedule` (cron) and `workflow_dispatch` triggers
- [ ] Cron expression is `0 9 1 * *` (monthly on the 1st at 09:00 UTC)
- [ ] Workflow uses `plugin_marketplaces` and `plugins` for Soleur discovery
- [ ] Prompt passes `--tiers 0,3` to the competitive-analysis skill
- [ ] YAML validates without syntax errors
- [ ] Manual `workflow_dispatch` trigger runs successfully
- [ ] Workflow run creates a GitHub Issue with competitive intelligence content
- [ ] Concurrency group prevents overlapping runs

## Test Scenarios

- Given the workflow file is merged to main, when `gh workflow run scheduled-competitive-analysis.yml` is executed, then the workflow starts and completes without error
- Given the workflow runs in CI, when the competitive-analysis skill executes, then it invokes the competitive-intelligence agent with `--tiers 0,3`
- Given the CI environment has read-only checkout, when the agent tries to write `competitive-intelligence.md`, then it falls back to creating a GitHub Issue with the report content
- Given a `scheduled-competitive-analysis` label does not exist, when the issue is created, then the label is auto-created by `gh issue create`
- Given the cron fires on the 1st of the month, when no other run is in progress, then the workflow executes normally
- Given a previous run is still in progress, when the cron fires again, then the concurrency group queues (not cancels) the new run

## Non-Goals

- Modifying the competitive-intelligence agent or competitive-analysis skill (tested as-is)
- Adding Slack/Discord notifications for completed scans (v2 of schedule skill)
- Carrying state between monthly runs (no cross-run persistence exists)
- Running all tiers (0-5) -- default `0,3` is sufficient for platform threat monitoring

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `ANTHROPIC_API_KEY` secret missing | Low | Check before triggering; document prerequisite |
| `claude-code-action` plugin discovery fails | Medium | Validated by schedule skill learning -- marketplace.json pattern is proven |
| Agent produces empty/malformed issue | Medium | Manual inspection after first run; iterate on prompt if needed |
| SHA resolution fails (network) | Low | Schedule skill blocks generation on failure; retry when online |
| GitHub Actions 15-min cron variance | N/A | Acceptable for monthly schedule; not a risk |

## Implementation Steps

1. Run `/soleur:schedule create` with `--name competitive-analysis --skill competitive-analysis --cron "0 9 1 * *" --model claude-sonnet-4-6`
2. Verify the generated workflow file has correct prompt with `--tiers 0,3`
3. If the default prompt does not include `--tiers`, manually edit the prompt line
4. Validate YAML syntax
5. Commit and push to `feat/dogfood-competitive-intel`
6. Create PR targeting main
7. After merge, trigger `gh workflow run scheduled-competitive-analysis.yml`
8. Monitor the run via `gh run watch`
9. Verify the created GitHub Issue contains competitive intelligence content

## References & Research

### Internal References

- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md`
- Competitive analysis skill: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Competitive intelligence agent: `plugins/soleur/agents/product/competitive-intelligence.md`
- Marketplace manifest: `.claude-plugin/marketplace.json`
- CI plugin discovery learning: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`
- Competitive intel implementation learning: `knowledge-base/learnings/2026-02-27-competitive-intelligence-agent-implementation.md`
- GitHub Actions security patterns: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`

### Related PRs

- #332 -- competitive-intelligence agent and competitive-analysis skill (v3.7.0)
- #321 -- schedule skill (v3.5.0)

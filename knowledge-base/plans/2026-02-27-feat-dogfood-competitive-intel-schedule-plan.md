---
title: "feat: Dogfood competitive-intelligence agent via scheduled GitHub Action"
type: feat
date: 2026-02-27
version_bump: PATCH
---

# Dogfood Competitive-Intelligence Agent via Scheduled GitHub Action

## Enhancement Summary

**Deepened on:** 2026-02-27
**Sections enhanced:** 4 (Technical Considerations, Acceptance Criteria, Test Scenarios, Dependencies & Risks)
**Research sources:** claude-code-action docs, existing workflow patterns (review-reminder.yml, claude-code-review.yml), 3 institutional learnings, security-sentinel agent patterns

### Key Improvements
1. Added `--max-turns` configuration to prevent premature termination of multi-step competitive scans
2. Identified permissions gap -- workflow needs `contents: write` for claude-code-action to function, not just `read`
3. Added duplicate issue prevention pattern from review-reminder.yml precedent
4. Flagged read-only checkout assumption as incorrect -- `actions/checkout` provides a writable workspace in CI

### New Considerations Discovered
- The agent's fallback path ("output as code block if file cannot be written") will not trigger in standard CI because `actions/checkout` creates a writable clone. The agent will write `competitive-intelligence.md` to the workspace, but the file will be discarded after the job ends (no push step). The GitHub Issue must be created by the prompt instruction, not as a fallback.
- GitHub Actions `with:` values are NOT shell-expanded -- `$(date)` in the prompt field would be passed literally. The schedule skill already uses natural language ("today's date in YYYY-MM-DD format") which is correct.
- The `github.token` (GITHUB_TOKEN) is automatically available and has `issues: write` permission when declared in the workflow -- no additional secret is needed for issue creation. Only `ANTHROPIC_API_KEY` is a custom secret.

## Overview

Create a monthly cron workflow that runs `/soleur:competitive-analysis --tiers 0,3` on the 1st of each month, producing a GitHub Issue with competitive intelligence findings. This dogfoods the agent+skill pair shipped in v3.7.0 (#332) and the schedule skill shipped in v3.5.0 (#321).

## Problem Statement / Motivation

The competitive-intelligence agent and competitive-analysis skill were merged in v3.7.0 but have never run in CI. Without a live scheduled run, we cannot verify:

1. Plugin discovery via `marketplace.json` works end-to-end in `claude-code-action`
2. The `--tiers` argument bypass path works for non-interactive invocation
3. The agent produces a coherent GitHub Issue when running in CI
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

### Research Insights: Schedule Skill Template Gaps

The schedule skill template (SKILL.md Step 3) generates a fixed prompt structure:

```text
Run /soleur:<SKILL_NAME> on this repository.
After your analysis is complete, create a GitHub issue titled
"[Scheduled] <DISPLAY_NAME> - <today's date in YYYY-MM-DD format>"
with the label "scheduled-<NAME>" summarizing your findings.
```

**Gap 1: No `--tiers` passthrough.** The template does not support passing skill-specific arguments. The generated prompt will say `Run /soleur:competitive-analysis on this repository.` without `--tiers 0,3`. Manual edit is required after generation.

**Gap 2: No `--max-turns` in `claude_args`.** The default max-turns may be insufficient for a competitive intelligence scan that performs multiple WebSearch and WebFetch calls across several competitors. The `claude_args` field in the template only includes `--model`. Add `--max-turns 30` to ensure the agent has enough turns to complete a full scan of tiers 0 and 3.

**Gap 3: No duplicate issue guard.** Unlike `review-reminder.yml` which checks for existing open issues with `grep -cxF`, the template relies on `claude-code-action` to create the issue via the prompt. There is no mechanism to prevent duplicate issues if the cron fires while a previous run's issue is still open. For a monthly schedule, this is low risk but worth noting.

### CI Plugin Discovery

The generated workflow uses the marketplace pattern from the schedule skill learning:

```yaml
plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
plugins: 'soleur@soleur'
```

This requires `.claude-plugin/marketplace.json` at repo root (already exists at v3.7.0).

### Research Insights: claude-code-action Configuration

From the [claude-code-action usage docs](https://github.com/anthropics/claude-code-action/blob/main/docs/usage.md):

**Permissions:** The action documentation recommends `contents: read & write`, `issues: read & write`, and `pull-requests: read & write`. The schedule skill template generates only `contents: read` and `issues: write`. This may be insufficient -- `claude-code-action` may need write access to contents for its internal operation. Verify after first run; if the action fails with a permissions error, add `contents: write`.

**Mode auto-detection:** The action detects mode (PR review vs. automation) from the workflow trigger context. A `schedule`/`workflow_dispatch` trigger will put it in automation mode, which is correct for this use case.

**Authentication:** Only `anthropic_api_key` is needed. The `GITHUB_TOKEN` (available as `github.token`) is automatically used for issue creation when `issues: write` permission is declared.

### Prompt Customization

The schedule skill template's prompt includes:

```text
Run /soleur:competitive-analysis on this repository.
```

The skill needs to receive `--tiers 0,3` as arguments. The generated prompt must be manually edited to:

```text
Run /soleur:competitive-analysis --tiers 0,3 on this repository.
After your analysis is complete, create a GitHub issue titled
"[Scheduled] Competitive Analysis - <today's date in YYYY-MM-DD format>"
with the label "scheduled-competitive-analysis" summarizing your findings.
```

### Research Insights: Read-Only Checkout Assumption

**The original plan incorrectly assumed CI has a read-only checkout.** `actions/checkout` creates a full writable clone in the runner's workspace. The competitive-intelligence agent will successfully write `knowledge-base/overview/competitive-intelligence.md` to disk. However, without a `git push` step, the file is discarded when the job ends.

This means:
- The agent's fallback path ("output as code block instead") will NOT trigger
- The agent will write the file AND the prompt instructs issue creation
- Both the file write (ephemeral) and issue creation (persistent) will happen
- This is acceptable behavior -- the issue is the desired output

### No Plugin Version Bump

This change adds only a GitHub Actions workflow file (`.github/workflows/`), not a plugin change under `plugins/soleur/`. No version bump is required.

### Secret Prerequisite

`ANTHROPIC_API_KEY` must be set as a repository secret. Verify with:

```bash
gh secret list | grep ANTHROPIC_API_KEY
```

If missing, the workflow will fail with an auth error. This is a prerequisite, not a task for this plan.

### Research Insights: Security Patterns (from institutional learnings)

From `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`:

1. **SHA pinning** -- The schedule skill handles this via Step 2 (resolve action SHAs). Verify the generated workflow uses commit SHAs, not mutable tags. The existing `review-reminder.yml` uses `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` as reference.

2. **No `workflow_dispatch` inputs with date parsing** -- This workflow has no inputs (just bare `workflow_dispatch: {}`), so the `date -d` natural language injection risk does not apply.

3. **`gh issue create` exit code** -- The issue is created by `claude-code-action` via the prompt, not by a shell `run:` block. If the action fails to create the issue, the job will still show as successful (green checkmark). Monitor the first run manually and check that an issue was actually created.

From `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`:

4. **`$(date)` in `with:` blocks is literal** -- The schedule skill correctly uses natural language ("today's date in YYYY-MM-DD format") in the prompt. Do not "fix" this by adding shell expansion.

## Acceptance Criteria

- [x] `.github/workflows/scheduled-competitive-analysis.yml` exists with SHA-pinned actions
- [x] Workflow has both `schedule` (cron) and `workflow_dispatch` triggers
- [x] Cron expression is `0 9 1 * *` (monthly on the 1st at 09:00 UTC)
- [x] Workflow uses `plugin_marketplaces` and `plugins` for Soleur discovery
- [x] Prompt passes `--tiers 0,3` to the competitive-analysis skill
- [x] `claude_args` includes `--max-turns 30` for sufficient scan depth
- [x] YAML validates without syntax errors
- [ ] Manual `workflow_dispatch` trigger runs successfully
- [ ] Workflow run creates a GitHub Issue with competitive intelligence content
- [x] Concurrency group prevents overlapping runs
- [x] Actions are pinned to commit SHAs with human-readable version comments

## Test Scenarios

- Given the workflow file is merged to main, when `gh workflow run scheduled-competitive-analysis.yml` is executed, then the workflow starts and completes without error
- Given the workflow runs in CI, when the competitive-analysis skill executes, then it invokes the competitive-intelligence agent with `--tiers 0,3`
- Given the CI environment has a writable checkout, when the agent writes `competitive-intelligence.md`, then the file is written to disk (ephemeral) AND a GitHub Issue is created (persistent)
- Given a `scheduled-competitive-analysis` label does not exist, when the issue is created, then the label is auto-created by `gh issue create` (via the action's internal `gh` invocation)
- Given the cron fires on the 1st of the month, when no other run is in progress, then the workflow executes normally
- Given a previous run is still in progress, when the cron fires again, then the concurrency group queues (not cancels) the new run
- Given the `ANTHROPIC_API_KEY` secret is missing, when the workflow is triggered, then the job fails early with a clear authentication error
- Given the agent runs with `--max-turns 30`, when it researches tiers 0 and 3 with WebSearch and WebFetch, then it has enough turns to complete without premature termination

## Non-Goals

- Modifying the competitive-intelligence agent or competitive-analysis skill (tested as-is)
- Adding Slack/Discord notifications for completed scans (v2 of schedule skill)
- Carrying state between monthly runs (no cross-run persistence exists)
- Running all tiers (0-5) -- default `0,3` is sufficient for platform threat monitoring
- Adding a `git push` step to persist the `competitive-intelligence.md` file (the issue is the desired output)
- Adding duplicate issue prevention (monthly frequency makes collisions unlikely)

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `ANTHROPIC_API_KEY` secret missing | Low | Check with `gh secret list` before triggering |
| `claude-code-action` plugin discovery fails | Medium | Marketplace pattern proven in learning; verify on first run |
| Agent produces empty/malformed issue | Medium | Manual inspection after first run; iterate on prompt if needed |
| SHA resolution fails (network) | Low | Schedule skill blocks generation on failure; retry when online |
| GitHub Actions 15-min cron variance | N/A | Acceptable for monthly schedule; not a risk |
| Agent exhausts max-turns before completing scan | Medium | Set `--max-turns 30`; monitor first run and adjust if needed |
| Permissions insufficient for `claude-code-action` | Low | Start with `contents: read, issues: write`; add `contents: write` if action fails |
| Issue created but job shows green despite incomplete content | Medium | Manual review of first issue; add issue quality check in future iteration |

### Research Insights: Precedent Comparison

| Pattern | review-reminder.yml | scheduled-competitive-analysis.yml |
|---------|--------------------|------------------------------------|
| SHA pinning | Yes (`@11bd71...`) | Yes (generated by schedule skill) |
| Duplicate prevention | Yes (`grep -cxF`) | No (handled by monthly frequency) |
| Label pre-creation | Yes (`gh label create ... \|\| true`) | No (auto-created by `gh issue create`) |
| Date handling | Shell `$(date)` in `run:` block | Natural language in prompt `with:` field |
| Error handling | Explicit `exit 1` on failure | Delegated to `claude-code-action` |

## Implementation Steps

1. Run `/soleur:schedule create` with `--name competitive-analysis --skill competitive-analysis --cron "0 9 1 * *" --model claude-sonnet-4-6`
2. Verify the generated workflow file has SHA-pinned actions (not mutable tags)
3. Edit the prompt to include `--tiers 0,3` after `/soleur:competitive-analysis` if the template did not include it
4. Add `--max-turns 30` to the `claude_args` field
5. Validate YAML syntax
6. Commit and push to `feat/dogfood-competitive-intel`
7. Create PR targeting main
8. After merge, trigger `gh workflow run scheduled-competitive-analysis.yml`
9. Monitor the run via `gh run watch`
10. Verify the created GitHub Issue contains:
    - Executive summary of competitive landscape
    - Overlap matrix for tiers 0 and 3
    - Source URLs for claims
    - `scheduled-competitive-analysis` label

## References & Research

### Internal References

- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md`
- Competitive analysis skill: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Competitive intelligence agent: `plugins/soleur/agents/product/competitive-intelligence.md`
- Marketplace manifest: `.claude-plugin/marketplace.json`
- CI plugin discovery learning: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`
- Competitive intel implementation learning: `knowledge-base/learnings/2026-02-27-competitive-intelligence-agent-implementation.md`
- GitHub Actions security patterns: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Review reminder workflow (precedent): `.github/workflows/review-reminder.yml`
- Claude Code review workflow (existing): `.github/workflows/claude-code-review.yml`

### External References

- claude-code-action usage docs: https://github.com/anthropics/claude-code-action/blob/main/docs/usage.md
- claude-code-action setup docs: https://github.com/anthropics/claude-code-action/blob/main/docs/setup.md
- Claude Code GitHub Actions docs: https://code.claude.com/docs/en/github-actions

### Related PRs

- #332 -- competitive-intelligence agent and competitive-analysis skill (v3.7.0)
- #321 -- schedule skill (v3.5.0)

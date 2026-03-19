---
title: "fix(ci): migrate 7 agent workflows from direct push to PR-based commit pattern"
type: fix
date: 2026-03-19
semver: patch
---

# fix(ci): Migrate 7 Agent Workflows to PR-Based Commit Pattern

Closes #772

## Overview

Seven scheduled `claude-code-action` workflows instruct the agent to `git push origin main` in their prompt blocks. The CLA Required ruleset (ID 13304872) blocks `github-actions[bot]` from pushing directly to `main` -- this was discovered when `scheduled-content-publisher.yml` failed (fixed in PR #771). These 7 workflows have the identical vulnerability: they will fail at the commit step when the agent tries to push.

## Problem Statement

Each affected workflow contains a "MANDATORY FINAL STEP" prompt block like:

```bash
git add <paths>
git diff --cached --quiet && echo "unchanged, skipping" && exit 0
git commit -m "<message>"
git push origin main || { git pull --rebase origin main && git push origin main; }
```

This direct-push pattern cannot satisfy the CLA Required ruleset's `cla-check` status requirement. The push is rejected with a permission error, leaving generated content uncommitted.

Additionally, these workflows lack `pull-requests: write` and `statuses: write` permissions needed for the PR-based alternative.

## Affected Workflows

| # | Workflow File | Commit Pattern Location | `git add` Target |
|---|---|---|---|
| 1 | `scheduled-growth-audit.yml` | Prompt Step 6 (line ~133-137) | `knowledge-base/marketing/audits/soleur-ai/` |
| 2 | `scheduled-community-monitor.yml` | Prompt step 5 (line ~113-118) | `knowledge-base/support/community/` |
| 3 | `scheduled-seo-aeo-audit.yml` | Prompt final step (line ~68-74) | `git add -A` |
| 4 | `scheduled-campaign-calendar.yml` | Prompt final step (line ~57-63) | `knowledge-base/marketing/campaign-calendar.md` |
| 5 | `scheduled-content-generator.yml` | Prompt final step (line ~133-143) | `git add -A` |
| 6 | `scheduled-competitive-analysis.yml` | Prompt final step (line ~56-63) | `knowledge-base/product/competitive-intelligence.md` |
| 7 | `scheduled-growth-execution.yml` | Prompt final step (line ~82-89) | `git add -A` |

## Proposed Solution

Apply the same PR-based commit pattern proven in `scheduled-weekly-analytics.yml` (lines 89-114) and `scheduled-content-publisher.yml` (lines 72-98, PR #771).

### Two-Part Change Per Workflow

**Part A -- YAML permissions block:** Add `pull-requests: write` and `statuses: write` to the `permissions:` key.

**Part B -- Agent prompt replacement:** Replace the "MANDATORY FINAL STEP" `git push origin main` block in the claude-code-action prompt with the PR-based sequence.

### Critical Distinction: Prompt-Level vs Step-Level

The already-fixed workflows (`scheduled-weekly-analytics.yml`, `scheduled-content-publisher.yml`) use a **dedicated YAML step** with `run:` for the commit. The 7 affected workflows embed the commit instructions **inside the `prompt:` text** of the `claude-code-action` step. This means:

- The replacement must be written as natural language instructions inside `prompt:`, not as a YAML `run:` block
- The agent interprets and executes these instructions at runtime, not GitHub Actions
- The agent has access to `git`, `gh`, and the GitHub API via the Bash tool

### Reference Pattern (from scheduled-weekly-analytics.yml lines 89-114)

```yaml
- name: Create PR with snapshot
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add knowledge-base/marketing/analytics/
    git diff --cached --quiet && echo "No changes to commit" && exit 0
    BRANCH="ci/weekly-analytics-$(date -u +%Y-%m-%d)"
    git checkout -b "$BRANCH"
    git commit -m "ci: weekly analytics snapshot [skip ci]"
    git push -u origin "$BRANCH"
    SHA=$(git rev-parse HEAD)
    gh api "repos/${{ github.repository }}/statuses/$SHA" \
      -f state=success \
      -f context=cla-check \
      -f description="CLA not required for automated PRs"
    gh pr create \
      --title "ci: weekly analytics snapshot $(date -u +%Y-%m-%d)" \
      --body "Automated weekly analytics snapshot from Plausible API." \
      --base main \
      --head "$BRANCH"
    gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

### Adapted Prompt Pattern (to embed in claude-code-action prompts)

Since these 7 workflows use `claude-code-action` where the agent runs bash commands from a prompt, the replacement prompt block should look like:

```text
MANDATORY FINAL STEP -- persist via PR (do not push directly to main):
Run these bash commands:

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add <target-paths>
git diff --cached --quiet && echo "No changes to commit" && exit 0
BRANCH="ci/<workflow-slug>-$(date -u +%Y-%m-%d)"
git checkout -b "$BRANCH"
git commit -m "<commit-message> [skip ci]"
git push -u origin "$BRANCH"
SHA=$(git rev-parse HEAD)
gh api repos/${GITHUB_REPOSITORY}/statuses/$SHA \
  -f state=success \
  -f context=cla-check \
  -f description="CLA not required for automated PRs"
gh pr create \
  --title "<pr-title>" \
  --body "Automated commit from <workflow-name> workflow." \
  --base main \
  --head "$BRANCH"
gh pr merge "$BRANCH" --squash --auto || gh pr merge "$BRANCH" --squash
```

**Important:** Inside `claude-code-action` prompts, `${{ github.repository }}` is NOT available as a template expression. The agent must use the `GITHUB_REPOSITORY` environment variable (set by GitHub Actions in all runners) or discover the repository from `gh repo view --json nameWithOwner`. The `scheduled-weekly-analytics.yml` uses `${{ github.repository }}` because its commit step is a YAML `run:` block (template-expanded by Actions), not an agent prompt.

### Per-Workflow Specifics

| Workflow | Branch Prefix | Commit Message | git add Target |
|---|---|---|---|
| `scheduled-growth-audit.yml` | `ci/growth-audit-` | `docs: weekly growth audit <date>` | `knowledge-base/marketing/audits/soleur-ai/` |
| `scheduled-community-monitor.yml` | `ci/community-digest-` | `docs: daily community digest` | `knowledge-base/support/community/` |
| `scheduled-seo-aeo-audit.yml` | `ci/seo-aeo-audit-` | `fix(seo): weekly SEO/AEO audit fixes` | `-A` (all changes) |
| `scheduled-campaign-calendar.yml` | `ci/campaign-calendar-` | `ci: update campaign calendar [skip ci]` | `knowledge-base/marketing/campaign-calendar.md` |
| `scheduled-content-generator.yml` | `ci/content-gen-` | `feat(content): auto-generate article from SEO queue` | `-A` (all changes) |
| `scheduled-competitive-analysis.yml` | `ci/competitive-analysis-` | `docs: update competitive intelligence report` | `knowledge-base/product/competitive-intelligence.md` |
| `scheduled-growth-execution.yml` | `ci/growth-execution-` | `fix(growth): biweekly keyword optimization` | `-A` (all changes) |

### Additional Prompt Changes

1. **Remove the "authorized to push to main" override.** Each workflow currently starts with:
   ```
   IMPORTANT: This is an automated CI workflow. The AGENTS.md rule
   "Never commit directly to main" does NOT apply here. You are
   explicitly authorized to commit and push to main in this context.
   ```
   Replace with:
   ```
   IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.
   Use the PR-based commit pattern in the MANDATORY FINAL STEP.
   ```

2. **Remove the "(do not skip, do not create a branch)" instruction** -- the new pattern explicitly creates a branch.

## Technical Considerations

### Environment Variable Availability

- `GITHUB_REPOSITORY` is set by GitHub Actions in all jobs (format: `owner/repo`)
- `GH_TOKEN` must be set in the `env:` of the `claude-code-action` step (some workflows already have it, some don't) -- verify each
- The `gh api` command uses `GH_TOKEN` automatically when set

### GH_TOKEN Propagation to Agent

The `claude-code-action` agent inherits environment variables set in the step's `env:` block. For the `gh` CLI and `gh api` commands to work inside the agent, `GH_TOKEN: ${{ github.token }}` must be present. Check each workflow:

| Workflow | Has GH_TOKEN in claude-code-action env? |
|---|---|
| `scheduled-growth-audit.yml` | No -- needs adding |
| `scheduled-community-monitor.yml` | No -- needs adding |
| `scheduled-seo-aeo-audit.yml` | No -- needs adding |
| `scheduled-campaign-calendar.yml` | No -- needs adding |
| `scheduled-content-generator.yml` | No -- needs adding |
| `scheduled-competitive-analysis.yml` | No -- needs adding |
| `scheduled-growth-execution.yml` | No -- needs adding |

All 7 need `GH_TOKEN: ${{ github.token }}` added to the `claude-code-action` step's `env:` block. Without it, `gh api` and `gh pr create` / `gh pr merge` will fail with authentication errors.

### Concurrency Races

Branch names include the date (`ci/<slug>-$(date -u +%Y-%m-%d)`). For workflows that might run multiple times per day (via `workflow_dispatch`), add a timestamp suffix: `ci/<slug>-$(date -u +%Y-%m-%d-%H%M%S)`. The `concurrency` group already prevents parallel runs, so collisions are unlikely but the timestamp makes it defensive.

### Content Generator Dual Commit Message

`scheduled-content-generator.yml` uses a conditional commit message based on which path was taken (queue item vs growth plan). The prompt replacement must preserve this conditional logic.

### SEO Audit Uses Older Action SHA

`scheduled-seo-aeo-audit.yml` and others use `@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1 tag) while newer workflows use `@1dd74842e568f373608605d9e45c9e854f65f543` (v1.0.63). This is out of scope for this PR but worth noting.

## Acceptance Criteria

- [ ] All 7 workflows have `pull-requests: write` and `statuses: write` in their `permissions:` block
- [ ] All 7 workflows replace `git push origin main` prompt instructions with the PR-based commit pattern
- [ ] All 7 workflows have `GH_TOKEN: ${{ github.token }}` in the `claude-code-action` step's `env:` block
- [ ] The "authorized to push to main" prompt override is replaced with "do not push directly" guidance
- [ ] Branch names use date-based slugs with the workflow's unique prefix
- [ ] CLA synthetic status is set before PR creation
- [ ] Auto-merge is queued with squash strategy
- [ ] `scheduled-content-generator.yml` preserves its conditional commit message logic
- [ ] No other prompt instructions are changed (only the commit/push section)

## Test Scenarios

- Given a workflow with `git push origin main` in its prompt, when the PR is merged, then the prompt should contain the PR-based commit sequence instead
- Given any of the 7 workflows, when the permissions block is inspected, then `pull-requests: write` and `statuses: write` should be present
- Given the `scheduled-content-generator.yml`, when the commit section is inspected, then both conditional commit messages (queue path and growth plan path) should be preserved
- Given the CLA Required ruleset is active, when any workflow's agent runs the PR-based commit step, then the PR should be auto-merged (CLA check satisfied by synthetic status)
- Given no changes to commit (empty diff), when the agent runs the commit step, then it should echo "No changes" and exit cleanly

## Pre-Existing Issues (Out of Scope)

- `post-merge-monitor.yml` (line 171) also uses `git push origin main` for revert operations -- this is a different pattern (emergency revert, not content commit) and should be tracked separately
- Action SHA pinning inconsistency across workflows (some on v1.0.63, some on v1)
- CLA integration lacks app-ID restrictions (tracked in #773)

## References

- PR #771: [fix(ci): use PR-based commit pattern in content publisher workflow](https://github.com/jikig-ai/soleur/pull/771)
- Issue #772: [fix(ci): migrate 7 agent workflows from direct push to PR-based commit pattern](https://github.com/jikig-ai/soleur/issues/772)
- Learning: [`knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`](../../knowledge-base/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md)
- Reference pattern: `scheduled-weekly-analytics.yml` lines 89-114
- Reference pattern: `scheduled-content-publisher.yml` lines 72-98

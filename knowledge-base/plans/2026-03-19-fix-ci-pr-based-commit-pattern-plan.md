---
title: "fix(ci): migrate 7 agent workflows from direct push to PR-based commit pattern"
type: fix
date: 2026-03-19
semver: patch
---

# fix(ci): Migrate 7 Agent Workflows to PR-Based Commit Pattern

Closes #772

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 4 (Technical Considerations, Adapted Prompt Pattern, Acceptance Criteria, Test Scenarios)
**Research sources:** SpecFlow edge-case analysis, institutional learnings (CLA push rejection, security reminder hook), cross-workflow pattern audit

### Key Improvements

1. **Branch name collision prevention**: Changed from date-only to date+timestamp format (`%Y-%m-%d-%H%M%S`) for all 7 workflows, preventing failures on repeated `workflow_dispatch` runs
2. **`gh` CLI authentication gap**: Confirmed all 7 workflows lack `GH_TOKEN` in `claude-code-action` `env:` -- the `gh api`, `gh pr create`, and `gh pr merge` commands will silently fail without it since `claude-code-action` does not auto-inject `GITHUB_TOKEN`
3. **`GITHUB_REPOSITORY` availability verified**: The `GITHUB_REPOSITORY` env var IS available inside `claude-code-action` agent shells (inherited from the GitHub Actions runner environment), so the prompt pattern using `${GITHUB_REPOSITORY}` is correct
4. **Security reminder hook warning**: Editing `.github/workflows/*.yml` triggers a PreToolUse advisory hook -- the implementer should expect this and verify edits applied (learning: `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`)

### New Edge Cases Discovered

- **Stale branch from prior failed run**: If a previous run created the branch but failed before auto-merge, `git checkout -b` will fail on retry. Mitigation: use timestamp suffix to guarantee unique branch names
- **Auto-merge not enabled on repo**: The `gh pr merge --squash --auto` fallback (`|| gh pr merge --squash`) forces immediate merge, which requires all checks to have already passed. If checks are pending, both commands fail. The existing reference patterns (`scheduled-weekly-analytics.yml`, `scheduled-content-publisher.yml`) use this same fallback, so this is accepted behavior
- **`id-token: write` permission**: All 7 workflows already have `id-token: write` (required for `claude-code-action` OIDC auth) -- no change needed for this permission

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
BRANCH="ci/<workflow-slug>-$(date -u +%Y-%m-%d-%H%M%S)"
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

**Important notes:**

1. Inside `claude-code-action` prompts, `${{ github.repository }}` is NOT available as a template expression. The agent must use the `GITHUB_REPOSITORY` environment variable (set by GitHub Actions in all runners and inherited by the agent's shell). The `scheduled-weekly-analytics.yml` uses `${{ github.repository }}` because its commit step is a YAML `run:` block (template-expanded by Actions), not an agent prompt.

2. Branch names use `%H%M%S` timestamp suffix (not just `%Y-%m-%d`) to prevent collisions when a workflow is triggered multiple times in the same day via `workflow_dispatch`. The concurrency group prevents parallel runs but does not prevent sequential runs that reuse the same date-based branch name.

3. The `gh` CLI commands (`gh api`, `gh pr create`, `gh pr merge`) require `GH_TOKEN` to be explicitly set in the `claude-code-action` step's `env:` block. Unlike regular `run:` steps which inherit `GITHUB_TOKEN` automatically, `claude-code-action` only passes through explicitly declared environment variables.

### Per-Workflow Specifics

| Workflow | Branch Pattern | Commit Message | git add Target |
|---|---|---|---|
| `scheduled-growth-audit.yml` | `ci/growth-audit-<timestamp>` | `docs: weekly growth audit <date> [skip ci]` | `knowledge-base/marketing/audits/soleur-ai/` |
| `scheduled-community-monitor.yml` | `ci/community-digest-<timestamp>` | `docs: daily community digest [skip ci]` | `knowledge-base/support/community/` |
| `scheduled-seo-aeo-audit.yml` | `ci/seo-aeo-audit-<timestamp>` | `fix(seo): weekly SEO/AEO audit fixes [skip ci]` | `-A` (all changes) |
| `scheduled-campaign-calendar.yml` | `ci/campaign-calendar-<timestamp>` | `ci: update campaign calendar [skip ci]` | `knowledge-base/marketing/campaign-calendar.md` |
| `scheduled-content-generator.yml` | `ci/content-gen-<timestamp>` | `feat(content): auto-generate article from SEO queue [skip ci]` (conditional) | `-A` (all changes) |
| `scheduled-competitive-analysis.yml` | `ci/competitive-analysis-<timestamp>` | `docs: update competitive intelligence report [skip ci]` | `knowledge-base/product/competitive-intelligence.md` |
| `scheduled-growth-execution.yml` | `ci/growth-execution-<timestamp>` | `fix(growth): biweekly keyword optimization [skip ci]` | `-A` (all changes) |

Where `<timestamp>` = `$(date -u +%Y-%m-%d-%H%M%S)` and `<date>` = `$(date -u +%Y-%m-%d)`.

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

All branch names use the full timestamp format `ci/<slug>-$(date -u +%Y-%m-%d-%H%M%S)` to guarantee uniqueness. Although the `concurrency` group prevents parallel runs, sequential `workflow_dispatch` triggers on the same day would collide on date-only branch names. An additional concern: if a prior run created a branch that failed before auto-merge cleaned it up, `git checkout -b` would fail with "branch already exists." The timestamp suffix eliminates both failure modes.

### Content Generator Dual Commit Message

`scheduled-content-generator.yml` uses a conditional commit message based on which path was taken (queue item vs growth plan). The prompt replacement must preserve this conditional logic.

### SEO Audit Uses Older Action SHA

`scheduled-seo-aeo-audit.yml` and others use `@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1 tag) while newer workflows use `@1dd74842e568f373608605d9e45c9e854f65f543` (v1.0.63). This is out of scope for this PR but worth noting.

### Implementation Warning: Security Reminder Hook

Editing `.github/workflows/*.yml` files triggers the `PreToolUse:Edit` hook (`security_reminder_hook.py`). This hook emits an advisory warning about GitHub Actions injection patterns. It does NOT block the edit, but its error-formatted output can cause the Edit tool to appear to fail. After each workflow file edit, re-read the file to confirm the edit applied. See learning: `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`.

### Ordering of Operations in the Prompt Pattern

The PR-based sequence has a strict ordering dependency:

1. `git push -u origin "$BRANCH"` -- branch must exist on remote before status can be set
2. `gh api .../statuses/$SHA` -- CLA status must be set before PR creation so the ruleset evaluates it
3. `gh pr create` -- PR must exist before auto-merge can be queued
4. `gh pr merge --squash --auto` -- must be last; the `|| gh pr merge --squash` fallback handles the case where auto-merge is already enabled or all checks already passed

If any step fails, subsequent steps will also fail. The agent should treat any non-zero exit from these commands as a workflow failure (the existing `claude-code-action` step will report failure to the workflow).

## Acceptance Criteria

- [x] All 7 workflows have `pull-requests: write` and `statuses: write` in their `permissions:` block
- [x] All 7 workflows replace `git push origin main` prompt instructions with the PR-based commit pattern
- [x] All 7 workflows have `GH_TOKEN: ${{ github.token }}` in the `claude-code-action` step's `env:` block
- [x] The "authorized to push to main" prompt override is replaced with "do not push directly" guidance
- [x] Branch names use timestamp format (`%Y-%m-%d-%H%M%S`) with the workflow's unique prefix
- [x] The `gh api` call uses `${GITHUB_REPOSITORY}` (not `${{ github.repository }}`) since it runs inside agent prompts
- [x] CLA synthetic status is set before PR creation (ordering: push, status, PR, merge)
- [x] Auto-merge is queued with squash strategy and fallback to immediate merge
- [x] `scheduled-content-generator.yml` preserves its conditional commit message logic
- [x] All commit messages include `[skip ci]` suffix to prevent recursive workflow triggers
- [x] No other prompt instructions are changed (only the authorization notice and commit/push section)
- [x] Grep confirms zero remaining `git push origin main` matches across all 7 files

## Test Scenarios

### Static Validation (pre-merge)

- Given a workflow with `git push origin main` in its prompt, when the PR is merged, then the prompt should contain the PR-based commit sequence instead
- Given any of the 7 workflows, when the permissions block is inspected, then `pull-requests: write` and `statuses: write` should be present
- Given any of the 7 workflows, when the `claude-code-action` step is inspected, then `GH_TOKEN: ${{ github.token }}` should be in its `env:` block
- Given the `scheduled-content-generator.yml`, when the commit section is inspected, then both conditional commit messages (queue path and growth plan path) should be preserved
- Given any of the 7 workflows, when the branch name in the prompt is inspected, then it should include `%H%M%S` timestamp (not just `%Y-%m-%d`)
- Given any of the 7 workflows, when the prompt authorization notice is inspected, then it should say "Do NOT push directly to main" (not "authorized to push to main")

### Runtime Validation (post-merge, manual dispatch)

- Given the CLA Required ruleset is active, when any workflow's agent runs the PR-based commit step, then the PR should be auto-merged (CLA check satisfied by synthetic status)
- Given no changes to commit (empty diff), when the agent runs the commit step, then it should echo "No changes" and exit cleanly without creating a branch or PR
- Given a workflow is dispatched twice in the same day, when the second run reaches the commit step, then it should create a distinct branch (no collision with the first run's branch)

### Regression

- Given the `scheduled-growth-audit.yml` prompt, when the agent finishes Steps 1-5, then the final step should still create a GitHub Issue before committing (Step 5 must precede the commit step)
- Given the `scheduled-community-monitor.yml` prompt, when the agent finishes collecting data, then it should still create the GitHub Issue in step 6 before the commit step

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

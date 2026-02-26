---
title: feat: Agent Scheduling via GitHub Actions
type: feat
date: 2026-02-26
---

# feat: Agent Scheduling via GitHub Actions

## Overview

Create a `soleur:schedule` skill that generates GitHub Actions workflow files for scheduling Soleur skill invocations on recurring cron schedules. Each schedule becomes a standalone `.github/workflows/scheduled-<name>.yml` using `claude-code-action`. Output is flexible per schedule (issues, PRs, or Discord notifications).

## Problem Statement / Motivation

Claude Code plugins have no scheduling mechanism. All invocations are user-initiated. Users who want recurring automation (security audits, content generation, repo maintenance) must manually craft GitHub Actions workflows — requiring CI expertise, knowledge of `claude-code-action` configuration, proper permission scoping, and SHA pinning. This feature provides an interactive skill that handles the complexity.

Related: #312

## Proposed Solution

A single skill (`soleur:schedule`) with a supporting bash script (`schedule-manager.sh`), following the `git-worktree` skill pattern. The bash script handles YAML generation and workflow management; the SKILL.md handles interactive input collection and subcommand routing.

### Architecture

```
User -> /soleur:schedule create -> SKILL.md interactive Q&A -> schedule-manager.sh generate -> .yml file

GitHub Actions cron -> scheduled-<name>.yml -> claude-code-action -> Skill -> Output routing

User -> /soleur:schedule list    -> schedule-manager.sh list   -> formatted table
User -> /soleur:schedule delete  -> schedule-manager.sh delete -> remove .yml
User -> /soleur:schedule run     -> schedule-manager.sh run    -> gh workflow run
```

### Scope Decisions (from SpecFlow analysis)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent vs. skill invocation | **Skills only for v1** | Skills are reliably invocable via `/soleur:<name>` in prompts. Agents are LLM-routed by description — unreliable for unattended cron execution. Agent support deferred to v2. |
| `update` subcommand | **Deferred (v2)** | YAGNI. Users can hand-edit the generated YAML. Delete + recreate is available. |
| Auto-commit/push on create | **No** | Write file and inform user. The workflow only activates on the default branch, so auto-pushing from a feature branch doesn't help. User decides when to merge. |
| State across runs | **Out of scope** | Each run is stateless. Document as known limitation. |
| Minimum cron interval | **Warn < 1 hour, block < 5 minutes** | Lightweight cost protection without formal budget controls. |
| Concurrency groups | **Yes** | Prevent overlapping runs of the same schedule. `cancel-in-progress: false` to queue rather than cancel. |
| Failure notification | **Yes** | `if: failure()` step that creates a GitHub issue with the run URL. |
| Secret validation | **Warn, don't block** | Check `gh secret list` during `create` and warn if `ANTHROPIC_API_KEY` is missing. |
| Degraded `list` | **File-only view** | Show name, cron, skill, output mode from YAML parsing. Add run status column if `gh` is authenticated. |
| Workflow file name | **User-provided during `create`** | Validated: lowercase, hyphens only, no collisions. |

## Technical Considerations

### Generated Workflow Template

Each generated `.github/workflows/scheduled-<name>.yml` includes:

```yaml
name: "Scheduled: <display-name>"

on:
  schedule:
    - cron: '<cron-expression>'
  workflow_dispatch: {}

concurrency:
  group: schedule-<name>
  cancel-in-progress: false

permissions:
  # Varies by output mode (see below)

jobs:
  run-schedule:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<SHA>  # Pinned

      - name: Run scheduled skill
        uses: anthropics/claude-code-action@<SHA>  # Pinned
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: '<generated prompt based on skill + output mode>'

      # Output-mode specific steps (issue/pr/discord)

      - name: Notify on failure
        if: failure()
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh issue create \
            --title "[Scheduled] <name> failed - $(date +%Y-%m-%d)" \
            --body "..." \
            --label "scheduled-failure"
```

### Permissions by Output Mode

| Mode | Permissions |
|------|------------|
| `issue` | `contents: read`, `issues: write` |
| `pr` | `contents: write`, `pull-requests: write` |
| `discord` | `contents: read` |
| All modes (failure step) | `+ issues: write` |

### Prompt Templates by Output Mode

**Issue mode:**
```
Run /soleur:<skill> on this repository. After analysis, create a GitHub issue titled
"[Scheduled] <name> - <date>" with label "scheduled-<name>" summarizing your findings.
```

**PR mode:**
```
Run /soleur:<skill> on this repository. Create a branch named
"scheduled/<name>/<date>" for any changes. If changes were made, open a draft PR
titled "[Scheduled] <name> - <date>". If no changes needed, create an issue
reporting "no changes required."
```

**Discord mode:**
```
Run /soleur:<skill> on this repository. After analysis, post a summary to Discord
using: curl -H "Content-Type: application/json" -d '{"content": "<your summary>",
"username": "Soleur Scheduler"}' "$DISCORD_WEBHOOK_URL"
```

### SHA Pinning Strategy

The bash script resolves the current SHA for `anthropics/claude-code-action@v1` and `actions/checkout@v4` at generation time using `gh api`:

```bash
gh api repos/anthropics/claude-code-action/git/ref/tags/v1 --jq '.object.sha'
gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
```

The resolved SHAs are embedded in the generated YAML with a comment showing the tag:

```yaml
uses: anthropics/claude-code-action@abc123def456 # v1
```

### Cron Validation

The bash script validates cron expressions:
1. Must have exactly 5 space-separated fields
2. Each field must contain only valid characters (`0-9`, `*`, `/`, `-`, `,`)
3. Ranges must be within valid bounds (minutes: 0-59, hours: 0-23, etc.)
4. Warn if effective interval < 1 hour
5. Block if effective interval < 5 minutes

### Plugin Discovery in CI

`claude-code-action` checks out the repository and runs Claude Code from the repo root. The Soleur plugin at `plugins/soleur/` should be auto-discovered via the `.claude/plugins.json` configuration. This needs to be verified during implementation — if auto-discovery doesn't work, the generated workflow will need explicit `plugin_marketplaces` or plugin path configuration.

## Acceptance Criteria

- [ ] `soleur:schedule create` interactively collects skill, cron, output mode, model and generates valid workflow YAML
- [ ] `soleur:schedule list` displays all `scheduled-*.yml` with name, cron, skill, output mode
- [ ] `soleur:schedule delete <name>` removes the workflow file with confirmation
- [ ] `soleur:schedule run <name>` triggers `gh workflow run` for the specified schedule
- [ ] Generated workflows include proper SHA pinning, permissions, concurrency groups, and failure notification
- [ ] Cron expressions are validated before generation (syntax + minimum interval)
- [ ] Missing `ANTHROPIC_API_KEY` secret produces a warning during `create`
- [ ] All three output modes (issue, PR, Discord) produce correct workflow templates
- [ ] Skill is registered in docs data files and version is bumped

## Test Scenarios

- Given a user runs `soleur:schedule create`, when they provide valid inputs (skill: `legal-audit`, cron: `0 9 * * MON`, mode: `issue`, model: `sonnet`), then a valid `.github/workflows/scheduled-legal-audit.yml` is generated with correct cron, permissions, and prompt
- Given a user provides cron `* * * * *`, when the script validates it, then it blocks with "minimum interval is 5 minutes"
- Given a user provides cron `0 */2 * * *`, when the script validates it, then it passes (2-hour interval)
- Given `scheduled-audit.yml` exists, when `soleur:schedule list` runs, then it displays the schedule in a formatted table
- Given `scheduled-audit.yml` exists, when `soleur:schedule delete audit` runs with confirmation, then the file is removed
- Given `scheduled-audit.yml` exists on the default branch, when `soleur:schedule run audit` runs, then `gh workflow run` is invoked

## Dependencies & Risks

**Dependencies:**
- `claude-code-action` must support running Soleur plugin skills from a checked-out repo
- `ANTHROPIC_API_KEY` must be configured as a repository secret
- `DISCORD_WEBHOOK_URL` secret needed for discord output mode

**Risks:**
- `claude-code-action` plugin discovery may not auto-detect Soleur from the repo — mitigation: verify empirically, add explicit config if needed
- Bash YAML templating is fragile — mitigation: use heredocs with proper quoting, test generated YAML with `yq` validation
- GitHub Actions cron has ~15 min variance — mitigation: document this limitation
- Long-running scheduled skills may overlap — mitigation: concurrency groups with queue behavior

## File Inventory

| File | Action | Purpose |
|------|--------|---------|
| `plugins/soleur/skills/schedule/SKILL.md` | Create | Skill definition with subcommand docs |
| `plugins/soleur/skills/schedule/scripts/schedule-manager.sh` | Create | Bash script: generate, list, delete, run, validate |
| `plugins/soleur/docs/_data/skills.js` | Edit | Register skill in SKILL_CATEGORIES |
| `plugins/soleur/.claude-plugin/plugin.json` | Edit | MINOR version bump |
| `plugins/soleur/CHANGELOG.md` | Edit | Document new skill |
| `plugins/soleur/README.md` | Edit | Update skill count |
| Root `README.md` | Edit | Update version badge |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Edit | Update version placeholder |

## References & Research

### Internal References
- Cron workflow pattern: `.github/workflows/review-reminder.yml`
- claude-code-action usage: `.github/workflows/claude-code-review.yml`
- Discord webhook pattern: `.github/workflows/auto-release.yml`
- Bash subcommand skill pattern: `plugins/soleur/skills/git-worktree/SKILL.md`
- Skill creation lifecycle: `knowledge-base/learnings/implementation-patterns/2026-02-22-new-skill-creation-lifecycle.md`
- GitHub Actions security: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Workflow cascade limitation: `knowledge-base/learnings/integration-issues/github-actions-auto-release-permissions.md`
- Extract $() to scripts: `knowledge-base/learnings/2026-02-24-extract-command-substitution-into-scripts.md`
- Merge-pr skill design lessons: `knowledge-base/learnings/2026-02-22-merge-pr-skill-design-lessons.md`

### Related Work
- Issue: #312
- Brainstorm: `knowledge-base/brainstorms/2026-02-26-agent-scheduling-brainstorm.md`
- Spec: `knowledge-base/specs/feat-agent-scheduling/spec.md`

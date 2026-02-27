---
title: feat: Agent Scheduling via GitHub Actions
type: feat
date: 2026-02-26
---

# feat: Agent Scheduling via GitHub Actions

[Updated 2026-02-26 — simplified after plan review: removed bash script, scoped to issue-only output, cut run/secret-validation/interval-computation]

## Overview

Create a `soleur:schedule` skill that generates GitHub Actions workflow files for scheduling Soleur skill invocations on recurring cron schedules. Each schedule becomes a standalone `.github/workflows/scheduled-<name>.yml` using `claude-code-action` with issue-based output.

## Problem Statement / Motivation

Claude Code plugins have no scheduling mechanism. All invocations are user-initiated. Users who want recurring automation (security audits, content generation, repo maintenance) must manually craft GitHub Actions workflows — requiring CI expertise, knowledge of `claude-code-action` configuration, proper permission scoping, and SHA pinning. This feature provides an interactive skill that handles the complexity.

Related: #312

## Proposed Solution

A single SKILL.md file (`soleur:schedule`) with no bash script. The YAML workflow template lives directly in SKILL.md as a code block. The LLM fills in placeholders during the interactive `create` flow and writes the file. No intermediate script layer — the LLM handles string interpolation, validation, and file I/O natively.

### Architecture

```
User -> /soleur:schedule create -> SKILL.md interactive Q&A -> LLM writes .yml file

GitHub Actions cron -> scheduled-<name>.yml -> claude-code-action -> Skill -> GitHub Issue

User -> /soleur:schedule list   -> LLM globs + greps scheduled-*.yml -> formatted output
User -> /soleur:schedule delete -> LLM removes .yml file after confirmation
```

### Scope Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent vs. skill invocation | **Skills only for v1** | Skills are reliably invocable via `/soleur:<name>` in prompts. Agents are LLM-routed by description — unreliable for unattended cron execution. |
| Output mode | **Issue only for v1** | Simplest permissions model. PR mode has branching conflicts with `claude-code-action`. Discord requires external secret + fragile curl-in-prompt. Both deferred to v2. |
| Implementation | **SKILL.md only, no bash script** | YAML generation is string interpolation. The LLM handles it natively. A bash heredoc template adds quoting hazards and a layer of indirection for no gain. |
| `update` subcommand | **Deferred (v2)** | YAGNI. Users can hand-edit the generated YAML. |
| `run` subcommand | **Deferred (v2)** | Wraps `gh workflow run` — a one-liner. Documented as a tip in SKILL.md. |
| Auto-commit/push on create | **No** | Write file and inform user. Workflow only activates on the default branch. |
| State across runs | **Out of scope** | Each run is stateless. Document as known limitation. |
| Cron validation | **Basic syntax check by LLM** | Validate 5-field format and warn if frequency > hourly. No bash cron parser — GitHub Actions rejects invalid cron at push time. |
| Concurrency groups | **Yes** | Prevent overlapping runs. Note: `cancel-in-progress: false` allows one pending run, not a true queue. |
| Failure notification | **Yes** | `if: failure()` step creates a GitHub issue. Prevents silent failures. |
| Secret validation | **Document, don't check** | `gh secret list` returns nothing for non-admin users → false warnings. Document `ANTHROPIC_API_KEY` as prerequisite instead. |
| SHA pinning | **LLM resolves at create time** | Two `gh api` commands during create flow. Two-step resolution for annotated tags (tag object → commit SHA). |

## Technical Considerations

### Prerequisite: Marketplace Support (RESOLVED)

`claude-code-action` does NOT auto-discover local plugins. Plugins must be installed from registered marketplaces via `plugins` + `plugin_marketplaces` inputs. The Soleur plugin is not published to any external marketplace.

**Solution:** Added `.claude-plugin/marketplace.json` at the repo root, making the repo itself a self-hosting marketplace. The generated workflow uses:

```yaml
plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
plugins: 'soleur@soleur'
```

This enables `claude-code-action` to install the Soleur plugin from the checked-out repo's marketplace definition, making all `/soleur:` skills available in CI.

### Generated Workflow Template

The SKILL.md contains this template with `<PLACEHOLDER>` markers:

```yaml
name: "Scheduled: <DISPLAY_NAME>"

on:
  schedule:
    - cron: '<CRON_EXPRESSION>'
  workflow_dispatch: {}

concurrency:
  group: schedule-<NAME>
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  run-schedule:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@<CHECKOUT_SHA> # v4

      - name: Run scheduled skill
        uses: anthropics/claude-code-action@<ACTION_SHA> # v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
          plugins: 'soleur@soleur'
          claude_args: '--model <MODEL>'
          prompt: |
            Run /soleur:<SKILL_NAME> on this repository.
            After analysis, create a GitHub issue titled
            "[Scheduled] <DISPLAY_NAME> - $(date +%Y-%m-%d)"
            with label "scheduled-<NAME>" summarizing your findings.

      - name: Notify on failure
        if: failure()
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "scheduled-failure" --color "B60205" \
            --description "Scheduled workflow failure" 2>/dev/null || true
          gh issue create \
            --title "[Scheduled] <NAME> failed - $(date +%Y-%m-%d)" \
            --body "Workflow run failed. See: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            --label "scheduled-failure"
```

### SHA Pinning — Two-Step Resolution for Annotated Tags

During `create`, the LLM resolves SHAs with:

```bash
# Step 1: Get the ref
REF_JSON=$(gh api repos/anthropics/claude-code-action/git/ref/tags/v1)
TYPE=$(echo "$REF_JSON" | jq -r '.object.type')
SHA=$(echo "$REF_JSON" | jq -r '.object.sha')

# Step 2: If annotated tag, dereference to commit
if [ "$TYPE" = "tag" ]; then
  SHA=$(gh api "repos/anthropics/claude-code-action/git/tags/$SHA" --jq '.object.sha')
fi
echo "claude-code-action SHA: $SHA"
```

Same two-step process for `actions/checkout@v4`. The resolved SHAs are embedded in the generated YAML with tag comments for readability.

### Cron Validation Rules (Natural Language in SKILL.md)

The SKILL.md instructs the LLM to:
1. Verify the expression has exactly 5 space-separated fields
2. Verify each field contains only valid characters: `0-9`, `*`, `/`, `-`, `,`
3. Reject named values (`MON`, `JAN`) — GitHub Actions POSIX cron does not support them
4. Warn the user if the schedule runs more frequently than hourly
5. Reject anything more frequent than every 5 minutes
6. Note that GitHub Actions cron has ~15-minute variance

### Concurrency Limitation

`cancel-in-progress: false` allows only one pending run to wait. If a third run triggers while one is running and one is pending, the pending run is replaced (not queued). This is a GitHub Actions limitation, not a true queue. Documented in SKILL.md as a known limitation.

## Acceptance Criteria

- [ ] `soleur:schedule create` interactively collects skill name, cron expression, schedule name, and model, then generates valid workflow YAML with SHA-pinned actions, permissions, concurrency group, and failure notification
- [ ] `soleur:schedule list` displays existing `scheduled-*.yml` with name, cron, skill from YAML parsing
- [ ] `soleur:schedule delete <name>` removes the workflow file with confirmation
- [ ] Generated YAML is valid GitHub Actions syntax
- [ ] Cron expressions are validated (5-field format, frequency guard)
- [ ] Skill is registered in docs data files and version is bumped
- [ ] `plugin.json` description count is updated

## Test Scenarios

- Given a user runs `soleur:schedule create`, when they provide valid inputs (skill: `legal-audit`, cron: `0 9 * * 1`, name: `weekly-legal-audit`, model: `sonnet`), then a valid `.github/workflows/scheduled-weekly-legal-audit.yml` is generated with correct cron, permissions, SHA-pinned actions, and issue-mode prompt
- Given a user provides cron `* * * * *`, when the LLM validates it, then it rejects with "minimum interval is 5 minutes"
- Given a user provides cron `MON` in the day-of-week field, when the LLM validates it, then it rejects with "use numeric values (0-6), not names"
- Given `scheduled-audit.yml` exists, when `soleur:schedule list` runs, then it displays the schedule name, cron, skill, and output mode
- Given `scheduled-audit.yml` exists, when `soleur:schedule delete audit` runs with confirmation, then the file is removed

## Dependencies & Risks

**Dependencies:**
- `claude-code-action` must support running Soleur plugin skills from a checked-out repo (spike required)
- `ANTHROPIC_API_KEY` must be configured as a repository secret

**Risks:**
- `claude-code-action` plugin discovery may not auto-detect Soleur — mitigation: spike before implementation, design fallback path
- GitHub Actions cron has ~15 min variance — mitigation: document limitation
- Long-running skills may overlap — mitigation: concurrency groups (with documented queue limitation)

## File Inventory

| File | Action | Purpose |
|------|--------|---------|
| `.claude-plugin/marketplace.json` | Create | Makes repo a self-hosting plugin marketplace for CI |
| `plugins/soleur/skills/schedule/SKILL.md` | Create | Skill definition with template, create/list/delete flows |
| `plugins/soleur/docs/_data/skills.js` | Edit | Register skill in SKILL_CATEGORIES |
| `plugins/soleur/.claude-plugin/plugin.json` | Edit | MINOR version bump + description count |
| `plugins/soleur/CHANGELOG.md` | Edit | Document new skill |
| `plugins/soleur/README.md` | Edit | Update skill count |
| Root `README.md` | Edit | Update version badge |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Edit | Update version placeholder |

## v2 Roadmap (Deferred)

- PR output mode (with `claude-code-action` branching integration)
- Discord output mode (with `jq`-based payload construction)
- `run` subcommand (manual trigger via `gh workflow run`)
- `update` subcommand (modify cron/model/output without delete+recreate)
- `list` run-status column (from `gh run list`)
- Agent invocation support (prompt engineering for LLM-routed agents)
- State across runs (for incremental analysis)

## References & Research

### Internal References
- Cron workflow pattern: `.github/workflows/review-reminder.yml`
- claude-code-action usage: `.github/workflows/claude-code-review.yml`
- Discord webhook pattern: `.github/workflows/auto-release.yml`
- Skill creation lifecycle: `knowledge-base/learnings/implementation-patterns/2026-02-22-new-skill-creation-lifecycle.md`
- GitHub Actions security: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Workflow cascade limitation: `knowledge-base/learnings/integration-issues/github-actions-auto-release-permissions.md`
- Merge-pr skill design lessons: `knowledge-base/learnings/2026-02-22-merge-pr-skill-design-lessons.md`

### Related Work
- Issue: #312
- Brainstorm: `knowledge-base/brainstorms/2026-02-26-agent-scheduling-brainstorm.md`
- Spec: `knowledge-base/specs/feat-agent-scheduling/spec.md`

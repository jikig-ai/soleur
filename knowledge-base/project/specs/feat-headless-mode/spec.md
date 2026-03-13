# Headless Mode for Repeatable Workflows

**Issue:** #393
**Branch:** feat-headless-mode
**Brainstorm:** `knowledge-base/brainstorms/2026-03-03-headless-mode-brainstorm.md`

## Problem Statement

Soleur skills require interactive confirmation (AskUserQuestion) for routine operations, preventing unattended execution. The constitution mandates `$ARGUMENTS` bypass (line 71) but it's unenforced across 23+ prompts. This blocks headless pipelines in GitHub Actions and increases manual overhead on repeatable workflows that account for 50%+ of sessions.

## Goals

1. Make ship, compound, and work skills executable without interactive prompts when `--headless` is passed
2. Create GitHub Actions workflows for scheduled ship-merge and compound-review
3. Enforce `--headless` bypass convention to prevent regression

## Non-Goals

- Local `claude -p` integration (blocked by plugin auto-load failure)
- New orchestration layers or wrapper scripts
- Making ALL skills headless (only priority pipeline skills)
- Changing the merge-pr or changelog skills (already headless)

## Functional Requirements

- **FR1:** When `$ARGUMENTS` contains `--headless`, ship skill auto-derives PR title/body from branch name and diff summary, auto-runs compound and tests without confirmation
- **FR2:** When `$ARGUMENTS` contains `--headless`, compound skill auto-promotes learnings to constitution.md using LLM judgment without human approval
- **FR3:** When `$ARGUMENTS` contains `--headless`, work skill skips interactive approval gates (same as existing pipeline mode behavior)
- **FR4:** `worktree-manager.sh` `create` and `cleanup` commands accept `--yes` flag to skip `read -r` prompts
- **FR5:** `scheduled-ship-merge.yml` workflow auto-ships and merges qualifying PRs on a schedule
- **FR6:** `scheduled-compound-review.yml` workflow runs compound weekly across recent sessions

## Technical Requirements

- **TR1:** `--headless` flag parsing follows the `schedule` skill pattern (check `$ARGUMENTS` string for flag presence)
- **TR2:** PreToolUse hooks must be verified to fire in GitHub Actions / `claude-code-action` context
- **TR3:** Headless pipelines must set `--max-turns` to prevent runaway API costs
- **TR4:** Constitution.md updated with `--headless` convention documentation
- **TR5:** Lefthook pre-commit check flags new AskUserQuestion calls without `--headless` bypass path

## Acceptance Criteria

- [ ] `skill: soleur:ship --headless` runs to completion without any AskUserQuestion calls
- [ ] `skill: soleur:compound --headless` auto-promotes learnings without human approval
- [ ] `skill: soleur:work --headless <plan-path>` skips interactive gates
- [ ] `worktree-manager.sh create <name> --yes` completes without `read -r` prompt
- [ ] `scheduled-ship-merge.yml` runs successfully in Actions
- [ ] `scheduled-compound-review.yml` runs successfully in Actions
- [ ] Lefthook check catches AskUserQuestion without bypass path

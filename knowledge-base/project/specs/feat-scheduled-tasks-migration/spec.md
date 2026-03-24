# Spec: Migrate Scheduled Workflows to Cloud Scheduled Tasks

**Status:** Draft
**Branch:** scheduled-tasks-migration
**Brainstorm:** [2026-03-24-scheduled-tasks-migration-brainstorm.md](../../brainstorms/2026-03-24-scheduled-tasks-migration-brainstorm.md)

## Problem Statement

Soleur's 11 `claude-code-action` GitHub Actions workflows consume Anthropic API credits at ~$40-120/month (growing). The Max subscription plan ($200/mo) includes Cloud scheduled tasks that share subscription rate limits instead of billing per-token. Moving applicable workflows to Cloud tasks would cap AI automation costs and simplify the YAML-heavy workflow setup.

## Goals

- G1: Migrate 8-9 simple workflows from API-billed GHA to Max-plan-billed Cloud scheduled tasks
- G2: Reduce monthly Anthropic API spend by 60-80%
- G3: Simplify workflow creation (Cloud task prompt vs. 100+ line YAML)
- G4: Preserve all orchestration safety for complex workflows (bug-fixer, ship-merge)

## Non-Goals

- Migrating pure-bash workflows (terraform-drift, content-publisher, etc.)
- Migrating workflows that require multi-step GHA orchestration
- Replacing GitHub Actions entirely
- Changing workflow scheduling frequencies

## Functional Requirements

- FR1: Each migrated workflow produces the same output (issues, PRs, labels) as the current GHA version
- FR2: Cloud tasks must load Soleur plugin and skills (verify plugin_marketplaces support)
- FR3: Environment variables (GH_TOKEN, API keys) must be configured in Cloud task environments
- FR4: Setup scripts must install dependencies (npm ci, Bun) before task execution
- FR5: Failure notifications must reach the team (not Discord community server)
- FR6: The `soleur:schedule` skill must support `--target cloud` to create Cloud tasks via CLI

## Technical Requirements

- TR1: Cloud task prompts must be self-contained if plugin marketplace is not supported
- TR2: Minimum Cloud task interval (1 hour) must accommodate all migrated workflow frequencies
- TR3: Rate limit monitoring must be established to detect contention between automated and interactive use
- TR4: GHA workflows for complex operations (bug-fixer, ship-merge) must remain functional
- TR5: Migration must be reversible — original GHA YAML preserved (disabled, not deleted) until Cloud tasks proven stable

## Migration Phases

### Phase 1: Validation

- Verify Cloud task plugin marketplace support
- Create one test Cloud task (campaign-calendar — lowest frequency, simplest logic)
- Compare output with GHA version over 2 weeks
- Monitor rate limit impact

### Phase 2: Simple weekly/monthly workflows

- Migrate: campaign-calendar, competitive-analysis, roadmap-review, growth-execution, seo-aeo-audit
- Disable (not delete) corresponding GHA workflows

### Phase 3: Simple daily workflows

- Migrate: daily-triage, community-monitor
- Monitor rate limit impact of daily tasks on interactive use

### Phase 4: Medium complexity

- Migrate: content-generator, growth-audit
- These have longer prompts and more turns — test thoroughly

### Phase 5: Schedule skill update

- Add `--target cloud|gha` flag to `soleur:schedule` skill
- Cloud target uses `/schedule` CLI or API to create tasks
- GHA target uses existing YAML generation

## Acceptance Criteria

- [ ] 8-9 workflows running as Cloud scheduled tasks producing equivalent output
- [ ] Anthropic API spend reduced by 60%+
- [ ] No degradation in interactive Claude Code rate limits
- [ ] `soleur:schedule` supports both Cloud and GHA targets
- [ ] Original GHA YAML preserved (disabled) for rollback

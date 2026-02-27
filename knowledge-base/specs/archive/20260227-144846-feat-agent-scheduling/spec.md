# Agent Scheduling Spec

**Issue:** #312
**Branch:** feat-agent-scheduling
**Date:** 2026-02-26

## Problem Statement

Claude Code plugins have no scheduling mechanism. All agent/skill invocations are user-initiated. Users who want recurring automation (security audits, content generation, repo maintenance) must manually create GitHub Actions workflows from scratch, which requires CI expertise and knowledge of `claude-code-action` configuration.

## Goals

- G1: Users can schedule any Soleur agent or skill to run on a recurring cron schedule
- G2: Each schedule is a standalone, auditable GitHub Actions workflow file
- G3: Output routing (issues, PRs, Discord) is configurable per schedule
- G4: Users can manage schedules (create, list, delete, test) through a single skill

## Non-Goals

- NG1: Building a persistent daemon or scheduler within Claude Code
- NG2: Sub-minute scheduling precision (GitHub Actions cron minimum is ~5 min)
- NG3: Cost controls, budget caps, or usage tracking (deferred — YAGNI)
- NG4: Local machine scheduling (cron, systemd, launchd)
- NG5: Telegram bridge integration (may add later as separate runtime)

## Functional Requirements

- FR1: `soleur:schedule create` — Interactive skill that generates `.github/workflows/scheduled-<name>.yml` from user input (agent/skill, cron expression, output mode, model)
- FR2: `soleur:schedule list` — Scans `.github/workflows/scheduled-*.yml` and displays a table of all scheduled tasks with name, cron, agent/skill, output mode, and last run status
- FR3: `soleur:schedule delete <name>` — Removes the specified workflow file
- FR4: `soleur:schedule run <name>` — Triggers a manual run via `gh workflow run` for testing
- FR5: Generated workflows must use `claude-code-action` to invoke the specified agent/skill
- FR6: Generated workflows must include `workflow_dispatch` trigger for manual testing alongside the cron trigger
- FR7: Output modes supported: `issue` (create GitHub issue with findings), `pr` (open draft PR with changes), `discord` (post to Discord webhook)

## Technical Requirements

- TR1: Generated workflows must pin `claude-code-action` to a commit SHA (not tag) per existing security learnings
- TR2: Generated workflows must declare explicit `permissions:` blocks with minimum required permissions
- TR3: Each scheduled run must operate in isolation — no shared state between concurrent runs
- TR4: Workflow template must include failure handling — failed runs should not produce false-positive "success" results
- TR5: The skill must validate cron expressions before generating the workflow

## Architecture

```
User -> /soleur:schedule create -> Interactive Q&A -> Generate .yml -> Commit

GitHub Actions cron -> scheduled-<name>.yml -> claude-code-action -> Agent/Skill -> Output (issue/PR/Discord)

User -> /soleur:schedule list -> Glob .github/workflows/scheduled-*.yml -> Display table
User -> /soleur:schedule run <name> -> gh workflow run scheduled-<name>.yml
User -> /soleur:schedule delete <name> -> Remove .yml file
```

## Success Criteria

- SC1: A user can create a weekly security audit schedule in under 2 minutes
- SC2: Scheduled workflows run successfully in GitHub Actions and produce expected output
- SC3: `schedule list` accurately shows all scheduled tasks and their status
- SC4: Manual `schedule run` triggers execute correctly for testing

# Brainstorm: Migrate GitHub Actions Workflows to Claude Code Cloud Scheduled Tasks

**Date:** 2026-03-24
**Status:** Complete
**Approach:** Hybrid (Cloud tasks for simple workflows, GHA for complex)

## What We're Building

Migrate 8 simple `claude-code-action` GitHub Actions workflows from API-billed execution to Claude Code Cloud scheduled tasks that run on the Max subscription plan. Keep 2 complex workflows (bug-fixer, ship-merge) and 7 pure-bash workflows on GitHub Actions.

**Goal:** Reduce API costs (~$40-120/mo, growing) by shifting AI workloads to the flat-rate Max subscription, while also simplifying the YAML-heavy automation setup.

## Why This Approach

1. **Cost trajectory matters more than current spend.** API costs scale linearly with each new workflow; Max plan is fixed. As Soleur adds more automation, the gap widens.
2. **Simple workflows are easy to migrate.** 8 of 11 claude-code-action workflows follow the same pattern: checkout → install deps → run a Soleur skill prompt. These map directly to Cloud task setup scripts + prompts.
3. **Complex workflows lose critical safety.** Bug-fixer's auto-merge gate runs OUTSIDE the agent's token scope. Ship-merge's PR selection and post-failure labeling use conditional GHA steps. These can't be replicated in a single Cloud task prompt without losing defense-in-depth.
4. **Pure-bash workflows can't move at all.** 7 workflows (terraform-drift, content-publisher, analytics, etc.) don't use Claude — they're bash scripts with social API tokens and infrastructure commands.

## Key Decisions

- **Hybrid split:** 8 simple → Cloud tasks, 2 complex + 7 bash → stay on GHA
- **Discord failure notifications:** Remove from community-facing Discord. Replace with internal notification (email or private channel).
- **Plugin marketplace support:** Must verify Cloud tasks support `plugin_marketplaces` and `plugins: 'soleur@soleur'` before migrating.
- **Schedule skill update:** `soleur:schedule` skill needs a `--target cloud|gha` flag to generate either Cloud task configs or GHA YAML.

## Workflows to Migrate (Cloud Tasks)

| Workflow | Frequency | Avg Duration | Est. API Cost/mo |
|----------|-----------|-------------|-----------------|
| daily-triage | Daily 04:00 | 1.4 min | $3.15 |
| community-monitor | Daily 08:00 | 3.4 min | $7.65 |
| content-generator | Tue+Thu 10:00 | 15.0 min | $9.00 |
| seo-aeo-audit | Mon 10:00 | 5.2 min | $1.56 |
| growth-audit | Mon 09:00 | 18.4 min | $5.52 |
| campaign-calendar | Mon 16:00 | 1.4 min | $0.42 |
| growth-execution | 1st+15th monthly | 4.5 min | $0.68 |
| competitive-analysis | 1st monthly | 14.0 min | $1.05 |
| roadmap-review | 1st monthly | 7.9 min | $0.59 |

**Estimated savings:** ~$29-90/mo (conservative to realistic range)

## Workflows Staying on GHA

| Workflow | Reason |
|----------|--------|
| bug-fixer | Multi-step orchestration: issue selection cascade, conditional Claude invocation, auto-merge gate with safety checks |
| ship-merge | PR selection, branch checkout, post-failure labeling — dispatch-only, no cron |
| terraform-drift | Pure bash + Terraform + Doppler |
| content-publisher | Pure bash + social API tokens |
| weekly-analytics | Pure bash |
| strategy-review | Pure bash |
| linkedin-token-check | Pure bash |
| plausible-goals | Pure bash |
| cf-token-expiry-check | Pure bash (disabled) |

## Open Questions

1. **Plugin support in Cloud tasks:** Do Cloud scheduled tasks support `plugin_marketplaces` for loading Soleur skills? If not, prompts need to be self-contained (no `/soleur:*` skill invocations).
2. **Rate limit impact:** Running 9 automated tasks (some daily) on the Max plan — how much rate limit headroom remains for interactive use? Need to monitor after migration.
3. **Environment secrets:** Cloud tasks support env vars, but do they support secret masking, rotation, and audit logging equivalent to GHA secrets?
4. **Setup script reliability:** Cloud tasks run setup scripts before each session. Installing `npm ci` + Bun on every run adds latency. Is there a way to cache dependencies?
5. **Failure monitoring:** Cloud tasks create sessions for each run. How do you get notified of failures? Is there a webhook or notification mechanism?
6. **MCP connectors:** Can Cloud tasks use MCP connectors for Discord/Slack notifications to replace the current Discord webhook approach?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Finance (CFO)

**Summary:** Estimated API spend of $40-120/mo, growing with each new workflow. Moving to Max plan (flat $200/mo) creates a fixed-cost ceiling for AI automation. The cost arbitrage is real but modest today — the strategic value is capping future costs as automation scales.

### Operations (COO)

**Summary:** Migration deepens Anthropic vendor dependency (model + compute + scheduling + environment). 12+ secrets need migration to Cloud task env vars. The `soleur:schedule` skill needs refactoring. 7 pure-bash workflows are not candidates. Split-platform monitoring adds operational overhead.

### Engineering (CTO)

**Summary:** Cloud tasks lack conditional execution, post-step logic, concurrency groups, fine-grained permissions, and `workflow_dispatch` inputs. Simple "run a prompt" workflows migrate cleanly; orchestrated workflows (bug-fixer, ship-merge) would lose safety guarantees. Plugin marketplace support is unverified.

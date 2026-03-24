---
title: "feat: Migrate Scheduled Workflows to Cloud Scheduled Tasks"
type: feat
date: 2026-03-24
---

# Migrate Scheduled Workflows to Cloud Scheduled Tasks

## Overview

Migrate 9 simple `claude-code-action` GitHub Actions workflows to Claude Code Cloud scheduled tasks, shifting AI workload costs from per-token API billing to the flat-rate Max subscription. Keep 2 complex workflows (bug-fixer, ship-merge) and 7 pure-bash workflows on GitHub Actions.

## Problem Statement / Motivation

Soleur runs 11 scheduled GHA workflows using `claude-code-action` with `ANTHROPIC_API_KEY` (pay-per-token). Estimated spend: ~$40-120/month, growing with each new automation. The Max subscription ($200/mo) includes Cloud scheduled tasks that share subscription rate limits instead of per-token billing. Moving applicable workflows caps future costs and simplifies the 100+ line YAML template pattern.

## Proposed Solution

**Hybrid approach:** Migrate workflows that follow the simple pattern (checkout → deps → prompt) to Cloud tasks. Keep workflows requiring multi-step GHA orchestration on GHA. Preserve original YAML (disabled) for rollback.

### Phase 0: Validate Cloud Task Capabilities

Before migrating anything, verify the blockers identified in brainstorm open questions.

**0.1 — Verify plugin marketplace support**

Create a throwaway Cloud task via the web UI at `claude.ai/code/scheduled` (or `/schedule` in CLI) that runs a minimal Soleur skill invocation:

```text
Prompt: "Run /soleur:help and report what you see."
Repository: jikig-ai/soleur
Schedule: Manual trigger only (run once, then delete)
```

If the task can load and execute Soleur skills → plugins work, proceed.
If not → all prompts must be self-contained (inline the skill logic). This significantly increases migration complexity and may warrant reconsidering the migration.

- [ ] Cloud tasks can load Soleur plugin via marketplace
- [ ] Cloud tasks can invoke `/soleur:*` skills

**0.2 — Create Cloud environment**

Set up a dedicated Cloud environment at `claude.ai/code` with:

- **Name:** `soleur-scheduled`
- **Network access:** Limited (default allowlist — covers GitHub, npm, package registries)
- **Environment variables:** `GH_TOKEN` (from GitHub App, auto-provided for connected repos)
- **Setup script:**

```bash
#!/bin/bash
# Install Node.js dependencies for Soleur plugin
npm ci --ignore-scripts 2>/dev/null || true
```

Note: Bun is NOT needed — Cloud tasks use Node.js from the universal image. Only `npm ci` for Soleur plugin dependencies.

- [ ] Cloud environment `soleur-scheduled` created
- [ ] Setup script tested (run a test task, verify `npm ci` succeeds)

**0.3 — Test with campaign-calendar (lowest risk)**

Create a Cloud scheduled task replicating `scheduled-campaign-calendar.yml`:

- **Name:** `Campaign Calendar Refresh`
- **Repository:** `jikig-ai/soleur`
- **Environment:** `soleur-scheduled`
- **Schedule:** Weekly (Monday)
- **Prompt:**

```text
Run /soleur:campaign-calendar on this repository.

After running the skill, persist changes via PR:
- Stage changed files: git add knowledge-base/marketing/campaign-calendar.md
- If no changes, stop
- Create branch: ci/campaign-calendar-YYYY-MM-DD
- Commit: "ci: update campaign calendar"
- Push and create PR targeting main
- Enable auto-merge: gh pr merge <branch> --squash --auto

Create a GitHub issue titled "[Scheduled] Campaign Calendar - <today's date>"
with label "scheduled-campaign-calendar" summarizing what changed.
```

Run immediately via "Run now". Compare output with the most recent GHA run.

- [ ] Cloud task created for campaign-calendar
- [ ] Output matches GHA version (same PR pattern, same issue label)
- [ ] No errors in Cloud task session

### Phase 1: Migrate Weekly/Monthly Workflows

After Phase 0 validates the approach, migrate the 5 lowest-frequency workflows:

| Workflow | Cloud Task Name | Schedule |
|----------|----------------|----------|
| `scheduled-campaign-calendar` | Campaign Calendar Refresh | Weekly (Monday) |
| `scheduled-competitive-analysis` | Competitive Analysis | Monthly (1st) |
| `scheduled-roadmap-review` | Roadmap Review | Monthly (1st) |
| `scheduled-growth-execution` | Growth Execution | Bi-monthly (1st, 15th) |
| `scheduled-seo-aeo-audit` | SEO/AEO Audit | Weekly (Monday) |

For each workflow:

1. Read the GHA YAML to extract the exact prompt
2. Create a Cloud task with equivalent prompt (remove GHA-specific preamble like `AGENTS.md rule` comments)
3. Adapt the PR-based commit pattern for Cloud task context (Cloud tasks already push to `claude/` branches — verify this works with the existing merge flow)
4. Run once via "Run now" and verify output
5. Disable the GHA workflow: comment out the `schedule:` trigger, keep `workflow_dispatch:` for rollback

**Disabling GHA workflows:**

```yaml
# MIGRATED TO CLOUD SCHEDULED TASK — 2026-03-XX
# Uncomment schedule to revert to GHA execution
on:
  # schedule:
  #   - cron: '0 16 * * 1'
  workflow_dispatch: {}  # Keep for manual rollback testing
```

- [ ] 5 Cloud tasks created and verified
- [ ] 5 GHA workflows disabled (schedule commented out, dispatch preserved)
- [ ] No duplicate runs (verify no overlap during transition)

### Phase 2: Migrate Daily Workflows

Higher frequency = higher rate limit impact. Monitor before and after.

| Workflow | Cloud Task Name | Schedule |
|----------|----------------|----------|
| `scheduled-daily-triage` | Daily Issue Triage | Daily |
| `scheduled-community-monitor` | Community Monitor | Daily |

**Rate limit baseline:** Before migrating, note current interactive Claude Code usage patterns. After migrating, monitor for:

- Slower response times during scheduled task windows
- Rate limit errors in interactive sessions
- Any queuing delays in Cloud task runs

The daily-triage workflow has special considerations:

- It creates labels (one-time) — labels already exist, so the pre-step is unnecessary in Cloud
- It uses `--max-turns 80` — verify Cloud tasks support this turn count
- It restricts tools to `Bash,Read,Glob,Grep` — include this in the Cloud prompt

- [ ] Daily triage Cloud task created and verified
- [ ] Community monitor Cloud task created and verified
- [ ] Rate limit impact assessed after 1 week of daily runs

### Phase 3: Migrate Medium-Complexity Workflows

These have longer run times and more complex prompts.

| Workflow | Cloud Task Name | Schedule | Notes |
|----------|----------------|----------|-------|
| `scheduled-content-generator` | Content Generator | Tue + Thu | Complex multi-step prompt, needs npm ci |
| `scheduled-growth-audit` | Growth Audit | Weekly (Monday) | 18+ minute avg run time |

**Content generator special handling:**

- The prompt is ~100 lines with 6 steps (topic selection, article generation, distribution, validation, queue update, PR)
- Uses `WebSearch` and `WebFetch` tools — verify these work in Cloud tasks with Limited network
- Requires `npm ci` for Eleventy build validation — covered by setup script
- References `/soleur:content-writer` and `/soleur:social-distribute` and `/soleur:growth` — all need plugin access

- [ ] Content generator Cloud task created with full prompt
- [ ] Growth audit Cloud task created
- [ ] Eleventy build works in Cloud environment (npm ci + npx @11ty/eleventy)
- [ ] WebSearch/WebFetch work with Limited network access

### Phase 4: Remove Discord Failure Notifications

Per brainstorm decision: Discord failure notifications go to the community server (wrong audience). Replace with:

**Option A (simplest):** Cloud tasks create sessions visible at `claude.ai/code`. Failures are visible in the session list. Set up a daily check: `/loop 24h check if any scheduled task sessions failed in the last 24 hours`.

**Option B (if MCP connectors available):** Connect a Slack or email MCP connector to the Cloud environment. Task prompts include: "If any step fails, notify via Slack/email."

**Option C (GHA-only fallback):** For the 2 remaining GHA workflows, replace Discord webhook with email via `gh` CLI or a simple curl to an email API.

For this migration, start with Option A. Remove Discord notification steps from the disabled GHA workflows when they're re-enabled for any reason.

- [ ] Verify Cloud task failure visibility in session list
- [ ] Document monitoring procedure (where to check, how often)

### Phase 5: Update Schedule Skill (Deferred)

The `soleur:schedule` skill (`plugins/soleur/skills/schedule/SKILL.md`) currently only generates GHA YAML. Adding `--target cloud` support requires:

1. Detect whether `/schedule` CLI tool is available (Cloud task management)
2. Generate a Cloud task configuration instead of YAML
3. Handle environment selection, repository connection, schedule picker

**This is deferred** to a separate issue. The immediate migration uses the web UI and CLI `/schedule` directly. The skill update is a nice-to-have for future workflow creation, not a blocker for the migration itself.

- [ ] GitHub issue created for schedule skill update (separate from #1094)

## Technical Considerations

### Cloud Task Prompt Pattern

Each migrated workflow's prompt follows this template:

```text
Run /soleur:<skill-name> on this repository.
[Optional: skill-specific instructions]

After your analysis is complete:
1. If changes were made, persist via PR:
   - Create branch: ci/<task-name>-YYYY-MM-DD
   - Commit with descriptive message
   - Push and create PR targeting main
   - Enable auto-merge: gh pr merge <branch> --squash --auto
2. Create a GitHub issue titled "[Scheduled] <Task Name> - <today's date>"
   with label "scheduled-<name>" summarizing your findings.
```

### Branch Naming

Cloud tasks default to pushing to `claude/`-prefixed branches. The prompts should use `ci/` prefix to match existing convention. Enable **"Allow unrestricted branch pushes"** for the repository in the Cloud task settings.

### Environment Secrets

Cloud task environments support environment variables. The following secrets need configuration:

| Secret | Used By | Notes |
|--------|---------|-------|
| `GH_TOKEN` | All workflows | Auto-provided via GitHub App connection |
| None additional | Simple workflows | Simple workflows only need GitHub access |

Content-generator may need additional env vars if `/soleur:content-writer` requires them, but this should be handled by the Soleur plugin configuration.

### Rollback Procedure

If a Cloud task produces incorrect output or rate limits degrade:

1. Re-enable the GHA workflow: uncomment the `schedule:` trigger
2. Pause or delete the Cloud task
3. Verify the GHA workflow runs successfully on next trigger

## Acceptance Criteria

- [ ] 9 Cloud scheduled tasks created and running
- [ ] Each produces equivalent output to its GHA counterpart (same issues, PRs, labels)
- [ ] Anthropic API spend reduced (verify on console.anthropic.com)
- [ ] No degradation in interactive Claude Code rate limits
- [ ] 9 GHA workflows disabled (schedule commented, dispatch preserved)
- [ ] Monitoring procedure documented for Cloud task failures
- [ ] Rollback tested for at least 1 workflow

## Test Scenarios

- Given a Cloud task runs campaign-calendar, when it completes, then it creates a PR with updated calendar and a labeled issue — matching GHA output
- Given 2 daily Cloud tasks run at 04:00 and 08:00, when interactive Claude Code is used at 09:00, then response times are normal (no rate limit impact)
- Given a Cloud task fails (e.g., Eleventy build error), when checking claude.ai/code, then the failed session is visible with error details
- Given the GHA workflow is re-enabled after disabling, when triggered manually, then it produces correct output (rollback works)

## Domain Review

**Domains relevant:** Finance, Operations, Engineering

Carried forward from brainstorm `## Domain Assessments`:

### Finance (CFO)

**Status:** reviewed
**Assessment:** API spend ~$40-120/mo, growing. Migration caps future AI automation costs under the flat Max subscription. Strategic value: fixed-cost ceiling as automation scales.

### Operations (COO)

**Status:** reviewed
**Assessment:** Deepens Anthropic vendor dependency. 7 pure-bash workflows stay on GHA regardless. Split-platform monitoring is the main operational overhead. Schedule skill needs future update.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Simple workflows migrate cleanly. Complex workflows (bug-fixer, ship-merge) keep GHA orchestration. Plugin marketplace support is the #1 technical risk — must validate before committing to migration.

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Plugin marketplace not supported in Cloud tasks | Medium | High — all prompts need rewriting | Phase 0 validates first; abort if not supported |
| Rate limits degraded by automated tasks | Low | Medium — slows interactive work | Phase 2 monitors; can pause tasks if needed |
| Cloud task creates wrong branch naming | Low | Low — PRs still work, just different prefix | Enable unrestricted branch pushes; adapt prompts |
| Cloud platform outage | Low | Medium — no scheduled tasks run | GHA workflows preserved for rollback |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-24-scheduled-tasks-migration-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-scheduled-tasks-migration/spec.md`
- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md`
- Canonical simple workflow: `.github/workflows/scheduled-campaign-calendar.yml`
- Issue: #1094, PR: #1095

### External References

- Cloud scheduled tasks docs: `https://code.claude.com/docs/en/web-scheduled-tasks`
- Cloud environment docs: `https://code.claude.com/docs/en/claude-code-on-the-web`
- Billing: "shares rate limits with all other Claude and Claude Code usage within your account"

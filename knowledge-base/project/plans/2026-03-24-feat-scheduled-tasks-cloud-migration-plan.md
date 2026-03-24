---
title: "feat: Migrate Scheduled Workflows to Cloud Scheduled Tasks"
type: feat
date: 2026-03-24
---

# Migrate Scheduled Workflows to Cloud Scheduled Tasks

## Overview

Migrate 9 `claude-code-action` GitHub Actions workflows to Claude Code Cloud scheduled tasks, shifting AI workload costs from per-token API billing to the flat-rate Max subscription. Keep 2 complex workflows (bug-fixer, ship-merge) and 7 pure-bash workflows on GitHub Actions. Centralize secrets in Doppler to avoid duplication across platforms.

## Problem Statement / Motivation

Soleur runs 11 scheduled GHA workflows using `claude-code-action` with `ANTHROPIC_API_KEY` (pay-per-token). Estimated spend: ~$40-120/month, growing with each new automation. The Max subscription ($200/mo) includes Cloud scheduled tasks that share subscription rate limits instead of per-token billing. Moving applicable workflows caps future costs and simplifies the 100+ line YAML template pattern.

## Proposed Solution

**Hybrid approach:** Migrate 9 workflows that follow the single-agent pattern to Cloud tasks. Keep 2 orchestrated workflows + 7 bash workflows on GHA. Use Doppler as centralized secret store to avoid duplicating secrets across GHA and Cloud environments.

### Phase 0: Validate and Setup

**0.1 — Create Doppler config for scheduled tasks**

Create a new Doppler config `prd_scheduled` (under the existing `soleur` project) containing all secrets used by the 9 candidate workflows:

| Secret | Used By |
|--------|---------|
| `DISCORD_BOT_TOKEN` | community-monitor |
| `DISCORD_GUILD_ID` | community-monitor |
| `DISCORD_WEBHOOK_URL` | community-monitor |
| `X_API_KEY` | community-monitor |
| `X_API_SECRET` | community-monitor |
| `X_ACCESS_TOKEN` | community-monitor |
| `X_ACCESS_TOKEN_SECRET` | community-monitor |
| `LINKEDIN_ACCESS_TOKEN` | community-monitor |
| `LINKEDIN_PERSON_URN` | community-monitor |
| `BSKY_HANDLE` | community-monitor |
| `BSKY_APP_PASSWORD` | community-monitor |

Workflows that only need GitHub access (daily-triage, campaign-calendar, etc.) get `GH_TOKEN` auto-provided by the GitHub App connection — no Doppler entry needed.

- [ ] Doppler `prd_scheduled` config created with all 11 secrets
- [ ] Values copied from GHA repository secrets (verify each is current)

**0.2 — Create Cloud environment + validate with campaign-calendar**

Set up a Cloud environment at `claude.ai/code`:

- **Name:** `soleur-scheduled`
- **Network access:** Limited (default allowlist)
- **Environment variables:** `DOPPLER_TOKEN` (service token for `prd_scheduled` config)
- **Setup script:**

```bash
#!/bin/bash
# Install Doppler CLI
curl -Ls https://cli.doppler.com/install.sh | sh
# Export secrets as env vars for Claude session
eval $(doppler secrets download --no-file --format env-no-quotes 2>/dev/null | sed 's/^/export /')
# Install Node.js dependencies
npm ci --ignore-scripts 2>/dev/null || true
```

Then create a Cloud task for campaign-calendar (simplest workflow):

- **Prompt:** Adapted from `.github/workflows/scheduled-campaign-calendar.yml` (lines 54-77)
- **Schedule:** Weekly (Monday)

Run via "Run now". Verify: (a) Soleur plugin loads, (b) skill executes, (c) PR created, (d) issue created with correct label.

If plugin loading fails → abort migration, all prompts would need to be self-contained.
If scheduled execution differs from manual → test a short-delay scheduled run before proceeding.

- [ ] Cloud environment `soleur-scheduled` created with Doppler setup
- [ ] Campaign-calendar Cloud task runs successfully
- [ ] Output matches GHA version (PR pattern, issue label, content)

### Phase 1: Migrate All 9 Workflows

After Phase 0 validates the approach, migrate the remaining 8 workflows in a single batch. The migration steps are identical regardless of frequency:

| # | Workflow | Cloud Task Name | Schedule |
|---|----------|----------------|----------|
| 1 | `scheduled-campaign-calendar` | Campaign Calendar Refresh | Weekly (Monday) |
| 2 | `scheduled-competitive-analysis` | Competitive Analysis | Monthly (1st) |
| 3 | `scheduled-roadmap-review` | Roadmap Review | Monthly (1st) |
| 4 | `scheduled-growth-execution` | Growth Execution | Bi-monthly (1st, 15th) |
| 5 | `scheduled-seo-aeo-audit` | SEO/AEO Audit | Weekly (Monday) |
| 6 | `scheduled-daily-triage` | Daily Issue Triage | Daily |
| 7 | `scheduled-community-monitor` | Community Monitor | Daily |
| 8 | `scheduled-content-generator` | Content Generator | Tue + Thu |
| 9 | `scheduled-growth-audit` | Growth Audit | Weekly (Monday) |

**Per workflow:**

1. Read the GHA YAML prompt
2. Adapt for Cloud task context: remove git-config lines (Cloud handles auth), remove GHA-specific preamble
3. Add failure fallback: "If any step fails, create a GitHub issue titled '[Scheduled] \<name\> - FAILED - \<date\>' with error details and label 'scheduled-\<name\>'."
4. Create Cloud task, run via "Run now", verify output
5. Disable GHA workflow: comment out `schedule:` trigger, keep `workflow_dispatch:` for rollback

**Community-monitor special handling:** Verify Doppler secrets are accessible from the Cloud task. The setup script exports them as env vars. Run the monitor manually and confirm it can authenticate to Discord, X, LinkedIn, and Bluesky APIs.

**Content-generator special handling:** Verify `WebSearch`/`WebFetch` work with Limited network access. Verify Eleventy build works (`npx @11ty/eleventy`). The 100-line prompt can be pasted directly — prompt length is not a migration risk.

- [ ] 9 Cloud tasks created, each verified with "Run now"
- [ ] 9 GHA `schedule:` triggers commented out, `workflow_dispatch:` preserved
- [ ] Community-monitor Doppler secrets verified (all 11 APIs authenticate)
- [ ] No duplicate runs during transition

### Phase 2: Verify and Monitor

After all tasks are migrated, observe for 1 week:

- [ ] All 9 Cloud tasks fire on schedule (check `claude.ai/code` session list)
- [ ] Cross-platform dependency chain intact: daily-triage (04:00, Cloud) → bug-fixer (06:00, GHA) finds triaged issues; content-generator (10:00, Cloud) → content-publisher (14:00, GHA) publishes generated content
- [ ] No interactive rate limit degradation. If degraded → pause daily tasks first (highest rate limit consumers)
- [ ] Update `soleur:schedule list` command to note Cloud tasks exist (add a `## Active Cloud Tasks` section to `plugins/soleur/skills/schedule/SKILL.md` or read from a knowledge-base manifest)

## Technical Considerations

### Secrets Architecture (Doppler)

```text
Doppler Project: soleur
├── prd_terraform    (existing — Terraform/infra secrets)
└── prd_scheduled    (new — social media API tokens for scheduled tasks)

GHA repository secrets:
├── ANTHROPIC_API_KEY    (stays — used by bug-fixer, ship-merge)
├── DOPPLER_TOKEN        (stays — used by terraform-drift, infra-validation)
└── DISCORD_WEBHOOK_URL  (stays temporarily — used by content-publisher bash script)

Cloud environment vars:
└── DOPPLER_TOKEN        (new — service token scoped to prd_scheduled)
```

This eliminates secret duplication. Token rotation happens in Doppler once — both platforms pick up the change on next run.

### Cross-Platform Dependencies

```text
04:00 UTC  daily-triage (Cloud)     ──depends-on──►  06:00 UTC  bug-fixer (GHA)
10:00 UTC  content-generator (Cloud) ──depends-on──► 14:00 UTC  content-publisher (GHA)
```

Cloud task scheduling may have different jitter than GHA (~15 min). The 2-hour and 4-hour gaps between dependent tasks absorb this. No changes needed, but document the dependency chain.

### AGENTS.md Context

Cloud tasks get a fresh checkout with AGENTS.md loaded. The worktree rules do not apply (no worktree in Cloud). Existing GHA prompts already include `AGENTS.md rule` context — Cloud prompts can drop this since they operate in a clean environment that cannot violate worktree rules.

### Rollback Procedure

If a Cloud task produces incorrect output:

1. Pause or delete the Cloud task at `claude.ai/code/scheduled`
2. Re-enable the GHA workflow: uncomment `schedule:` trigger
3. Trigger manually via `gh workflow run scheduled-<name>.yml` to verify

## Acceptance Criteria

- [ ] 9 Cloud scheduled tasks created, each producing equivalent output to GHA
- [ ] 9 GHA cron triggers disabled, `workflow_dispatch` preserved
- [ ] Doppler `prd_scheduled` config created with community-monitor secrets verified
- [ ] No duplicate runs observed across platforms

## Test Scenarios

- Given a Cloud task runs campaign-calendar, when it completes, then it creates a PR with updated calendar and a labeled issue — matching GHA output
- Given a Cloud task fails (e.g., Eleventy build error), when checking claude.ai/code, then a GitHub issue titled "[Scheduled] ... - FAILED" exists with error details
- Given bug-fixer runs at 06:00 after daily-triage migrated to Cloud (04:00), when it searches for triaged issues, then it finds issues labeled by the Cloud triage task
- Given the GHA workflow is re-enabled after disabling, when triggered manually, then it produces correct output

## Domain Review

**Domains relevant:** Finance, Operations, Engineering

Carried forward from brainstorm `## Domain Assessments`:

### Finance (CFO)

**Status:** reviewed
**Assessment:** API spend ~$40-120/mo, growing. Migration caps future AI automation costs under the flat Max subscription. Doppler adds no cost (free tier covers <5 configs).

### Operations (COO)

**Status:** reviewed [Updated 2026-03-24]
**Assessment:** Doppler centralization eliminates secret duplication. Split-platform monitoring mitigated by failure-fallback issue creation in every Cloud task prompt. Schedule skill `list` update needed (not deferred — minimal change).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Simple workflows migrate cleanly. Complex workflows keep GHA orchestration. Plugin marketplace support is the #1 technical risk — Phase 0 validates before committing. Concurrency guarantees in Cloud should be tested during Phase 0.

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Plugin marketplace not supported in Cloud tasks | Medium | High | Phase 0 validates first; abort if not supported |
| Rate limits degraded by daily automated tasks | Low | Medium | Pause daily tasks first if degraded |
| Cloud task concurrency overlap (long-running task + next trigger) | Low | Medium | Test in Phase 0; document behavior |
| Cloud platform outage | Low | Medium | GHA workflows preserved for rollback |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-24-scheduled-tasks-migration-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-scheduled-tasks-migration/spec.md`
- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md`
- Canonical simple workflow: `.github/workflows/scheduled-campaign-calendar.yml`
- Doppler pattern: `.github/workflows/scheduled-terraform-drift.yml` (existing Doppler usage)
- Issue: #1094, PR: #1095

### External References

- Cloud scheduled tasks docs: `https://code.claude.com/docs/en/web-scheduled-tasks`
- Cloud environment docs: `https://code.claude.com/docs/en/claude-code-on-the-web`
- Doppler service tokens: `https://docs.doppler.com/docs/service-tokens`
- Billing: "shares rate limits with all other Claude and Claude Code usage within your account"

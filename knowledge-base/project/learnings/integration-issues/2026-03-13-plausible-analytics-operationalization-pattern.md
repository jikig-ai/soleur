---
title: Plausible Analytics Operationalization Pattern
date: 2026-03-13
category: integration-issues
tags: [plausible, analytics, api, shell-scripting, ci, marketing, growth-targets]
symptoms: [analytics deployed but no baselines, KPIs defined but never measured, content distribution without feedback loop]
module: marketing/analytics, scripts, ci
root_cause: Deploying an analytics tool is not the same as operationalizing it
---

# Learning: Plausible Analytics Operationalization Pattern

## Problem

Plausible Analytics was deployed on soleur.ai but not operationalized. The marketing strategy defined KPIs (unique visitors, page views, visit duration, bounce rate) and a weekly review cadence, but zero measurements had been taken. Content distribution started March 12 -- without baselines, week-over-week tracking, and growth targets, there was no feedback loop connecting marketing effort to measurable outcomes.

The gap: the strategy said "review analytics weekly" but provided no targets to review against, no automation to collect data, and no historical snapshots to compare.

## Solution

Three deliverables turned passive tracking into active growth feedback:

### 1. Marketing strategy updated with 3-phase WoW growth targets

Added concrete week-over-week growth targets to the marketing strategy document, calibrated by phase:

- **Phase 1 (Weeks 1-4, foundation):** +15% WoW -- high percentage on a small base, driven by initial content seeding
- **Phase 2 (Weeks 5-12, momentum):** +10% WoW -- sustained growth as content library and backlinks compound
- **Phase 3 (Weeks 13+, optimization):** +7% WoW -- mature growth rate, shift from acquisition to engagement quality

Each phase includes specific metric thresholds (e.g., Phase 1 exit criteria: 50+ weekly visitors, bounce rate below 70%).

### 2. Shell script for Plausible API v1 data extraction

Created `scripts/weekly-analytics.sh` that pulls data from Plausible's Stats API v1 and writes markdown snapshots to `knowledge-base/marketing/analytics-snapshots/`:

- Uses `compare=previous_period` parameter to get WoW percentages natively from the API, avoiding complex delta calculations in shell
- Extracts top pages, traffic sources, and geographic breakdown
- Formats output as a markdown file with YAML frontmatter for date indexing
- Requires only `PLAUSIBLE_API_KEY` environment variable (uses `plausible.io` cloud endpoint by default)
- Includes `jq` dependency check and graceful error handling

### 3. CI workflow for automated Monday snapshots

Created `.github/workflows/scheduled-weekly-analytics.yml`:

- Runs on `cron: '0 8 * * 1'` (Monday 08:00 UTC)
- Executes the shell script via `bash scripts/weekly-analytics.sh`
- Commits the snapshot file directly to main with `[skip ci]` to prevent recursive triggers
- Sends Discord webhook notification on failure so missed snapshots are caught immediately
- Uses `PLAUSIBLE_API_KEY` from GitHub Actions secrets

### 4. Follow-up issues for full operationalization

Filed two GitHub issues to track remaining work:
- **#578:** Configure Plausible dashboard goals (signup conversions, docs engagement, CTA clicks)
- **#579:** Establish UTM parameter conventions for campaign attribution

## Key Insight

Deploying an analytics tool is not the same as operationalizing it. The gap between "tracking visits" and "acting on data" requires three components working together:

1. **Growth targets** to measure against -- without targets, data is informational rather than actionable
2. **Automated data extraction** -- manual dashboard checks create a discipline dependency that fails silently
3. **Review cadence with historical snapshots** -- WoW comparison requires persisted prior-week data, not just live dashboards

Plausible's API v1 `compare=previous_period` parameter is the critical enabler for shell-script-based snapshots. It returns both absolute values and percentage changes in a single API call, making the shell script straightforward rather than requiring the script to load, store, and diff historical data.

The 3-phase growth target model (+15/+10/+7%) accounts for the mathematical reality that percentage growth must decline as the base grows. Setting a flat target (e.g., "+10% every week") either sets up early failure (too ambitious on a tiny base) or creates false confidence (easy to hit when the base is 20 visitors).

## Session Errors

1. **Nested worktree creation** -- Ran `worktree-manager.sh` from inside an existing worktree instead of from the repo root. The script expects to run from the main repo directory.
2. **gh label creation failure** -- Attempted to create an issue with a label (`analytics`) that did not exist. Had to create the label first with `gh label create` before attaching it to issues.
3. **Security hook warning on workflow YAML write** -- PreToolUse hook flagged the GitHub Actions workflow file as a potential command injection vector. Resolved by ensuring all interpolated values use GitHub's `${{ }}` expression syntax rather than shell variable expansion.
4. **Bare URL lint error (MD034)** -- Markdownlint flagged bare URLs in the plan document. Wrapped URLs in angle brackets to satisfy the linter.
5. **Bare repo cannot run worktree-manager cleanup** -- The worktree-manager cleanup script cannot run from a bare checkout or detached HEAD state; it requires a valid main branch reference.

## Tags

category: integration-issues
module: marketing/analytics, scripts, ci
symptoms: analytics deployed but unmeasured, KPIs without targets, content distribution without feedback loop
related: 2026-02-21-cookie-free-analytics-legal-update-pattern.md, 2026-03-03-marketing-strategy-unification-pattern.md, 2026-03-03-scheduled-bot-fix-workflow-patterns.md, 2026-03-12-llm-as-script-pattern-for-ci-file-generation.md

# Spec: Plausible Analytics Operationalization & Growth Targets

**Feature:** feat-plausible-growth-targets
**Date:** 2026-03-13
**Brainstorm:** [2026-03-13-plausible-growth-targets-brainstorm.md](../../brainstorms/2026-03-13-plausible-growth-targets-brainstorm.md)

## Problem Statement

Plausible analytics is deployed on soleur.ai but not operationalized. The marketing strategy defines KPIs and weekly review cadences, but no measurements have been taken. Content distribution started March 12 -- without baselines, WoW tracking, and growth targets, there is no feedback loop to know if the content strategy is working.

## Goals

1. Upgrade analytics priority and add WoW growth targets to marketing-strategy.md
2. Build a shell script + CI workflow for automated weekly Plausible data extraction into markdown snapshots
3. File GitHub issues for Plausible dashboard configuration and UTM conventions (follow-up work)

## Non-Goals

- Code changes to soleur.ai (CTA tracking, script changes)
- Plausible dashboard configuration (founder manual task, tracked as GitHub issue)
- UTM convention implementation (tracked as GitHub issue for social-distribute integration)
- A/B testing or heatmap setup
- Google Search Console integration (future consideration)

## Functional Requirements

- **FR1:** marketing-strategy.md updated with WoW growth targets (3-phase framework) and upgraded analytics priority (Low -> Medium)
- **FR2:** Shell script (`scripts/weekly-analytics.sh`) that calls Plausible API v1, formats weekly snapshot markdown at `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md`
- **FR3:** GitHub Actions workflow (`scheduled-weekly-analytics.yml`) that runs weekly, executes the script, and commits snapshots

## Technical Requirements

- **TR1:** CI workflow requires `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` as GitHub secrets
- **TR2:** Script must exit 0 with warning if API key is not configured (graceful skip, not failure)
- **TR3:** Script uses Plausible v1 aggregate endpoint with `compare=previous_period` for WoW delta calculation
- **TR4:** Shell script follows constitution.md conventions (`set -euo pipefail`, `# --- Section ---` headers, `jq // empty`)

## Acceptance Criteria

- [ ] marketing-strategy.md contains WoW growth targets for all 3 phases
- [ ] marketing-strategy.md analytics priority is Medium (not Low)
- [ ] Shell script makes 3 API calls, formats markdown, exits 0 on missing secrets, exits 1 on API errors
- [ ] CI workflow runs weekly, commits snapshots, notifies Discord on failure
- [ ] GitHub issues filed for Plausible goal config and UTM conventions

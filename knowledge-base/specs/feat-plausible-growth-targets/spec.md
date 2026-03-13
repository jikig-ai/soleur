# Spec: Plausible Analytics Operationalization & Growth Targets

**Feature:** feat-plausible-growth-targets
**Date:** 2026-03-13
**Brainstorm:** [2026-03-13-plausible-growth-targets-brainstorm.md](../../brainstorms/2026-03-13-plausible-growth-targets-brainstorm.md)

## Problem Statement

Plausible analytics is deployed on soleur.ai but not operationalized. The marketing strategy defines KPIs and weekly review cadences, but no measurements have been taken. Content distribution started March 12 — without baselines, WoW tracking, and growth targets, there is no feedback loop to know if the content strategy is working.

## Goals

1. Upgrade analytics priority and add WoW growth targets to marketing-strategy.md
2. Create a weekly analytics snapshot template for structured metric capture
3. Build a GitHub Actions CI workflow for automated weekly Plausible data extraction
4. Document Plausible dashboard configuration tasks (goals, outbound links)

## Non-Goals

- Code changes to soleur.ai (CTA tracking, script changes)
- Plausible dashboard configuration (founder manual task)
- A/B testing or heatmap setup
- Google Search Console integration (future consideration)

## Functional Requirements

- **FR1:** marketing-strategy.md updated with WoW growth targets (3-phase framework), upgraded analytics priority (Low → Medium), UTM conventions, and Plausible goal configuration checklist
- **FR2:** Weekly analytics snapshot template at `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-snapshot.md` with Tier 1 metrics and WoW delta calculations
- **FR3:** GitHub Actions workflow (`scheduled-weekly-analytics.yml`) that runs weekly, calls Plausible API, generates the snapshot markdown, and commits it
- **FR4:** Plausible setup checklist documenting goals to configure (Newsletter Signup, Getting Started pageview, blog pageviews, outbound link tracking)

## Technical Requirements

- **TR1:** CI workflow requires `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` as GitHub secrets
- **TR2:** CI workflow must gracefully skip if API key is not configured (warn, don't fail)
- **TR3:** Snapshot template must include WoW percentage change calculations
- **TR4:** UTM parameter conventions must be consistent with existing social-distribute skill output

## Acceptance Criteria

- [ ] marketing-strategy.md contains WoW growth targets for all 3 phases
- [ ] marketing-strategy.md analytics priority is Medium (not Low)
- [ ] marketing-strategy.md contains UTM convention section
- [ ] Weekly snapshot template exists with all Tier 1 metrics
- [ ] CI workflow exists and runs without error (even without API key)
- [ ] Plausible goal configuration checklist is documented

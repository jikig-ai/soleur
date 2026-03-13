---
title: "feat: Plausible analytics operationalization and WoW growth targets"
type: feat
date: 2026-03-13
semver: patch
---

# Plausible Analytics Operationalization and WoW Growth Targets

## Overview

Turn Plausible from a passive tracking tool into an active growth feedback loop by updating the marketing strategy with WoW growth targets, creating a weekly snapshot template, building CI automation for Plausible API data extraction, and documenting Plausible dashboard configuration.

## Problem Statement / Motivation

Plausible is deployed on soleur.ai but not operationalized. The marketing strategy defines KPIs and a weekly review cadence (line 379) but zero measurements have been taken. Content distribution started March 12 -- without baselines, WoW tracking, and growth targets, there is no feedback loop. The existing KPIs are absolute milestones (500+ monthly visitors) which are lagging indicators. WoW growth rates are leading indicators that surface problems while fixable.

## Proposed Solution

Four deliverables, each building on the last:

### Deliverable 1: Update marketing-strategy.md

Edit `knowledge-base/marketing/marketing-strategy.md` with these changes:

**1a. Upgrade analytics priority (line 56)**

Change the "Analytics insights" row in "What Is Broken or Missing" table from `Low` to `Medium`:

```markdown
| Analytics insights | Plausible tracks visits but no documented insights, funnels, or conversion metrics. Weekly snapshots automated via CI. | Medium |
```

**1b. Add WoW growth targets to KPIs section (after line 330)**

Insert a new subsection `### Week-over-Week Growth Targets` after the Scale Phase table. Growth targets apply to **unique visitors only** -- other Tier 1 metrics are monitored directionally.

| Phase | Period | WoW Target | Absolute Target | Transition Trigger |
|-------|--------|-----------|----------------|-------------------|
| Phase 1: Content Traction | Weeks 1-4 (Mar 13 - Apr 10) | +15% WoW | 100/week by week 4 | Time-based |
| Phase 2: Content Velocity | Weeks 5-8 (Apr 11 - May 9) | +10% WoW | 250/week by week 8 | Time-based |
| Phase 3: Organic Growth | Weeks 9-16 (May 10 - Jul 4) | +7% WoW | 500/week by week 16 | Time-based |

Phase transitions are time-based (not threshold-based) to keep evaluation simple. The founder assesses target adherence during weekly review.

**1c. Add UTM Conventions section (before Review Cadence, ~line 376)**

Insert a new `## UTM Conventions` section. No UTM parameters exist anywhere in the codebase today -- distribution content uses bare URLs. Define:

| Parameter | Convention | Examples |
|-----------|-----------|----------|
| `utm_source` | Platform name (lowercase) | `discord`, `x`, `indiehackers`, `hackernews`, `github`, `email` |
| `utm_medium` | Channel type | `social`, `community`, `referral`, `newsletter` |
| `utm_campaign` | Article slug or campaign name | `caas-pillar`, `billion-dollar-solo`, `weekly-digest` |

Plausible reads UTM parameters natively from URL query strings -- no JavaScript changes needed. These conventions apply to all URLs in `distribution-content/*.md` files and social-distribute output.

**1d. Add Plausible Goal Configuration Checklist (in UTM Conventions or as subsection)**

Documented tasks for the founder to complete in the Plausible dashboard:

- [ ] Configure Newsletter Signup as a Plausible Goal (custom event -- already instrumented in `base.njk:134`)
- [ ] Create pageview goal for Getting Started (`/pages/getting-started.html`)
- [ ] Create pageview goal for blog articles (`/blog/*`)
- [ ] Enable outbound link tracking (built-in Plausible extension -- tracks clicks to GitHub, Discord)

### Deliverable 2: Weekly Analytics Snapshot Template

Create `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md` as a template. The CI workflow generates files matching this pattern.

**Template structure:**

```markdown
# Weekly Analytics Snapshot: YYYY-MM-DD

**Period:** YYYY-MM-DD to YYYY-MM-DD
**Generated:** YYYY-MM-DD (automated)

## Tier 1 Metrics

| Metric | This Week | Previous Week | Change |
|--------|-----------|--------------|--------|
| Unique visitors | N | N | +N% |
| Total pageviews | N | N | +N% |
| Bounce rate | N% | N% | +N pp |
| Visit duration | Nm Ns | Nm Ns | +N% |

## Top Pages (by visitors)

| Page | Visitors |
|------|----------|
| /path | N |

## Top Referral Sources

| Source | Visitors |
|--------|----------|
| source | N |

## Growth Target Check

- **Current phase:** Phase N (description)
- **WoW target:** +N%
- **Actual WoW change:** +N%
- **Status:** On track / Behind / Ahead
```

**Naming convention:** `YYYY-MM-DD-weekly-analytics.md` where the date is the Monday of the snapshot week. Matches the `YYYY-MM-DD-digest.md` pattern from community-monitor. Files accumulate (no pruning -- 52 small files/year is negligible).

### Deliverable 3: CI Workflow and Shell Script

**Shell script:** `scripts/weekly-analytics.sh`

Uses the Plausible Stats API v1 (`GET /api/v1/stats/...`). v1 is simpler for shell scripting (GET with query params vs. v2's POST with JSON bodies). The `compare=previous_period` parameter on the aggregate endpoint returns percent change natively, eliminating file-based delta calculation and division-by-zero edge cases.

**API calls (3 total):**

1. `GET /api/v1/stats/aggregate?site_id=<id>&period=7d&metrics=visitors,pageviews,bounce_rate,visit_duration&compare=previous_period`
   - Returns `{"visitors": {"value": N, "change": P}, ...}` with WoW percent change
2. `GET /api/v1/stats/breakdown?site_id=<id>&period=7d&property=event:page&limit=10`
   - Returns top 10 pages by visitors
3. `GET /api/v1/stats/breakdown?site_id=<id>&period=7d&property=visit:source&limit=10`
   - Returns top 10 referral sources

**Script requirements:**

- `#!/usr/bin/env bash` with `set -euo pipefail`
- Environment variables: `PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID`, optional `PLAUSIBLE_BASE_URL` (defaults to `https://plausible.io`)
- Early exit with warning if either required env var is empty
- HTTP status code checks on all API calls (401 = bad key, 429 = rate limited, 5xx = server error)
- On API error: print diagnostic, exit 1 (triggers Discord failure notification)
- Format visit_duration as "Nm Ns" (e.g., "1m 26s")
- Format bounce_rate change as percentage points, not percent change
- Growth target phase determined by date math (weeks since March 13, 2026)
- Output file: `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md`
- Uses `jq` for JSON parsing (available on `ubuntu-latest`)

**GitHub Actions workflow:** `.github/workflows/scheduled-weekly-analytics.yml`

```yaml
name: Weekly Analytics Snapshot
on:
  schedule:
    - cron: '0 6 * * 1'  # Every Monday at 06:00 UTC
  workflow_dispatch: {}

concurrency:
  group: weekly-analytics
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  snapshot:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Generate analytics snapshot
        env:
          PLAUSIBLE_API_KEY: ${{ secrets.PLAUSIBLE_API_KEY }}
          PLAUSIBLE_SITE_ID: ${{ secrets.PLAUSIBLE_SITE_ID }}
        run: bash scripts/weekly-analytics.sh

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add knowledge-base/marketing/analytics/
          git diff --cached --quiet && echo "No changes to commit" && exit 0
          git commit -m "ci: weekly analytics snapshot [skip ci]"
          git push origin main || { git pull --rebase origin main && git push origin main; }

      - name: Notify on failure
        if: failure()
        run: |
          # Standard Discord failure notification pattern
          # (implementation matches content-publisher.sh pattern)
```

**Follows established patterns:**
- `workflow_dispatch` alongside `schedule` for manual testing
- SHA-pinned checkout action
- `[skip ci]` commit message
- `git diff --cached --quiet` empty commit guard
- Push with rebase retry
- Discord failure notification step
- `permissions: contents: write`
- 10-minute timeout

### Deliverable 4: Plausible Setup Documentation

Included in Deliverable 1d (checklist in marketing-strategy.md). No separate document needed.

## Technical Considerations

- **Plausible API v1 vs v2:** Using v1. Simpler GET requests for shell scripting. `compare=previous_period` handles WoW deltas natively. v1 is still supported with no deprecation timeline. If Plausible deprecates v1, the fix is straightforward (rewrite curl calls to POST).
- **No claude-code-action needed:** This is a deterministic API-call-and-format workflow. Shell script is simpler, cheaper, and faster than an LLM agent. Follows content-publisher.sh pattern (Pattern A), not competitive-analysis pattern (Pattern B).
- **Secret setup required (founder action):** Create Plausible API key in dashboard, add `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` as GitHub repository secrets. Workflow gracefully skips if secrets are missing.
- **No legal document updates needed:** Plausible is already disclosed in all four legal documents. Reading data via API does not change what is tracked.
- **UTM integration with social-distribute:** The UTM conventions defined here should eventually be integrated into the social-distribute skill and content-publisher.sh. That is a follow-up task, not in scope for this PR.

## Acceptance Criteria

- [ ] marketing-strategy.md analytics priority upgraded from Low to Medium
- [ ] marketing-strategy.md contains WoW growth targets for all 3 phases with transition criteria
- [ ] marketing-strategy.md contains UTM Conventions section with parameter table
- [ ] marketing-strategy.md contains Plausible Goal Configuration Checklist
- [ ] Weekly snapshot template exists in `knowledge-base/marketing/analytics/`
- [ ] Shell script `scripts/weekly-analytics.sh` makes 3 API calls, formats markdown, handles errors
- [ ] CI workflow `scheduled-weekly-analytics.yml` runs weekly, commits snapshots, notifies on failure
- [ ] CI workflow exits 0 (not failure) when API key secrets are missing
- [ ] Shell script uses `set -euo pipefail` and follows constitution.md shell conventions

## Test Scenarios

- Given PLAUSIBLE_API_KEY and PLAUSIBLE_SITE_ID are set, when the workflow runs, then a snapshot markdown file is committed to `knowledge-base/marketing/analytics/`
- Given PLAUSIBLE_API_KEY is empty, when the workflow runs, then it prints a warning and exits 0 (no failure notification)
- Given the Plausible API returns HTTP 401, when the script runs, then it prints a diagnostic and exits 1 (triggers Discord notification)
- Given the Plausible API returns HTTP 429, when the script runs, then it prints a rate-limit warning and exits 1
- Given the previous week had 0 visitors and this week has 50, when `compare=previous_period` is used, then Plausible returns the correct percent change (no division by zero in script)
- Given a snapshot was already committed this week, when the workflow runs again, then `git diff --cached --quiet` skips the commit
- Given the growth target phase is Phase 1 (week 2 of 4), when the snapshot is generated, then the Growth Target Check section shows Phase 1 with +15% WoW target

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Plausible v1 API deprecated | v1 has no deprecation timeline. Fix is straightforward curl rewrite to v2 POST. |
| API key not configured for weeks | Workflow exits cleanly. Template supports manual capture until automation is live. |
| `compare=previous_period` returns unexpected format | Script validates response shape with jq before formatting. |
| Plausible rate limit (600 req/hr) | 3 calls per weekly run is negligible. Manual reruns via workflow_dispatch are the only risk -- mitigated by concurrency group. |

## References and Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-13-plausible-growth-targets-brainstorm.md`
- Spec: `knowledge-base/specs/feat-plausible-growth-targets/spec.md`
- Marketing strategy: `knowledge-base/marketing/marketing-strategy.md` (lines 56, 297-330, 377-382)
- Plausible script: `plugins/soleur/docs/_includes/base.njk:68-70`
- Shell script pattern: `scripts/content-publisher.sh`
- CI workflow pattern: `.github/workflows/scheduled-content-publisher.yml`
- Learning: `knowledge-base/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
- Learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Learning: `knowledge-base/learnings/2026-02-27-github-actions-sha-pinning-workflow.md`

### External References

- Plausible Stats API v1: https://plausible.io/docs/stats-api
- GitHub issue: #575
- Draft PR: #574

---
title: "feat: Plausible analytics operationalization and WoW growth targets"
type: feat
date: 2026-03-13
semver: patch
---

# Plausible Analytics Operationalization and WoW Growth Targets

## Overview

Turn Plausible from a passive tracking tool into an active growth feedback loop by updating the marketing strategy with WoW growth targets, building a shell script to pull Plausible API data into weekly markdown snapshots, and automating it via CI.

## Problem Statement / Motivation

Plausible is deployed on soleur.ai but not operationalized. The marketing strategy defines KPIs and a weekly review cadence (line 379) but zero measurements have been taken. Content distribution started March 12 -- without baselines, WoW tracking, and growth targets, there is no feedback loop. The existing KPIs are absolute milestones (500+ monthly visitors) which are lagging indicators. WoW growth rates are leading indicators that surface problems while fixable.

## Proposed Solution

Three deliverables:

### Deliverable 1: Update marketing-strategy.md

Edit `knowledge-base/marketing/marketing-strategy.md`:

**1a. Upgrade analytics priority (line 56)**

Change the "Analytics insights" row in "What Is Broken or Missing" table from `Low` to `Medium` and update the description to note weekly snapshots are automated via CI.

**1b. Add WoW growth targets to KPIs section (after line 330)**

Insert a new subsection `### Week-over-Week Growth Targets` after the Scale Phase table. Growth targets apply to **unique visitors only** -- other metrics are monitored directionally.

| Phase | Period | WoW Target | Absolute Target |
|-------|--------|-----------|----------------|
| Phase 1: Content Traction | Weeks 1-4 (Mar 13 - Apr 10) | +15% WoW | 100/week by week 4 |
| Phase 2: Content Velocity | Weeks 5-8 (Apr 11 - May 9) | +10% WoW | 250/week by week 8 |
| Phase 3: Organic Growth | Weeks 9-16 (May 10 - Jul 4) | +7% WoW | 500/week by week 16 |

Phase transitions are time-based. The founder assesses target adherence during weekly review. After Phase 3 ends, review targets quarterly based on accumulated data.

### Deliverable 2: Shell Script + CI Workflow

**Shell script:** `scripts/weekly-analytics.sh`

Uses the Plausible Stats API v1 (`GET /api/v1/stats/...`). v1 is simpler for shell scripting (GET with query params vs. v2's POST with JSON bodies). The `compare=previous_period` parameter on the aggregate endpoint returns percent change natively, eliminating file-based delta calculation and division-by-zero edge cases.

**API calls (3 total):**

1. `GET /api/v1/stats/aggregate?site_id=<id>&period=7d&metrics=visitors,pageviews&compare=previous_period`
   - Returns aggregate metrics with WoW percent change
   - **Note:** The exact response shape when `compare=previous_period` is used must be verified with a test request before implementation. The script must validate response shape with `jq` before formatting.
2. `GET /api/v1/stats/breakdown?site_id=<id>&period=7d&property=event:page&limit=10`
   - Returns top 10 pages by visitors
3. `GET /api/v1/stats/breakdown?site_id=<id>&period=7d&property=visit:source&limit=10`
   - Returns top 10 referral sources

**Script requirements:**

- `#!/usr/bin/env bash` with `set -euo pipefail`
- `# --- Section Name ---` comment headers per constitution.md convention
- `SCRIPT_DIR` / `REPO_ROOT` resolution for output path (matches content-publisher.sh pattern)
- Environment variables: `PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID`, optional `PLAUSIBLE_BASE_URL` (defaults to `https://plausible.io`)
- `PLAUSIBLE_SITE_ID` is typically the domain (e.g., `soleur.ai`)
- Early `exit 0` with warning to stdout if either required env var is empty (graceful skip, not failure)
- HTTP status code checks on all API calls (401 = bad key, 429 = rate limited, 5xx = server error)
- On API error: print diagnostic to stderr, exit 1 (triggers Discord failure notification)
- Use `jq` with `// empty` convention for null handling (constitution.md line 28)
- Handle empty breakdown results (zero-traffic weeks): show "No data" instead of empty table
- Current growth phase hardcoded as a variable at script top (e.g., `CURRENT_PHASE="Phase 1"`, `CURRENT_TARGET="+15%"`). Update manually when phases change -- avoids fragile bash date arithmetic.
- Output file: `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md` (date = Monday of snapshot week)
- Uses `jq` for JSON parsing (available on `ubuntu-latest`)
- **Local testing note:** GNU `date -d` is used for date formatting. macOS requires `gdate` from coreutils.

**Snapshot template (simplified):**

```markdown
# Weekly Analytics: YYYY-MM-DD

**Period:** YYYY-MM-DD to YYYY-MM-DD
**Generated:** automated

## Traffic

| Metric | This Week | Change |
|--------|-----------|--------|
| Unique visitors | N | +N% |
| Total pageviews | N | +N% |

**Growth target:** PHASE_NAME -- target PHASE_TARGET WoW, actual +N%.

## Top Pages

| Page | Visitors |
|------|----------|
| /path | N |

## Top Sources

| Source | Visitors |
|--------|----------|
| source | N |
```

**GitHub Actions workflow:** `.github/workflows/scheduled-weekly-analytics.yml`

```yaml
name: "Scheduled: Weekly Analytics"
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
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
        run: |
          [[ -z "${DISCORD_WEBHOOK_URL:-}" ]] && echo "No Discord webhook, skipping notification" && exit 0
          jq -n --arg content "Weekly analytics snapshot failed. Check: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            '{username: "Sol", avatar_url: "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/img/logo-mark-512.png", content: $content, allowed_mentions: {parse: []}}' \
            | curl -sf -X POST -H "Content-Type: application/json" -d @- "${DISCORD_WEBHOOK_URL}" -o /dev/null -w "%{http_code}" || true
```

### Deliverable 3: GitHub Issues for Follow-up Work

File two GitHub issues (not part of this PR, but tracked):

1. **Plausible dashboard goal configuration** -- checklist for founder: Newsletter Signup goal, Getting Started pageview goal, blog pageview goals, outbound link tracking
2. **UTM conventions + social-distribute integration** -- define UTM parameter conventions and integrate into social-distribute skill and content-publisher.sh

## Technical Considerations

- **Plausible API v1 vs v2:** Using v1. Simpler GET requests for shell scripting. v1 is still supported with no deprecation timeline. If Plausible deprecates v1, the fix is a straightforward curl rewrite to v2 POST.
- **No claude-code-action needed:** This is a deterministic API-call-and-format workflow. Shell script is simpler, cheaper, and faster than an LLM agent.
- **Secret setup required (founder action):** Create Plausible API key in dashboard, add `PLAUSIBLE_API_KEY` (API key) and `PLAUSIBLE_SITE_ID` (domain, e.g., `soleur.ai`) as GitHub repository secrets. Workflow gracefully skips if secrets are missing.
- **No legal document updates needed:** Plausible is already disclosed in all four legal documents. Reading data via API does not change what is tracked.

## Acceptance Criteria

- [ ] marketing-strategy.md analytics priority upgraded from Low to Medium
- [ ] marketing-strategy.md contains WoW growth targets for all 3 phases
- [ ] Shell script `scripts/weekly-analytics.sh` makes 3 API calls, formats markdown, handles errors
- [ ] Shell script exits 0 with warning when API key secrets are missing
- [ ] Shell script exits 1 on API errors (401, 429, 5xx)
- [ ] CI workflow `scheduled-weekly-analytics.yml` runs weekly, commits snapshots, notifies on failure
- [ ] Shell script uses `set -euo pipefail`, `# --- Section ---` headers, `jq // empty` convention
- [ ] GitHub issues filed for Plausible goal config and UTM conventions

## Test Scenarios

- Given PLAUSIBLE_API_KEY and PLAUSIBLE_SITE_ID are set, when the workflow runs, then a snapshot markdown file is committed to `knowledge-base/marketing/analytics/`
- Given PLAUSIBLE_API_KEY is empty, when the script runs, then it prints a warning and exits 0
- Given the Plausible API returns HTTP 401, when the script runs, then it prints a diagnostic to stderr and exits 1
- Given the site had zero visitors this week, when breakdown endpoints return empty arrays, then the snapshot shows "No data" for top pages and sources
- Given a snapshot was already committed this week, when the workflow runs again, then `git diff --cached --quiet` skips the commit

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Plausible v1 API deprecated | v1 has no deprecation timeline. Fix is straightforward curl rewrite to v2 POST. |
| API key not configured for weeks | Workflow exits cleanly with exit 0. |
| `compare=previous_period` returns unexpected format | Script validates response shape with jq before formatting. Verify with test request during implementation. |
| Plausible rate limit (600 req/hr) | 3 calls per weekly run is negligible. |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-13-plausible-growth-targets-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-plausible-growth-targets/spec.md`
- Marketing strategy: `knowledge-base/marketing/marketing-strategy.md` (lines 56, 297-330, 377-382)
- Shell script pattern: `scripts/content-publisher.sh`
- CI workflow pattern: `.github/workflows/scheduled-content-publisher.yml`
- Learning: `knowledge-base/project/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
- Learning: `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- [Plausible Stats API v1](https://plausible.io/docs/stats-api)
- GitHub issue: #575 / Draft PR: #574

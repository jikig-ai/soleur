# Tasks: Plausible Analytics Operationalization

## Phase 1: Marketing Strategy Updates

- [ ] 1.1 Update analytics priority in "What Is Broken or Missing" table (line 56) from `Low` to `Medium`
  - File: `knowledge-base/marketing/marketing-strategy.md`
- [ ] 1.2 Add `### Week-over-Week Growth Targets` subsection after Scale Phase table (after line 330)
  - 3-phase table: +15% / +10% / +7% WoW for unique visitors
  - Phase transition criteria: time-based (weeks since March 13)
  - Note: growth targets apply to unique visitors only; other metrics monitored directionally
- [ ] 1.3 Add `## UTM Conventions` section before Review Cadence (~line 376)
  - Parameter table: utm_source, utm_medium, utm_campaign
  - Platform names: discord, x, indiehackers, hackernews, github, email
  - Note: Plausible reads UTM params natively from URL query strings
- [ ] 1.4 Add `### Plausible Goal Configuration Checklist` within UTM section
  - Newsletter Signup goal (custom event, already instrumented)
  - Getting Started pageview goal (`/pages/getting-started.html`)
  - Blog pageview goals (`/blog/*`)
  - Outbound link tracking (built-in extension)
- [ ] 1.5 Update `last_updated` frontmatter field to `2026-03-13`
- [ ] 1.6 Update `depends_on` to add reference to analytics snapshot directory

## Phase 2: Weekly Analytics Snapshot Template

- [ ] 2.1 Create `knowledge-base/marketing/analytics/` directory
- [ ] 2.2 Create snapshot template file `knowledge-base/marketing/analytics/README.md`
  - Explain purpose, naming convention (YYYY-MM-DD-weekly-analytics.md), and how CI populates it
  - Reference the growth targets from marketing-strategy.md

## Phase 3: Shell Script

- [ ] 3.1 Create `scripts/weekly-analytics.sh`
  - [ ] 3.1.1 Shebang + `set -euo pipefail` + section headers
  - [ ] 3.1.2 Environment variable validation (early exit with warning if PLAUSIBLE_API_KEY or PLAUSIBLE_SITE_ID empty)
  - [ ] 3.1.3 Plausible API aggregate call with `compare=previous_period` (visitors, pageviews, bounce_rate, visit_duration)
  - [ ] 3.1.4 Plausible API breakdown call for top pages (event:page, limit 10)
  - [ ] 3.1.5 Plausible API breakdown call for referral sources (visit:source, limit 10)
  - [ ] 3.1.6 HTTP status code validation on all API calls (401, 429, 5xx handling)
  - [ ] 3.1.7 Format visit_duration as "Nm Ns" (seconds to human-readable)
  - [ ] 3.1.8 Growth target phase calculation (date math: weeks since 2026-03-13)
  - [ ] 3.1.9 Assemble snapshot markdown from API data
  - [ ] 3.1.10 Write output to `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md`
- [ ] 3.2 Make script executable: `chmod +x scripts/weekly-analytics.sh`

## Phase 4: GitHub Actions Workflow

- [ ] 4.1 Create `.github/workflows/scheduled-weekly-analytics.yml`
  - [ ] 4.1.1 Triggers: schedule (cron Monday 06:00 UTC) + workflow_dispatch
  - [ ] 4.1.2 Concurrency group: `weekly-analytics`, cancel-in-progress: false
  - [ ] 4.1.3 Permissions: contents: write
  - [ ] 4.1.4 Job: ubuntu-latest, timeout-minutes: 10
  - [ ] 4.1.5 Step: checkout (SHA-pinned: `34e114876b0b11c390a56381ad16ebd13914f8d5`)
  - [ ] 4.1.6 Step: run script with PLAUSIBLE_API_KEY and PLAUSIBLE_SITE_ID from secrets
  - [ ] 4.1.7 Step: commit and push with `[skip ci]`, git diff guard, rebase retry
  - [ ] 4.1.8 Step: Discord failure notification (standard pattern)

## Phase 5: Testing

- [ ] 5.1 Verify shell script runs locally with mock/empty env vars (graceful skip)
- [ ] 5.2 Verify workflow YAML is valid (actionlint or manual inspection)
- [ ] 5.3 Verify marketing-strategy.md renders correctly with all new sections
- [ ] 5.4 Run markdownlint on all modified/created files

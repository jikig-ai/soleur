# Tasks: Plausible Analytics Operationalization

## Phase 1: Marketing Strategy Updates

- [ ] 1.1 Edit `knowledge-base/marketing/marketing-strategy.md`:
  - Upgrade analytics priority row (line 56) from `Low` to `Medium`, update description
  - Add `### Week-over-Week Growth Targets` subsection after Scale Phase table (after line 330)
  - Update `last_updated` frontmatter to `2026-03-13`

## Phase 2: Shell Script

- [ ] 2.1 Create `scripts/weekly-analytics.sh`
  - Shebang + `set -euo pipefail` + `SCRIPT_DIR`/`REPO_ROOT` resolution + `# --- Section ---` headers
  - Early `exit 0` with warning if `PLAUSIBLE_API_KEY` or `PLAUSIBLE_SITE_ID` is empty
  - 3 Plausible API v1 calls (aggregate with `compare=previous_period`, page breakdown, source breakdown)
  - HTTP status code validation (401, 429, 5xx → stderr diagnostic + exit 1)
  - `jq` parsing with `// empty` null handling
  - Empty breakdown handling ("No data" for zero-traffic weeks)
  - Hardcoded `CURRENT_PHASE` and `CURRENT_TARGET` variables (no date math)
  - Assemble and write snapshot markdown to `knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md`
- [ ] 2.2 `chmod +x scripts/weekly-analytics.sh`

## Phase 3: CI Workflow

- [ ] 3.1 Create `.github/workflows/scheduled-weekly-analytics.yml`
  - `"Scheduled: Weekly Analytics"` name (repo convention)
  - Triggers: schedule (cron Monday 06:00 UTC) + workflow_dispatch
  - Concurrency, permissions (contents: write), timeout (10 min)
  - Checkout (SHA-pinned), run script with secrets, commit/push with `[skip ci]` + git diff guard + rebase retry
  - Discord failure notification step (full implementation, not stub)

## Phase 4: Follow-up Issues

- [ ] 4.1 File GitHub issue: Plausible dashboard goal configuration (Newsletter Signup, Getting Started, blog, outbound links)
- [ ] 4.2 File GitHub issue: UTM conventions + social-distribute integration

## Phase 5: Verification

- [ ] 5.1 Run `weekly-analytics.sh` with empty env vars, verify exit 0 with warning
- [ ] 5.2 Run markdownlint on all modified/created files

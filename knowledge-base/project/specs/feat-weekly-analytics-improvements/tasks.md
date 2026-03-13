# Tasks: Weekly Analytics Improvements

## Phase 1: Setup

- [ ] 1.1 Read existing `scripts/weekly-analytics.sh` and `.github/workflows/scheduled-weekly-analytics.yml`
- [ ] 1.2 Read `knowledge-base/marketing/marketing-strategy.md` lines 331-341 for phase date ranges
- [ ] 1.3 Read learnings: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`

## Phase 2: Core Implementation

- [ ] 2.1 Add `detect_phase()` function to `scripts/weekly-analytics.sh`
  - [ ] 2.1.1 Define phase config block with date ranges and targets (Phase 1: Mar 13 - Apr 10 +15%, Phase 2: Apr 11 - May 9 +10%, Phase 3: May 10 - Jul 4 +7%)
  - [ ] 2.1.2 Implement epoch-based date comparison using `date -d` with macOS `date -v` fallback
  - [ ] 2.1.3 Add "Post-Phase 3" fallback for dates after Jul 4
  - [ ] 2.1.4 Remove hardcoded `CURRENT_PHASE` and `CURRENT_TARGET` variables (lines 31-32)
  - [ ] 2.1.5 Call `detect_phase` before snapshot generation to set `CURRENT_PHASE` and `CURRENT_TARGET`

- [ ] 2.2 Add trend summary append logic to `scripts/weekly-analytics.sh`
  - [ ] 2.2.1 Define `TREND_FILE` path as `$OUTPUT_DIR/trend-summary.md`
  - [ ] 2.2.2 Create trend summary file with header if it does not exist
  - [ ] 2.2.3 Calculate week number from Phase 1 start date (2026-03-13)
  - [ ] 2.2.4 Determine status: compare numeric `VISITORS_CHANGE` against numeric target threshold
  - [ ] 2.2.5 Add idempotency guard: check if `SNAPSHOT_DATE` already exists in trend file before appending
  - [ ] 2.2.6 Append data row to trend summary file

- [ ] 2.3 Add KPI miss signal logic to `scripts/weekly-analytics.sh`
  - [ ] 2.3.1 After computing metrics, compare `VISITORS_CHANGE` against numeric target
  - [ ] 2.3.2 Skip alert when: change is empty/null/N/A, or phase is post-Phase 3
  - [ ] 2.3.3 Write signal file with miss details (phase, target, actual, visitors) when below target
  - [ ] 2.3.4 Use `GITHUB_WORKSPACE` for signal file path if available, otherwise `/tmp`

- [ ] 2.4 Add KPI miss Discord alert step to `.github/workflows/scheduled-weekly-analytics.yml`
  - [ ] 2.4.1 Add step after "Generate analytics snapshot" that checks for signal file
  - [ ] 2.4.2 Send Discord notification with phase, target, actual values (matching existing webhook payload format: username, avatar_url, allowed_mentions)
  - [ ] 2.4.3 Gracefully skip if `DISCORD_WEBHOOK_URL` is not set

## Phase 3: Testing

- [ ] 3.1 Verify `detect_phase()` returns correct values for dates in each phase and post-Phase 3
- [ ] 3.2 Verify trend summary file creation and append (no duplicates on re-run)
- [ ] 3.3 Verify KPI miss signal file is written when WoW < target and not written when WoW >= target
- [ ] 3.4 Verify KPI alert step sends Discord notification when signal file exists
- [ ] 3.5 Verify script still exits 0 on KPI miss
- [ ] 3.6 Verify existing snapshot format is unchanged
- [ ] 3.7 Run `bash -n scripts/weekly-analytics.sh` for syntax validation
- [ ] 3.8 Run markdownlint on plan and any new markdown files

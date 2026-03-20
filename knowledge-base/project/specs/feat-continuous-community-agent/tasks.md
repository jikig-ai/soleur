# Tasks: Continuous Community Agent

**Issue:** #145
**Plan:** `knowledge-base/project/plans/2026-03-10-feat-scheduled-community-monitoring-workflow-plan.md`

## Phase 1: Create Workflow

- [x] 1.1 Create `.github/workflows/scheduled-community-monitor.yml` with:
  - `workflow_dispatch` trigger only (cron added after validation)
  - `concurrency: { group: schedule-community-monitor, cancel-in-progress: false }`
  - `permissions: { contents: write, issues: write, id-token: write }`
  - `timeout-minutes: 30`
- [x] 1.2 Add checkout step pinned to SHA (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`)
- [x] 1.3 Add label pre-creation step (`scheduled-community-monitor`)
- [x] 1.4 Add `claude-code-action` step with:
  - `--model claude-sonnet-4-6 --max-turns 30 --allowedTools Bash,Read,Write,Edit,Glob,Grep`
  - `env:` block mapping all platform secrets
  - Agent prompt: AGENTS.md override, run community skill with 1-day lookback, X fetch-metrics only, commit+push with rebase fallback, create GitHub Issue
- [x] 1.5 Add Discord failure notification step (`if: failure()`) with `allowed_mentions: {parse: []}`

## Phase 2: Verify

- [x] 2.1 Validate YAML syntax
- [x] 2.2 Verify all Actions pinned to commit SHAs
- [x] 2.3 Verify `env:` block maps all secrets correctly
- [ ] 2.4 Test with `gh workflow run scheduled-community-monitor.yml` after merge

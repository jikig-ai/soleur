# Tasks: Continuous Community Agent

**Issue:** #145
**Plan:** `knowledge-base/plans/2026-03-10-feat-scheduled-community-monitoring-workflow-plan.md`

## Phase 1: Workflow Creation

- [ ] 1.1 Create `.github/workflows/scheduled-community-monitor.yml` with:
  - `cron: '0 8 * * *'` + `workflow_dispatch` triggers
  - `concurrency: { group: schedule-community-monitor, cancel-in-progress: false }`
  - `permissions: { contents: write, issues: write, id-token: write }`
  - `timeout-minutes: 30`
- [ ] 1.2 Add `Checkout repository` step pinned to commit SHA (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`)
- [ ] 1.3 Add `Ensure label exists` step: pre-create `scheduled-community-monitor` label via `gh label create`
- [ ] 1.4 Add `Check for existing failure issue` step: query `gh issue list --label scheduled-community-monitor --state open` and set output for dedup
- [ ] 1.5 Add `Run community monitor` step using `anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf # v1` with:
  - `--model claude-sonnet-4-6 --max-turns 30 --allowedTools Bash,Read,Write,Edit,Glob,Grep`
  - `plugin_marketplaces` and `plugins` for Soleur
  - Full agent prompt (see 1.6)
- [ ] 1.6 Write agent prompt covering:
  - AGENTS.md override for direct-to-main commits
  - Platform detection (Discord: 2 vars, X: all 4 vars, partial = error)
  - Discord data collection via `discord-community.sh` (guild-info, members, channels, messages)
  - X metrics via `x-community.sh fetch-metrics` only (skip fetch-mentions/fetch-timeline)
  - 1-day lookback window (override default 7-day)
  - Digest generation to `knowledge-base/community/YYYY-MM-DD-digest.md`
  - Commit and push with rebase fallback
  - GitHub Issue creation with `scheduled-community-monitor` label
  - Brand guide voice reference
  - `allowed_mentions: {parse: []}` on any Discord payloads
  - No raw message storage (brief quotes OK)

## Phase 2: Failure Handling

- [ ] 2.1 Add `Discord notification (failure)` step with `if: failure()`:
  - Check `DISCORD_WEBHOOK_URL` presence
  - Build JSON payload with `allowed_mentions: {parse: []}`, `username: "Sol"`, `avatar_url`
  - Post via `curl` with HTTP status check
- [ ] 2.2 Add failure issue dedup logic:
  - If `failure_check` found an open issue, `gh issue comment` on it
  - Otherwise, `gh issue create` with `scheduled-community-monitor` label

## Phase 3: Verification

- [ ] 3.1 Validate YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-community-monitor.yml'))"`
- [ ] 3.2 Verify all GitHub Actions are pinned to commit SHAs (not tags)
- [ ] 3.3 Verify secrets are referenced correctly (`${{ secrets.ANTHROPIC_API_KEY }}`, etc.)
- [ ] 3.4 Verify `allowed_mentions: {parse: []}` is present in all Discord webhook payloads
- [ ] 3.5 Test with `gh workflow run scheduled-community-monitor.yml` after merge (manual verification)

# Tasks: Scheduled Ship-Merge Workflow

**Plan:** `knowledge-base/plans/2026-03-05-feat-scheduled-ship-merge-workflow-plan.md`
**Issue:** #417
**Branch:** feat-scheduled-ship-merge

## Phase 1: Implementation

### 1.1 Create `scheduled-ship-merge.yml` workflow file

- [ ] Create `.github/workflows/scheduled-ship-merge.yml`
- [ ] Add security comment block at top (same pattern as `scheduled-bug-fixer.yml`)
- [ ] Configure triggers: `schedule` (cron `0 9 * * *`) + `workflow_dispatch` with optional `pr_number` input
- [ ] Set concurrency group `schedule-ship-merge`, cancel-in-progress false
- [ ] Set permissions: `contents: write`, `pull-requests: write`, `issues: write`, `id-token: write`
- [ ] Set `timeout-minutes: 30` on the job

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.2 Implement label pre-creation step

- [ ] Pre-create `ship/scheduled`, `ship/failed`, `no-auto-ship` labels idempotently
- [ ] Use `gh label create ... 2>/dev/null || true` pattern

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.3 Implement PR selection step

- [ ] Handle `workflow_dispatch` `pr_number` override (bypass query if provided)
- [ ] Implement jq filter: not draft, targets main, 24h+ old, CI all passing, no exclusion labels
- [ ] Calculate CUTOFF with `date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ`
- [ ] Use `statusCheckRollup` for CI status (require length > 0, all COMPLETED + SUCCESS)
- [ ] Apply `ship/scheduled` label to selected PR
- [ ] Write `pr_number` to `GITHUB_OUTPUT` (sanitize with `tr -d '\n\r'`)
- [ ] If no qualifying PR found, exit 0 with message

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.4 Implement setup and checkout steps

- [ ] Add `actions/checkout` step (SHA: `34e114876b0b11c390a56381ad16ebd13914f8d5`)
- [ ] Add `oven-sh/setup-bun` step (SHA: `3d267786b128fe76c2f16a390aa2448b815359f3`)
- [ ] Add `gh pr checkout` step (conditional on PR being selected)

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.5 Implement claude-code-action step

- [ ] Use `anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1)
- [ ] Configure `anthropic_api_key`, `plugin_marketplaces`, `plugins` inputs
- [ ] Set `claude_args`: `--model claude-sonnet-4-6 --max-turns 40 --allowedTools Bash,Read,Write,Edit,Glob,Grep`
- [ ] Set prompt: `Run /soleur:ship --headless`
- [ ] Conditional on PR being selected

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.6 Implement post step (cleanup/failure handling)

- [ ] Use `if: always()` to run regardless of previous step outcome
- [ ] Check PR state via `gh pr view <number> --json state --jq .state`
- [ ] If MERGED: remove `ship/scheduled` label, exit 0
- [ ] If job succeeded but not merged: remove `ship/scheduled` label (ship updated PR)
- [ ] If job failed: remove `ship/scheduled`, apply `ship/failed`, post PR comment with Actions run URL
- [ ] PR comment includes: failure notice, run URL (`$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID`), instructions to remove `ship/failed` to re-queue

**Files:** `.github/workflows/scheduled-ship-merge.yml`

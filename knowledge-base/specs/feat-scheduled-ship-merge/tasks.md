# Tasks: Scheduled Ship-Merge Workflow

**Plan:** `knowledge-base/plans/2026-03-05-feat-scheduled-ship-merge-workflow-plan.md`
**Issue:** #417
**Branch:** feat-scheduled-ship-merge

## Phase 1: Implementation

### 1.1 Create workflow file with triggers, permissions, and concurrency

- [ ] Create `.github/workflows/scheduled-ship-merge.yml`
- [ ] Add security comment block at top (copy pattern from `scheduled-bug-fixer.yml`)
- [ ] Configure trigger: `workflow_dispatch` with optional `pr_number` input (cron deferred to post-#419)
- [ ] Set concurrency group `schedule-ship-merge`, cancel-in-progress false
- [ ] Set permissions: `contents: write`, `pull-requests: write`, `issues: write`, `id-token: write`
- [ ] Set `timeout-minutes: 30` on the job

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.2 Implement label pre-creation and PR selection steps

- [ ] Pre-create `ship/failed`, `no-auto-ship` labels idempotently (`2>/dev/null || true`)
- [ ] Handle `workflow_dispatch` `pr_number` override (bypass query if provided)
- [ ] Implement jq filter: not draft, targets main, 24h+ old, no `ship/failed` or `no-auto-ship` labels
- [ ] Calculate CUTOFF with `date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ`
- [ ] Post-selection: verify required checks pass via `gh pr checks "$PR" --required`
- [ ] Write `pr_number` to `GITHUB_OUTPUT` (sanitize with `tr -d '\n\r'`)
- [ ] If no qualifying PR found or checks failing, exit 0 with message

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.3 Implement checkout, setup, and claude-code-action steps

- [ ] Add `actions/checkout` step (SHA: `34e114876b0b11c390a56381ad16ebd13914f8d5`)
- [ ] Add `oven-sh/setup-bun` step (SHA: `3d267786b128fe76c2f16a390aa2448b815359f3`)
- [ ] Add `bun install` step
- [ ] Add `gh pr checkout` step (conditional on PR being selected)
- [ ] Add `claude-code-action` step with `--model claude-sonnet-4-6 --max-turns 40 --allowedTools Bash,Read,Write,Edit,Glob,Grep`
- [ ] Set prompt: `Run /soleur:ship --headless`
- [ ] Configure `plugin_marketplaces` and `plugins` inputs (same as bug-fixer)

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.4 Implement post step

- [ ] Use `if: always()` condition
- [ ] Check PR state via `gh pr view <number> --json state --jq .state`
- [ ] If MERGED: exit 0
- [ ] If not MERGED: apply `ship/failed` label, post PR comment with Actions run URL

**Files:** `.github/workflows/scheduled-ship-merge.yml`

# Tasks: Scheduled Ship-Merge Workflow

**Plan:** `knowledge-base/project/plans/2026-03-05-feat-scheduled-ship-merge-workflow-plan.md`
**Issue:** #417
**Branch:** feat-scheduled-ship-merge

## Phase 1: Implementation

### 1.1 Create workflow file with triggers, permissions, and concurrency

- [x] Create `.github/workflows/scheduled-ship-merge.yml`
- [x] Add security comment block at top (copy pattern from `scheduled-bug-fixer.yml`)
- [x] Configure trigger: `workflow_dispatch` with optional `pr_number` input (cron deferred to post-#419)
- [x] Set concurrency group `schedule-ship-merge`, cancel-in-progress false
- [x] Set permissions: `contents: write`, `pull-requests: write`, `issues: write`, `id-token: write`
- [x] Set `timeout-minutes: 30` on the job

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.2 Implement label pre-creation and PR selection steps

- [x] Pre-create `ship/failed`, `no-auto-ship` labels idempotently (`2>/dev/null || true`)
- [x] Handle `workflow_dispatch` `pr_number` override (bypass query if provided)
- [x] Implement jq filter: not draft, targets main, 24h+ old, no `ship/failed` or `no-auto-ship` labels
- [x] Calculate CUTOFF with `date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ`
- [x] Post-selection: verify required checks pass via `gh pr checks "$PR" --required`
- [x] Write `pr_number` to `GITHUB_OUTPUT` (sanitize with `tr -d '\n\r'`)
- [x] If no qualifying PR found or checks failing, exit 0 with message

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.3 Implement checkout, setup, and claude-code-action steps

- [x] Add `actions/checkout` step (SHA: `34e114876b0b11c390a56381ad16ebd13914f8d5`)
- [x] Add `oven-sh/setup-bun` step (SHA: `3d267786b128fe76c2f16a390aa2448b815359f3`)
- [x] Add `bun install` step
- [x] Add `gh pr checkout` step (conditional on PR being selected)
- [x] Add `claude-code-action` step with `--model claude-sonnet-4-6 --max-turns 40 --allowedTools Bash,Read,Write,Edit,Glob,Grep`
- [x] Set prompt: `Run /soleur:ship --headless`
- [x] Configure `plugin_marketplaces` and `plugins` inputs (same as bug-fixer)

**Files:** `.github/workflows/scheduled-ship-merge.yml`

### 1.4 Implement post step

- [x] Use `if: always()` condition
- [x] Check PR state via `gh pr view <number> --json state --jq .state`
- [x] If MERGED: exit 0
- [x] If not MERGED: apply `ship/failed` label, post PR comment with Actions run URL

**Files:** `.github/workflows/scheduled-ship-merge.yml`

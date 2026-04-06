---
module: System
date: 2026-04-06
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Pre-push hook fails on deleted test files"
  - "Docker image prune removes unrelated images"
  - "Worktrees disappear between conversation turns"
  - "GitHub API connection resets on bulk secret deletion"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [app-removal, pre-push-hook, docker-prune, worktree-race, github-api]
---

# Learning: App Removal Blast Radius Patterns

## Problem

When removing an entire application (`apps/telegram-bridge/`) from a monorepo, several infrastructure edge cases surfaced that are not covered by standard development workflows.

## Solution

### 1. Pre-push hook: deleted test files

The `scripts/hooks/pre-push` hook collects changed files from `git diff --name-only origin/main...HEAD`, which includes deleted files. When a deleted `.test.ts` file was passed to `bun test`, it failed because the file doesn't exist on disk.

**Fix:** Add `-f "$file"` existence check before adding test files to the run list (line 50 of `scripts/hooks/pre-push`).

### 2. Docker image prune blast radius

`docker image prune -af` on the production server removed ALL unused images, including the `soleur-web-platform` image — not just the bridge image. The running container was unaffected (it holds a reference), but the image would need to be re-pulled on next deploy.

**Prevention:** Use targeted removal instead of blanket prune: `docker rmi ghcr.io/jikig-ai/soleur-telegram-bridge:v0.1.28` to remove only the specific image.

### 3. Worktree race condition with concurrent sessions

The worktree created in one conversation turn was absent in the next. Root cause: another concurrent Claude Code session ran `cleanup-merged`, which removed worktrees whose branches no longer had upstream tracking.

**Prevention:** After creating a worktree, immediately push the branch (`git push -u origin <branch>`) so `cleanup-merged` won't consider it orphaned.

### 4. GitHub API connection resets

Bulk deleting 6 GitHub secrets sequentially hit TCP connection resets on 2 of 6 calls. The GitHub API occasionally resets connections during rapid sequential requests.

**Prevention:** Retry failed `gh secret delete` calls. The operation is idempotent — retrying is safe.

## Key Insight

App removal is a rare but high-blast-radius operation. Standard hooks and scripts are designed for additive changes (new files, new tests) and can break on subtractive changes (deleted apps, deleted test files). When planning a removal, audit each hook and script for assumptions about file existence.

## Session Errors

1. **Worktree disappeared between conversation turns** — Recovery: recreated with `git worktree add`. Prevention: push branch immediately after worktree creation to prevent cleanup-merged race.
2. **Pre-push hook blocked push due to deleted test files** — Recovery: fixed the hook to check file existence. Prevention: hooks that collect files from git diff should always verify files exist on disk before running them.
3. **Two GitHub secret deletions failed (connection reset)** — Recovery: retried successfully. Prevention: add retry logic for bulk GitHub API operations.
4. **Docker image prune removed web-platform image** — Recovery: no immediate action needed (container still running). Prevention: use targeted `docker rmi` instead of `docker image prune -af` when removing specific app images.

## Tags

category: workflow-patterns
module: System

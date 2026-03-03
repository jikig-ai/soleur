# Learning: Scheduled Bot-Fix Workflow Patterns

## Problem

Designing a daily automated agent that picks up low-priority bugs and opens PRs requires several non-obvious patterns to avoid infinite loops, false negatives, and auto-closing issues prematurely.

## Solution

Four key patterns emerged during the supervised bug-fix agent implementation (#376, #385):

### 1. Test Baseline Before Changes

Run `bun test` before making any changes. Record pass/fail state. After the fix, compare against baseline. Only new failures introduced by the fix are grounds for aborting -- pre-existing failures are acceptable. Without this, agents abort on repos with any pre-existing test failures.

### 2. Cascading Priority Selection

Don't hardcode a single priority level. If no p3-low bugs exist, the bot sits idle. Instead, cascade through priority levels:

```bash
for PRIORITY in priority/p3-low priority/p2-medium priority/p1-high; do
  ISSUE=$(gh issue list --label "$PRIORITY" --label "type/bug" ...)
  if [[ -n "$ISSUE" ]]; then break; fi
done
```

This ensures the bot always attempts the lowest-priority available bug first, but escalates when the backlog at lower levels is empty. Discovered during dogfooding when both open bugs were p2-medium and the bot found nothing to fix.

### 3. Label-Based Retry Prevention

Add `bot-fix/attempted` label on failure. Filter with `--jq` since `gh issue list` has no `--exclude-label` flag:

```bash
gh issue list --label "priority/p3-low" --label "type/bug" --state open \
  --json number,labels,createdAt \
  --jq '[.[] | select(.labels | map(.name) | index("bot-fix/attempted") | not)] | sort_by(.createdAt) | .[0].number // empty'
```

Note: `gh issue list` returns newest-first by default. Use `sort_by(.createdAt) | .[0]` to get the oldest issue (FIFO backlog processing).

### 4. Ref Not Closes in Bot PRs

Use `Ref #N` in PR body, never `Closes #N`, `Fixes #N`, or `Resolves #N`. Bot PRs must not auto-close issues. The human reviewer verifies the fix works and manually closes the issue. This prevents premature closure of issues that the bot only partially fixed.

## Key Insight

Prompt-only constraints (single-file, no deps) are acceptable when a human reviewer is the real safety gate. Mechanical enforcement adds complexity without value when every PR requires human approval anyway. The bot's job is to produce a candidate fix, not a guaranteed one.

## Tags

category: workflow-patterns
module: scheduled-bug-fixer

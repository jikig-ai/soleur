---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, architecture, configuration]
dependencies: []
---

# Make model and permission flag configurable via env vars

## Problem Statement

`--model claude-opus-4-6` and `--dangerously-skip-permissions` are hardcoded. Changing the model or permission mode requires code changes and redeployment.

## Findings

- **architecture-strategist**: "should be configurable via environment variable with a sensible default"

## Proposed Solutions

Add env vars:
```typescript
const CLAUDE_MODEL = process.env.CLAUDE_MODEL ?? "claude-opus-4-6";
const SKIP_PERMISSIONS = process.env.SKIP_PERMISSIONS !== "false"; // default true for headless
```

- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] `CLAUDE_MODEL` env var controls `--model` flag
- [ ] `SKIP_PERMISSIONS` env var controls `--dangerously-skip-permissions`
- [ ] `.env.example` updated with new vars
- [ ] README documents new configuration

## Work Log
- 2026-02-11: Identified during /soleur:review

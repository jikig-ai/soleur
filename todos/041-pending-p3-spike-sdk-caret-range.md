---
status: pending
priority: p3
issue_id: 1045
tags: [code-review, security, supply-chain]
dependencies: []
---

# spike/package.json still uses caret range for Agent SDK

## Problem Statement

`spike/package.json` declares `"@anthropic-ai/claude-agent-sdk": "^0.2.76"` with a caret range. While this is not production code, it could mislead a developer into copying the caret pattern when adding new SDK dependencies.

## Findings

- **Source:** security-sentinel review of PR #1182
- **Location:** `spike/package.json:13`
- **Severity:** P3 (pre-existing, not introduced by this PR)
- **Note:** The spike directory is an exploratory artifact. If it is still referenced for testing, consider aligning it with the production pin or archiving it.

## Proposed Solutions

### Option A: Pin spike to exact version

- **Pros:** Consistent with production, prevents copy-paste drift
- **Cons:** Spike may be archived/unused
- **Effort:** Small
- **Risk:** Low

### Option B: Archive spike directory

- **Pros:** Removes the inconsistency entirely
- **Cons:** Loses reference material
- **Effort:** Small
- **Risk:** Low

## Recommended Action

(To be filled during triage)

## Acceptance Criteria

- [ ] `spike/package.json` either pinned to exact version or spike directory archived

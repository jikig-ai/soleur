---
status: complete
priority: p3
issue_id: "009"
tags: [code-review, performance, ux]
dependencies: []
---

# Debounce tool-use notifications to prevent rate limiting

## Problem Statement

Each tool-use fires a separate Telegram API call. Bursts of 20+ tool calls can hit Telegram's 30 msg/sec rate limit, silently dropping notifications.

## Findings

- **performance-oracle**: "burst of 30+ tool calls could trigger 429 from Telegram"

## Proposed Solutions

Batch tool names over a 500ms window, send single message listing all tools invoked.
- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Tool notifications batched within 500ms window
- [ ] Single message sent per batch
- [ ] 429 errors logged instead of swallowed

## Work Log
- 2026-02-11: Identified during /soleur:review

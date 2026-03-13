---
title: Repurpose existing message for streaming to avoid flicker
date: 2026-03-02
category: infrastructure
tags: [implementation-patterns, telegram-bridge]
---

# Learning: Repurpose existing message for streaming to avoid flicker

## Problem
The Telegram bridge showed a static "Thinking..." message for 10-30+ seconds while Claude generated responses. Users had no feedback during generation.

## Solution
Repurposed the "Thinking..." status message via `editMessageText` with accumulated text deltas from the CLI's `stream_event` NDJSON lines. Key patterns:

- **Throttled edits** at 2.5s intervals (Telegram allows ~20 edits/min)
- **messageId: 0 sentinel** guards edits before the status message resolves (reused from P1-012 async lifecycle learning)
- **Split at MAX_CHUNK_SIZE** (4000 chars) to stay under Telegram's 4096-char limit — finalize current, start new streaming message
- **cleanupTurnStatus skips deleteMessage** when streaming is active — the status message IS the streaming message
- **Plain text during streaming, HTML on final edit** — avoids partial markdown rendering artifacts

## Key Insight
Editing an existing message instead of delete+send eliminates flicker and halves API calls. When a message transitions roles (status → streaming content), cleanup logic must know about the transition to avoid destroying the repurposed message. The `streamState` field serves as both state tracker and cleanup guard.

## Related
- `knowledge-base/learnings/runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md` (messageId sentinel, null-before-cleanup)
- `knowledge-base/learnings/implementation-patterns/2026-02-11-testability-refactoring-dependency-injection.md` (BotApi interface for mocking)

## Tags
category: implementation-patterns
module: telegram-bridge

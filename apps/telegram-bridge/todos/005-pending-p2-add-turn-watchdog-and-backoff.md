---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, reliability, architecture]
dependencies: []
---

# Add turn-completion watchdog and exponential restart backoff

## Problem Statement

If the CLI hangs mid-turn (no output, no exit), `processing` stays `true` forever, blocking all messages. The fixed 5s restart delay can cause tight restart loops if CLI consistently fails.

## Findings

- **architecture-strategist**: "No turn-completion watchdog" -- permanent deadlock risk
- **pattern-recognition-specialist**: "fixed 5-second delay can cause tight restart loops"

## Proposed Solutions

### Turn watchdog
Start a timer (e.g., 10 min) in `sendUserMessage`, clear in `result` handler. On timeout, reset `processing`, notify user, optionally restart CLI.
- **Effort**: Small

### Exponential backoff
Replace fixed 5s with 5s, 10s, 20s, 40s... capped at 5min. Reset on successful turn.
- **Effort**: Small

## Acceptance Criteria
- [ ] Turn watchdog fires after configurable timeout, resets processing
- [ ] User notified when watchdog fires
- [ ] Restart delay increases exponentially on consecutive failures
- [ ] Backoff resets after a successful turn

## Work Log
- 2026-02-11: Identified during /soleur:review

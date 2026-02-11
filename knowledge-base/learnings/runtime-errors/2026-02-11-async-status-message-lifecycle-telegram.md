# Learning: Async status message lifecycle in Telegram bots

## Problem

Building a Telegram bridge with a "Thinking..." status message revealed four async coordination failures:

1. **Response delivery blocked by cleanup failure**: `.then()` chaining between `cleanupTurnStatus()` and `sendChunked()` meant if `deleteMessage` threw, the user never received their response.
2. **Race in async initialization**: `startTurnStatus()` was fire-and-forget, but `recordToolUse()` could execute before the status message was sent, referencing a message that didn't exist yet.
3. **Over-engineered throttling (YAGNI)**: `pendingEdit` + `setTimeout` for delayed edits added complexity and a timing bug -- the setTimeout could fire after cleanup deleted the message.
4. **Double-delete race**: Concurrent calls to `cleanupTurnStatus()` could both attempt to delete the same message.

## Solution

**Decouple cleanup from delivery** -- run as independent promises:
```typescript
cleanupTurnStatus().catch(err => console.error("Cleanup failed:", err));
sendChunked(chatId, html).catch(err => console.error("Send failed:", err));
```

**Create state synchronously, backfill async data**:
```typescript
turnStatus = { chatId, messageId: 0, tools: [], typingTimer };
const sent = await bot.api.sendMessage(chatId, "Thinking...");
if (turnStatus && turnStatus.typingTimer === typingTimer) {
  turnStatus.messageId = sent.message_id;
}
```

**Guard operations on async readiness**:
```typescript
function recordToolUse(toolName: string): void {
  if (!turnStatus || turnStatus.messageId === 0) return;
  // ...
}
```

**Throttle via time-check, not timers**:
```typescript
if (Date.now() - turnStatus.lastEditTime >= STATUS_EDIT_INTERVAL_MS) {
  flushStatusEdit();
}
```

**Null-out before async delete for idempotent cleanup**:
```typescript
async function cleanupTurnStatus(): Promise<void> {
  const status = turnStatus;
  if (!status) return;
  turnStatus = null; // prevent concurrent calls
  clearInterval(status.typingTimer);
  if (status.messageId !== 0) {
    try { await bot.api.deleteMessage(status.chatId, status.messageId); } catch {}
  }
}
```

## Key Insight

Async coordination in message lifecycle requires: (1) create state synchronously with placeholders, (2) run independent operations as separate promises -- never chain cleanup to delivery, (3) guard dependent operations with readiness checks, (4) throttle via simple time-checks not timers, (5) null-out state before async cleanup to prevent races. The `.then()` chaining anti-pattern is especially dangerous because it silently blocks downstream operations when the upstream fails.

## Related

- [Cloud deploy SDK integration](../integration-issues/2026-02-10-cloud-deploy-infra-and-sdk-integration.md) -- WebSocket initialization race

## Tags
category: runtime-errors
module: telegram-bridge
symptoms: response not delivered, race condition, status message not deleted, timer fires after cleanup

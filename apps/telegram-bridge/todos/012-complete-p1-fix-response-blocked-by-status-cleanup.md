---
status: complete
priority: p1
issue_id: "012"
tags: [code-review, silent-failures, reliability]
dependencies: []
---

# Fix response delivery blocked by status cleanup failure

## Problem Statement

In the assistant message handler, `cleanupTurnStatus().then(() => sendChunked(...))` chains response delivery to status cleanup. If `deleteMessage` throws an uncaught error (e.g., network timeout, unexpected API error), the `.then()` never fires and the user NEVER receives their response. The response is silently lost.

## Findings

- **silent-failure-hunter**: CRITICAL -- "if cleanupTurnStatus rejects, the user's response is never delivered"
- **architecture-strategist**: "status message leak on error paths"
- **performance-oracle**: "status cleanup blocks response delivery 0-3s"

## Proposed Solutions

### Option A: Decouple cleanup from delivery (Recommended)
Replace `.then()` chain with parallel execution using error isolation:
```typescript
case "assistant": {
  // ... existing content filtering ...
  if (textParts.length > 0) {
    const html = markdownToHtml(textParts.join("\n"));
    cleanupTurnStatus().catch((err) => console.error("Status cleanup failed:", err));
    sendChunked(activeChatId!, html).catch((err) => console.error("sendChunked failed:", err));
  }
  break;
}
```
- **Effort**: Small (3-line change)
- **Risk**: Low -- status message may briefly overlap with response, but response is never lost

### Option B: Use try/finally pattern
```typescript
try {
  await cleanupTurnStatus();
} finally {
  await sendChunked(activeChatId!, html);
}
```
- **Effort**: Small
- **Risk**: Low -- requires making the handler async

## Acceptance Criteria
- [ ] Response delivery does not depend on status cleanup success
- [ ] Status cleanup errors are logged
- [ ] User always receives their response even if deleteMessage fails

## Work Log
- 2026-02-11: Identified during /soleur:review round 2

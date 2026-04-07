# Learning: Code review batch fixes — WS validation, error logging, concurrency comments

## Problem

Four code-review GitHub issues (#1733, #1734, #1735, #1736) identified gaps in the web-platform's KB reader and chat WebSocket handling:

1. **Silent error suppression** — Empty catch block in KB context fetch swallowed network errors with no logging, making production debugging impossible
2. **Missing runtime validation** — ConversationContext WS payload accepted arbitrary path, type, and content with only a type assertion (`as WSMessage`), enabling path traversal and token cost inflation
3. **Undocumented concurrency requirement** — Per-callback RegExp instantiation in searchKb was a correctness requirement (stateful /g flag) with no comment, inviting accidental hoisting
4. **Undocumented scaling asymmetry** — searchKb uses flat Promise.all (unbounded) while buildTree/collectMdFiles use tree-recursive parallelism (depth-bounded), but the difference was not documented

## Solution

### #1734: Per-callback RegExp comment (kb-reader.ts:245-246)

Added inline comment explaining concurrency safety requirement:

```typescript
// Created per-callback to avoid lastIndex contention across concurrent callbacks.
// Do not hoist — RegExp with /g flag is stateful and shared instances would skip matches.
const regex = new RegExp(escapedQuery, "gi");
```

### #1733: Flat-parallel scaling comment (kb-reader.ts:231-233)

Added comment documenting scaling asymmetry and deferred p-limit:

```typescript
// Flat-parallel: every file is read concurrently via Promise.all, unlike collectMdFiles
// and buildTree which use tree-recursive parallelism (bounded by directory depth).
// For very large KBs (10,000+ files), this is the first bottleneck — apply p-limit here.
```

### #1736: Error logging + network error test (page.tsx:67, chat-page.test.tsx)

Changed empty catch to logged catch:

```typescript
} catch (err) {
  // Graceful degradation: proceed without context
  console.error("KB context fetch failed:", err);
}
```

Added test for fetch rejection path (not just HTTP error):

```typescript
fetchSpy.mockRejectedValueOnce(new Error("network failure"));
// Verifies graceful degradation AND error logging
```

### #1735: ConversationContext validation (context-validation.ts, ws-handler.ts)

Created `server/context-validation.ts` with `validateConversationContext()`:
- Path: `^[a-zA-Z0-9_\-/]+\.md$` (blocks traversal, null bytes, spaces)
- Type: allowlist enum (`"kb-viewer"`)
- Content: max 1MB (matches kb-reader MAX_FILE_SIZE)

Extracted to separate module because ws-handler.ts triggers Supabase initialization at module load, preventing pure unit testing. Applied in start_session **before side effects** (before abortActiveSession). 15 test cases covering all rejection paths.

## Key Insight

Security-critical validation and modules with heavy initialization dependencies (database clients, SDK connections) should be separated at the module level. This enables pure unit testing of validation logic without mocking infrastructure. The pattern matches existing extractions in the codebase (sandbox.ts, error-sanitizer.ts).

Empty catch blocks at system boundaries are a code smell — even when graceful degradation is correct, the error should be observable (logged, metricated) so production failures are diagnosable.

## Related

- [2026-03-20-websocket-first-message-auth-toctou-race.md](2026-03-20-websocket-first-message-auth-toctou-race.md) — WS async-with-timeout TOCTOU race pattern
- [2026-03-20-cwe22-path-traversal-canusertool-sandbox.md](2026-03-20-cwe22-path-traversal-canusertool-sandbox.md) — Module extraction for testability pattern
- GitHub #1662 — Tracking issue for MCP tool extraction from agent-runner.ts

## Tags

category: security-issues
module: web-platform

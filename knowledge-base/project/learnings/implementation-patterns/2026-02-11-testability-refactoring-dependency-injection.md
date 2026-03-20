---
title: "Testability Refactoring via Dependency Injection for Monolithic Entry Points"
category: implementation-patterns
module: telegram-bridge
tags: [testing, refactoring, dependency-injection, bun, typescript]
date: 2026-02-11
severity: medium
---

# Learning: Testability Refactoring via Dependency Injection for Monolithic Entry Points

## Problem

A 613-line monolithic Telegram-to-Claude-Code bridge (`apps/telegram-bridge/src/index.ts`) had zero automated tests. Three critical bugs were fixed but had no regression tests:

- **P1-012**: Response delivery blocked when `deleteMessage` rejected during async cleanup
- **P2-013**: Health endpoint always returning 200 regardless of CLI state
- **P2-014**: Typing indicator race conditions when `messageId` was still 0

The file mixed module-level mutable state, hardcoded grammY `bot.api.*` calls, and coordination logic in a way that made unit testing impossible without a real Telegram bot token.

## Investigation

Attempts to test the monolithic file revealed five blockers:

1. **Module-level mutable state**: All state (`cliState`, `processing`, `turnStatus`, etc.) was `let` variables at file scope -- no way to reset between tests.
2. **Hardcoded grammY calls**: Functions directly called `bot.api.sendMessage(...)` which requires a valid Telegram token and network access.
3. **No interface boundaries**: No abstraction over the 4 bot API methods actually used.
4. **Mixed concerns**: Pure functions (HTML escaping, message chunking) tangled with side effects (API calls, timers, HTTP server).
5. **ATDD not followed**: Tests were never written alongside the initial implementation.

## Root Cause

The file grew past its testable complexity threshold without extracting a dependency-injectable component. The core issue: **no seam existed between business logic and the grammY bot API**, making it impossible to substitute test doubles.

## Solution

Refactored into 4 focused modules. No logic changes -- just moving code and adding `export`.

### Step 1: Define a minimal BotApi interface (`types.ts`)

Only the 4 methods the bridge actually calls:

```typescript
export interface BotApi {
  sendMessage(chatId: number, text: string, other?: Record<string, unknown>): Promise<{ message_id: number }>;
  editMessageText(chatId: number, messageId: number, text: string): Promise<unknown>;
  deleteMessage(chatId: number, messageId: number): Promise<true>;
  sendChatAction(chatId: number, action: string): Promise<true>;
}
```

### Step 2: Extract pure functions (`helpers.ts`)

Move `escapeHtml`, `markdownToHtml`, `chunkMessage`, `stripHtmlTags`, `formatStatusText` -- testable with zero mocking (28 tests).

### Step 3: Extract health server factory (`health.ts`)

`createHealthServer(port, state)` with a `HealthState` interface. Test with real HTTP server on port 0:

```typescript
const server = createHealthServer(0, state); // OS-assigned port
const res = await fetch(`http://127.0.0.1:${server.port}/health`);
expect(res.status).toBe(503); // P2-013 regression
```

### Step 4: Extract Bridge class (`bridge.ts`)

Constructor takes `BotApi` + optional config. All mutable state becomes instance properties:

```typescript
export class Bridge {
  constructor(api: BotApi, config?: Partial<BridgeConfig>) { ... }

  // All state as public instance properties for testability
  cliState: CliState = "connecting";
  processing = false;
  turnStatus: TurnStatus | null = null;
  messageQueue: QueuedMessage[] = [];
  // ... methods: handleCliMessage, sendChunked, startTurnStatus, etc.
}
```

Tests create a mock BotApi with `mock()` from bun:test:

```typescript
function createMockApi(): BotApi & { sendMessage: Mock<...>; ... } {
  return {
    sendMessage: mock(() => Promise.resolve({ message_id: 42 })),
    editMessageText: mock(() => Promise.resolve(true)),
    deleteMessage: mock(() => Promise.resolve(true as const)),
    sendChatAction: mock(() => Promise.resolve(true as const)),
  };
}
```

Key regression test (P1-012):

```typescript
test("P1-012: response delivered even when deleteMessage rejects", async () => {
  api.deleteMessage.mockRejectedValueOnce(new Error("message not found"));
  bridge.handleCliMessage(cliMsg({ type: "assistant", message: { content: [{ type: "text", text: "The answer" }] } }));
  await new Promise((r) => setTimeout(r, 50));
  expect(api.sendMessage).toHaveBeenCalled(); // Response MUST still be sent
});
```

### Step 5: Thin wiring in `index.ts`

Production code adapts grammY's API to our interface:

```typescript
const botApi: BotApi = {
  sendMessage: (chatId, text, other?) => bot.api.sendMessage(chatId, text, other as any),
  editMessageText: (chatId, messageId, text) => bot.api.editMessageText(chatId, messageId, text),
  deleteMessage: (chatId, messageId) => bot.api.deleteMessage(chatId, messageId),
  sendChatAction: (chatId, action) => bot.api.sendChatAction(chatId, action as any),
};
const bridge = new Bridge(botApi, { statusEditIntervalMs: 3_000, typingIntervalMs: 4_000 });
```

Result: `index.ts` shrunk from 613 to 289 lines. 84 tests across 3 files, all passing.

## Key Insight

When a file exceeds ~200 lines and mixes state management with external API calls, extract a class with constructor-injected dependencies. The interface should be **minimal** (only methods actually called), not a full API wrapper. This creates a clean testing boundary: the class is unit-testable with simple mocks while the entry point remains a thin wiring layer. The `as any` casts in the adapter are acceptable -- they're at the wiring seam, not in business logic.

## Prevention

1. **Define integration interfaces early**: Before writing coordination logic, create a minimal interface for external dependencies.
2. **Extract state into a class at ~200 LOC**: Use constructor injection. Store mutable state as instance properties.
3. **Separate concerns by test strategy**: Pure functions (no mocks), HTTP servers (port 0), stateful classes (mock interfaces), entry points (no tests needed).
4. **Follow ATDD**: Write tests alongside implementation. If a function is hard to test, that's a signal to extract and inject.
5. **Mock at the interface level**: Never mock grammY's `Bot` class; mock your own `BotApi` interface.

## Related

- `knowledge-base/learnings/runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md` -- the P1-012 bug this testing catches
- `knowledge-base/learnings/workflow-patterns/2026-02-11-worktree-edit-discipline.md` -- worktree discipline learned during this feature
- PR #47 on `feat/telegram-live-status` branch

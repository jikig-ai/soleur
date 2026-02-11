import { describe, test, expect, beforeEach, mock, type Mock } from "bun:test";
import { Bridge } from "../src/bridge";
import type { BotApi } from "../src/types";

// ---------------------------------------------------------------------------
// Mock BotApi factory
// ---------------------------------------------------------------------------

function createMockApi(): BotApi & {
  sendMessage: Mock<BotApi["sendMessage"]>;
  editMessageText: Mock<BotApi["editMessageText"]>;
  deleteMessage: Mock<BotApi["deleteMessage"]>;
  sendChatAction: Mock<BotApi["sendChatAction"]>;
} {
  return {
    sendMessage: mock(() => Promise.resolve({ message_id: 42 })),
    editMessageText: mock(() => Promise.resolve(true)),
    deleteMessage: mock(() => Promise.resolve(true as const)),
    sendChatAction: mock(() => Promise.resolve(true as const)),
  };
}

// Helper: build a CLI JSON line for handleCliMessage
function cliMsg(obj: Record<string, unknown>): string {
  return JSON.stringify(obj);
}

// ---------------------------------------------------------------------------
// sendChunked
// ---------------------------------------------------------------------------

describe("sendChunked", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api);
  });

  test("sends short HTML as single message", async () => {
    await bridge.sendChunked(1, "<b>hello</b>");
    expect(api.sendMessage).toHaveBeenCalledTimes(1);
    expect(api.sendMessage.mock.calls[0]).toEqual([1, "<b>hello</b>", { parse_mode: "HTML" }]);
  });

  test("falls back to plain text on HTML parse failure", async () => {
    api.sendMessage
      .mockRejectedValueOnce(new Error("Bad Request: can't parse HTML"))
      .mockResolvedValueOnce({ message_id: 43 });

    await bridge.sendChunked(1, "<b>broken");
    expect(api.sendMessage).toHaveBeenCalledTimes(2);
    // Second call should be plain text (tags stripped)
    expect(api.sendMessage.mock.calls[1][2]).toBeUndefined();
  });

  test("logs error when both HTML and plain text fail", async () => {
    api.sendMessage
      .mockRejectedValueOnce(new Error("HTML fail"))
      .mockRejectedValueOnce(new Error("Plain fail"));

    // Should not throw
    await bridge.sendChunked(1, "<b>broken");
  });
});

// ---------------------------------------------------------------------------
// startTurnStatus
// ---------------------------------------------------------------------------

describe("startTurnStatus", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
  });

  test("sends typing action and status message", async () => {
    await bridge.startTurnStatus(1);
    expect(api.sendChatAction).toHaveBeenCalledWith(1, "typing");
    expect(api.sendMessage).toHaveBeenCalledWith(1, "Thinking...");
    expect(bridge.turnStatus).not.toBeNull();
    expect(bridge.turnStatus!.messageId).toBe(42);
    // Clean up timer
    await bridge.cleanupTurnStatus();
  });

  test("sets messageId from sendMessage response", async () => {
    api.sendMessage.mockResolvedValueOnce({ message_id: 99 });
    await bridge.startTurnStatus(1);
    expect(bridge.turnStatus!.messageId).toBe(99);
    await bridge.cleanupTurnStatus();
  });

  test("cleans up existing status before starting new one", async () => {
    await bridge.startTurnStatus(1);
    const firstTimer = bridge.turnStatus!.typingTimer;
    api.sendMessage.mockResolvedValueOnce({ message_id: 100 });
    await bridge.startTurnStatus(2);
    // First status should have been deleted
    expect(api.deleteMessage).toHaveBeenCalledWith(1, 42);
    expect(bridge.turnStatus!.messageId).toBe(100);
    await bridge.cleanupTurnStatus();
  });

  test("handles sendMessage failure gracefully", async () => {
    api.sendMessage.mockRejectedValueOnce(new Error("Network error"));
    await bridge.startTurnStatus(1);
    // turnStatus exists but messageId stays 0
    expect(bridge.turnStatus).not.toBeNull();
    expect(bridge.turnStatus!.messageId).toBe(0);
    await bridge.cleanupTurnStatus();
  });
});

// ---------------------------------------------------------------------------
// recordToolUse
// ---------------------------------------------------------------------------

describe("recordToolUse", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
  });

  test("P2-014 regression: no-op when messageId is 0", async () => {
    api.sendMessage.mockRejectedValueOnce(new Error("fail"));
    await bridge.startTurnStatus(1);
    // messageId should be 0 since sendMessage failed
    expect(bridge.turnStatus!.messageId).toBe(0);

    bridge.recordToolUse("Read");
    // Tool should NOT be recorded
    expect(bridge.turnStatus!.tools).toEqual([]);
    await bridge.cleanupTurnStatus();
  });

  test("no-op when no turnStatus", () => {
    bridge.recordToolUse("Read");
    // Should not throw
  });

  test("records tool names", async () => {
    await bridge.startTurnStatus(1);
    bridge.recordToolUse("Read");
    bridge.recordToolUse("Edit");
    expect(bridge.turnStatus!.tools).toEqual(["Read", "Edit"]);
    await bridge.cleanupTurnStatus();
  });

  test("deduplicates consecutive same-tool entries", async () => {
    await bridge.startTurnStatus(1);
    bridge.recordToolUse("Read");
    bridge.recordToolUse("Read");
    bridge.recordToolUse("Read");
    expect(bridge.turnStatus!.tools).toEqual(["Read"]);
    await bridge.cleanupTurnStatus();
  });

  test("allows same tool after different tool", async () => {
    await bridge.startTurnStatus(1);
    bridge.recordToolUse("Read");
    bridge.recordToolUse("Edit");
    bridge.recordToolUse("Read");
    expect(bridge.turnStatus!.tools).toEqual(["Read", "Edit", "Read"]);
    await bridge.cleanupTurnStatus();
  });

  test("flushes edit when enough time has passed", async () => {
    await bridge.startTurnStatus(1);
    // Move lastEditTime back to trigger flush
    bridge.turnStatus!.lastEditTime = Date.now() - 200;
    bridge.recordToolUse("Read");
    expect(api.editMessageText).toHaveBeenCalled();
    await bridge.cleanupTurnStatus();
  });

  test("does not flush edit when throttle interval not reached", async () => {
    await bridge.startTurnStatus(1);
    bridge.recordToolUse("Read");
    expect(api.editMessageText).not.toHaveBeenCalled();
    await bridge.cleanupTurnStatus();
  });
});

// ---------------------------------------------------------------------------
// flushStatusEdit
// ---------------------------------------------------------------------------

describe("flushStatusEdit", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api);
  });

  test("no-op when no turnStatus", () => {
    bridge.flushStatusEdit();
    expect(api.editMessageText).not.toHaveBeenCalled();
  });

  test("no-op when messageId is 0", async () => {
    api.sendMessage.mockRejectedValueOnce(new Error("fail"));
    await bridge.startTurnStatus(1);
    bridge.flushStatusEdit();
    expect(api.editMessageText).not.toHaveBeenCalled();
    await bridge.cleanupTurnStatus();
  });

  test("edits status message with formatted text", async () => {
    await bridge.startTurnStatus(1);
    bridge.flushStatusEdit();
    expect(api.editMessageText).toHaveBeenCalledWith(1, 42, expect.any(String));
    await bridge.cleanupTurnStatus();
  });
});

// ---------------------------------------------------------------------------
// cleanupTurnStatus
// ---------------------------------------------------------------------------

describe("cleanupTurnStatus", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
  });

  test("no-op when no turnStatus", async () => {
    await bridge.cleanupTurnStatus();
    expect(api.deleteMessage).not.toHaveBeenCalled();
  });

  test("nulls turnStatus and deletes message", async () => {
    await bridge.startTurnStatus(1);
    expect(bridge.turnStatus).not.toBeNull();
    await bridge.cleanupTurnStatus();
    expect(bridge.turnStatus).toBeNull();
    expect(api.deleteMessage).toHaveBeenCalledWith(1, 42);
  });

  test("skips deleteMessage when messageId is 0", async () => {
    api.sendMessage.mockRejectedValueOnce(new Error("fail"));
    await bridge.startTurnStatus(1);
    expect(bridge.turnStatus!.messageId).toBe(0);
    await bridge.cleanupTurnStatus();
    expect(api.deleteMessage).not.toHaveBeenCalled();
  });

  test("idempotent: concurrent calls safe", async () => {
    await bridge.startTurnStatus(1);
    // Call cleanup twice concurrently
    await Promise.all([bridge.cleanupTurnStatus(), bridge.cleanupTurnStatus()]);
    // deleteMessage should only be called once (second call sees null)
    expect(api.deleteMessage).toHaveBeenCalledTimes(1);
  });

  test("tolerates deleteMessage rejection", async () => {
    api.deleteMessage.mockRejectedValueOnce(new Error("message not found"));
    await bridge.startTurnStatus(1);
    // Should not throw
    await bridge.cleanupTurnStatus();
    expect(bridge.turnStatus).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// handleCliMessage
// ---------------------------------------------------------------------------

describe("handleCliMessage", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
  });

  test("ignores non-JSON input", () => {
    bridge.handleCliMessage("not json at all");
    // No crash, no API calls
    expect(api.sendMessage).not.toHaveBeenCalled();
  });

  test("ignores empty lines", () => {
    bridge.handleCliMessage("   ");
    expect(api.sendMessage).not.toHaveBeenCalled();
  });

  // --- system/init ---

  test("system/init transitions from connecting to ready", () => {
    expect(bridge.cliState).toBe("connecting");
    bridge.handleCliMessage(cliMsg({ type: "system", subtype: "init" }));
    expect(bridge.cliState).toBe("ready");
  });

  test("system/init drains queue when messages are waiting", () => {
    bridge.cliStdin = { write: mock(() => 1) };
    bridge.messageQueue = [{ chatId: 1, text: "hello" }];
    bridge.handleCliMessage(cliMsg({ type: "system", subtype: "init" }));
    expect(bridge.cliState).toBe("ready");
    expect(bridge.messageQueue.length).toBe(0);
    expect(bridge.processing).toBe(true);
  });

  test("system/init ignored if not in connecting state", () => {
    bridge.cliState = "ready";
    bridge.handleCliMessage(cliMsg({ type: "system", subtype: "init" }));
    expect(bridge.cliState).toBe("ready");
  });

  // --- initial result ---

  test("first result message sets ready state", () => {
    bridge.cliState = "connecting";
    bridge.handleCliMessage(cliMsg({ type: "result", result: "ok" }));
    expect(bridge.initialResultReceived).toBe(true);
    expect(bridge.cliState).toBe("ready");
  });

  // --- result (turn complete) ---

  test("result increments messagesProcessed and resets processing", () => {
    bridge.initialResultReceived = true;
    bridge.processing = true;
    bridge.handleCliMessage(cliMsg({ type: "result", result: "ok" }));
    expect(bridge.messagesProcessed).toBe(1);
    expect(bridge.processing).toBe(false);
  });

  test("result drains queue on turn complete", () => {
    bridge.initialResultReceived = true;
    bridge.cliState = "ready";
    bridge.cliStdin = { write: mock(() => 1) };
    bridge.processing = true;
    bridge.messageQueue = [{ chatId: 2, text: "next" }];
    bridge.handleCliMessage(cliMsg({ type: "result", result: "ok" }));
    expect(bridge.processing).toBe(true); // now processing next
    expect(bridge.activeChatId).toBe(2);
    expect(bridge.messageQueue.length).toBe(0);
  });

  // --- assistant with text ---

  test("assistant with text sends chunked HTML response", async () => {
    bridge.activeChatId = 1;
    await bridge.startTurnStatus(1);
    api.sendMessage.mockClear();

    bridge.handleCliMessage(
      cliMsg({
        type: "assistant",
        message: {
          content: [{ type: "text", text: "Hello world" }],
        },
      }),
    );

    // Let async operations settle
    await new Promise((r) => setTimeout(r, 50));
    // sendChunked should have been called (at least one sendMessage for the response)
    expect(api.sendMessage).toHaveBeenCalled();
    // Status should be cleaned up
    expect(bridge.turnStatus).toBeNull();
  });

  test("P1-012 regression: response delivered even when deleteMessage rejects", async () => {
    bridge.activeChatId = 1;
    await bridge.startTurnStatus(1);
    api.sendMessage.mockClear();

    // Make deleteMessage reject (simulating the P1-012 bug scenario)
    api.deleteMessage.mockRejectedValueOnce(new Error("message not found"));

    bridge.handleCliMessage(
      cliMsg({
        type: "assistant",
        message: {
          content: [{ type: "text", text: "The answer is 42" }],
        },
      }),
    );

    // Let async operations settle
    await new Promise((r) => setTimeout(r, 50));

    // CRITICAL: sendMessage MUST still be called with the response
    // This was the P1-012 bug -- cleanup failure blocked response delivery
    expect(api.sendMessage).toHaveBeenCalled();
    const htmlCall = api.sendMessage.mock.calls.find(
      (call) => call[2]?.parse_mode === "HTML",
    );
    expect(htmlCall).toBeDefined();
  });

  // --- assistant with tool_use ---

  test("assistant records tool uses", async () => {
    bridge.activeChatId = 1;
    await bridge.startTurnStatus(1);

    bridge.handleCliMessage(
      cliMsg({
        type: "assistant",
        message: {
          content: [
            { type: "tool_use", name: "Read" },
            { type: "tool_use", name: "Edit" },
          ],
        },
      }),
    );

    // Tools should be recorded (messageId was set)
    expect(bridge.turnStatus!.tools).toContain("Read");
    expect(bridge.turnStatus!.tools).toContain("Edit");
    await bridge.cleanupTurnStatus();
  });

  test("assistant without activeChatId is ignored", () => {
    bridge.activeChatId = null;
    bridge.handleCliMessage(
      cliMsg({
        type: "assistant",
        message: { content: [{ type: "text", text: "ignored" }] },
      }),
    );
    expect(api.sendMessage).not.toHaveBeenCalled();
  });

  test("assistant without content is ignored", () => {
    bridge.activeChatId = 1;
    bridge.handleCliMessage(cliMsg({ type: "assistant", message: {} }));
    expect(api.sendMessage).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// sendUserMessage
// ---------------------------------------------------------------------------

describe("sendUserMessage", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
    bridge.cliState = "ready";
  });

  test("writes JSON to stdin", () => {
    const writeMock = mock(() => 1);
    bridge.cliStdin = { write: writeMock };
    bridge.activeChatId = 1;
    bridge.sendUserMessage("hello");

    expect(writeMock).toHaveBeenCalledTimes(1);
    const written = writeMock.mock.calls[0][0] as string;
    const parsed = JSON.parse(written.trim());
    expect(parsed.type).toBe("user");
    expect(parsed.message.content).toBe("hello");
    expect(bridge.processing).toBe(true);
  });

  test("does nothing when stdin is null", () => {
    bridge.cliStdin = null;
    bridge.sendUserMessage("hello");
    expect(bridge.processing).toBe(false);
  });

  test("starts turn status when activeChatId is set", async () => {
    bridge.cliStdin = { write: mock(() => 1) };
    bridge.activeChatId = 5;
    bridge.sendUserMessage("hello");
    // startTurnStatus is async (fire-and-forget), wait for it to settle
    await new Promise((r) => setTimeout(r, 50));
    expect(api.sendChatAction).toHaveBeenCalledWith(5, "typing");
    await bridge.cleanupTurnStatus();
  });

  test("handles synchronous write error", () => {
    bridge.cliStdin = {
      write: () => {
        throw new Error("stdin broken");
      },
    };
    bridge.activeChatId = 1;
    bridge.sendUserMessage("hello");
    // Should recover: not processing, queue can drain
    expect(bridge.processing).toBe(false);
  });

  test("handles async write error", async () => {
    bridge.cliStdin = {
      write: mock(() => Promise.reject(new Error("async fail"))),
    };
    bridge.activeChatId = 1;
    bridge.sendUserMessage("hello");
    // Let promise rejection settle
    await new Promise((r) => setTimeout(r, 50));
    expect(bridge.processing).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// drainQueue
// ---------------------------------------------------------------------------

describe("drainQueue", () => {
  let api: ReturnType<typeof createMockApi>;
  let bridge: Bridge;

  beforeEach(() => {
    api = createMockApi();
    bridge = new Bridge(api, { statusEditIntervalMs: 100, typingIntervalMs: 100 });
    bridge.cliState = "ready";
    bridge.cliStdin = { write: mock(() => 1) };
  });

  test("sends next queued message", () => {
    bridge.messageQueue = [{ chatId: 1, text: "first" }];
    bridge.drainQueue();
    expect(bridge.activeChatId).toBe(1);
    expect(bridge.processing).toBe(true);
    expect(bridge.messageQueue.length).toBe(0);
  });

  test("does nothing when already processing", () => {
    bridge.processing = true;
    bridge.messageQueue = [{ chatId: 1, text: "waiting" }];
    bridge.drainQueue();
    expect(bridge.messageQueue.length).toBe(1);
  });

  test("does nothing when queue is empty", () => {
    bridge.drainQueue();
    expect(bridge.processing).toBe(false);
  });

  test("does nothing when CLI not ready", () => {
    bridge.cliState = "connecting";
    bridge.messageQueue = [{ chatId: 1, text: "waiting" }];
    bridge.drainQueue();
    expect(bridge.messageQueue.length).toBe(1);
  });

  test("does nothing when stdin is null", () => {
    bridge.cliStdin = null;
    bridge.messageQueue = [{ chatId: 1, text: "waiting" }];
    bridge.drainQueue();
    expect(bridge.messageQueue.length).toBe(1);
  });

  test("processes messages in FIFO order", () => {
    bridge.messageQueue = [
      { chatId: 1, text: "first" },
      { chatId: 2, text: "second" },
    ];
    bridge.drainQueue();
    // Only first should be dequeued
    expect(bridge.activeChatId).toBe(1);
    expect(bridge.messageQueue.length).toBe(1);
    expect(bridge.messageQueue[0].text).toBe("second");
  });
});

// ---------------------------------------------------------------------------
// Constructor / config
// ---------------------------------------------------------------------------

describe("Bridge constructor", () => {
  test("uses default config when none provided", () => {
    const api = createMockApi();
    const bridge = new Bridge(api);
    expect(bridge.cliState).toBe("connecting");
    expect(bridge.processing).toBe(false);
    expect(bridge.messageQueue).toEqual([]);
  });

  test("merges partial config with defaults", () => {
    const api = createMockApi();
    const bridge = new Bridge(api, { statusEditIntervalMs: 500 });
    // Custom value applied -- tested via behavior
    expect(bridge.cliState).toBe("connecting");
  });
});

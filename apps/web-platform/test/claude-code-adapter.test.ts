import { describe, expect, it, vi } from "vitest";
import { CLAUDE_CODE_ENGINE_ID, createClaudeCodeAdapter } from "@/server/claude-code-adapter";

describe("Claude Code neutral adapter boundary", () => {
  it("delegates lifecycle operations without exposing SDK-shaped types", async () => {
    expect(CLAUDE_CODE_ENGINE_ID).toBe("claude-code");
    const transport = {
      start: vi.fn(async function* () { yield { runId: "run-1", eventId: "evt-1", sequence: 1, payload: { type: "text", text: "ok" } as const }; }),
      continue: vi.fn(async function* () { yield* []; }),
      cancel: vi.fn().mockResolvedValue("requested" as const),
      reconcile: vi.fn().mockResolvedValue("running" as const),
      resumeFromCursor: vi.fn(async function* () { yield* []; }),
      respondToApproval: vi.fn().mockResolvedValue(undefined),
      erase: vi.fn().mockResolvedValue("confirmed" as const),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const adapter = createClaudeCodeAdapter(transport);
    const context = { runId: "run-1", binding: { engineId: "claude-code" } } as never;
    const events = [];
    for await (const event of adapter.start(context, { text: "hi", attachmentIds: [] })) events.push(event);
    await expect(adapter.cancel(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("requested");
    await expect(adapter.reconcile(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("running");
    await expect(adapter.erase(context, { resumeHandle: "opaque", sessionId: null })).resolves.toBe("confirmed");
    await adapter.respondToApproval(context, "approval-1", "deny");
    await adapter.dispose();
    expect(transport.start).toHaveBeenCalledOnce();
    expect(transport.cancel).toHaveBeenCalledOnce();
    expect(transport.reconcile).toHaveBeenCalledOnce();
    expect(transport.erase).toHaveBeenCalledOnce();
    expect(transport.respondToApproval).toHaveBeenCalledWith(context, "approval-1", "deny");
    expect(transport.dispose).toHaveBeenCalledOnce();
    expect(events).toHaveLength(1);
  });
});

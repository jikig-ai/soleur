import { describe, it, expect, vi, beforeEach } from "vitest";

// feat-reasoning-chat-boxes (#5370) — drive the extracted `emitNarration` side
// effect directly (the onToolUse closure is unreachable from a unit test).
// Reuses the cc-dispatcher harness for the heavy module-graph mocks; adds a spy
// on the turn_summary write helper so we can assert insert vs. no-insert.
const { mockReportSilentFallback, mockInsertTurnSummary } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockInsertTurnSummary: vi.fn(),
}));

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return conversationWriterFactory({ mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }) });
});

vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped: vi.fn(),
    withTtlDedupWrapper: true,
  });
});

vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return costWriterFactory();
});

vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath: vi.fn() });
});

vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseTenantFactory({ mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }), mockConversationWorkspaceId: "ws-A" });
});

vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseServiceFactory({ mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }), mockConversationWorkspaceId: "ws-A" });
});

vi.mock("@/server/cc-reprovision", () => ({
  reprovisionWorkspaceOnDispatch: vi.fn().mockResolvedValue("ok"),
}));

// Spy on the write choke point so insert vs. no-insert is observable. Real
// redaction (formatAssistantText + probe) runs in emitNarration BEFORE this.
vi.mock("@/server/messages/insert-turn-summary", () => ({
  insertTurnSummary: mockInsertTurnSummary,
}));

import {
  __emitNarrationForTests,
  __setAssertWriteScopeForTests,
  __resetAssertWriteScopeForTests,
  CC_OP_SLUGS,
} from "@/server/cc-dispatcher";
import { NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN } from "@/server/narrate-tool";
import type { WSMessage } from "@/lib/types";

const USER = "founder-uuid";
const CONV = "conv-uuid";

let sent: WSMessage[];
let sendToClient: (userId: string, msg: WSMessage) => void;

function run(toolName: string, input: Record<string, unknown>, aborted = false) {
  return __emitNarrationForTests({ toolName, input, userId: USER, conversationId: CONV, aborted, sendToClient });
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetAssertWriteScopeForTests();
  mockInsertTurnSummary.mockResolvedValue({ status: "inserted", id: "row-1" });
  sent = [];
  sendToClient = (_u, msg) => sent.push(msg);
});

describe("emitNarration — summarize happy path", () => {
  it("inserts a turn_summary row AND emits the SAME redacted string to the buffered frame (M-1)", async () => {
    await run(SUMMARIZE_TOOL_FQN, { summary: "Fixed the side panel on mobile." });
    expect(mockInsertTurnSummary).toHaveBeenCalledTimes(1);
    const insertArg = mockInsertTurnSummary.mock.calls[0][0];
    expect(insertArg.founderId).toBe(USER);
    expect(insertArg.conversationId).toBe(CONV);
    const frame = sent.find((m) => m.type === "turn_summary");
    expect(frame).toBeDefined();
    // Same bytes to both sinks.
    expect((frame as { summary: string }).summary).toBe(insertArg.content);
  });

  it("scrubs a host path from BOTH the inserted content and the frame", async () => {
    await run(SUMMARIZE_TOOL_FQN, {
      summary: "Saved at /workspaces/11111111-1111-1111-1111-111111111111/x.md done",
    });
    const insertArg = mockInsertTurnSummary.mock.calls[0][0];
    const frame = sent.find((m) => m.type === "turn_summary") as { summary: string };
    expect(insertArg.content).not.toContain("/workspaces/");
    expect(frame.summary).not.toContain("/workspaces/");
    expect(frame.summary).toBe(insertArg.content);
  });
});

describe("emitNarration — summarize drop guards", () => {
  it("DROPS (0 rows, 0 frame) when the dispatch is aborted (FR5)", async () => {
    await run(SUMMARIZE_TOOL_FQN, { summary: "Done." }, /*aborted*/ true);
    expect(mockInsertTurnSummary).not.toHaveBeenCalled();
    expect(sent).toHaveLength(0);
  });

  it("DROPS when assertWriteScope returns false (write-scope seam)", async () => {
    __setAssertWriteScopeForTests(() => false);
    await run(SUMMARIZE_TOOL_FQN, { summary: "Done." });
    expect(mockInsertTurnSummary).not.toHaveBeenCalled();
    expect(sent).toHaveLength(0);
  });

  it("DROPS + mirrors to Sentry when a secret SHAPE survives redaction (drop-on-trip)", async () => {
    // An IPv4 is not a path, so formatAssistantText leaves it; the redaction
    // probe then trips → the whole summary is dropped (no row, no frame).
    await run(SUMMARIZE_TOOL_FQN, { summary: "Connected to host 10.0.0.5 successfully." });
    expect(mockInsertTurnSummary).not.toHaveBeenCalled();
    expect(sent).toHaveLength(0);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: CC_OP_SLUGS.narrationRedactionDrop }),
    );
  });

  it("does NOT emit the frame when the insert throws (no row → no replay parity)", async () => {
    mockInsertTurnSummary.mockRejectedValue(new Error("db down"));
    await run(SUMMARIZE_TOOL_FQN, { summary: "Done." });
    expect(sent.find((m) => m.type === "turn_summary")).toBeUndefined();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: CC_OP_SLUGS.summaryInsertFail }),
    );
  });
});

describe("emitNarration — narrate (live-only, never persisted)", () => {
  it("emits a reasoning_narration frame and NEVER inserts a row", async () => {
    await run(NARRATE_TOOL_FQN, { message: "Looking into your billing settings…" });
    expect(mockInsertTurnSummary).not.toHaveBeenCalled();
    const frame = sent.find((m) => m.type === "reasoning_narration");
    expect(frame).toBeDefined();
    expect((frame as { message: string }).message).toContain("billing settings");
  });

  it("DROPS the live frame when a secret SHAPE survives redaction (M-2 parity)", async () => {
    await run(NARRATE_TOOL_FQN, { message: "pinging 10.0.0.5 now" });
    expect(sent).toHaveLength(0);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: CC_OP_SLUGS.narrationRedactionDrop }),
    );
  });
});

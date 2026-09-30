import { describe, it, expect, vi, beforeEach } from "vitest";

// Wire-sequence characterization for the cc-soleur-go turn end. The dispatcher's
// real `sendToClient` frames are folded through the REAL client reducer, so this
// pins the property the chat UI depends on: after a cc turn's text + `stream_end`
// the bubble is done AND `streamState` returns to "idle" (Send replaces Stop,
// "Still working..." clears). Mocks mirror test/cc-dispatcher.test.ts.
const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockMirrorP0Deduped,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockMirrorP0Deduped: vi.fn(),
}));

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return conversationWriterFactory({ mockUpdateConversationFor });
});
vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped,
    withTtlDedupWrapper: true,
  });
});
vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return costWriterFactory();
});
vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});
vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseTenantFactory({ mockMessagesInsert, mockConversationWorkspaceId: "ws-A" });
});
vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import("@/test/helpers/cc-dispatcher-harness");
  return supabaseServiceFactory({ mockMessagesInsert, mockConversationWorkspaceId: "ws-A" });
});
vi.mock("@/server/cc-reprovision", () => ({
  reprovisionWorkspaceOnDispatch: vi.fn().mockResolvedValue("ok"),
}));

import {
  dispatchSoleurGo,
  __resetDispatcherForTests,
  __setCcRunnerForTests,
  TurnPersistenceState,
} from "@/server/cc-dispatcher";
import { chatReducer, type ChatState } from "@/lib/ws-client";

const QUESTION_LIST = "To enter the lead I need:\n- **lastContact**\n- **amount**";
const FOLDED = new Set(["stream_start", "stream", "stream_end", "tool_use", "tool_progress"]);

function idleState(): ChatState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: null,
  };
}

type Events = { onText: (t: string) => void; onResult?: (r: { totalCostUsd: number }) => void; onTextTurnEnd?: () => void };

function stubRunner(onDispatch: (events: Events) => void) {
  return {
    dispatch: vi.fn(async (a: { events: Events }) => {
      await Promise.resolve();
      onDispatch(a.events);
      return { queryReused: false };
    }),
    hasActiveQuery: () => false,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

async function frameFold(
  onDispatch: (events: Events) => void,
): Promise<{ state: ChatState; frameTypes: string[]; stateTrail: string[] }> {
  __setCcRunnerForTests(stubRunner(onDispatch));
  const frames: Array<{ type: string; leaderId?: string }> = [];
  const sendToClient = vi.fn((_uid: string, msg: { type: string; leaderId?: string }) => {
    frames.push(msg);
    return true;
  });
  await dispatchSoleurGo({
    persona: "command_center",
    userId: "u-wire",
    conversationId: "conv-wire",
    userMessage: "I want to enter a new CRM lead",
    currentRouting: { kind: "soleur_go_pending" },
    sendToClient,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  });
  let state = idleState();
  const stateTrail: string[] = [];
  for (const f of frames) {
    if (!FOLDED.has(f.type)) continue;
    // biome-ignore lint/suspicious/noExplicitAny: frames are WS messages
    state = chatReducer(state, { type: "stream_event", msg: f as any });
    stateTrail.push(state.streamState);
  }
  return { state, frameTypes: frames.map((f) => f.type), stateTrail };
}

describe("cc turn end over the wire", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
    vi.stubEnv("CC_PERSIST_USAGE", "");
  });

  it("text + turn end -> one done bubble with the list, and streamState returns to idle", async () => {
    const { state, frameTypes } = await frameFold((events) => {
      events.onText(QUESTION_LIST);
      events.onTextTurnEnd?.();
    });
    const bubbles = state.messages.filter((m) => m.role === "assistant");
    expect(bubbles).toHaveLength(1);
    expect(bubbles[0].content).toBe(QUESTION_LIST);
    expect(bubbles[0].state).toBe("done");
    expect(state.activeStreams.size).toBe(0);
    expect(state.streamState).toBe("idle");
    // The cc path must not emit a per-turn session_ended (it would clear_streams and
    // blank the workflow bar). The list is UNFILTERED: FOLDED cannot hide such a frame.
    expect(frameTypes).not.toContain("session_ended");
    expect(frameTypes.filter((t) => t === "stream_end")).toHaveLength(1);
  });

  it("a second turn re-enters streaming and returns to idle again", async () => {
    const { state, stateTrail } = await frameFold((events) => {
      events.onText(QUESTION_LIST);
      events.onTextTurnEnd?.();
      events.onText("Second turn.");
      events.onTextTurnEnd?.();
    });
    expect(stateTrail).toEqual(["streaming", "idle", "streaming", "idle"]);
    expect(state.streamState).toBe("idle");
  });
});

describe("cc turn persistence when a markup-only block is dropped", () => {
  it("the persisted text stays the previous block's text (the runner never calls onText for the dropped block)", () => {
    const turn = new TurnPersistenceState();
    turn.setText(QUESTION_LIST);
    // A markup-only block never reaches onText, so setText is not called again.
    expect(turn.consumeForComplete()).toEqual({ text: QUESTION_LIST, usage: null });
  });

  it("a markup-only ONLY turn persists empty text, which saveAssistantMessage drops (no row)", () => {
    const turn = new TurnPersistenceState();
    expect(turn.consumeForComplete()).toEqual({ text: "", usage: null });
  });
});

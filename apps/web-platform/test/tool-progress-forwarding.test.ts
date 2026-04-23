import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// FR4 (#2861): agent-runner forwards SDKToolProgressMessage heartbeats
// to the client as `tool_progress` WS events, debounced to ≤1 emission
// per 5 seconds per `tool_use_id`.
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockRpc, mockSendToClient } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockRpc: vi.fn(),
  mockSendToClient: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(() => ({ type: "sdk", name: "test", instance: { tools: [] } })),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => "sk-test-key"),
  decryptKeyLegacy: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn(),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => ({
  ROUTABLE_DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
  DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
}));
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));
vi.mock("../server/github-app", () => ({ createPullRequest: vi.fn() }));
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn(),
  buildVisionEnhancementPrompt: vi.fn(),
}));
vi.mock("../server/providers", () => ({
  PROVIDER_CONFIG: {},
  EXCLUDED_FROM_SERVICES_UI: [],
}));

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers({ now: 0 });
  createSupabaseMockImpl(mockFrom);
  mockRpc.mockResolvedValue({ error: null });
});

afterEach(() => {
  vi.useRealTimers();
});

function makeToolProgress(toolUseId: string, elapsedSeconds = 5) {
  return {
    type: "tool_progress",
    tool_use_id: toolUseId,
    tool_name: "Bash",
    parent_tool_use_id: null,
    elapsed_time_seconds: elapsedSeconds,
    uuid: `uuid-${toolUseId}-${elapsedSeconds}`,
    session_id: "sess-1",
  };
}

describe("agent-runner: tool_progress forwarding (FR4 #2861)", () => {
  test("forwards SDKToolProgressMessage as tool_progress WS event", async () => {
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        yield makeToolProgress("tu-1", 5);
        yield { type: "result", session_id: "sess-1" };
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-1", "cpo");

    const calls = mockSendToClient.mock.calls.filter(
      ([, msg]) => msg?.type === "tool_progress",
    );
    expect(calls.length).toBe(1);
    // Raw SDK tool_name is routed through buildToolLabel so internal tool
    // names don't leak — `Bash` → `Running command...` (FALLBACK_LABELS.Bash).
    // Security review (#2861) mandated parity with the `tool_use` channel.
    expect(calls[0][1]).toMatchObject({
      type: "tool_progress",
      leaderId: "cpo",
      toolUseId: "tu-1",
      toolName: "Running command...",
      elapsedSeconds: 5,
    });
  });

  test("missing tool_use_id is dropped (defense against SDK shape drift)", async () => {
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        yield {
          type: "tool_progress",
          // tool_use_id intentionally omitted
          tool_name: "Bash",
          parent_tool_use_id: null,
          elapsed_time_seconds: 5,
          uuid: "x",
          session_id: "sess-1",
        };
        yield { type: "result", session_id: "sess-1" };
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-drift", "cpo");

    const calls = mockSendToClient.mock.calls.filter(
      ([, msg]) => msg?.type === "tool_progress",
    );
    expect(calls.length).toBe(0);
  });

  test("debounces ≤1 emission per 5s per tool_use_id", async () => {
    // Advance `vi` system time between yields from inside the iterator. The
    // server branch reads `Date.now()`; driving the clock as heartbeats are
    // consumed mimics real wall-clock cadence without clobbering the Date
    // constructor.
    const iter = {
      i: 0,
      heartbeats: [
        { hb: makeToolProgress("tu-1", 0), now: 0 },
        { hb: makeToolProgress("tu-1", 2), now: 2_000 },   // within 5s → debounced
        { hb: makeToolProgress("tu-1", 6), now: 6_000 },   // > 5s → forwards
      ],
      async next() {
        if (this.i < this.heartbeats.length) {
          const entry = this.heartbeats[this.i++];
          vi.setSystemTime(entry.now);
          return { value: entry.hb, done: false };
        }
        if (this.i === this.heartbeats.length) {
          this.i++;
          return { value: { type: "result", session_id: "sess-1" }, done: false };
        }
        return { value: undefined as any, done: true };
      },
      [Symbol.asyncIterator]() { return this; },
      return: vi.fn(),
      throw: vi.fn(),
    };
    mockQuery.mockReturnValue(iter as any);

    await startAgentSession("user-1", "conv-2", "cpo");

    const progressCalls = mockSendToClient.mock.calls.filter(
      ([, msg]) => msg?.type === "tool_progress",
    );
    expect(progressCalls.length).toBe(2);
    expect(progressCalls[0][1]).toMatchObject({ elapsedSeconds: 0 });
    expect(progressCalls[1][1]).toMatchObject({ elapsedSeconds: 6 });
  });

  test("separate tool_use_ids do not share a debounce window", async () => {
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        yield makeToolProgress("tu-a", 0);
        yield makeToolProgress("tu-b", 1);
        yield { type: "result", session_id: "sess-1" };
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    await startAgentSession("user-1", "conv-3", "cpo");

    const progressCalls = mockSendToClient.mock.calls.filter(
      ([, msg]) => msg?.type === "tool_progress",
    );
    expect(progressCalls.length).toBe(2);
    expect(progressCalls[0][1].toolUseId).toBe("tu-a");
    expect(progressCalls[1][1].toolUseId).toBe("tu-b");
  });
});

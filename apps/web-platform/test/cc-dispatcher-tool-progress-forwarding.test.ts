import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// #5214 — RED tests for the two-layer cc-surface `tool_progress` forward.
//
// Server layer 1 (runner): `soleur-go-runner.ts` must EMIT an `onToolProgress`
// DispatchEvent (shape-guarded) from its `tool_progress` branch, in addition
// to the existing watchdog re-arm.
// Server layer 2 (dispatcher): `cc-dispatcher.ts` must WIRE `events.onToolProgress`
// to `sendToClient(buildToolProgressWSMessage(...))`, debounced ≤1/5s per
// `toolUseId`, mirroring `agent-runner.ts:1889-1948`.
//
// The downstream client consumer (`chat-state-machine.ts:490`, the
// `tool_progress` WS variant, `ws-constants.ts`) is ALREADY complete — its
// regression-lock lives in `cc-soleur-go-tool-progress-no-terminal-error.test.ts`.
//
// The dispatcher-layer mock header mirrors `cc-dispatcher.test.ts` (the
// `cc-dispatcher-harness.ts` factories). The runner-layer tests reuse the
// `soleur-go-fixtures.ts` harness and drive a real `createSoleurGoRunner` with
// an injected mock query — no SDK, no dispatcher.

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
  const { conversationWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return conversationWriterFactory({ mockUpdateConversationFor });
});

vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped,
    withTtlDedupWrapper: true,
  });
});

vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return costWriterFactory();
});

vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});

vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseTenantFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseServiceFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

import {
  dispatchSoleurGo,
  __resetDispatcherForTests,
  __setCcRunnerForTests,
} from "@/server/cc-dispatcher";
import { __resetMirrorP0DedupForTests } from "@/server/observability";
import { createSoleurGoRunner } from "@/server/soleur-go-runner";
import {
  createMockQueryScripted as createMockQuery,
  makeAssistant,
  makeToolProgress,
  makeRecordingEvents as makeEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";

// ---------------------------------------------------------------------------
// Server layer 1 — the runner emits `onToolProgress`
// ---------------------------------------------------------------------------

describe("soleur-go-runner — emits onToolProgress heartbeat (server layer 1)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockReportSilentFallback.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // Test #1 — the runner's `tool_progress` branch invokes `onToolProgress`
  // with the RAW SDK fields (toolUseId/toolName/elapsedSeconds). RAW because
  // label routing is the DISPATCHER's job (#2138 invariant lives at the emit
  // boundary, not the runner). RED: no `onToolProgress` callback exists yet.
  it("Test #1: invokes onToolProgress with the raw SDK tool fields", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-1",
      userId: "u1",
      userMessage: "summarize this pdf",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(makeToolProgress("tu-1", 5));
    await flushMicrotasks();

    expect(events._progress).toHaveLength(1);
    expect(events._progress[0]).toEqual({
      toolUseId: "tu-1",
      // RAW name at the runner boundary — `makeToolProgress` uses "Read".
      toolName: "Read",
      elapsedSeconds: 5,
    });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // Test #4 — a malformed `tool_progress` (missing `tool_use_id`) is dropped
  // by the runtime shape-guard (no emit + a `tool-progress-shape` Sentry
  // mirror), BUT the watchdog re-arm STILL fires. POSITIVE CONTROL: the
  // re-arm survives the malformed message, so a `runner_runaway` does NOT
  // fire after a fresh idle window — proving the shape-guard skips ONLY the
  // emit, not the re-arm (the intentional divergence from agent-runner, which
  // `continue`s past both on a shape fail).
  it("Test #4: malformed tool_progress → no emit + Sentry mirror, but re-arm still fires", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-4",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Arm the 10s idle window at t=0 with a real tool_use.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "tu-1", name: "Read", input: { file_path: "/x.pdf" } },
        ],
      }),
    );
    await flushMicrotasks();

    // At t=8s, a MALFORMED tool_progress (no tool_use_id) — the sole
    // tool_progress in this test, so the "no forward" assertion is
    // attributable solely to the shape-guard (not a debounce window).
    vi.advanceTimersByTime(8_000);
    await flushMicrotasks();
    const malformed = {
      type: "tool_progress",
      tool_name: "Read",
      elapsed_time_seconds: 8,
      parent_tool_use_id: null,
      uuid: "00000000-0000-0000-0000-0000000000cc",
      session_id: "sess-1",
      // biome-ignore lint/suspicious/noExplicitAny: malformed SDK fixture (no tool_use_id)
    } as any as SDKMessage;
    mock.emit(malformed);
    await flushMicrotasks();

    // No emit — the shape-guard dropped it.
    expect(events._progress).toHaveLength(0);
    // Sentry mirror with the canonical op.
    const shapeMirrors = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "soleur-go-runner" && ctx?.op === "tool-progress-shape",
    );
    expect(shapeMirrors).toHaveLength(1);

    // POSITIVE CONTROL: the re-arm reset the window at t=8s, so advancing 7s
    // more (total t=15s) must NOT fire runner_runaway. Under a fix that
    // skipped the re-arm on malformed, runaway would have fired at t=10s.
    vi.advanceTimersByTime(7_000);
    await flushMicrotasks();
    expect(
      events._ended.find((e) => e.status === "runner_runaway"),
    ).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Server layer 2 — the dispatcher forwards a `tool_progress` WS message
// ---------------------------------------------------------------------------

type ToolProgressBlock = {
  toolUseId: string;
  toolName: string;
  elapsedSeconds: number;
};

interface CapturedEvents {
  onToolProgress?: (block: ToolProgressBlock) => void;
}

function makeStubCcRunner(args: {
  onDispatch: (events: CapturedEvents) => void;
}) {
  return {
    dispatch: vi.fn(async (a: { events: CapturedEvents }) => {
      // Yield one microtask so the dispatcher's parallel workspace-resolve
      // `.then` settles before the stub touches the events object (mirrors
      // the production SDK-construction ordering).
      await Promise.resolve();
      args.onDispatch(a.events);
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

function captureToolProgressFrames(sendToClient: ReturnType<typeof vi.fn>) {
  return sendToClient.mock.calls
    .filter(
      ([, msg]) =>
        msg &&
        typeof msg === "object" &&
        (msg as { type?: string }).type === "tool_progress",
    )
    .map(
      ([, msg]) =>
        msg as {
          type: string;
          leaderId?: string;
          toolUseId?: string;
          toolName?: string;
          elapsedSeconds?: number;
        },
    );
}

describe("cc-dispatcher — forwards tool_progress WS message (server layer 2)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    __resetMirrorP0DedupForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    mockMirrorP0Deduped.mockClear();
    vi.unstubAllEnvs();
    vi.stubEnv("CC_PERSIST_USAGE", "");
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
  });

  // Test #2 — the load-bearing RED for the bug: the dispatcher forwards a
  // `tool_progress` WS frame on the cc_router leader, routing the raw tool
  // name through `buildToolLabel` (#2138 invariant — `toolName !== "Read"`).
  it("Test #2: forwards a tool_progress WS frame with a human label (not the raw name)", async () => {
    let captured: CapturedEvents | undefined;
    __setCcRunnerForTests(
      makeStubCcRunner({ onDispatch: (events) => (captured = events) }),
    );

    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({
      persona: "command_center",
      userId: "u-tp",
      conversationId: "conv-tp",
      userMessage: "summarize this PDF",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    await flushMicrotasks();

    expect(captured?.onToolProgress).toBeTypeOf("function");
    captured!.onToolProgress!({ toolUseId: "tu-1", toolName: "Read", elapsedSeconds: 5 });

    const frames = captureToolProgressFrames(sendToClient);
    expect(frames).toHaveLength(1);
    const frame = frames[0]!;
    expect(frame.leaderId).toBe("cc_router");
    expect(frame.toolUseId).toBe("tu-1");
    expect(frame.elapsedSeconds).toBe(5);
    // #2138 invariant: the raw SDK tool name MUST NOT reach the wire — the
    // forward routes it through `buildToolLabel` (human label only). "Read"
    // with no `tool_input` falls to FALLBACK_LABELS.Read ("Reading file...").
    expect(frame.toolName).not.toBe("Read");
    expect(frame.toolName).toBe("Reading file...");
  });

  // Test #3 — debounce: ≤1 forward per 5s per toolUseId. CLOCK-DRIVE: the
  // debounce compares `Date.now()`, so `vi.setSystemTime()` must advance the
  // wall clock per heartbeat (mirrors agent-runner precedent
  // `tool-progress-forwarding.test.ts:204-209`). t=0 forwards, t=2s is
  // suppressed (<5s), t=6s forwards again → exactly 2 forwards.
  it("Test #3: debounces to <=1 forward / 5s / toolUseId (clock-driven)", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(0);
      let captured: CapturedEvents | undefined;
      __setCcRunnerForTests(
        makeStubCcRunner({ onDispatch: (events) => (captured = events) }),
      );

      const sendToClient = vi.fn().mockReturnValue(true);
      await dispatchSoleurGo({
        persona: "command_center",
        userId: "u-tp3",
        conversationId: "conv-tp3",
        userMessage: "long read",
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient,
        persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      });
      await flushMicrotasks();
      expect(captured?.onToolProgress).toBeTypeOf("function");

      vi.setSystemTime(0);
      captured!.onToolProgress!({ toolUseId: "tu-1", toolName: "Read", elapsedSeconds: 0 });
      vi.setSystemTime(2_000);
      captured!.onToolProgress!({ toolUseId: "tu-1", toolName: "Read", elapsedSeconds: 2 });
      vi.setSystemTime(6_000);
      captured!.onToolProgress!({ toolUseId: "tu-1", toolName: "Read", elapsedSeconds: 6 });

      const frames = captureToolProgressFrames(sendToClient);
      // t=0 (first always forwards) + t=6s (>=5s window) — NOT t=2s (<5s).
      expect(frames).toHaveLength(2);
      expect(frames[0]!.elapsedSeconds).toBe(0);
      expect(frames[1]!.elapsedSeconds).toBe(6);

      // A DISTINCT toolUseId forwards independently (its own first-heartbeat).
      vi.setSystemTime(6_500);
      captured!.onToolProgress!({ toolUseId: "tu-2", toolName: "Read", elapsedSeconds: 1 });
      const after = captureToolProgressFrames(sendToClient);
      expect(after).toHaveLength(3);
      expect(after[2]!.toolUseId).toBe("tu-2");
    } finally {
      vi.useRealTimers();
    }
  });
});

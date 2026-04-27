import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import type {
  Query,
  SDKMessage,
  SDKUserMessage,
  SDKResultMessage,
  SDKAssistantMessage,
  SDKPartialAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  createSoleurGoRunner,
  buildSoleurGoSystemPrompt,
  type QueryFactory,
  type WorkflowEnd,
  type DispatchEvents,
} from "@/server/soleur-go-runner";
import type { ConversationRouting } from "@/server/conversation-routing";

// RED test for Stage 2.2 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// `soleur-go-runner.ts` is the single source of truth for `/soleur:go` SDK
// invocation. This test pins the behavioral contract with a mocked
// `QueryFactory` — no real SDK subprocess, no real Anthropic API call.
//
// Invariants under test (per plan Stage 2 + Stage 2.2 task):
//   (a) Dispatch: first call with `soleur_go_pending` routing creates one
//       Query per conversation, wraps user input via prompt-injection-wrap,
//       passes streaming-input prompt (AsyncIterable<SDKUserMessage>), and
//       builds a systemPrompt containing the pre-dispatch narration directive.
//   (b) Sticky workflow detection: first `tool_use` block with name="Skill"
//       and skill argument in the workflow allowlist triggers a single
//       `persistActiveWorkflow(workflow)` call plus `events.onWorkflowDetected`.
//       Subsequent Skill calls in the same conversation do NOT overwrite.
//   (c) Sentinel consumption: when `currentRouting.kind === "soleur_go_pending"`,
//       the runner persists the detected workflow (replacing the sentinel).
//   (d) Per-workflow cost cap: synthetic SDKResultMessage with
//       `total_cost_usd` that crosses the cap fires
//       `events.onWorkflowEnded({ status: "cost_ceiling", ... })` and closes
//       the Query. Pre-detection uses the `default` cap.
//   (e) Secondary wall-clock trigger: if tool_use events stream for
//       >= wallClockTriggerMs (30s) without any SDKResultMessage, the
//       runner fires `workflow_ended { status: "runner_runaway" }` and
//       calls `query.close()`.

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeAssistant(
  partial: Partial<SDKAssistantMessage> & {
    content: Array<
      | { type: "text"; text: string }
      | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
    >;
  },
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: partial.uuid ?? "msg_1",
      role: "assistant",
      model: "claude-sonnet-4-6",
      stop_reason: null,
      stop_sequence: null,
      type: "message",
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        server_tool_use: null,
        service_tier: null,
      },
      content: partial.content,
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: partial.parent_tool_use_id ?? null,
    uuid: (partial.uuid ?? "00000000-0000-0000-0000-000000000001") as never,
    session_id: partial.session_id ?? "sess-1",
  } as SDKAssistantMessage;
}

function makeResult(totalCostUsd: number, sessionId = "sess-1"): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 100,
    duration_api_ms: 50,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: totalCostUsd,
    // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: sessionId,
  } as SDKResultMessage;
}

// A minimal scriptable Query. Tests drive the stream by calling `emit(msg)`
// or pre-loading `scripted` messages. Once `close()` is called, the async
// iterator returns on the next pull.
function createMockQuery(scripted: SDKMessage[] = []) {
  let closed = false;
  const queue: SDKMessage[] = [...scripted];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const emitted: SDKMessage[] = [];
  const closeSpy = vi.fn();

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (queue.length > 0) {
        const value = queue.shift()!;
        emitted.push(value);
        return { value, done: false };
      }
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((resolve) => {
        resolveNext = resolve;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(err) {
      closed = true;
      throw err;
    },
    async [Symbol.asyncDispose]() {
      closed = true;
    },
    [Symbol.asyncIterator]() {
      return iter;
    },
  };

  function emit(msg: SDKMessage): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      emitted.push(msg);
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }

  function finish(): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: undefined, done: true });
    }
    closed = true;
  }

  const q: Mutable<Partial<Query>> = {
    ...(iter as unknown as Query),
    close: () => {
      closeSpy();
      finish();
    },
    interrupt: vi.fn(async () => {}),
    setPermissionMode: vi.fn(async () => {}),
    setModel: vi.fn(async () => {}),
    setMaxThinkingTokens: vi.fn(async () => {}),
    applyFlagSettings: vi.fn(async () => {}),
    // biome-ignore lint/suspicious/noExplicitAny: test stub
    initializationResult: vi.fn(async () => ({}) as any),
    supportedCommands: vi.fn(async () => []),
    supportedModels: vi.fn(async () => []),
    streamInput: vi.fn(async () => {}),
    stopTask: vi.fn(async () => {}),
  };

  return {
    query: q as Query,
    emit,
    finish,
    closeSpy,
    emitted,
    isClosed: () => closed,
  };
}

type CapturedFactoryCall = {
  prompt: AsyncIterable<SDKUserMessage>;
  systemPrompt: string;
  resumeSessionId: string | undefined;
};

function makeEvents(): DispatchEvents & {
  _text: string[];
  _tools: Array<{ name: string; input: Record<string, unknown> }>;
  _workflowDetected: string[];
  _ended: WorkflowEnd[];
  _results: Array<{ totalCostUsd: number }>;
} {
  const text: string[] = [];
  const tools: Array<{ name: string; input: Record<string, unknown> }> = [];
  const workflowDetected: string[] = [];
  const ended: WorkflowEnd[] = [];
  const results: Array<{ totalCostUsd: number }> = [];
  return {
    onText: (t) => text.push(t),
    onToolUse: (b) => tools.push(b),
    onWorkflowDetected: (w) => workflowDetected.push(w),
    onWorkflowEnded: (e) => ended.push(e),
    onResult: (r) => results.push(r),
    _text: text,
    _tools: tools,
    _workflowDetected: workflowDetected,
    _ended: ended,
    _results: results,
  };
}

async function flushMicrotasks(count = 8): Promise<void> {
  for (let i = 0; i < count; i++) await Promise.resolve();
}

describe("soleur-go-runner dispatch (Stage 2.2)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("creates a Query, wraps user input, and pushes an SDKUserMessage into the streaming-input iterable", async () => {
    const captures: CapturedFactoryCall[] = [];
    const mock = createMockQuery();
    const factory: QueryFactory = (args) => {
      captures.push({
        prompt: args.prompt,
        systemPrompt: args.systemPrompt,
        resumeSessionId: args.resumeSessionId,
      });
      return mock.query;
    };
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => 0,
      pluginPath: "/plugin",
      cwd: "/work",
    });
    const events = makeEvents();
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);
    const routing: ConversationRouting = { kind: "soleur_go_pending" };

    await runner.dispatch({
      conversationId: "conv-1",
      userId: "user-1",
      userMessage: "Plan a new feature for onboarding.",
      currentRouting: routing,
      events,
      persistActiveWorkflow,
    });

    expect(captures).toHaveLength(1);
    expect(runner.hasActiveQuery("conv-1")).toBe(true);

    // Systemprompt carries the narration directive.
    expect(captures[0]!.systemPrompt).toContain(
      "Before invoking the Skill tool, emit a one-line text block",
    );

    // Prompt is an AsyncIterable (not a string). Drain the first pushed
    // message and assert the wrap + postamble landed.
    const iter = captures[0]!.prompt[Symbol.asyncIterator]();
    const first = await iter.next();
    expect(first.done).toBe(false);
    const msg = first.value as SDKUserMessage;
    expect(msg.type).toBe("user");
    const content = (msg.message as { content: unknown }).content;
    const text =
      typeof content === "string"
        ? content
        : Array.isArray(content) && content[0] && typeof content[0] === "object"
          ? ((content[0] as { text?: string }).text ?? "")
          : "";
    expect(text).toContain("<user-input>");
    expect(text).toContain("Plan a new feature for onboarding.");
    expect(text).toContain("Invoke /soleur:go on the user's intent.");

    mock.finish();
    await flushMicrotasks();
  });

  it("on first Skill tool_use, persists the workflow and emits onWorkflowDetected exactly once", async () => {
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "conv-1",
      userId: "user-1",
      userMessage: "hey",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow,
    });

    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "toolu_1",
            name: "Skill",
            input: { skill: "brainstorm", args: "onboarding" },
          },
        ],
      }),
    );
    await flushMicrotasks();
    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "toolu_2",
            name: "Skill",
            input: { skill: "plan" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    expect(persistActiveWorkflow).toHaveBeenCalledTimes(1);
    expect(persistActiveWorkflow).toHaveBeenCalledWith("brainstorm");
    expect(events._workflowDetected).toEqual(["brainstorm"]);

    mock.finish();
    await flushMicrotasks();
  });

  it("consumes the '__unrouted__' sentinel by calling persistActiveWorkflow with the detected workflow name", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => 0,
    });
    const events = makeEvents();
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "conv-sentinel",
      userId: "u1",
      userMessage: "review my branch",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow,
    });

    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "toolu_x",
            name: "Skill",
            input: { skill: "review" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    expect(persistActiveWorkflow).toHaveBeenCalledWith("review");
    mock.finish();
    await flushMicrotasks();
  });

  it("per-workflow cost cap: brainstorm > $5.00 emits workflow_ended cost_ceiling and closes the Query", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => 0,
      defaultCostCaps: {
        perWorkflow: { brainstorm: 5.0, work: 2.0 },
        default: 2.0,
      },
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "c-cap",
      userId: "u1",
      userMessage: "brainstorm a feature",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Skill", input: { skill: "brainstorm" } },
        ],
      }),
    );
    await flushMicrotasks();

    // Cumulative cost rises to $5.50 — over the $5.00 brainstorm cap.
    mock.emit(makeResult(5.5));
    await flushMicrotasks();

    const ceiling = events._ended.find((e) => e.status === "cost_ceiling");
    expect(ceiling).toBeDefined();
    expect(ceiling).toMatchObject({ status: "cost_ceiling", cap: 5.0 });
    expect(mock.closeSpy).toHaveBeenCalled();
  });

  it("default cost cap applies when no workflow has been detected yet", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => 0,
      defaultCostCaps: {
        perWorkflow: { brainstorm: 5.0, work: 2.0 },
        default: 2.0,
      },
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "c-default-cap",
      userId: "u1",
      userMessage: "do something",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(makeResult(2.5));
    await flushMicrotasks();

    expect(events._ended.find((e) => e.status === "cost_ceiling")).toMatchObject({
      status: "cost_ceiling",
      cap: 2.0,
    });
    expect(mock.closeSpy).toHaveBeenCalled();
  });

  it("secondary wall-clock trigger: >=30s of tool-use events without a SDKResultMessage fires runner_runaway and closes the Query", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "c-runaway",
      userId: "u1",
      userMessage: "do forever",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Stream tool_use events at t=0, t=10s, t=20s, t=31s — no terminal result.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "sleep 1" } },
        ],
      }),
    );
    await flushMicrotasks();

    vi.advanceTimersByTime(10_000);
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t2", name: "Bash", input: { command: "sleep 1" } },
        ],
      }),
    );
    await flushMicrotasks();

    vi.advanceTimersByTime(15_000);
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t3", name: "Bash", input: { command: "sleep 1" } },
        ],
      }),
    );
    await flushMicrotasks();

    // Advance past the 30s trigger relative to the first tool_use.
    vi.advanceTimersByTime(10_000);
    await flushMicrotasks();

    const runaway = events._ended.find((e) => e.status === "runner_runaway");
    expect(runaway).toBeDefined();
    expect(mock.closeSpy).toHaveBeenCalled();
  });

  it("emits onResult with total_cost_usd on SDKResultMessage", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => 0,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "c-cost",
      userId: "u1",
      userMessage: "ok",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(makeResult(0.25));
    await flushMicrotasks();

    expect(events._results.at(-1)).toEqual({ totalCostUsd: 0.25 });
  });

  it("streams text blocks to events.onText", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => 0,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "c-text",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [{ type: "text", text: "Routing to brainstorm…" }],
      }),
    );
    await flushMicrotasks();

    expect(events._text.join("")).toContain("Routing to brainstorm");
    mock.finish();
    await flushMicrotasks();
  });
});

// -------------------------------------------------------------------------
// #2923 — buildSoleurGoSystemPrompt context-injection parity
// Default-args call preserves the pre-existing 5-line baseline (PR #2901
// contract). New args inject ONLY routing-relevant context: artifact
// path (when context.path provided) + sticky-workflow sentence (when
// currentRouting.kind === "soleur_go_active").
// -------------------------------------------------------------------------
describe("buildSoleurGoSystemPrompt context injection (#2923)", () => {
  it("T1: default-args call preserves the pre-existing baseline (no extra sentences)", () => {
    const prompt = buildSoleurGoSystemPrompt();
    expect(prompt).toContain("Command Center router");
    expect(prompt).toContain(
      "Before invoking the Skill tool, emit a one-line text block",
    );
    expect(prompt).toContain("/soleur:go");
    // Baseline must not mention artifact or sticky-workflow.
    expect(prompt).not.toContain("currently viewing");
    expect(prompt).not.toContain("workflow is active");
  });

  it("T2: artifactPath injects the artifact-aware sentence", () => {
    const prompt = buildSoleurGoSystemPrompt({ artifactPath: "vision.md" });
    expect(prompt).toContain("currently viewing");
    expect(prompt).toContain("vision.md");
    // Sticky-workflow sentence stays absent.
    expect(prompt).not.toContain("workflow is active");
  });

  it("T3: activeWorkflow injects the sticky-workflow sentence with /soleur:<name>", () => {
    const prompt = buildSoleurGoSystemPrompt({ activeWorkflow: "work" });
    expect(prompt).toContain("workflow is active");
    expect(prompt).toContain("/soleur:work");
    // No artifact sentence.
    expect(prompt).not.toContain("currently viewing");
  });

  it("T4: both args present — both sentences appear", () => {
    const prompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/product/vision.md",
      activeWorkflow: "brainstorm",
    });
    expect(prompt).toContain("currently viewing");
    expect(prompt).toContain("knowledge-base/product/vision.md");
    expect(prompt).toContain("workflow is active");
    expect(prompt).toContain("/soleur:brainstorm");
  });

  it("T5: empty/undefined artifactPath → baseline preserved", () => {
    expect(buildSoleurGoSystemPrompt({ artifactPath: "" })).toBe(
      buildSoleurGoSystemPrompt(),
    );
    expect(buildSoleurGoSystemPrompt({ activeWorkflow: null })).toBe(
      buildSoleurGoSystemPrompt(),
    );
  });
});

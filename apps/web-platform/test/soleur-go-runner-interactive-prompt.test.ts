import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type {
  Query,
  SDKMessage,
  SDKAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  createSoleurGoRunner,
  type QueryFactory,
} from "@/server/soleur-go-runner";
import {
  PendingPromptRegistry,
  makePendingPromptKey,
} from "@/server/pending-prompt-registry";
import type { WSMessage } from "@/lib/types";
type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;

// RED test for Stage 2.10 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// The "interactive-tool bridge" in the runner classifies assistant-message
// `tool_use` blocks whose `name` matches one of the six interactive kinds,
// synthesizes a payload, registers the prompt in the PendingPromptRegistry
// (composite key `${userId}:${conversationId}:${promptId}`), and emits
// `interactive_prompt` events via `deps.emitInteractivePrompt`.
//
// Non-interactive tool_use blocks (Skill, Glob, Grep, Read, LS, etc.) must
// NOT produce registry entries or WS events. This negative-space case is
// gated behind a dedicated assertion so a classifier that accidentally
// widens never falls back to a no-op pass.
//
// Invariants under test:
//   (a) ExitPlanMode → kind="plan_preview"; plan markdown in payload.
//   (b) TodoWrite → kind="todo_write"; items forwarded.
//   (c) NotebookEdit → kind="notebook_edit"; cellIds extracted.
//   (d) Edit / Write → kind="diff"; file path + coarse add/del counts.
//   (e) Bash → kind="bash_approval"; command + cwd + gated flag.
//   (f) AskUserQuestion → kind="ask_user"; question + options.
//   (g) Non-interactive tool_use (Skill) → neither emit nor register.
//   (h) Every emission is paired 1:1 with a registry entry under the same
//       composite key, so the `interactive_prompt_response` handler can
//       resolve back to the tool_use.
//   (i) Ownership key composition matches `makePendingPromptKey(userId,
//       conversationId, promptId)`. The promptId in the emitted event
//       matches the registered record's promptId.

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeAssistant(
  content: Array<
    | { type: "text"; text: string }
    | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
  >,
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: "msg_1",
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
      content,
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    uuid: "00000000-0000-0000-0000-000000000001" as never,
    session_id: "sess-1",
  } as SDKAssistantMessage;
}

function createMockQuery() {
  let closed = false;
  const queue: SDKMessage[] = [];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (queue.length > 0) return { value: queue.shift()!, done: false };
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

  return { query: q as Query, emit, finish };
}

async function flushMicrotasks(count = 8): Promise<void> {
  for (let i = 0; i < count; i++) await Promise.resolve();
}

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
  };
}

describe("soleur-go-runner interactive-prompt bridge (Stage 2.10)", () => {
  let emittedEvents: Array<{ userId: string; event: InteractivePromptEvent }>;
  let registry: PendingPromptRegistry;
  let emitInteractivePrompt: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers({ now: 0 });
    emittedEvents = [];
    registry = new PendingPromptRegistry({ nowFn: () => Date.now() });
    emitInteractivePrompt = vi.fn(
      (userId: string, event: InteractivePromptEvent) => {
        emittedEvents.push({ userId, event });
      },
    );
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  async function runOneToolUse(
    toolUse: {
      id: string;
      name: string;
      input: Record<string, unknown>;
    },
  ): Promise<void> {
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    await runner.dispatch({
      conversationId: "conv-1",
      userId: "user-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: makeEvents(),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emit(makeAssistant([{ type: "tool_use", ...toolUse }]));
    await flushMicrotasks();
    mock.finish();
    await flushMicrotasks();
  }

  it("ExitPlanMode tool_use → emit interactive_prompt with kind plan_preview", async () => {
    await runOneToolUse({
      id: "toolu_plan",
      name: "ExitPlanMode",
      input: { plan: "1. Do A\n2. Do B" },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event, userId } = emittedEvents[0]!;
    expect(userId).toBe("user-1");
    expect(event.type).toBe("interactive_prompt");
    expect(event.kind).toBe("plan_preview");
    expect(event.conversationId).toBe("conv-1");
    if (event.kind === "plan_preview") {
      expect(event.payload.markdown).toBe("1. Do A\n2. Do B");
    }

    // Registry contains the matching record.
    const key = makePendingPromptKey("user-1", "conv-1", event.promptId);
    const record = registry.get(key, "user-1");
    expect(record).toBeDefined();
    expect(record!.kind).toBe("plan_preview");
    expect(record!.toolUseId).toBe("toolu_plan");
  });

  it("TodoWrite tool_use → emit interactive_prompt with kind todo_write", async () => {
    await runOneToolUse({
      id: "toolu_todo",
      name: "TodoWrite",
      input: {
        todos: [
          { content: "First", status: "pending", activeForm: "Doing first" },
        ],
      },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("todo_write");
    if (event.kind === "todo_write") {
      expect(event.payload.items.length).toBeGreaterThanOrEqual(1);
    }
  });

  it("NotebookEdit tool_use → emit interactive_prompt with kind notebook_edit", async () => {
    await runOneToolUse({
      id: "toolu_nb",
      name: "NotebookEdit",
      input: { notebook_path: "/w/book.ipynb", cell_id: "c-1", new_source: "print(1)" },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("notebook_edit");
    if (event.kind === "notebook_edit") {
      expect(event.payload.notebookPath).toBe("/w/book.ipynb");
      expect(event.payload.cellIds).toContain("c-1");
    }
  });

  it("Edit tool_use → emit interactive_prompt with kind diff", async () => {
    await runOneToolUse({
      id: "toolu_edit",
      name: "Edit",
      input: {
        file_path: "/w/src/foo.ts",
        old_string: "a\nb\nc",
        new_string: "a\nb\nc\nd",
      },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("diff");
    if (event.kind === "diff") {
      expect(event.payload.path).toBe("/w/src/foo.ts");
      // Input: old_string="a\nb\nc" (3 lines), new_string="a\nb\nc\nd" (4 lines).
      // classifier computes max(0, new-old)=1 / max(0, old-new)=0 — pin exactly
      // so a classifier drift (e.g., swapping add/del) surfaces as a diff, not
      // as a tautology per `cq-mutation-assertions-pin-exact-post-state`.
      expect(event.payload.additions).toBe(1);
      expect(event.payload.deletions).toBe(0);
    }
  });

  it("Bash tool_use → emit interactive_prompt with kind bash_approval", async () => {
    await runOneToolUse({
      id: "toolu_bash",
      name: "Bash",
      input: { command: "ls -la", cwd: "/w" },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("bash_approval");
    if (event.kind === "bash_approval") {
      expect(event.payload.command).toBe("ls -la");
      expect(event.payload.cwd).toBe("/w");
      expect(event.payload.gated).toBe(true);
    }
  });

  it("AskUserQuestion tool_use → emit interactive_prompt with kind ask_user", async () => {
    await runOneToolUse({
      id: "toolu_ask",
      name: "AskUserQuestion",
      input: {
        questions: [
          { question: "A or B?", header: "h", multiSelect: false, options: [{ label: "A" }, { label: "B" }] },
        ],
      },
    });

    expect(emittedEvents).toHaveLength(1);
    const { event } = emittedEvents[0]!;
    expect(event.kind).toBe("ask_user");
    if (event.kind === "ask_user") {
      expect(event.payload.question).toBe("A or B?");
      expect(event.payload.options).toEqual(["A", "B"]);
      expect(event.payload.multiSelect).toBe(false);
    }
  });

  it("non-interactive tool_use (Skill) does NOT emit or register", async () => {
    await runOneToolUse({
      id: "toolu_skill",
      name: "Skill",
      input: { skill: "brainstorm" },
    });

    expect(emittedEvents).toHaveLength(0);
    expect(registry.size()).toBe(0);
  });

  it("no emit / no register when both deps are absent (runner remains usable w/o bridge)", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
    });
    await runner.dispatch({
      conversationId: "conv-2",
      userId: "user-2",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: makeEvents(),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    mock.emit(
      makeAssistant([
        {
          type: "tool_use",
          id: "toolu_plan_2",
          name: "ExitPlanMode",
          input: { plan: "stuff" },
        },
      ]),
    );
    await flushMicrotasks();
    mock.finish();
    await flushMicrotasks();

    // With no registry and no emitter, the runner must still run cleanly.
    expect(emittedEvents).toHaveLength(0);
  });
});

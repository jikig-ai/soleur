import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mock observability BEFORE importing the runner so the managed-soft-cap
// warn and any silent-fallback assertions inspect the mocks.
const { mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

import {
  createSoleurGoRunner,
  type QueryFactory,
  type WorkflowEnd,
  CAP_PROMPT_PARK_MS,
} from "@/server/soleur-go-runner";
import {
  createMockQueryLean as createMockQuery,
  flushMicrotasks,
  makeResult,
} from "./helpers/soleur-go-fixtures";
import {
  PendingPromptRegistry,
  makePendingPromptKey,
  COST_CAP_TOOL_USE_ID_PREFIX,
} from "@/server/pending-prompt-registry";
import { mintConversationId, mintPromptId } from "@/lib/branded-ids";
import type { WSMessage } from "@/lib/types";

type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;

// feat-cc-cap-raise-resume (#9565) — resumable per-conversation cost cap.
//
// Invariants under test:
//   (a) Managed sessions (credential.scheme === "oauth_token", captured via
//       the `setAuthScheme` sink) are NEVER hard-ended by the
//       per-conversation cap — no `cost_ceiling`, Query stays open.
//   (b) Managed soft-warn: crossing `managedWarnCapUsd` emits exactly one
//       warnSilentFallback per ActiveQuery.
//   (c) BYOK sessions keep the cap but it is RESUMABLE: cap breach emits an
//       `interactive_prompt` (kind "ask_user", sentinel `cost-cap:` toolUseId)
//       instead of `emitWorkflowEnded`, and the conversation parks
//       (awaitingUser → reapIdle skips).
//   (d) `applyCostCapRaise` with a raise tier sets the per-conversation
//       override, fires `persistCostCapOverride`, and resumes the Query.
//   (e) "Keep the cap" un-parks without raising and drops the parked message.
//   (f) A send while over cap (enforced session) is PARKED, not pushed to the
//       SDK, and re-emits the raise prompt.
//   (g) With no prompt machinery (`pendingPrompts`/`emitInteractivePrompt`
//       absent), cap breach falls back to legacy `cost_ceiling` teardown.
//   (h) Unknown / stale authScheme ⇒ enforce (fail toward protective).

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn<(end: WorkflowEnd) => void>(),
    onResult: vi.fn(),
  };
}

function makeDispatchArgs(
  overrides: Partial<Parameters<ReturnType<typeof createSoleurGoRunner>["dispatch"]>[0]> = {},
) {
  return {
    persona: "command_center" as const,
    conversationId: "conv-cap",
    userId: "u1",
    userMessage: "hello",
    currentRouting: { kind: "soleur_go_pending" as const },
    events: makeEvents(),
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

describe("soleur-go-runner resumable cost cap (#9565)", () => {
  let registry: PendingPromptRegistry;
  let promptEvents: Array<{ userId: string; event: InteractivePromptEvent }>;
  let emitInteractivePrompt: ReturnType<
    typeof vi.fn<(userId: string, event: InteractivePromptEvent) => void>
  >;

  beforeEach(() => {
    vi.useFakeTimers({ now: 0 });
    registry = new PendingPromptRegistry({ nowFn: () => Date.now() });
    promptEvents = [];
    emitInteractivePrompt = vi.fn<
      (userId: string, event: InteractivePromptEvent) => void
    >((userId: string, event: InteractivePromptEvent) => {
      promptEvents.push({ userId, event });
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("managed session (oauth_token) never receives cost_ceiling at cap breach", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("oauth_token");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      managedWarnCapUsd: 50,
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));

    mock.emit(makeResult({ totalCostUsd: 5.0 }));
    await flushMicrotasks(10);

    const ends = events.onWorkflowEnded.mock.calls.map((c) => c[0]);
    expect(ends.some((e) => e.status === "cost_ceiling")).toBe(false);
    expect(runner.activeQueriesSize()).toBe(1);
    expect(promptEvents).toHaveLength(0);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("managed soft-cap warns once per ActiveQuery at managedWarnCapUsd", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("oauth_token");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      managedWarnCapUsd: 3.0,
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    await runner.dispatch(makeDispatchArgs());

    mock.emit(makeResult({ totalCostUsd: 2.0 }));
    await flushMicrotasks(10);
    mock.emit(makeResult({ totalCostUsd: 4.0 }));
    await flushMicrotasks(10);
    mock.emit(makeResult({ totalCostUsd: 9.0 }));
    await flushMicrotasks(10);

    const warnCalls = mockWarnSilentFallback.mock.calls.filter((c) => {
      const ctx = c[1] as { op?: string } | undefined;
      return ctx?.op === "managed-soft-cap";
    });
    expect(warnCalls).toHaveLength(1);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("BYOK cap breach emits an ask_user interactive_prompt and keeps the Query open", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);

    // No cost_ceiling teardown — the prompt path replaces it.
    const ends = events.onWorkflowEnded.mock.calls.map((c) => c[0]);
    expect(ends.some((e) => e.status === "cost_ceiling")).toBe(false);
    expect(runner.activeQueriesSize()).toBe(1);
    expect(mock.isClosed()).toBe(false);

    expect(promptEvents).toHaveLength(1);
    const ev = promptEvents[0].event;
    expect(ev.kind).toBe("ask_user");
    const payload = ev.payload as { question: string; options: string[]; multiSelect: boolean };
    expect(payload.multiSelect).toBe(false);
    expect(payload.options.some((o) => o.startsWith("Raise to $"))).toBe(true);
    expect(payload.options).toContain("Keep the cap");

    // The registry record carries the sentinel toolUseId.
    const key = makePendingPromptKey(
      "u1",
      mintConversationId("conv-cap"),
      mintPromptId(ev.promptId),
    );
    const record = registry.get(key, "u1");
    expect(record?.toolUseId.startsWith(COST_CAP_TOOL_USE_ID_PREFIX)).toBe(true);

    // Parked inside the bounded window (CAP_PROMPT_PARK_MS = 5.5 min):
    // the Query survives and awaitingUser blocks idle reaping.
    vi.advanceTimersByTime(4 * 60 * 1000);
    expect(runner.activeQueriesSize()).toBe(1);
    expect(mock.isClosed()).toBe(false);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("applyCostCapRaise sets the override, persists it, and resumes", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      return mock.query;
    });
    const persistCap = vi.fn().mockResolvedValue(undefined);
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events, persistCostCapOverride: persistCap }));

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);
    expect(promptEvents).toHaveLength(1);

    const ok = runner.applyCostCapRaise({
      conversationId: "conv-cap",
      response: "Raise to $10",
    });
    expect(ok).toBe(true);
    expect(persistCap).toHaveBeenCalledWith(10);

    // Resume: subsequent result under the new cap does not re-prompt.
    mock.emit(makeResult({ totalCostUsd: 5.0 }));
    await flushMicrotasks(10);
    expect(promptEvents).toHaveLength(1);
    const ends = events.onWorkflowEnded.mock.calls.map((c) => c[0]);
    expect(ends.some((e) => e.status === "cost_ceiling")).toBe(false);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("over-cap send parks the user message instead of pushing to the SDK", async () => {
    const mock = createMockQuery();
    // Capture the factory's `prompt` async iterable — pushUserMessage
    // feeds it via inputQueue; collect what the SDK would consume.
    const pushed: Array<{ content: unknown }> = [];
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      void (async () => {
        for await (const m of args.prompt) {
          pushed.push(m.message as { content: unknown });
        }
      })();
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));
    await flushMicrotasks(10);
    expect(pushed).toHaveLength(1);

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);
    expect(promptEvents).toHaveLength(1);

    // Follow-up send while over cap: parked + prompt re-emitted, NO push.
    await runner.dispatch(
      makeDispatchArgs({ events, userMessage: "continue the work" }),
    );
    await flushMicrotasks(10);
    expect(promptEvents.length).toBeGreaterThanOrEqual(2);
    expect(pushed).toHaveLength(1);

    // Raise releases the parked message into the live Query.
    const ok = runner.applyCostCapRaise({
      conversationId: "conv-cap",
      response: "Raise to $10",
    });
    expect(ok).toBe(true);
    await flushMicrotasks(10);
    expect(pushed).toHaveLength(2);
    expect(String(pushed[1].content)).toContain("continue the work");
    mock.finish();
    await flushMicrotasks(5);
  });

  it("Keep-the-cap un-parks without raising and drops the parked message", async () => {
    const mock = createMockQuery();
    const pushed: Array<{ content: unknown }> = [];
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      void (async () => {
        for await (const m of args.prompt) {
          pushed.push(m.message as { content: unknown });
        }
      })();
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);
    await runner.dispatch(
      makeDispatchArgs({ events, userMessage: "continue the work" }),
    );
    await flushMicrotasks(10);
    expect(pushed).toHaveLength(1); // parked

    const ok = runner.applyCostCapRaise({
      conversationId: "conv-cap",
      response: "Keep the cap",
    });
    expect(ok).toBe(true);
    await flushMicrotasks(10);

    // Parked message dropped (honest copy on the wire), cap unchanged —
    // the next send re-prompts instead of spending.
    expect(pushed).toHaveLength(1);
    const text = events.onText.mock.calls.map((c) => c[0]).join("\n");
    expect(text).toContain("wasn't sent");

    await runner.dispatch(
      makeDispatchArgs({ events, userMessage: "again" }),
    );
    await flushMicrotasks(10);
    expect(promptEvents.length).toBeGreaterThanOrEqual(3);
    expect(pushed).toHaveLength(1);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("rejects an invalid or stale tier response", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    await runner.dispatch(makeDispatchArgs());
    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);

    expect(
      runner.applyCostCapRaise({ conversationId: "conv-cap", response: "yes please" }),
    ).toBe(false);
    // A tier at/below the effective cap must not apply either.
    expect(
      runner.applyCostCapRaise({ conversationId: "conv-cap", response: "Raise to $1" }),
    ).toBe(false);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("legacy fallback: no prompt machinery ⇒ cost_ceiling teardown as before", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);

    const ends = events.onWorkflowEnded.mock.calls.map((c) => c[0]);
    expect(ends.some((e) => e.status === "cost_ceiling")).toBe(true);
    expect(runner.activeQueriesSize()).toBe(0);
  });

  it("unknown authScheme (no sink call) still enforces the cap", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    const events = makeEvents();
    await runner.dispatch(makeDispatchArgs({ events }));

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);

    // Prompt path fires — the cap is enforced (fail toward protective).
    expect(promptEvents).toHaveLength(1);
    mock.finish();
    await flushMicrotasks(5);
  });

  it("park timer expiry un-parks the conversation so idle reaping resumes", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>((args) => {
      args.setAuthScheme?.("api_key");
      return mock.query;
    });
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 1.0 },
      pendingPrompts: registry,
      emitInteractivePrompt,
    });
    await runner.dispatch(makeDispatchArgs());

    mock.emit(makeResult({ totalCostUsd: 1.5 }));
    await flushMicrotasks(10);
    expect(promptEvents).toHaveLength(1);

    // Park timer fires at CAP_PROMPT_PARK_MS; afterwards the conversation
    // rejoins normal idle reaping (no permanent park).
    vi.advanceTimersByTime(CAP_PROMPT_PARK_MS + 1000);
    await flushMicrotasks(10);
    vi.advanceTimersByTime(15 * 60 * 1000);
    expect(runner.reapIdle()).toBe(1);
    expect(runner.activeQueriesSize()).toBe(0);
  });
});

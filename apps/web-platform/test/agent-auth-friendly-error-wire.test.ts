// #11086 wire test for the cc-soleur-go runner: the REAL tapAgentAuthFailure + REAL createAgentAuthFailureProbe + REAL runner.
// A stubbed tap would make the ordering assertion vacuous (Guard 2 harness row a). The legacy runner has its own wire cases
// in agent-runner-unix-deny-wire.test.ts-style harness: see agent-auth-friendly-error-wire-legacy.test.ts.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  createMockQueryScripted as createMockQuery,
  flushMicrotasks,
  makeRecordingEvents,
  makeResult,
} from "./helpers/soleur-go-fixtures";

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
  __resetAgentAuthDedupeForTests,
  createAgentAuthFailureProbe,
  tapAgentAuthFailure,
} from "@/server/agent-auth-failure";
import { authFailureCopy } from "@/server/agent-auth-user-message";
import { createSoleurGoRunner } from "@/server/soleur-go-runner";

const CLI_TEXT = "Not logged in · Please run /login";
const EXPIRED_TEXT = "Session expired. Please run /login to sign in again.";

function cliAssistant(text: string): Record<string, unknown> {
  return {
    type: "assistant",
    error: "authentication_failed",
    is_api_error_message: true,
    session_id: "sess-1",
    message: { model: "<synthetic>", content: [{ type: "text", text }] },
  };
}

function systemInit(): Record<string, unknown> {
  return { type: "system", subtype: "init", apiKeySource: "none", session_id: "sess-1" };
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value as Record<string, unknown>)) deepFreeze(v);
  }
  return value;
}

type Order = string[];

function recordingEvents(order: Order) {
  const events = makeRecordingEvents();
  const texts: string[] = [];
  const frames: unknown[] = [];
  events.onText = (t: string) => {
    texts.push(t);
    order.push("onText");
  };
  events.onResult = () => {
    order.push("onResult");
  };
  events.onTextTurnEnd = () => {
    order.push("onTextTurnEnd");
  };
  events.onAgentAuthFailure = (frame) => {
    frames.push(frame);
    order.push("onAgentAuthFailure");
  };
  return { events, texts, frames };
}

/** A runner whose factory taps the mock Query with the REAL tap + REAL probe, exactly as cc-dispatcher does. */
function makeRunner(mock: ReturnType<typeof createMockQuery>, scheme: "api_key" | "oauth_token" | null, factoryCalls?: { n: number }) {
  return createSoleurGoRunner({
    queryFactory: (args) => {
      if (factoryCalls) factoryCalls.n += 1;
      if (scheme) args.setAuthScheme?.(scheme);
      const probe = createAgentAuthFailureProbe({
        runner: "cc-soleur-go",
        credentialScheme: scheme ?? "unknown",
        dedupeToken: "user-A",
      });
      return tapAgentAuthFailure(mock.query, probe);
    },
    now: () => Date.now(),
    wallClockTriggerMs: 30_000,
  });
}

function dispatchArgs(events: ReturnType<typeof makeRecordingEvents>) {
  return {
    persona: "command_center" as const,
    conversationId: "conv-auth",
    userId: "user-A",
    userMessage: "hi",
    currentRouting: { kind: "soleur_go_pending" as const },
    events,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  };
}

function authEvents(): unknown[][] {
  return mockReportSilentFallback.mock.calls.filter(
    (c) => (c[1] as { feature?: string } | undefined)?.feature === "agent-auth",
  );
}

describe("cc runner — friendly CLI auth-failure reply (#11086)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetAgentAuthDedupeForTests();
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("rewrites the raw reply for a tenant, emits the probe on the RAW message, and sends key_invalid AFTER stream_end", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock, "api_key");
    const order: Order = [];
    const { events, texts, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));

    const raw = deepFreeze(cliAssistant(CLI_TEXT));
    mock.emit(systemInit() as never);
    mock.emit(raw as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);

    // Friendly text, never the raw CLI line.
    expect(texts).toEqual([authFailureCopy("not_logged_in", "api_key")]);
    expect(texts.join(" ")).not.toContain("Please run /login");
    // Order: text, result bookkeeping, stream_end, then the recovery frame.
    expect(order).toEqual(["onText", "onResult", "onTextTurnEnd", "onAgentAuthFailure"]);
    expect(frames).toEqual([
      {
        type: "error",
        message: authFailureCopy("not_logged_in", "api_key"),
        errorCode: "key_invalid",
        credentialScheme: "api_key",
      },
    ]);
    // The diagnostic saw the original message exactly once (real tap + real probe), with the raw-derived kind.
    const emitted = authEvents();
    expect(emitted).toHaveLength(1);
    expect((emitted[0][1] as { tags: { match_kind: string } }).tags.match_kind).toBe("not_logged_in");
    // The SDK message object is unchanged.
    expect((raw.message as { content: Array<{ text: string }> }).content[0].text).toBe(CLI_TEXT);
  });

  it("uses the operator copy for the oauth_token scheme", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock, "oauth_token");
    const order: Order = [];
    const { events, texts, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    mock.emit(systemInit() as never);
    mock.emit(cliAssistant(CLI_TEXT) as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(texts).toEqual([authFailureCopy("not_logged_in", "oauth_token")]);
    expect((frames[0] as { credentialScheme: string }).credentialScheme).toBe("oauth_token");
  });

  it("session_expired is bubble-only: friendly text, no recovery frame, warm Query kept", async () => {
    const mock = createMockQuery();
    const calls = { n: 0 };
    const runner = makeRunner(mock, "api_key", calls);
    const order: Order = [];
    const { events, texts, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    mock.emit(systemInit() as never);
    mock.emit(cliAssistant(EXPIRED_TEXT) as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(texts).toEqual([authFailureCopy("session_expired", "api_key")]);
    expect(frames).toEqual([]);
    expect(order).not.toContain("onAgentAuthFailure");

    // Non-terminal: the next dispatch reuses the warm Query (the factory is not called again).
    await runner.dispatch(dispatchArgs(events));
    expect(calls.n).toBe(1);
  });

  it("a terminal failure makes the NEXT dispatch cold, so the credential is re-leased", async () => {
    const mock = createMockQuery();
    const calls = { n: 0 };
    const runner = makeRunner(mock, "api_key", calls);
    const order: Order = [];
    const { events, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    mock.emit(systemInit() as never);
    mock.emit(cliAssistant(CLI_TEXT) as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(frames).toHaveLength(1);
    expect(calls.n).toBe(1);

    // The failing turn's Query is NOT closed at the result (a queued message is never dropped)...
    expect(mock.closeSpy).not.toHaveBeenCalled();
    // ...but the next dispatch tears it down and builds a cold one.
    await runner.dispatch(dispatchArgs(events));
    expect(calls.n).toBe(2);
    expect(mock.closeSpy).toHaveBeenCalledTimes(1);
  });

  it("does not rewrite or emit for a forged reply (non-synthetic model, no CLI flag, no structured code)", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock, "api_key");
    const order: Order = [];
    const { events, texts, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    mock.emit(systemInit() as never);
    mock.emit({
      type: "assistant",
      session_id: "sess-1",
      message: { model: "claude-sonnet-4", content: [{ type: "text", text: CLI_TEXT }] },
    } as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(texts).toEqual([CLI_TEXT]); // the model's own text passes through unchanged
    expect(frames).toEqual([]);
    expect(authEvents()).toHaveLength(0);
  });

  it("a multi-block authentication_failed message stays raw but is still observed", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock, "api_key");
    const order: Order = [];
    const { events, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    const msg = cliAssistant(CLI_TEXT);
    (msg.message as { content: unknown[] }).content.push({ type: "text", text: "more" });
    mock.emit(systemInit() as never);
    mock.emit(msg as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(frames).toEqual([]);
    expect(authEvents()).toHaveLength(1); // the probe's structured arm still fired on the raw message
  });

  it("emits one recovery frame per turn even when two matching messages arrive", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock, "api_key");
    const order: Order = [];
    const { events, frames } = recordingEvents(order);
    await runner.dispatch(dispatchArgs(events));
    mock.emit(systemInit() as never);
    mock.emit(cliAssistant(CLI_TEXT) as never);
    mock.emit(cliAssistant(CLI_TEXT) as never);
    mock.emit(makeResult(0, "sess-1") as never);
    await flushMicrotasks(40);
    expect(frames).toHaveLength(1);
  });
});

describe("cc runner — lease refusal for an unusable stored credential (#11086)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rethrows without a second Sentry mirror from the runner's queryFactory catch", async () => {
    const err = Object.assign(new Error("refused"), { name: "ByokLeaseError", cause: "oauth_unusable" });
    const runner = createSoleurGoRunner({
      queryFactory: () => {
        throw err;
      },
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const { events } = recordingEvents([]);
    await expect(runner.dispatch(dispatchArgs(events))).rejects.toBe(err);
    const queryFactoryMirrors = mockReportSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string } | undefined)?.op === "queryFactory",
    );
    expect(queryFactoryMirrors).toHaveLength(0);
  });

  it("still mirrors any other factory failure (the skip is specific to oauth_unusable)", async () => {
    const err = Object.assign(new Error("boom"), { name: "ByokLeaseError", cause: "fetch_failed" });
    const runner = createSoleurGoRunner({
      queryFactory: () => {
        throw err;
      },
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const { events } = recordingEvents([]);
    await expect(runner.dispatch(dispatchArgs(events))).rejects.toBe(err);
    expect(
      mockReportSilentFallback.mock.calls.filter((c) => (c[1] as { op?: string } | undefined)?.op === "queryFactory"),
    ).toHaveLength(1);
  });
});

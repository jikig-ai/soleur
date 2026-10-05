import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import {
  createMockQueryScripted as createMockQuery,
  makeRecordingEvents as makeEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";

// #9538 — mid-stream stale-resume recovery. When the persisted
// `conversations.session_id` points at a Claude Code session that no
// longer exists, `query({ resume })` constructs cleanly and the SDK
// subprocess surfaces `No conversation found with session ID` THROUGH
// the message iterator — landing in `consumeStream`'s catch, not the
// dispatch-time catch that already clears the column (R7). The runner
// must NOT emit terminal `internal_error` (which wedges the
// conversation — every retry re-seeds the same dead id) and must NOT
// `reportSilentFallback` (expected operational behavior, not an
// incident). Instead it fires `DispatchEvents.onStaleResume` so the
// dispatcher can clear `session_id` and re-dispatch cold.
//
// Suite shape mirrors `soleur-go-runner-session-revoked.test.ts`
// (sibling discriminator on the same catch).

const {
  mockReportSilentFallback,
  mockWarnSilentFallback,
  mockMirrorWithDebounce,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockMirrorWithDebounce: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  mirrorWithDebounce: mockMirrorWithDebounce,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

vi.mock("@/lib/supabase/tenant", async () => {
  // Re-export the real `RuntimeAuthError` class so `instanceof` checks
  // inside the runner match; substitute `getMyRevocationStatus` (only
  // reachable on the denied_jti sibling arm, never on this one).
  const actual = await vi.importActual<typeof import("@/lib/supabase/tenant")>(
    "@/lib/supabase/tenant",
  );
  return {
    ...actual,
    getMyRevocationStatus: vi.fn().mockResolvedValue(null),
  };
});

import { createSoleurGoRunner } from "@/server/soleur-go-runner";

const STALE_MSG =
  "Claude Code returned an error result: No conversation found with session ID: dead-id";

function makeRunner(mock: ReturnType<typeof createMockQuery>) {
  return createSoleurGoRunner({
    queryFactory: () => mock.query,
    now: () => Date.now(),
    wallClockTriggerMs: 30_000,
  });
}

function dispatchArgs(
  events: ReturnType<typeof makeEvents>,
  sessionId?: string,
) {
  return {
    persona: "command_center" as const,
    conversationId: "conv-stale",
    userId: "user-A",
    userMessage: "hi",
    currentRouting: { kind: "soleur_go_pending" as const },
    events,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    ...(sessionId ? { sessionId } : {}),
  };
}

describe("consumeStream — stale-resume discriminator (#9538)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("stale signature + sessionId → onStaleResume once, no internal_error, no reportSilentFallback, query closed", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock);
    const events = makeEvents();
    const onStaleResume = vi.fn();
    events.onStaleResume = onStaleResume;

    await runner.dispatch(dispatchArgs(events, "dead-id"));

    mock.emitError(new Error(STALE_MSG));
    await flushMicrotasks(20);

    expect(onStaleResume).toHaveBeenCalledTimes(1);
    expect(onStaleResume).toHaveBeenCalledWith({ deadSessionId: "dead-id" });
    // The terminal contract is bypassed entirely — no WorkflowEnd at all
    // (an `internal_error` would disable the client input via
    // `session_ended` and wedge the conversation).
    expect(events._ended).toHaveLength(0);
    // Not an incident — no error-tier Sentry mirror for the stale error.
    // (The warn-tier occurrence marker is asserted separately below.)
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "soleur-go-runner",
        op: "stale-resume-recovery",
      }),
    );
    // Teardown parity — the query closes exactly as emitWorkflowEnded's
    // path would (timers, inputQueue, onCloseQuery hook, map delete).
    expect(mock.closeSpy).toHaveBeenCalled();
    expect(mock.isClosed()).toBe(true);
  });

  it("stale signature WITHOUT sessionId (no resume attempted) → internal_error unchanged", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock);
    const events = makeEvents();
    const onStaleResume = vi.fn();
    events.onStaleResume = onStaleResume;

    await runner.dispatch(dispatchArgs(events));

    mock.emitError(new Error(STALE_MSG));
    await flushMicrotasks(20);

    expect(onStaleResume).not.toHaveBeenCalled();
    expect(events._ended).toHaveLength(1);
    expect(events._ended[0]?.status).toBe("internal_error");
    expect(mockReportSilentFallback).toHaveBeenCalled();
  });

  it("non-stale mid-stream error with sessionId → internal_error + reportSilentFallback unchanged", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock);
    const events = makeEvents();
    const onStaleResume = vi.fn();
    events.onStaleResume = onStaleResume;

    await runner.dispatch(dispatchArgs(events, "live-id"));

    mock.emitError(new Error("SDK connection reset"));
    await flushMicrotasks(20);

    expect(onStaleResume).not.toHaveBeenCalled();
    expect(events._ended).toHaveLength(1);
    expect(events._ended[0]?.status).toBe("internal_error");
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "consumeStream" }),
    );
  });

  it("a throwing onStaleResume listener is contained (query still closes)", async () => {
    const mock = createMockQuery();
    const runner = makeRunner(mock);
    const events = makeEvents();
    events.onStaleResume = vi.fn(() => {
      throw new Error("listener blew up");
    });

    await runner.dispatch(dispatchArgs(events, "dead-id"));

    mock.emitError(new Error(STALE_MSG));
    await flushMicrotasks(20);

    expect(events._ended).toHaveLength(0);
    expect(mock.isClosed()).toBe(true);
    // The listener throw mirrors under its own op — it must not re-enter
    // the stale arm or leak as the turn's error.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "onStaleResume" }),
    );
  });
});

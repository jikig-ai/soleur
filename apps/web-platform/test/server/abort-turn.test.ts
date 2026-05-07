/**
 * Abort-turn unit tests (PR1, plan §1.9).
 *
 * Covers:
 *   - `abortSession` reason union widened to include `"user_requested_stop"`,
 *     and the Error message routes through `controller.signal.reason` for the
 *     for-await classifier (`classifyAbortReason`).
 *   - Multi-leader broadcast: an un-keyed `abortSession(userId, conv)` aborts
 *     every leader session for the conversation. (TR3 / G3 — no hidden leader
 *     keeps burning the user's BYOK key after Stop.)
 *   - Cross-user invariant: aborting `(alice, conv1)` cannot touch `(bob, *)`
 *     even when conv IDs collide. The wire format ALSO blocks userId forging
 *     via the strictObject zod schema.
 *   - Idempotency: a second `abortSession` after the session has been
 *     unregistered is a silent no-op.
 *   - WSMessage parser: `abort_turn` accepts `{conversationId}`, rejects
 *     `userId` and any other extra field (TR4).
 *
 * Lives next to other server unit tests (`apps/web-platform/test/server/`)
 * per project convention. Targets the registry helpers extracted from
 * `agent-runner.ts` so the assertions don't have to spin up the SDK or
 * Supabase.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

import {
  abortSession,
  abortAllUserSessions,
  registerSession,
  unregisterSession,
  __test_only__ as registryTestOnly,
} from "@/server/agent-session-registry";
import type { AgentSession } from "@/server/review-gate";
import { classifyAbortReason } from "@/server/abort-classifier";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

function makeSession(): AgentSession {
  return {
    abort: new AbortController(),
    reviewGateResolvers: new Map(),
    sessionId: null,
  };
}

describe("agent-session-registry · abortSession", () => {
  beforeEach(() => {
    registryTestOnly.clear();
  });

  it("calls controller.abort with reason 'user_requested_stop' carried in the Error message", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "user_requested_stop");

    expect(session.abort.signal.aborted).toBe(true);
    const reason = session.abort.signal.reason as Error;
    expect(reason).toBeInstanceOf(Error);
    expect(reason.message).toContain("user_requested_stop");
  });

  it("preserves existing 'disconnected' reason path", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "disconnected");

    const reason = session.abort.signal.reason as Error;
    expect(reason.message).toContain("disconnected");
  });

  it("preserves existing 'superseded' reason path", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "superseded");

    const reason = session.abort.signal.reason as Error;
    expect(reason.message).toContain("superseded");
  });

  it("multi-leader broadcast: un-keyed abort fires every leader's controller for the conversation", () => {
    const cpo = makeSession();
    const cmo = makeSession();
    const cto = makeSession();
    registerSession("alice", "conv1", cpo, "cpo");
    registerSession("alice", "conv1", cmo, "cmo");
    registerSession("alice", "conv1", cto, "cto");

    abortSession("alice", "conv1", "user_requested_stop");

    expect(cpo.abort.signal.aborted).toBe(true);
    expect(cmo.abort.signal.aborted).toBe(true);
    expect(cto.abort.signal.aborted).toBe(true);
    for (const s of [cpo, cmo, cto]) {
      const reason = s.abort.signal.reason as Error;
      expect(reason.message).toContain("user_requested_stop");
    }
  });

  it("leader-keyed abort scopes to that single leader's session", () => {
    const cpo = makeSession();
    const cmo = makeSession();
    registerSession("alice", "conv1", cpo, "cpo");
    registerSession("alice", "conv1", cmo, "cmo");

    abortSession("alice", "conv1", "user_requested_stop", "cmo");

    expect(cpo.abort.signal.aborted).toBe(false);
    expect(cmo.abort.signal.aborted).toBe(true);
  });

  it("cross-user invariant: aborting alice does not touch bob's conv1 session", () => {
    // Both users have a session keyed to "conv1" — distinct keys
    // (`alice:conv1`, `bob:conv1`) ensure no prefix collision.
    const aliceSession = makeSession();
    const bobSession = makeSession();
    registerSession("alice", "conv1", aliceSession);
    registerSession("bob", "conv1", bobSession);

    abortSession("alice", "conv1", "user_requested_stop");

    expect(aliceSession.abort.signal.aborted).toBe(true);
    expect(bobSession.abort.signal.aborted).toBe(false);
  });

  it("forged conversationId that alice does not own is a silent no-op (does not touch bob)", () => {
    // Simulate the ws-handler path with WS-resolved userId="alice" but a
    // forged conversationId="conv2" (which actually belongs to bob).
    // abortSession resolves the prefix `alice:conv2` — no entries match.
    // Bob's session at `bob:conv2` is a different prefix, so it stays.
    const bobSession = makeSession();
    registerSession("bob", "conv2", bobSession);

    abortSession("alice", "conv2", "user_requested_stop");

    expect(bobSession.abort.signal.aborted).toBe(false);
  });

  it("idempotent: a second abort call after unregister is a silent no-op (no controller.abort)", () => {
    const session = makeSession();
    const abortSpy = vi.spyOn(session.abort, "abort");
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "user_requested_stop");
    unregisterSession("alice", "conv1");
    abortSession("alice", "conv1", "user_requested_stop");

    expect(abortSpy).toHaveBeenCalledTimes(1);
  });

  it("abortAllUserSessions sweeps every conversation for the user", () => {
    const a1 = makeSession();
    const a2 = makeSession();
    const b1 = makeSession();
    registerSession("alice", "conv1", a1);
    registerSession("alice", "conv2", a2);
    registerSession("bob", "conv1", b1);

    abortAllUserSessions("alice");

    expect(a1.abort.signal.aborted).toBe(true);
    expect(a2.abort.signal.aborted).toBe(true);
    expect(b1.abort.signal.aborted).toBe(false);
  });
});

describe("classifyAbortReason", () => {
  it("returns isUserRequested=true when the signal reason Error message contains 'user_requested_stop'", () => {
    const err = new Error("Session aborted: user_requested_stop");
    expect(classifyAbortReason(err)).toEqual({ isUserRequested: true });
  });

  it("returns isUserRequested=false for 'disconnected'", () => {
    const err = new Error("Session aborted: disconnected");
    expect(classifyAbortReason(err)).toEqual({ isUserRequested: false });
  });

  it("returns isUserRequested=false for 'superseded'", () => {
    const err = new Error("Session aborted: superseded");
    expect(classifyAbortReason(err)).toEqual({ isUserRequested: false });
  });

  it("returns isUserRequested=false when reason is undefined", () => {
    expect(classifyAbortReason(undefined)).toEqual({ isUserRequested: false });
  });

  it("returns isUserRequested=false when reason is a non-Error value", () => {
    expect(classifyAbortReason("user_requested_stop")).toEqual({ isUserRequested: false });
    expect(classifyAbortReason(null)).toEqual({ isUserRequested: false });
  });
});

describe("parseWSMessage · abort_turn", () => {
  it("accepts a well-formed abort_turn frame", () => {
    const result = parseWSMessage({ type: "abort_turn", conversationId: "conv1" });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.msg.type).toBe("abort_turn");
    }
  });

  it("rejects an abort_turn frame with extra `userId` field (TR4 cross-user invariant)", () => {
    const result = parseWSMessage({
      type: "abort_turn",
      conversationId: "conv2",
      userId: "bob",
    });
    expect(result.ok).toBe(false);
  });

  it("rejects an abort_turn frame missing conversationId", () => {
    const result = parseWSMessage({ type: "abort_turn" });
    expect(result.ok).toBe(false);
  });

  it("rejects an abort_turn frame with empty-string conversationId", () => {
    const result = parseWSMessage({ type: "abort_turn", conversationId: "" });
    expect(result.ok).toBe(false);
  });
});
